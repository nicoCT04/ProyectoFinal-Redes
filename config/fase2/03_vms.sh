#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2 / Paso 3: maquinas virtuales
#
# Crea las VMs vacias (Ubuntu). Cada integrante instala su servicio encima:
#   vm-dns         10.10.0.132  Data Center  DNS interno (BIND9)
#   vm-intranet    10.10.0.133  Data Center  Intranet RRHH (nginx)
#   vm-web-dmz     10.10.0.148  DMZ          Web publica de Ventas (IP publica)
#   vm-ti-01       10.10.0.100  TI           Jump host de TI (IP publica, SSH)
#   vm-ventas-01   10.10.0.68   Ventas       Cliente de prueba
#   vm-visitas-01  10.10.0.4    Visitas      Cliente de prueba
#
# Todas: Ubuntu 22.04, misma llave SSH (farmaruta-key), disco Standard SSD,
# sin NSG en la NIC (el filtrado lo hace el NSG de la subred) y auto-apagado
# diario a las 23:00 de Guatemala.
#
# Uso:  bash 03_vms.sh                 crea todas
#       bash 03_vms.sh dns intranet    crea solo esas (si no alcanza la cuota)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
source 00_variables.sh

DNS_LABEL="farmaruta-ventas"   # -> farmaruta-ventas.mexicocentral.cloudapp.azure.com

# Llave SSH unica guardada en Azure; la privada queda en ~/.ssh del Cloud Shell
if ! az sshkey show -g "$RG" -n "$SSH_KEY_NAME" -o none 2>/dev/null; then
  echo ">> Creando llave SSH $SSH_KEY_NAME"
  az sshkey create -g "$RG" -n "$SSH_KEY_NAME" -l "$LOC" -o none
fi

# vm <nombre> <subred> <ip> [args extra de az vm create]
vm() {
  local nombre="$1" subred="$2" ip="$3"; shift 3
  if az vm show -g "$RG" -n "$nombre" -o none 2>/dev/null; then
    echo "   $nombre ya existe, se omite"; return
  fi
  echo ">> Creando $nombre ($ip en $subred)"
  az vm create -g "$RG" -n "$nombre" -l "$LOC" \
    --image "$IMAGE" --size "$SIZE" --zone "$ZONE" \
    --vnet-name "$VNET" --subnet "$subred" --private-ip-address "$ip" \
    --nsg "" --admin-username "$ADMIN" --ssh-key-name "$SSH_KEY_NAME" \
    --storage-sku "$DISK_SKU" --os-disk-delete-option Delete --nic-delete-option Delete \
    "$@" --query "{VM:name, IP_privada:privateIpAddress, IP_publica:publicIpAddress, Zona:zones}" -o table
  az vm auto-shutdown -g "$RG" -n "$nombre" --time "$AUTO_SHUTDOWN_UTC" -o none
}

# Visitas y DMZ no pueden llegar al DNS interno (lo bloquean los NSG), asi que
# resuelven nombres con el DNS de Azure configurado directo en su NIC.
usar_dns_azure() {
  az network nic update -g "$RG" -n "${1}VMNic" --dns-servers "$AZURE_DNS" -o none
}

crear() {
  case "$1" in
    dns)      vm vm-dns        snet-datacenter "$IP_DNS"        --public-ip-address "" ;;
    intranet) vm vm-intranet   snet-datacenter "$IP_INTRANET"   --public-ip-address "" ;;
    web)      vm vm-web-dmz    snet-dmz        "$IP_WEB_DMZ" \
                --public-ip-address pip-web-dmz --public-ip-sku Standard \
                --public-ip-address-allocation static --public-ip-address-dns-name "$DNS_LABEL"
              usar_dns_azure vm-web-dmz ;;
    ti)       vm vm-ti-01      snet-ti         "$IP_TI_01" \
                --public-ip-address pip-ti-01 --public-ip-sku Standard \
                --public-ip-address-allocation static ;;
    ventas)   vm vm-ventas-01  snet-ventas     "$IP_VENTAS_01"  --public-ip-address "" ;;
    visitas)  vm vm-visitas-01 snet-visitas    "$IP_VISITAS_01" --public-ip-address ""
              usar_dns_azure vm-visitas-01 ;;
    *) echo "Rol desconocido: $1 (usar: dns intranet web ti ventas visitas)"; exit 1 ;;
  esac
}

ROLES=("$@")
[ ${#ROLES[@]} -eq 0 ] && ROLES=(ti dns intranet web ventas visitas)
for r in "${ROLES[@]}"; do crear "$r"; done

echo ">> VMs en $RG"
az vm list -g "$RG" -d \
  --query "[].{VM:name, Estado:powerState, IP_privada:privateIps, IP_publica:publicIps, FQDN:fqdns}" -o table

cat <<EOF
>> Listo. Para entrar por SSH (desde Cloud Shell):
   ssh $ADMIN@\$(az vm show -d -g $RG -n vm-ti-01 --query publicIps -o tsv)
   ssh -J $ADMIN@<IP_PUBLICA_TI> $ADMIN@$IP_DNS        # saltando por TI
   (requiere la regla Allow-SSH-Admin: ADMIN_IPS="tu.ip" bash 02_firewall_nsg.sh)
>> Siguiente: cada integrante instala su servicio; luego bash 04_pruebas_firewall.sh
EOF
