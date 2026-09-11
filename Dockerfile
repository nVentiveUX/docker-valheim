# hadolint ignore=DL3007
FROM cm2network/steamcmd:steam

LABEL maintainer="nVentiveUX <https://github.com/nVentiveUX>"
LABEL license="MIT"
LABEL description="A Docker image to easily setup and run a dedicated server for the early access game Valheim."

USER root

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN echo "** 🏗️ Set locales..." \
  && apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
		ca-certificates \
		file \
		lib32z1 \
		libatomic1 \
		libc6-dev \
    libpulse-dev \
		libpulse0 \
		tini \
	  wget \
    locales \
  && rm -rf /var/lib/apt/lists/* \
  && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
  && echo "** 👍 Done."

USER ${USER}

ENV TZ="Europe/Paris" \
    LANG="en_US.utf8" \
    SteamAppId="892970" \
    templdpath="" \
    LD_LIBRARY_PATH="/home/steam/valheim/linux64"

RUN echo "** 🏗️ Prepare config folders..." \
  && mkdir -pv "${HOMEDIR}/valheim" \
  && mkdir -pv "${HOMEDIR}/.config/unity3d/IronGate/Valheim" \
  && echo "** 👍 Done."

EXPOSE 2456-2457/udp

VOLUME ${HOMEDIR}/valheim ${HOMEDIR}/.config/unity3d/IronGate/Valheim

COPY entrypoint.sh /entrypoint.sh

WORKDIR ${HOMEDIR}/valheim
STOPSIGNAL SIGINT
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
