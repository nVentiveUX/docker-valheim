#!/bin/bash

set -eu -o pipefail

PROGNAME="$(basename "$0")"

usage() {
    printf "usage: %s --subscription=<name> --location=<name> --rg-vnet=<name> --vnet-name=<name> --subnet-name=<name> --subnet=<name> --rg-vm=<name> --vm-name=<name> --lb-name=<name> --dns-name=<name> --ssh-key-file=<path> --ssh-source-prefixes=<cidr>\\n" "${PROGNAME}"
}

# Parse arguments
ARGS=$(getopt \
    --options hs:l:g:v:n:u:r:m:b:d \
    --longoptions help,subscription:,location:,rg-vnet:,vnet-name:,subnet-name:,subnet:,rg-vm:,vm-name:,lb-name:,dns-name:,ssh-key-file:,ssh-source-prefixes: \
    -n "${PROGNAME}" -- "$@")
eval set -- "${ARGS}"
unset ARGS

AZ_SUBSCRIPTION_ID=""
AZ_LOCATION=""
AZ_SHARED_RG=""
AZ_VNET=""
AZ_VNET_SUBNET_NAME=""
AZ_VNET_SUBNET=""
AZ_VM_RG=""
AZ_VM=""
AZ_LB=""
AZ_LB_DNS=""
AZ_SSH_KEY_FILE="${SSH_KEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"
AZ_SSH_SOURCE_PREFIXES="${SSH_SOURCE_PREFIXES:-}"
AZ_CONTAINER="backup-001"
AZ_VM_IMAGE="${VM_IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"
AZ_VM_SIZE="${VM_SIZE:-Standard_D2as_v7}"
AZ_VM_ADMIN_USERNAME="${VM_ADMIN_USERNAME:-yandolfat}"
AZ_OS_DISK_SKU="${OS_DISK_SKU:-Premium_LRS}"
AZ_STORAGE_SKU="${STORAGE_SKU:-Standard_ZRS}"
AZ_TAGS=(service=valheim environment=production managed-by=create_vm.sh)

while true; do
  case "$1" in
        '-h'|'--help')
                usage
                exit 0
        ;;
    '-s'|'--subscription')
        AZ_SUBSCRIPTION_ID="$2"
        shift 2
        continue
    ;;
    '-l'|'--location')
        AZ_LOCATION="$2"
        shift 2
        continue
    ;;
    '-g'|'--rg-vnet')
        AZ_SHARED_RG="$2"
        shift 2
        continue
    ;;
    '-v'|'--vnet-name')
        AZ_VNET="$2"
        shift 2
        continue
    ;;
    '-n'|'--subnet-name')
        AZ_VNET_SUBNET_NAME="$2"
        shift 2
        continue
    ;;
    '-u'|'--subnet')
        AZ_VNET_SUBNET="$2"
        shift 2
        continue
    ;;
    '-r'|'--rg-vm')
        AZ_VM_RG="$2"
        shift 2
        continue
    ;;
    '-m'|'--vm-name')
        AZ_VM="$2"
        shift 2
        continue
    ;;
    '-b'|'--lb-name')
        AZ_LB="$2"
        shift 2
        continue
    ;;
    '-d'|'--dns-name')
        AZ_LB_DNS="$2"
        shift 2
        continue
    ;;
    '--ssh-key-file')
        AZ_SSH_KEY_FILE="$2"
        shift 2
        continue
    ;;
    '--ssh-source-prefixes')
        AZ_SSH_SOURCE_PREFIXES="$2"
        shift 2
        continue
    ;;
    '--')
        shift
        break
    ;;
    *)
        usage
        exit 1
    ;;
  esac
done

# Pre-checks
if [[ -z $AZ_SUBSCRIPTION_ID ]]; then
    echo "Error: --subscription is required !"
    usage
    exit 1
fi

if [[ -z $AZ_LOCATION ]]; then
    echo "Error: --location is required !"
    usage
    exit 1
fi

if [[ -z $AZ_SHARED_RG ]]; then
    echo "Error: --rg-vnet is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VNET ]]; then
    echo "Error: --vnet-name is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VNET_SUBNET_NAME ]]; then
    echo "Error: --subnet-name is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VNET_SUBNET ]]; then
    echo "Error: --subnet is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VM_RG ]]; then
    echo "Error: --rg-vm is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VM ]]; then
    echo "Error: --vm-name is required !"
    usage
    exit 1
fi

if [[ -z $AZ_LB ]]; then
    echo "Error: --lb-name is required !"
    usage
    exit 1
fi

if [[ -z $AZ_LB_DNS ]]; then
    echo "Error: --dns-name is required !"
    usage
    exit 1
fi

if [[ ! -r $AZ_SSH_KEY_FILE ]]; then
    echo "Error: SSH public key file is not readable: ${AZ_SSH_KEY_FILE}"
    usage
    exit 1
fi

if [[ -z $AZ_SSH_SOURCE_PREFIXES ]]; then
    echo "Error: --ssh-source-prefixes is required; do not expose SSH to the Internet"
    usage
    exit 1
fi

AZ_SSH_KEY_VALUE="$(<"${AZ_SSH_KEY_FILE}")"

printf "Switch to %s subscription...\\n" "$(az account show --subscription "${AZ_SUBSCRIPTION_ID}"  --query name --output tsv)"
az account set --subscription "${AZ_SUBSCRIPTION_ID}" --output none

if ! az storage account show --subscription "${AZ_SUBSCRIPTION_ID}" --resource-group "${AZ_SHARED_RG}" --name "${AZ_LB_DNS}${AZ_LOCATION}" --output none; then
    printf "Create %s resource group...\\n" "${AZ_SHARED_RG}"
    az group create \
        --location "${AZ_LOCATION}" \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --name "${AZ_SHARED_RG}" \
        --output none

    printf "Create %s%s Storage Account...\\n" "${AZ_LB_DNS}" "${AZ_LOCATION}"
    az storage account create \
        --location "${AZ_LOCATION}" \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --resource-group "${AZ_SHARED_RG}" \
        --name "${AZ_LB_DNS}${AZ_LOCATION}" \
        --https-only true \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        --allow-cross-tenant-replication false \
        --kind StorageV2 \
        --encryption-services blob \
        --access-tier Hot \
        --sku "${AZ_STORAGE_SKU}" \
        --tags "${AZ_TAGS[@]}" \
        --output none

    printf "Awaiting Storage Account creation...\\n"
    sleep 60
fi

if ! az storage container show --subscription "${AZ_SUBSCRIPTION_ID}" --account-name "${AZ_LB_DNS}${AZ_LOCATION}" --name "${AZ_CONTAINER}" --auth-mode login --output none; then
    printf "Create %s blob container...\\n" "${AZ_CONTAINER}"
    az storage container create \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --name "${AZ_CONTAINER}" \
        --account-name "${AZ_LB_DNS}${AZ_LOCATION}" \
        --auth-mode login \
        --public-access "off" \
        --output none

    printf "Create a ReadWriteList policy for %s blob container...\\n" "${AZ_CONTAINER}"
    az storage container policy create \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --container-name "${AZ_CONTAINER}" \
        --account-name "${AZ_LB_DNS}${AZ_LOCATION}" \
        --name "rwl" \
        --auth-mode login \
        --permissions "rwl" \
        --expiry "$(date -u -d "100 years" '+%Y-%m-%dT%H:%MZ')" \
        --start "$(date -u -d "-1 days" '+%Y-%m-%dT%H:%MZ')" \
        --output none

    printf "Generate SAS Token to access the %s blob container...\\n" "${AZ_CONTAINER}"
    sas=$(az storage container generate-sas \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --name "${AZ_CONTAINER}" \
        --account-name "${AZ_LB_DNS}${AZ_LOCATION}" \
        --policy-name "rwl" \
        --auth-mode login \
        --https-only \
        --output tsv)

    printf "Your Storage access key is saved locally.\\n"
    SAS_FILE="${HOME}/${AZ_LB_DNS}${AZ_LOCATION}_${AZ_CONTAINER}_sas.txt"
    umask 077
    printf '%s\\n' "${sas}" > "${SAS_FILE}"
    chmod 600 "${SAS_FILE}"
fi


if ! az network vnet subnet show --subscription "${AZ_SUBSCRIPTION_ID}" --resource-group "${AZ_SHARED_RG}" --vnet-name "${AZ_VNET}" --name "${AZ_VNET_SUBNET_NAME}" --output none; then
    printf "Create a new 10.1.0.0/16 VNET named %s...\\n" "${AZ_VNET}"
    az network vnet create \
        --location "${AZ_LOCATION}" \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --resource-group "${AZ_SHARED_RG}" \
        --name "${AZ_VNET}" \
        --address-prefix "10.1.0.0/16" \
        --output none

    printf "Create a new %s subnet named %s...\\n" "${AZ_VNET_SUBNET}" "${AZ_VNET_SUBNET_NAME}"
    az network vnet subnet create \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --resource-group "${AZ_SHARED_RG}" \
        --vnet-name "${AZ_VNET}" \
        --name "${AZ_VNET_SUBNET_NAME}" \
        --address-prefix "${AZ_VNET_SUBNET}" \
        --output none
fi

printf "Create %s resource group...\\n" "${AZ_VM_RG}"
az group create \
    --location "${AZ_LOCATION}" \
    --subscription "${AZ_SUBSCRIPTION_ID}" \
    --name "${AZ_VM_RG}" \
    --tags "${AZ_TAGS[@]}" \
    --output none

printf "Create NSG %s-nsg...\\n" "${AZ_VM}"
az network nsg create \
    --location "${AZ_LOCATION}" \
    --subscription "${AZ_SUBSCRIPTION_ID}" \
    --name "${AZ_VM}-nsg" \
    --resource-group "${AZ_VM_RG}" \
    --tags "${AZ_TAGS[@]}" \
    --output none

printf "Create NSG rule to allow inbound connections...\\n"
az network nsg rule create \
    --name "AllowSSH" \
    --nsg-name "${AZ_VM}-nsg" \
    --resource-group "${AZ_VM_RG}" \
    --priority "1000" \
    --direction "Inbound" \
    --source-address-prefixes "${AZ_SSH_SOURCE_PREFIXES}" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges "4160" \
    --access "Allow" \
    --protocol "tcp" \
    --description "Allow SSH traffic from the configured source prefixes" \
    --output none

az network nsg rule create \
    --name "AllowValheim" \
    --nsg-name "${AZ_VM}-nsg" \
    --resource-group "${AZ_VM_RG}" \
    --priority "1010" \
    --direction "Inbound" \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges "2456-2457" \
    --access "Allow" \
    --protocol "udp" \
    --description "Allow Valheim traffic from Any" \
    --output none

printf "Create %s.%s.cloudapp.azure.com standard public IP address...\\n" "${AZ_LB_DNS}" "${AZ_LOCATION}"
az network public-ip create \
    --location "${AZ_LOCATION}" \
    --subscription "${AZ_SUBSCRIPTION_ID}" \
    --name "${AZ_LB}-public-ip" \
    --resource-group "${AZ_VM_RG}" \
    --allocation-method "Static" \
    --sku "Standard" \
    --version "IPv4" \
    --ip-tags 'RoutingPreference=Internet' \
    --zone 1 2 3 \
    --dns-name "${AZ_LB_DNS}" \
    --tags "${AZ_TAGS[@]}" \
    --output none

printf "Create NIC...\\n"
az network nic create \
    --location "${AZ_LOCATION}" \
    --subscription "${AZ_SUBSCRIPTION_ID}" \
    --name "${AZ_VM}-nic" \
    --resource-group "${AZ_VM_RG}" \
    --subnet "/subscriptions/${AZ_SUBSCRIPTION_ID}/resourceGroups/${AZ_SHARED_RG}/providers/Microsoft.Network/virtualNetworks/${AZ_VNET}/subnets/${AZ_VNET_SUBNET_NAME}" \
    --public-ip-address "${AZ_LB}-public-ip" \
    --network-security-group "${AZ_VM}-nsg" \
    --accelerated-networking true \
    --tags "${AZ_TAGS[@]}" \
    --output none

printf "Create %s Azure Virtual Machine...\\n" "${AZ_VM}"
az vm create \
    --location "${AZ_LOCATION}" \
    --subscription "${AZ_SUBSCRIPTION_ID}" \
    --name "${AZ_VM}" \
    --resource-group "${AZ_VM_RG}" \
    --image "${AZ_VM_IMAGE}" \
    --size "${AZ_VM_SIZE}" \
    --nics "${AZ_VM}-nic" \
    --storage-sku "${AZ_OS_DISK_SKU}" \
    --admin-username "${AZ_VM_ADMIN_USERNAME}" \
    --ssh-key-value "${AZ_SSH_KEY_VALUE}" \
    --authentication-type ssh \
    --security-type TrustedLaunch \
    --enable-secure-boot true \
    --enable-vtpm true \
    --patch-mode AutomaticByPlatform \
    --enable-agent true \
    --tags "${AZ_TAGS[@]}" \
    --custom-data "./cloudinit.yml" \
    --output none

printf "Done.\\n\\n"
