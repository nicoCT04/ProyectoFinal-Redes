#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2 / Paso 8: hardening de todas las VMs (ufw + SSH + servicios)
#
# El hardening se aplico a mano por SSH (saltando por vm-ti-01) con
# hardening/hardening.sh. Este script hace lo mismo desde Cloud Shell con
# az vm run-command, que no depende de SSH: si una regla de ufw dejara a
# alguien afuera, por aqui se puede revisar o corregir.
#
#   VM             rol        ufw (entrada permitida)
#   vm-ti-01       ti         22 (el NSG ya limita a las IPs de los administradores)
#   vm-dns         dns        22 desde TI; 53 udp/tcp desde Ventas, TI y Data Center
#   vm-intranet    intranet   22 desde TI; 80 desde Ventas, TI y Data Center
#   vm-web-dmz     web        22 desde TI; 80 y 443 desde cualquiera
#   vm-ventas-01   cliente    22 desde TI
#   vm-visitas-01  cliente    22 desde TI
#
# Uso (desde config/fase2/ en Cloud Shell):
#   bash 08_hardening.sh aplicar [vm ...]    aplica el hardening (todas si no se indica)
#   bash 08_hardening.sh verificar [vm ...]  ufw, puertos en escucha y sshd de cada VM
#   bash 08_hardening.sh desactivar <vm>     emergencia: apaga ufw en esa VM
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
source 00_variables.sh

TODAS=(vm-ti-01 vm-dns vm-intranet vm-web-dmz vm-ventas-01 vm-visitas-01)

rol() {
  case "$1" in
    vm-ti-01) echo ti ;;
    vm-dns) echo dns ;;
    vm-intranet) echo intranet ;;
    vm-web-dmz) echo web ;;
    vm-ventas-01|vm-visitas-01) echo cliente ;;
    *) echo "VM desconocida: $1" >&2; exit 1 ;;
  esac
}

# correr <vm> <script>: ejecuta un script dentro de la VM y muestra su salida
correr() {
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
    --scripts "$2" --query "value[0].message" -o tsv
}

existe() {
  [ "$(az vm show -g "$RG" -n "$1" -d --query powerState -o tsv 2>/dev/null)" = "VM running" ] \
    || { echo "   $1 no existe o esta apagada, se omite"; return 1; }
}

aplicar() {
  # Los archivos viajan en base64 para no pelear con comillas ni saltos de linea
  local sh conf
  sh=$(base64 -w0 hardening/hardening.sh)
  conf=$(base64 -w0 hardening/sshd_hardening.conf)
  for vm in "$@"; do
    existe "$vm" || continue
    echo ">> Hardening de $vm ($(rol "$vm"))"
    correr "$vm" "
set -e
mkdir -p /tmp/hardening
echo '$sh'   | base64 -d > /tmp/hardening/hardening.sh
echo '$conf' | base64 -d > /tmp/hardening/sshd_hardening.conf
bash /tmp/hardening/hardening.sh $(rol "$vm")
"
  done
}

verificar() {
  for vm in "$@"; do
    existe "$vm" || continue
    echo ">> $vm"
    correr "$vm" "
ufw status numbered
echo '--- puertos en escucha (fuera de loopback)'
ss -tulpn | grep -vE '127\.0\.0\.|\[::1\]|%lo' | awk 'NR==1 {print \"Proto Local Proceso\"; next} {print \$1, \$5, \$7}'
echo '--- sshd'
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|allowtcpforwarding|maxauthtries|allowusers) '
"
  done
}

ACCION="${1:-}"; shift || true
VMS=("$@"); [ ${#VMS[@]} -eq 0 ] && VMS=("${TODAS[@]}")

case "$ACCION" in
  aplicar)    aplicar "${VMS[@]}" ;;
  verificar)  verificar "${VMS[@]}" ;;
  desactivar) [ $# -eq 1 ] || { echo "Uso: bash 08_hardening.sh desactivar <vm>"; exit 1; }
              correr "$1" "ufw disable; ufw status" ;;
  *) echo "Uso: bash 08_hardening.sh [aplicar|verificar|desactivar] [vm ...]"; exit 1 ;;
esac
