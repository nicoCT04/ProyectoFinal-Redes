#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2 / Paso 1: red base + DMZ
# Recrea la red de la Fase 1 (se borro con limpiar.sh) y agrega la subred DMZ.
# Uso (Azure Cloud Shell, Bash):  bash 01_red_base.sh
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
source 00_variables.sh

echo ">> 0. Cuota de vCPUs en $LOC (cada $SIZE usa 2 vCPU, la Fase 2 usa 6 VMs)"
az vm list-usage -l "$LOC" \
  --query "[?contains(name.value, 'cores') || contains(name.value, 'Cores')].{Recurso:localName, Uso:currentValue, Limite:limit}" \
  -o table

echo ">> 1. Resource group"
az group create -n "$RG" -l "$LOC" -o table

echo ">> 2. NSGs (uno por subred; las reglas van en 02_firewall_nsg.sh)"
for n in visitas ventas ti datacenter dmz; do
  az network nsg create -g "$RG" -n "nsg-$n" -l "$LOC" -o none
done

echo ">> 3. VNet y subredes"
az network vnet create -g "$RG" -n "$VNET" -l "$LOC" \
  --address-prefixes 10.10.0.0/16 -o none

# --default-outbound-access true: las VMs sin IP publica necesitan salir a
# internet para instalar paquetes (apt) y para que Visitas navegue.
crear_subred() {
  az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$1" \
    --address-prefixes "$2" --network-security-group "$3" \
    --default-outbound-access true -o none
}
crear_subred snet-visitas    "$NET_VISITAS" nsg-visitas
crear_subred snet-ventas     "$NET_VENTAS"  nsg-ventas
crear_subred snet-ti         "$NET_TI"      nsg-ti
crear_subred snet-datacenter "$NET_DC"      nsg-datacenter
crear_subred snet-dmz        "$NET_DMZ"     nsg-dmz

az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
  --query "[].{Subred:name, Prefijo:addressPrefix, NSG:networkSecurityGroup.id}" -o table \
  | sed 's#/subscriptions/.*/networkSecurityGroups/##'

echo ">> Listo. Siguiente: bash 02_firewall_nsg.sh"
