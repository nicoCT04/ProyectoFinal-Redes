#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2: apaga y borra todo para no gastar creditos.
# Uso:  bash limpiar_fase2.sh            libera las VMs y pregunta si borrar
#       bash limpiar_fase2.sh --apagar   solo libera las VMs (se retoma luego)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
source 00_variables.sh

if [ "$(az group exists -n "$RG")" != "true" ]; then
  echo "El resource group $RG no existe. Nada que limpiar."
  exit 0
fi

echo ">> Liberando (deallocate) las VMs: dejan de cobrar computo"
VMS=$(az vm list -g "$RG" --query "[].id" -o tsv)
[ -n "$VMS" ] && az vm deallocate --ids $VMS --no-wait

[ "${1:-}" = "--apagar" ] && { echo ">> VMs liberadas. Para retomar: az vm start --ids \$(az vm list -g $RG --query '[].id' -o tsv)"; exit 0; }

echo ">> Recursos en $RG"
az resource list -g "$RG" --query "[].{Nombre:name, Tipo:type}" -o table

read -r -p "¿Borrar TODO el resource group $RG? (s/N) " r
if [[ "$r" == "s" ]]; then
  az group delete -n "$RG" --yes --no-wait
  echo ">> Borrado en curso. Verificar en unos minutos con: az group exists -n $RG"
fi
