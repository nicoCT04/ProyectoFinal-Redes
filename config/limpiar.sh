#!/usr/bin/env bash
# Apaga y borra TODO lo creado para FarmaRuta Fase 1, para no gastar créditos.
set -euo pipefail
RG="rg-farmaruta"

echo ">> Liberando (deallocate) las VMs: dejan de cobrar cómputo"
az vm deallocate -g "$RG" -n vm-ventas-01 --no-wait || true
az vm deallocate -g "$RG" -n vm-ventas-02 --no-wait || true

read -r -p "¿Borrar también todo el resource group $RG? (s/N) " r
if [[ "$r" == "s" ]]; then
  az group delete -n "$RG" --yes --no-wait
  echo ">> Borrado en curso (unos minutos). Revisa en el portal que desaparezca."
fi
