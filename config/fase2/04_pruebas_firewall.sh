#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2 / Paso 4: pruebas del firewall entre subredes
#
# Desde cada VM de prueba intenta llegar a las demas subredes y a internet.
# Los comandos corren DENTRO de la VM con az vm run-command (no hace falta SSH).
#
# Resultado por prueba:
#   ABIERTO    la conexion TCP se establecio (hay servicio escuchando)
#   RECHAZADO  el paquete llego, pero no hay servicio en ese puerto
#   BLOQUEADO  no hubo respuesta: el NSG descarto el paquete
#   OK         ping o internet respondieron
#
# Uso:  bash 04_pruebas_firewall.sh                 desde todas
#       bash 04_pruebas_firewall.sh vm-visitas-01   desde una sola
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
source 00_variables.sh

read -r -d '' PRUEBAS <<EOF || true
probar() {
  if [ "\$3" = icmp ]; then
    ping -c 2 -W 2 "\$2" >/dev/null 2>&1 && r=OK || r=BLOQUEADO
  else
    timeout 3 bash -c "</dev/tcp/\$2/\$3" 2>/dev/null; c=\$?
    case \$c in 0) r=ABIERTO ;; 124) r=BLOQUEADO ;; *) r=RECHAZADO ;; esac
  fi
  printf '%-26s %-20s %s\n' "\$1" "\$2:\$3" "\$r"
}
echo "Origen: \$(hostname) \$(hostname -I)"
printf '%-26s %-20s %s\n' DESTINO IP:PUERTO RESULTADO
probar "TI (ping)"                $IP_TI_01     icmp
probar "TI (SSH)"                 $IP_TI_01     22
probar "Ventas (ping)"            $IP_VENTAS_01 icmp
probar "Visitas (ping)"           $IP_VISITAS_01 icmp
probar "DNS interno (TCP 53)"     $IP_DNS       53
probar "Intranet RRHH (HTTP)"     $IP_INTRANET  80
probar "Intranet RRHH (SSH)"      $IP_INTRANET  22
probar "Web DMZ privada (HTTP)"   $IP_WEB_DMZ   80
if curl -s -o /dev/null -m 5 http://example.com; then r=OK; else r=BLOQUEADO; fi
printf '%-26s %-20s %s\n' "Internet" "example.com:80" "\$r"
if command -v nslookup >/dev/null; then
  echo; echo "nslookup rrhh.farmaruta.local:"; nslookup -timeout=3 rrhh.farmaruta.local 2>&1 | tail -n 3
fi
EOF

ORIGENES=("$@")
[ ${#ORIGENES[@]} -eq 0 ] && ORIGENES=(vm-visitas-01 vm-ventas-01 vm-ti-01 vm-web-dmz)

for vm in "${ORIGENES[@]}"; do
  echo
  echo "================ Desde $vm ================"
  az vm run-command invoke -g "$RG" -n "$vm" --command-id RunShellScript \
    --scripts "$PRUEBAS" --query "value[0].message" -o tsv \
    | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
done

cat <<'EOF'

Resultado esperado (antes del hardening con ufw):
  Origen    TI     Ventas  Visitas  DNS:53  Intranet:80  DMZ:80  Internet
  Visitas   BLOQ   BLOQ    OK       BLOQ    BLOQ         BLOQ    OK
  Ventas    BLOQ   OK      OK       ABIERTO ABIERTO      BLOQ    OK
  TI        OK     OK      OK       ABIERTO ABIERTO      ABIERTO OK
  DMZ       BLOQ   BLOQ    BLOQ     BLOQ    BLOQ         -       OK
EOF
