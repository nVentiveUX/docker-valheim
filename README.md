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

## Disclaimer

**This software comes with no warranty of any kind**. USE AT YOUR OWN RISK! This a personal project and is NOT endorsed by Microsoft. If you encounter an issue, please submit it on GitHub.

## Known issue

- [ ] Backup scheduling - [#3](https://github.com/nVentiveUX/docker-valheim/issues/3)

## Usage

### Create the infrastructure in Azure

For Valheim, you need a strong CPU, so I pick a **Standard_F2s_v2** (2 vcpus, 4 GiB memory)
The Fsv2-series runs on the Intel® Xeon® Platinum 8272CL (Cascade Lake) processors and Intel® Xeon® Platinum 8168 (Skylake) processors.
It features a sustained all core Turbo clock speed of 3.4 GHz and a maximum single-core turbo frequency of 3.7 GHz.

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
    --subscription="8d8af6bf-9138-4d9d-a2e6-5bff1e3044c5" \
    --location="francecentral" \
    --rg-vnet="rg-shared-001" \
    --vnet-name="vnt-shared-001" \
    --subnet-name="snt-lebonserv-001" \
    --subnet="10.1.0.0/29" \
    --rg-vm="rg-app-lebonserv-001" \
    --vm-name="vm-lebonserv-001" \
    --lb-name="lb-lebonserv-001" \
    --dns-name="lebonserv"
)
```

### Install Docker

Following are **examples**

```shell
$ scp -P 4160 ~/lebonservfrancecentral_backup-001_sas.txt $(id -un)@lebonserv.francecentral.cloudapp.azure.com:~/
$ ssh lebonserv.francecentral.cloudapp.azure.com -p 4160 -l $(id -un)
sudo apt update && sudo apt dist-upgrade -Vy
sudo reboot

$ ssh lebonserv.francecentral.cloudapp.azure.com -p 4160 -l $(id -un)
{
# Install packages to allow apt to use a repository over HTTPS
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg \
    lsb-release

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add stable Docker repository
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update the apt package index
sudo apt update

# Install the latest version of Docker CE
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $(id -un)

# Install docker-compose
sudo curl \
  -L https://github.com/docker/compose/releases/download/$(curl -Ls https://www.servercow.de/docker-compose/latest.php)/docker-compose-$(uname -s)-$(uname -m) \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install bash completion for Docker
sudo curl \
  -L https://raw.githubusercontent.com/docker/compose/$(docker-compose version --short)/contrib/completion/bash/docker-compose \
  -o /etc/bash_completion.d/docker-compose
}
```

### First run

Disconnect and reconnect so `docker` command will be knowned.

```shell
{
sudo mkdir -p /srv/valheim/saves /srv/valheim/server
sudo chown -R 1000:1000 /srv/valheim
docker run -d \
  --name valheim \
  --publish 2456-2457:2456-2457/udp \
  --volume "/srv/valheim/server:/home/steam/valheim" \
  --volume "/srv/valheim/saves:/home/steam/.config/unity3d/IronGate/Valheim" \
  --restart unless-stopped \
  nventiveux/docker-valheim:latest ./valheim_server.x86_64 -name "nVentiveUX" -port 2456 -world "Dedicated" -password "ChangeMe1234"
}
```

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

printf "Set-up \"/etc/cron.d/valheim\" backup system...\\n"
sudo mkdir -p /usr/local/share/valheim/maintenance
sudo wget -q "https://github.com/nVentiveUX/docker-valheim/raw/main/azure_backup.sh" -O /usr/local/share/valheim/maintenance/azure_backup.sh
sudo chmod +x /usr/local/share/valheim/maintenance/azure_backup.sh
cat <<EOF | sudo tee /etc/cron.d/valheim >/dev/null 2>&1
SHELL=/bin/bash
# m h dom mon dow user    command
0 5 * * * root    /usr/local/share/valheim/maintenance/azure_backup.sh "$STORAGE_ACCOUNT_NAME" "$STORAGE_SAS_TOKEN" "$STORAGE_ACCOUNT_CONTAINER" >/dev/null 2>&1
EOF
)
```

### Update

```bash
docker restart valheim
# or
{
docker stop valheim
docker run -it --rm -v "/srv/valheim/server:/home/steam/valheim" -v "/srv/valheim/saves:/home/steam/.config/unity3d/IronGate/Valheim" nventiveux/docker-valheim:latest ./steamcmd.sh +login anonymous +force_install_dir "/home/steam/valheim" +app_update "896660" +quit
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
