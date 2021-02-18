# hadolint ignore=DL3007
FROM cm2network/steamcmd:latest

LABEL maintainer="nVentiveUX <https://github.com/nVentiveUX>"
LABEL license="MIT"
LABEL description="A Docker image to easily setup and run a dedicated server for the early access game Valheim."

VOLUME ${HOMEDIR}/valheim ${HOMEDIR}/.config/unity3d/IronGate/Valheim

USER root

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN echo "** 🏗️ Update system..." \
  && apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
    locales \
  && rm -rf /var/lib/apt/lists/* \
  && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
  && echo "** 👍 Done."

USER ${USER}

RUN echo "** 🏗️ Install Valheim app..." \
  && ./steamcmd.sh +login anonymous +force_install_dir "/tmp/valheim" +app_update "896660" validate +quit \
  && echo "** 👍 Done."

WORKDIR ${HOMEDIR}/valheim

ARG NAME="nVentiveUX docker-valheim" \
    WORLD="Dedicated" \
    PUBLIC=1 \
    PASSWORD="ChangeMe1234"

ENV TZ="Europe/Paris" \
    LANG="en_US.utf8" \
    SteamAppId="892970" \
    templdpath="$LD_LIBRARY_PATH" \
    LD_LIBRARY_PATH="/home/steam/valheim/linux64:$LD_LIBRARY_PATH"

EXPOSE 2456-2458/udp

CMD [ "./valheim_server.x86_64", "-nographics", "-batchmode", "-name", "${NAME}", "-port", "2456", "-world", "${WORLD}", "-password", "${PASSWORD}", "-public", "${PUBLIC}" ]
