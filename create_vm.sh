#!/bin/bash

set -eu -o pipefail

PROGNAME="$(basename "$0")"

# Parse arguments
ARGS=$(getopt \
    --options s:l:g:v:n:u:r:m:b:d \
    --longoptions subscription:,location:,rg-vnet:,vnet-name:,subnet-name:,subnet:,rg-vm:,vm-name:,lb-name:,dns-name: \
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
AZ_CONTAINER="backup-001"

while true; do
  case "$1" in
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

# Show usage
usage() {
    printf "usage: %s --subscription=<name> --location=<name> --rg-vnet=<name> --vnet-name=<name> --subnet-name=<name> --subnet=<name> --rg-vm=<name> --vm-name=<name> --lb-name=<name> --dns-name=<name>\\n" "${PROGNAME}"
}

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
        --kind StorageV2 \
        --encryption-services blob \
        --access-tier Hot \
        --sku Standard_LRS \
        --output none

    printf "Awaiting Storage Account creation...\\n"
    sleep 60
fi

if ! az storage container show --subscription "${AZ_SUBSCRIPTION_ID}" --account-name "${AZ_LB_DNS}${AZ_LOCATION}" --name "${AZ_CONTAINER}" --output none; then
    printf "Create %s blob container...\\n" "${AZ_CONTAINER}"
    az storage container create \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --name "${AZ_CONTAINER}" \
        --account-name "${AZ_LB_DNS}${AZ_LOCATION}" \
        --public-access "off" \
        --output none

    printf "Create a ReadWriteList policy for %s blob container...\\n" "${AZ_CONTAINER}"
    az storage container policy create \
        --subscription "${AZ_SUBSCRIPTION_ID}" \
        --container-name "${AZ_CONTAINER}" \
        --account-name "${AZ_LB_DNS}${AZ_LOCATION}" \
        --name "rwl" \
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
        --https-only \
        --output tsv)

    printf "Your Storage access key is: \"%s\"\\n" "${sas}"
    echo "${sas}" > ~/"${AZ_LB_DNS}""${AZ_LOCATION}"_"${AZ_CONTAINER}"_sas.txt
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
    --output none

printf "Create NSG %s-nsg...\\n" "${AZ_VM}"
az network nsg create \
    --location "${AZ_LOCATION}" \
    --subscription "${AZ_SUBSCRIPTION_ID}" \
    --name "${AZ_VM}-nsg" \
    --resource-group "${AZ_VM_RG}" \
    --output none

printf "Create NSG rule to allow inbound connections...\\n"
az network nsg rule create \
    --name "AllowSSH" \
    --nsg-name "${AZ_VM}-nsg" \
    --resource-group "${AZ_VM_RG}" \
    --priority "1000" \
    --direction "Inbound" \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges "4160" \
    --access "Allow" \
    --protocol "tcp" \
    --description "Allow SSH traffic from Any" \
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
    --output none

printf "Create %s Azure Virtual Machine...\\n" "${AZ_VM}"
az vm create \
    --location "${AZ_LOCATION}" \
    --subscription "${AZ_SUBSCRIPTION_ID}" \
    --name "${AZ_VM}" \
    --resource-group "${AZ_VM_RG}" \
    --image "Canonical:0001-com-ubuntu-server-focal:20_04-lts-gen2:latest" \
    --size "Standard_F2s_v2" \
    --nics "${AZ_VM}-nic" \
    --storage-sku "StandardSSD_LRS" \
    --admin-username "yandolfat" \
    --ssh-key-value "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCe0lgCF/ZKiUJnl8gbSQSKvzIiWZM8ZouxUxjmXGJIXvacmZCC/Ou7UvX5JMQFqUcYe63BSGOz93X2r4e17M++JbOR+ShloGS+4+w+wu6MAYaiVIC6/PmhSfyzFXEWuE+dLadNwJMF8ePUXqwYZntRy5Gahu1wYSkqaif3TNsDRCDYcd0viCOEmGN+NYeoNJwGQ9HIWJ29sY/BUZJWEVB0ZweTvNqwtl3bMvY/JHmEmEIYwdRcdROPEPmxcuBH81Tt2fsD9V7DYhyvz2lQPVJD++3jIZX2i9sPQj8SVJbo23xOZZykVIKU7WaztBtPPz3RdytBiyQ8sgNwKLbJX7Vv0+qY1no4xUnKwJPc5zfikje4rYxTksjIRg7igMNrCFGWZA75hb+Nm+HhQsKqVHtOIaw3P6j6slysQQ5MOQYTqg7k60yxTRGTv8Y6V45jrYWQg+vhKO4gzVTKsqrqJTRhJXU3vv//1NPW7ucNlNPCF8n0RyjXue6Y1Xr8rZv5QheLZvcHumd23pA+Z6aRA/Hd2VINy00PQz9dscOpWHpUiiu4HMPHLcLdlhaVMFr2otwB2749xHciZFCsWnprMGX6V3lVGHQ3OFfIBFz1ZVFG+eAbXmZZepdtwVJDidXDfvzAtMol/+PwVVUJgpA1a1dryyZkg9k2FbO1bSVolvmkpQ== Yves ANDOLFATTO" \
    --custom-data "./cloudinit.yml" \
    --output none

printf "Done.\\n\\n"
