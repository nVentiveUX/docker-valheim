#!/bin/bash

set -eux

echo "** 🏗️ Install Valheim app..."
${STEAMCMDDIR}/steamcmd.sh +login anonymous +force_install_dir "${HOMEDIR}/valheim" +app_update "896660" +quit
echo "** 👍 Done."

exec "$@"
