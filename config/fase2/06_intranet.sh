#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2 / Paso 6: Intranet de RRHH con nginx (vm-intranet 10.10.0.133)
#
# La configuracion se hizo a mano por SSH (saltando por vm-ti-01); este
# script reproduce exactamente lo mismo desde Cloud Shell con
# az vm run-command, usando los archivos de config/fase2/intranet/.
#
#   http://rrhh.farmaruta.local      sitio de RRHH (pagina estatica)
#   http://intranet.farmaruta.local  alias (CNAME en el DNS interno)
#   Accesible: Ventas, TI, Data Center.  Bloqueado: Visitas, DMZ, Internet.
#
# Uso (desde config/fase2/ en Cloud Shell):
#   bash 06_intranet.sh instalar   instala nginx, copia la pagina y el sitio
#   bash 06_intranet.sh probar     pruebas desde ventas, ti y visitas + IP publica
#   bash 06_intranet.sh            las dos cosas en orden
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
source 00_variables.sh

VM_INTRANET="vm-intranet"

# correr <vm> <script>: ejecuta un script dentro de la VM y muestra su salida
correr() {
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
    --scripts "$2" --query "value[0].message" -o tsv
}

instalar() {
  echo ">> Instalando nginx en $VM_INTRANET ($IP_INTRANET)"
  # Los archivos viajan en base64 para no pelear con comillas ni saltos de linea
  local html conf
  html=$(base64 -w0 intranet/index.html)
  conf=$(base64 -w0 intranet/rrhh.conf)
  correr "$VM_INTRANET" "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -q && apt-get install -y -q nginx
mkdir -p /var/www/rrhh
echo '$html' | base64 -d > /var/www/rrhh/index.html
echo '$conf' | base64 -d > /etc/nginx/sites-available/rrhh
chown -R www-data:www-data /var/www/rrhh
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/rrhh /etc/nginx/sites-enabled/rrhh
nginx -t
systemctl enable nginx
systemctl reload nginx || systemctl restart nginx
systemctl is-active nginx
ss -tlnp | grep ':80 '
curl -s -o /dev/null -w 'local: HTTP %{http_code}\n' -H 'Host: rrhh.farmaruta.local' http://$IP_INTRANET
"
}

probar() {
  echo ">> Desde vm-ventas-01 (debe devolver el HTML)"
  correr vm-ventas-01 "
echo '--- curl http://rrhh.farmaruta.local'
curl -s -m 5 http://rrhh.farmaruta.local | grep -o '<title>.*</title>'
echo '--- curl http://intranet.farmaruta.local (alias)'
curl -s -m 5 -o /dev/null -w 'HTTP %{http_code}\n' http://intranet.farmaruta.local
"
  echo ">> Desde vm-ti-01 (debe devolver el HTML)"
  correr vm-ti-01 "
curl -s -m 5 http://rrhh.farmaruta.local | grep -o '<title>.*</title>'
"
  echo ">> Desde vm-visitas-01 (debe dar timeout: el NSG bloquea)"
  correr vm-visitas-01 "
curl -m 5 http://$IP_INTRANET || echo 'BLOQUEADO (timeout)'
"
  echo ">> IP publica de $VM_INTRANET (debe salir vacio: no existe desde internet)"
  az vm list-ip-addresses -g "$RG" -n "$VM_INTRANET" \
    --query "[0].virtualMachine.network.{privada:privateIpAddresses[0], publica:publicIpAddresses[0].ipAddress}" -o table
}

case "${1:-todo}" in
  instalar) instalar ;;
  probar)   probar ;;
  todo)     instalar; probar ;;
  *) echo "Uso: bash 06_intranet.sh [instalar|probar]"; exit 1 ;;
esac
