#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2 / Paso 7: web publica de Ventas en la DMZ (June)
#
# Se corre desde la compu del administrador (no desde Cloud Shell):
#   1. Sube dmz/index.html y dmz/farmaruta.conf a vm-web-dmz, saltando por
#      vm-ti-01 (el puerto 22 de la DMZ no esta abierto a internet).
#   2. Instala nginx, publica el sitio y quita el sitio por defecto.
#   3. Saca el certificado de Let's Encrypt con certbot (reto HTTP-01 por el
#      puerto 80) y activa la redireccion 301 de HTTP a HTTPS.
#   4. Verifica desde afuera: HTTP -> 301 y HTTPS -> 200.
#
# Uso:  bash 07_web_dmz.sh ruta/a/farmaruta-key.pem
# Requiere: la IP del admin en la regla Allow-SSH-Admin de nsg-ti.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

KEY="${1:?Uso: bash 07_web_dmz.sh ruta/a/farmaruta-key.pem}"
TI="azureuser@158.23.161.215"      # vm-ti-01 (jump host)
WEB="azureuser@10.10.0.148"        # vm-web-dmz
DOMINIO="farmaruta-ventas.mexicocentral.cloudapp.azure.com"

# ProxyCommand en vez de -J para que el salto tambien use la llave
SALTO=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o "ProxyCommand=ssh -i '$KEY' -o StrictHostKeyChecking=accept-new -W %h:%p $TI")

echo ">> Subiendo la pagina y el sitio de nginx a vm-web-dmz"
scp "${SALTO[@]}" dmz/index.html dmz/farmaruta.conf "$WEB:/tmp/"

echo ">> Instalando nginx + certbot y publicando el sitio"
ssh "${SALTO[@]}" "$WEB" "sudo DOMINIO=$DOMINIO bash -s" <<'REMOTO'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nginx certbot python3-certbot-nginx

mkdir -p /var/www/farmaruta
install -m 644 /tmp/index.html /var/www/farmaruta/index.html
install -m 644 /tmp/farmaruta.conf /etc/nginx/sites-available/farmaruta
ln -sf /etc/nginx/sites-available/farmaruta /etc/nginx/sites-enabled/farmaruta
rm -f /etc/nginx/sites-enabled/default
# No mostrar la version de nginx en ningun sitio (tambien en el bloque 301 que crea certbot)
sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf

nginx -t
systemctl reload nginx

# --redirect agrega el 301 de HTTP a HTTPS. Sin correo: no se usa ningun dato personal.
certbot --nginx -d "$DOMINIO" --redirect --agree-tos --register-unsafely-without-email -n
systemctl list-timers certbot.timer --no-pager
REMOTO

echo ">> Copia del sitio ya modificado por certbot (para el reporte)"
scp "${SALTO[@]}" "$WEB:/etc/nginx/sites-available/farmaruta" dmz/farmaruta-https.conf

echo ">> Verificacion desde internet"
curl -sI "http://$DOMINIO"  | grep -iE '^HTTP|^Location'
curl -sI "https://$DOMINIO" | head -1
