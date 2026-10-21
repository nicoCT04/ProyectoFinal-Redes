#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Proyecto Final Fase 1 (CC3067 Redes, UVG)
# Crea la red segmentada en Azure y 2 VMs de prueba en la subred Ventas.
# Uso (en Azure Cloud Shell, modo Bash):  bash farmaruta_fase1.sh
# =====================================================================
set -euo pipefail

# ---------- Variables ----------
RG="rg-farmaruta"            # Resource group: "carpeta" que agrupa todo
LOC="mexicocentral"          # Región permitida por la suscripción de estudiante
VNET="vnet-farmaruta"        # Virtual Network (equivale a la red de la empresa)
SIZE="Standard_B2ats_v2"     # VM pequeña disponible en la región
ZONE="1"                     # La zona 3 está restringida para la suscripción
IMAGE="Ubuntu2204"           # Linux: ICMP (ping) permitido por defecto
ADMIN="azureuser"

# ---------- 1. Resource group ----------
echo ">> 1. Creando resource group"
az group create -n "$RG" -l "$LOC" -o table

# ---------- 2. Network Security Groups (uno por subred) ----------
# Las reglas por defecto de un NSG permiten todo el tráfico dentro de la VNet
# (AllowVnetInBound / AllowVnetOutBound). Solo agregamos reglas para aislar
# el Data Center y la red de Visitas.
echo ">> 2. Creando NSGs"
for n in visitas ventas ti datacenter; do
  az network nsg create -g "$RG" -n "nsg-$n" -l "$LOC" -o none
done

# Data Center: solo TI y los propios servidores pueden entrar; el resto de la
# VNet queda bloqueado. Sin la regla 150, Deny-VNet también bloquearía el
# tráfico entre servidores (VirtualNetwork incluye la propia subred).
az network nsg rule create -g "$RG" --nsg-name nsg-datacenter -n Allow-TI \
  --priority 100 --direction Inbound --access Allow --protocol '*' \
  --source-address-prefixes 10.10.0.96/27 --destination-address-prefixes '*' \
  --destination-port-ranges '*' -o none
az network nsg rule create -g "$RG" --nsg-name nsg-datacenter -n Allow-Propia-Subred \
  --priority 150 --direction Inbound --access Allow --protocol '*' \
  --source-address-prefixes 10.10.0.128/28 --destination-address-prefixes '*' \
  --destination-port-ranges '*' -o none
az network nsg rule create -g "$RG" --nsg-name nsg-datacenter -n Deny-VNet \
  --priority 200 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes VirtualNetwork --destination-address-prefixes '*' \
  --destination-port-ranges '*' -o none

# Visitas: puede hablar dentro de su propia subred, pero no con las redes internas
az network nsg rule create -g "$RG" --nsg-name nsg-visitas -n Allow-Propia-Subred \
  --priority 100 --direction Outbound --access Allow --protocol '*' \
  --source-address-prefixes '*' --destination-address-prefixes 10.10.0.0/26 \
  --destination-port-ranges '*' -o none
az network nsg rule create -g "$RG" --nsg-name nsg-visitas -n Deny-Internas \
  --priority 200 --direction Outbound --access Deny --protocol '*' \
  --source-address-prefixes '*' --destination-address-prefixes VirtualNetwork \
  --destination-port-ranges '*' -o none

# ---------- 3. VNet y subredes (VLSM, de mayor a menor) ----------
echo ">> 3. Creando VNet y subredes"
az network vnet create -g "$RG" -n "$VNET" -l "$LOC" \
  --address-prefixes 10.10.0.0/16 -o none

az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-visitas \
  --address-prefixes 10.10.0.0/26   --network-security-group nsg-visitas   -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-ventas \
  --address-prefixes 10.10.0.64/27  --network-security-group nsg-ventas    -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-ti \
  --address-prefixes 10.10.0.96/27  --network-security-group nsg-ti        -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-datacenter \
  --address-prefixes 10.10.0.128/28 --network-security-group nsg-datacenter -o none

az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
  --query "[].{Subred:name, Prefijo:addressPrefix}" -o table

# ---------- 4. VMs de prueba en Ventas ----------
# Sin IP pública (no hace falta y ahorra créditos). La primera IP usable de
# una subred en Azure es la .4 del bloque (las 4 primeras están reservadas):
# Ventas = 10.10.0.64/27 -> primeras usables 10.10.0.68 y 10.10.0.69
echo ">> 4. Creando VMs (tarda unos minutos)"
for i in 1 2; do
  az vm create -g "$RG" -n "vm-ventas-0$i" -l "$LOC" \
    --image "$IMAGE" --size "$SIZE" --zone "$ZONE" \
    --vnet-name "$VNET" --subnet snet-ventas \
    --private-ip-address "10.10.0.$((67 + i))" \
    --public-ip-address "" --nsg "" \
    --admin-username "$ADMIN" --generate-ssh-keys -o table
done

# ---------- 5. Prueba de conectividad ----------
# run-command ejecuta el ping DENTRO de la VM sin necesitar SSH ni IP pública
echo ">> 5. Ping de vm-ventas-01 (10.10.0.68) a vm-ventas-02 (10.10.0.69)"
az vm run-command invoke -g "$RG" -n vm-ventas-01 \
  --command-id RunShellScript --scripts "hostname -I; ping -c 4 10.10.0.69" \
  --query "value[0].message" -o tsv

echo ">> Listo. Al terminar las capturas, corre: bash limpiar.sh"
