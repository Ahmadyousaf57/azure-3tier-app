#!/usr/bin/env bash
set -euo pipefail

# ---- Settings ----
RG="${RG:-rg-3tier-prod}"
LOCATION="${LOCATION:-indiasouthcentral}"   # must be an allowed region for your subscription
VNET="vnet-3tier"
MYSQL_NAME="${MYSQL_NAME:?export MYSQL_NAME=<globally-unique-name>}"
ADMIN_IPS="${ADMIN_IPS:?export ADMIN_IPS='1.2.3.4/32 5.6.7.8/32'}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/azure_3tier}"
if [ -z "${DB_PASSWORD:-}" ]; then read -s -p "DB password: " DB_PASSWORD; echo; fi

# ---- SSH key (created only if missing) ----
[ -f "$SSH_KEY" ] || ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "azure-3tier"

# ---- Resource group + providers ----
az group create -n "$RG" -l "$LOCATION" -o none
az provider register --namespace Microsoft.DBforMySQL --wait

# ---- Network: VNet + 3 subnets ----
az network vnet create -g "$RG" -n "$VNET" --address-prefix 10.0.0.0/16 \
  --subnet-name snet-frontend --subnet-prefix 10.0.1.0/24 -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-backend \
  --address-prefixes 10.0.2.0/24 -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-db \
  --address-prefixes 10.0.3.0/24 --delegations Microsoft.DBforMySQL/flexibleServers -o none

# ---- NSGs ----
for n in frontend backend db; do az network nsg create -g "$RG" -n "nsg-$n" -o none; done

az network nsg rule create -g "$RG" --nsg-name nsg-frontend -n allow-http --priority 100 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes '*' --destination-port-ranges 80 -o none
az network nsg rule create -g "$RG" --nsg-name nsg-frontend -n allow-ssh-admin --priority 110 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes $ADMIN_IPS --destination-port-ranges 22 -o none

az network nsg rule create -g "$RG" --nsg-name nsg-backend -n allow-api-from-frontend --priority 100 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.0.1.0/24 --destination-port-ranges 3000 -o none
az network nsg rule create -g "$RG" --nsg-name nsg-backend -n allow-ssh-from-frontend --priority 110 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.0.1.0/24 --destination-port-ranges 22 -o none

az network nsg rule create -g "$RG" --nsg-name nsg-db -n allow-mysql-from-backend --priority 100 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.0.2.0/24 --destination-port-ranges 3306 -o none

for n in frontend backend db; do
  az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "snet-$n" \
    --network-security-group "nsg-$n" -o none
done

# ---- VMs ----
az vm create -g "$RG" -n vm-frontend --image Ubuntu2204 --size Standard_B1s \
  --vnet-name "$VNET" --subnet snet-frontend --public-ip-sku Standard \
  --admin-username azureuser --ssh-key-values "$SSH_KEY.pub" --nsg "" -o table
az vm create -g "$RG" -n vm-backend --image Ubuntu2204 --size Standard_B1s \
  --vnet-name "$VNET" --subnet snet-backend --public-ip-address "" \
  --admin-username azureuser --ssh-key-values "$SSH_KEY.pub" --nsg "" -o table

# ---- MySQL (private, in snet-db) ----
az mysql flexible-server create -g "$RG" -n "$MYSQL_NAME" -l "$LOCATION" \
  --admin-user dbadmin --admin-password "$DB_PASSWORD" \
  --sku-name Standard_B1ms --tier Burstable --storage-size 20 --version 8.0.21 \
  --vnet "$VNET" --subnet snet-db --database-name appdb --yes -o none

echo "Done. MySQL host: $MYSQL_NAME.mysql.database.azure.com"
echo "Cleanup when finished: az group delete -n $RG --yes --no-wait"
