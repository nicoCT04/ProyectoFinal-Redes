#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2 / Paso 5: DNS interno con BIND9 (vm-dns 10.10.0.132)
#
# La configuracion se hizo a mano por SSH (saltando por vm-ti-01); este
# script reproduce exactamente lo mismo desde Cloud Shell con
# az vm run-command, usando los archivos de config/fase2/dns/.
#
#   farmaruta.local       zona directa  (A, CNAME)
#   0.10.10.in-addr.arpa  zona inversa  (PTR)
#   resto de nombres      forwarder -> DNS de Azure (168.63.129.16)
#
# Uso (desde config/fase2/ en Cloud Shell):
#   bash 05_dns.sh instalar   instala BIND9 y copia la configuracion en vm-dns
#   bash 05_dns.sh red        la VNet anuncia 10.10.0.132 por DHCP y reinicia clientes
#   bash 05_dns.sh probar     consultas de prueba desde vm-ventas-01 y vm-visitas-01
#   bash 05_dns.sh            las tres cosas en orden
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
source 00_variables.sh

VM_DNS="vm-dns"
ARCHIVOS=(named.conf.options named.conf.local db.farmaruta.local db.10.10.0)

# correr <vm> <script>: ejecuta un script dentro de la VM y muestra su salida
correr() {
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
    --scripts "$2" --query "value[0].message" -o tsv
}

instalar() {
  echo ">> Instalando BIND9 en $VM_DNS ($IP_DNS)"
  # Los archivos viajan en base64 para no pelear con comillas ni saltos de linea
  local copiar=""
  for f in "${ARCHIVOS[@]}"; do
    copiar+="echo '$(base64 -w0 "dns/$f")' | base64 -d > /etc/bind/$f"$'\n'
  done
  correr "$VM_DNS" "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -q && apt-get install -y -q bind9 bind9utils dnsutils
$copiar
chown root:bind /etc/bind/named.conf.* /etc/bind/db.*
chmod 644 /etc/bind/named.conf.* /etc/bind/db.*
named-checkconf
named-checkzone farmaruta.local /etc/bind/db.farmaruta.local
named-checkzone 0.10.10.in-addr.arpa /etc/bind/db.10.10.0
systemctl enable named
systemctl restart named
systemctl is-active named
ss -ulnp | grep ':53 '
dig +short @127.0.0.1 rrhh.farmaruta.local
"
}

red() {
  echo ">> La VNet anuncia $IP_DNS como servidor DNS (DHCP de Azure)"
  az network vnet update -g "$RG" -n "$VNET" --dns-servers "$IP_DNS" \
    --query "dhcpOptions.dnsServers" -o tsv
  # Visitas y DMZ tienen 168.63.129.16 fijo en su NIC (03_vms.sh): la NIC manda
  # sobre la VNet, asi que no cambian. Los demas renuevan DHCP al reiniciar.
  for vm in vm-ventas-01 vm-ti-01 vm-intranet; do
    echo "   reiniciando $vm"
    az vm restart -g "$RG" -n "$vm" --no-wait -o none || echo "   ($vm no existe, se omite)"
  done
  echo "   esperar ~1 minuto antes de probar"
}

probar() {
  echo ">> Desde vm-ventas-01 (debe resolver todo)"
  correr vm-ventas-01 "
resolvectl dns eth0
echo '--- nslookup rrhh.farmaruta.local';  nslookup rrhh.farmaruta.local
echo '--- nslookup intranet.farmaruta.local (CNAME)'; nslookup intranet.farmaruta.local
echo '--- nslookup 10.10.0.133 (inversa)'; nslookup 10.10.0.133
echo '--- nslookup google.com (forwarder)'; nslookup google.com
"
  echo ">> Desde vm-visitas-01 (debe dar timeout: el NSG bloquea el puerto 53)"
  correr vm-visitas-01 "
echo '--- nslookup rrhh.farmaruta.local 10.10.0.132'
nslookup -timeout=3 -retry=1 rrhh.farmaruta.local 10.10.0.132 || true
"
}

case "${1:-todo}" in
  instalar) instalar ;;
  red)      red ;;
  probar)   probar ;;
  todo)     instalar; red; echo ">> Esperando 90 s a que reinicien"; sleep 90; probar ;;
  *) echo "Uso: bash 05_dns.sh [instalar|red|probar]"; exit 1 ;;
esac
