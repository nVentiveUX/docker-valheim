# Valheim server on Azure

[![Docker Image CI](https://github.com/nVentiveUX/docker-valheim/workflows/Docker%20Image%20CI/badge.svg)](https://hub.docker.com/repository/docker/nventiveux/docker-valheim) [![Docker Pulls](https://img.shields.io/docker/pulls/nventiveux/docker-valheim)](https://hub.docker.com/r/nventiveux/docker-valheim)

Table of contents

  1. [About](#about)
  2. [Disclaimer](#disclaimer)
  3. [Known issue](#known-issue)
  4. [Usage](#usage)

## About

![Valheim](https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/896660/233d73a1c963515ee4a9b59507bc093d85a4e2dc.jpg "Valheim")

A Docker image to easily setup and run a dedicated server for the early access game Valheim.
Check also this [Official guide](https://valheim.com/support/a-guide-to-dedicated-servers).

## Disclaimer

**This software comes with no warranty of any kind**. USE AT YOUR OWN RISK! This a personal project and is NOT endorsed by Microsoft. If you encounter an issue, please submit it on GitHub.

## Known issue

- [ ] Backup scheduling - [#3](https://github.com/nVentiveUX/docker-valheim/issues/3)

## Usage

### Create the infrastructure in Azure

For Valheim, the script defaults to **Standard_D2as_v7** (2 vCPUs, 8 GiB memory), a current x64 SKU available in France Central. This non-`d` variant has no local temporary NVMe disk; persistent game data remains on managed storage.
The VM image defaults to `Canonical:ubuntu-24_04-lts:server:latest`.

Override the defaults with `VM_SIZE`, `VM_IMAGE`, `VM_ADMIN_USERNAME`, and `OS_DISK_SKU` when needed.

You can launch an [Azure Cloud Shell](https://shell.azure.com/) to run the following notebook. (It will create automatically a storage account in the proper location)

All commands are documented here: [](https://docs.microsoft.com/fr-fr/cli/azure/reference-index)

For **France Central**

```shell
(
[[ ! -d "${HOME}/docker-valheim" ]] && git clone https://github.com/nVentiveUX/docker-valheim.git ~/docker-valheim
cd ~/docker-valheim
git fetch --prune
git pull

# Yvesub example
./create_vm.sh \
  --subscription="2aa7db02-cab6-4205-9ac5-51857c211abe" \
  --location="francecentral" \
  --rg-vnet="rg-shared-001" \
  --vnet-name="vnt-shared-001" \
  --subnet-name="snt-lebonserv-001" \
  --subnet="10.1.0.0/29" \
  --rg-vm="rg-app-lebonserv-001" \
  --vm-name="vm-lebonserv-001" \
  --lb-name="lb-lebonserv-001" \
  --dns-name="lebonserv" \
  --ssh-key-file="$HOME/.ssh/id_ed25519.pub" \
  --ssh-source-prefixes="203.0.113.10/32"
)
```

Replace `203.0.113.10/32` with the trusted public IP or CIDR used to administer the VM.

### First run

Disconnect and reconnect so `docker` command will be knowned.

```shell
$ scp -P 4160 ~/lebonservfrancecentral_backup-001_sas.txt $(id -un)@lebonserv.francecentral.cloudapp.azure.com:~/
$ ssh lebonserv.francecentral.cloudapp.azure.com -p 4160 -l $(id -un)
{
sudo mkdir -p /srv/valheim/saves /srv/valheim/server
sudo chown -R 1000:1000 /srv/valheim
docker run -d \
  --name valheim \
  --publish 2456-2457:2456-2457/udp \
  --stop-timeout 60 \
  --security-opt no-new-privileges:true \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  --volume "/srv/valheim/server:/home/steam/valheim" \
  --volume "/srv/valheim/saves:/home/steam/.config/unity3d/IronGate/Valheim" \
  --restart unless-stopped \
  nventiveux/docker-valheim:latest ./valheim_server.x86_64 \
    -name "LeBonServ" \
    -port 2456 \
    -world "Dedicated001" \
    -password "$(read -rsp 'Valheim password: ' password; printf '%s' "$password")" \
    -public 0 \
    -saveinterval 900 \
    -backups 4 \
    -backupshort 7200 \
    -backuplong 43200 \
    -crossplay \
    -preset Normal \
    -modifier DeathPenalty casual \
    -modifier Raids none \
    -setkey nobuildcost
}
```

This configuration keeps the server out of the public browser, saves the world every 15 minutes, keeps four rolling Valheim backups, and enables crossplay for players on supported platforms. The Azure backup job provides an additional off-host recovery copy.

The 60-second stop timeout gives Valheim time to save cleanly. The password is entered interactively, but Docker can still expose command arguments through container inspection; rotate the password if it is shared or logged.

World customization is optional. Edit the launch command directly: use `-preset` with `Normal`, `Casual`, `Easy`, `Hard`, `Hardcore`, `Immersive`, or `Hammer`; add `-modifier <name> <value>` for combat, deathpenalty, resources, raids, or portals; and use `-setkey` with `nobuildcost`, `playerevents`, `passivemobs`, or `nomap`.

Valid modifiers and values are:
`Combat`: veryeasy, easy, hard, veryhard
`DeathPenalty`: casual, veryeasy, easy, hard, hardcore
`Resources`: muchless, less, more, muchmore, most
`Raids`: none, muchless, less, more, muchmore
`Portals`: casual, hard, veryhard

You can test on you laptop the connectivity.

```shell
nc -v lebonserv.francecentral.cloudapp.azure.com 2457 -u
```

### Set-up the backup system

```shell
(
STORAGE_ACCOUNT_NAME="lebonservfrancecentral"
STORAGE_SAS_TOKEN="$(cat lebonservfrancecentral_backup-001_sas.txt)"
STORAGE_ACCOUNT_CONTAINER="backup-001"
STORAGE_SAS_TOKEN_FILE="/etc/valheim/storage-sas-token"

printf "Set-up \"/etc/cron.d/valheim\" backup system...\\n"
sudo mkdir -p /usr/local/share/valheim/maintenance
sudo install -d -m 700 /etc/valheim
sudo install -m 600 /dev/null "${STORAGE_SAS_TOKEN_FILE}"
printf '%s\n' "$STORAGE_SAS_TOKEN" | sudo tee "${STORAGE_SAS_TOKEN_FILE}" >/dev/null
sudo wget -q "https://github.com/nVentiveUX/docker-valheim/raw/refs/heads/main/azure_backup.sh" -O /usr/local/share/valheim/maintenance/azure_backup.sh
sudo chmod +x /usr/local/share/valheim/maintenance/azure_backup.sh
cat <<EOF | sudo tee /etc/cron.d/valheim >/dev/null 2>&1
SHELL=/bin/bash
# m h dom mon dow user    command
0 5 * * * root    /usr/local/share/valheim/maintenance/azure_backup.sh "$STORAGE_ACCOUNT_NAME" "$STORAGE_SAS_TOKEN_FILE" "$STORAGE_ACCOUNT_CONTAINER" >/dev/null 2>&1
EOF
)
```

To run the backup immediately for testing, execute the command from the cron entry directly. Do not run `/etc/cron.d/valheim` with `run-one`; it is a cron configuration file, not an executable script:

```bash
sudo /usr/local/share/valheim/maintenance/azure_backup.sh \
  lebonservfrancecentral \
  /etc/valheim/storage-sas-token \
  backup-001
```

### Update

```bash
docker restart valheim
# or
{
docker stop valheim
docker run -it --rm \
  --entrypoint /home/steam/steamcmd/steamcmd.sh \
  -v "/srv/valheim/server:/home/steam/valheim" \
  -v "/srv/valheim/saves:/home/steam/.config/unity3d/IronGate/Valheim" \
  nventiveux/docker-valheim:latest \
  +force_install_dir "/home/steam/valheim" \
  +login anonymous \
  +app_update "896660" \
  +quit
docker start valheim
}
```

### Play

Connect on ```lebonserv.francecentral.cloudapp.azure.com:2456```. (If you would like to connect using Steam server list, use port+1: **2457**)

### Get the logs

```shell
# Server logs
docker logs --tail 20 -f valheim
# Backup logs
tail -f /var/log/valheim/azure_backup.sh.log
```
