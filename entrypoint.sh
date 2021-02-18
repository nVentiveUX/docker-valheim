#!/bin/bash

echo "** 🏗️ Install Valheim app..."
mkdir -pv "${HOMEDIR}/valheim"
${STEAMCMDDIR}/steamcmd.sh +login anonymous +force_install_dir "${HOMEDIR}/valheim" +app_update "896660" +quit
echo "** 👍 Done."

exec "$@"
