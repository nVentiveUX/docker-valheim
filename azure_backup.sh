#!/bin/bash
# Backup files script for Ubuntu on Azure
# $1 = STORAGE_ACCOUNT_NAME
# $2 = STORAGE_SAS_TOKEN_FILE
# $3 = STORAGE_ACCOUNT_CONTAINER

set -eu -o pipefail

if [[ $# -ne 3 ]]; then
  printf 'Usage: %s <storage-account> <sas-token-file> <container>\n' "$0" >&2
  exit 64
fi

umask 077
LOCK_FILE="${LOCK_FILE:-/run/lock/valheim-backup.lock}"
exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

# Please edit according to your need.
BACKUP_DIR="${BACKUP_DIR:-/var/backups/valheim}"
FILES_DIR="${FILES_DIR:-/srv/valheim/saves}"
LOG_DIR="${LOG_DIR:-/var/log/valheim}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
STORAGE_ACCOUNT_NAME=$1
STORAGE_SAS_TOKEN_FILE=$2
STORAGE_ACCOUNT_CONTAINER=$3
#-------------------------------------------------------------------------------

# Init
TMPDIR=$(mktemp -d /tmp/backup.XXXXXX)
BASENAME=$(basename "$0")
TIMESTAMP=$(date "+%Y-%m-%dT%H-%M-%S%z")
BACKUP_FILE="${BACKUP_DIR}/full-backup-${TIMESTAMP}.tar.xz"
LOGFILE="${LOG_DIR}/${BASENAME}.log"

if [[ ! -r $STORAGE_SAS_TOKEN_FILE ]]; then
  printf 'SAS token file is not readable: %s\n' "$STORAGE_SAS_TOKEN_FILE" >&2
  exit 64
fi
STORAGE_SAS_TOKEN="$(<"${STORAGE_SAS_TOKEN_FILE}")"

if [[ ! -d $FILES_DIR ]]; then
  printf 'Save directory is not readable: %s\n' "$FILES_DIR" >&2
  exit 66
fi

if [[ ! $RETENTION_DAYS =~ ^[0-9]+$ ]]; then
  printf 'RETENTION_DAYS must be a non-negative integer: %s\n' "$RETENTION_DAYS" >&2
  exit 64
fi

# Check backup destination is there
if [ ! -d "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR"
fi

# Utilities
write_log() {
  # Write a message to log file.
  message=$1
  timestamp=$(date "+[%Y-%m-%d %H:%M:%S.%N]")
  echo "${timestamp} ${message}" >> "${LOGFILE}"
}

cleanup() {
  # Clean the temp files on exit.
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

# Status codes
rCodeBackup=0
rCodeFinalTar=0
rCodeUpload=0

# Install AzCopy
AZCOPY_PATH="${AZCOPY_PATH:-/usr/local/bin/azcopy}"
if [ ! -x "$AZCOPY_PATH" ]; then
  write_log "Install AzCopy..."
  AZCOPY_TMPDIR=$(mktemp -d /tmp/azcopy.XXXXXX)
  wget -q -O "${AZCOPY_TMPDIR}/azcopy.tar.gz" "https://aka.ms/downloadazcopy-v10-linux"
  mkdir "${AZCOPY_TMPDIR}/extract"
  tar -xzf "${AZCOPY_TMPDIR}/azcopy.tar.gz" -C "${AZCOPY_TMPDIR}/extract" --strip-components=1 --wildcards 'azcopy_linux_amd64_*/azcopy'
  install -m 0755 "${AZCOPY_TMPDIR}/extract/azcopy" "$AZCOPY_PATH"
  rm -rf "$AZCOPY_TMPDIR"
  write_log "AzCopy installed."
fi

# Backup begin
write_log "#### BACKUP BEGIN ####"

# Check backup destination is there
if [ ! -d "$BACKUP_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
fi

if ! df -P "$BACKUP_DIR" >/dev/null; then
  write_log "Unable to access backup storage."
  exit 1
fi

# Application backup
write_log "Copy files."
# docker stop valheim
cp -a "${FILES_DIR}" "${TMPDIR}" || rCodeBackup=$?
# docker start valheim
if [ $rCodeBackup -ne 0 ]; then
  write_log "Unable to backup the files!"
  write_log "!!!! BACKUP FAILED !!!!"
  exit 2
fi

if ! find "${TMPDIR}" -type f -print -quit | grep -q .; then
  write_log "Save directory contains no files; refusing to create an empty backup."
  exit 2
fi

# Final archiving
write_log "Archive all in \"${BACKUP_FILE}\"."
tar Jcf "${BACKUP_FILE}" -C "${TMPDIR}" . >/dev/null 2>&1 || rCodeFinalTar=$?
if [ $rCodeFinalTar -ne 0 ]; then
  write_log "Unable to create the final archive!"
  write_log "!!!! BACKUP FAILED !!!!"
  exit 2
fi

# Upload the archive
write_log "Upload \"${BACKUP_FILE}\" into \"https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${STORAGE_ACCOUNT_CONTAINER}\"."
AZCOPY_ERROR_LOG="${TMPDIR}/azcopy-error.log"
"$AZCOPY_PATH" copy \
  "${BACKUP_FILE}" \
  "https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${STORAGE_ACCOUNT_CONTAINER}/$(basename "${BACKUP_FILE}")?${STORAGE_SAS_TOKEN}" \
  >/dev/null 2>"${AZCOPY_ERROR_LOG}" || rCodeUpload=$?
if [ $rCodeUpload -ne 0 ]; then
  while IFS= read -r message; do
    write_log "AzCopy: ${message}"
  done < "${AZCOPY_ERROR_LOG}"
  write_log "Unable to upload the final archive into Azure!"
  write_log "!!!! BACKUP FAILED !!!!"
  exit 2
fi

find "$BACKUP_DIR" -type f -name 'full-backup-*.tar.xz' -mtime "+${RETENTION_DAYS}" -delete

write_log "#### BACKUP END ####"
exit 0
