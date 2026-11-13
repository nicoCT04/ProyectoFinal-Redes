#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2 / Paso 2: Firewall y ACLs con Network Security Groups
#
# Los NSG son firewalls stateful asociados a cada subred: si una conexion se
# permite, la respuesta pasa sola. Se evaluan de menor a mayor prioridad y
# gana la primera regla que coincide. Usamos 4000 para los Deny generales,
# asi quedan espacios libres para excepciones (100-3999).
#
# Comportamiento pedido por el enunciado:
#   - Visitas: internet si, redes internas no            -> nsg-visitas (salida)
#   - TI llega a todas; nadie llega a TI                 -> nsg-ti (entrada)
#   - Intranet accesible desde las subredes internas,
#     no desde Visitas ni desde Internet                 -> nsg-datacenter (entrada)
#   - DMZ: publica en 80/443, aislada de la red interna  -> nsg-dmz
#
# Uso:  bash 02_firewall_nsg.sh   (se puede correr varias veces: actualiza)
#       ADMIN_IPS="1.2.3.4" bash 02_firewall_nsg.sh   (ademas abre SSH a vm-ti-01)
# =====================================================================
set -euo pipefail
set -f   # sin globbing: los '*' sin comillas se pasan tal cual a az
cd "$(dirname "$0")"
source 00_variables.sh

# regla <nsg> <nombre> <prioridad> <Inbound|Outbound> <Allow|Deny> <protocolo> <origen> <destino> <puertos> <descripcion>
regla() {
  az network nsg rule create -g "$RG" --nsg-name "$1" -n "$2" \
    --priority "$3" --direction "$4" --access "$5" --protocol "$6" \
    --source-address-prefixes $7 --source-port-ranges '*' \
    --destination-address-prefixes $8 --destination-port-ranges $9 \
    --description "${10}" -o none
  printf '   %-15s %-28s %5s %-8s %-5s\n' "$1" "$2" "$3" "$4" "$5"
}

echo ">> Visitas: solo internet"
regla nsg-visitas Allow-Propia-Subred   100 Outbound Allow '*' '*' "$NET_VISITAS" '*' \
  "Los dispositivos de visitas se ven entre si"
regla nsg-visitas Deny-Redes-Internas  4000 Outbound Deny  '*' '*' VirtualNetwork '*' \
  "Visitas no alcanza ninguna subred interna; internet sigue por AllowInternetOutBound"

echo ">> TI: nadie inicia conexiones hacia TI (salvo SSH de administracion desde internet)"
if [ -n "$ADMIN_IPS" ]; then
  regla nsg-ti Allow-SSH-Admin           90 Inbound  Allow Tcp "$ADMIN_IPS" "$IP_TI_01" 22 \
    "SSH al jump host de TI solo desde las IPs de los administradores"
else
  echo "   (ADMIN_IPS vacio: no se crea Allow-SSH-Admin; nadie entra por SSH desde internet)"
fi
regla nsg-ti Allow-Propia-Subred        100 Inbound  Allow '*' "$NET_TI" '*' '*' \
  "Los equipos de TI se ven entre si"
regla nsg-ti Deny-VNet-hacia-TI        4000 Inbound  Deny  '*' VirtualNetwork '*' '*' \
  "Las demas subredes no tienen conectividad hacia TI"

echo ">> Data Center: TI administra, el resto solo usa DNS e Intranet"
regla nsg-datacenter Allow-TI           100 Inbound  Allow '*' "$NET_TI" '*' '*' \
  "TI tiene conectividad total"
regla nsg-datacenter Allow-Propia-Subred 110 Inbound Allow '*' "$NET_DC" '*' '*' \
  "Los servidores se comunican entre si (intranet -> DNS)"
regla nsg-datacenter Allow-DNS-Interno  120 Inbound  Allow '*' "$NET_VENTAS" "$IP_DNS" 53 \
  "Ventas resuelve nombres con el DNS interno (UDP y TCP 53)"
regla nsg-datacenter Allow-Web-Intranet 130 Inbound  Allow Tcp "$NET_VENTAS" "$IP_INTRANET" '80 443' \
  "Ventas entra a la intranet de RRHH (HTTP y HTTPS)"
regla nsg-datacenter Deny-VNet         4000 Inbound  Deny  '*' VirtualNetwork '*' '*' \
  "Visitas, DMZ y cualquier otro origen interno no llegan al Data Center"
# Internet no llega: los servidores del DC no tienen IP publica y la regla por
# defecto DenyAllInBound bloquea todo lo que no venga de la VNet.

echo ">> DMZ: publica en 80/443, aislada de la red interna"
regla nsg-dmz Allow-Web-Internet        100 Inbound  Allow Tcp Internet '*' '80 443' \
  "Clientes de FarmaRuta entran a la web publica (HTTP y HTTPS)"
regla nsg-dmz Allow-TI                  110 Inbound  Allow '*' "$NET_TI" '*' '*' \
  "TI administra el servidor de la DMZ"
regla nsg-dmz Deny-VNet                4000 Inbound  Deny  '*' VirtualNetwork '*' '*' \
  "Ninguna otra subred interna entra a la DMZ"
regla nsg-dmz Allow-Propia-Subred       100 Outbound Allow '*' '*' "$NET_DMZ" '*' \
  "Servidores de la DMZ entre si"
regla nsg-dmz Deny-DMZ-hacia-Internas  4000 Outbound Deny  '*' '*' VirtualNetwork '*' \
  "DMZ no inicia conexiones hacia la red interna."

# nsg-ventas usa solo las reglas por defecto: Ventas es una red interna normal.

echo ">> Reglas efectivas"
for n in visitas ti datacenter dmz; do
  echo "--- nsg-$n"
  az network nsg rule list -g "$RG" --nsg-name "nsg-$n" \
    --query "sort_by([], &priority)[].{Prioridad:priority, Nombre:name, Dir:direction, Accion:access, Proto:protocol, Origen:sourceAddressPrefix, Destino:destinationAddressPrefix, Puertos:destinationPortRange || join(',', destinationPortRanges)}" \
    -o table
done

echo ">> Listo. Siguiente: bash 03_vms.sh"
