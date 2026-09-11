#!/bin/bash

set -eu -o pipefail

if [[ "${UPDATE_ON_START:-true}" == "true" ]]; then
	echo "** Install Valheim app..."
	"${STEAMCMDDIR}/steamcmd.sh" +login anonymous +force_install_dir "${HOMEDIR}/valheim" +app_update "896660" +quit
	echo "** Done."
fi

exec "$@"
