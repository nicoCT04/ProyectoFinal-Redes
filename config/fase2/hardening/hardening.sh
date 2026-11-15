#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Fase 2: hardening basico de una VM (se corre DENTRO de la VM)
#
#   sudo bash hardening.sh <rol>
#   roles: ti | dns | intranet | web | cliente
#
# Hace tres cosas:
#   1. ufw: default deny de entrada y solo los puertos que el rol necesita,
#      y solo desde las subredes que los usan (segunda capa, ademas del NSG)
#   2. sshd: sin root, sin contrasenas, solo azureuser, menos intentos
#   3. apaga servicios que no se usan en un servidor de Azure
#
# Es idempotente: se puede correr varias veces y deja el mismo resultado.
# =====================================================================
set -euo pipefail

ROL="${1:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"

NET_VENTAS="10.10.0.64/27"
NET_TI="10.10.0.96/27"
NET_DC="10.10.0.128/28"

[ "$(id -u)" -eq 0 ] || { echo "Correr con sudo"; exit 1; }
case "$ROL" in ti|dns|intranet|web|cliente) ;; *)
  echo "Uso: sudo bash hardening.sh <ti|dns|intranet|web|cliente>"; exit 1 ;;
esac

# ---------------------------------------------------------------------
# 1. Firewall del host (ufw)
# ---------------------------------------------------------------------
echo ">> ufw ($ROL)"
command -v ufw >/dev/null || apt-get install -y -q ufw

# Se arranca de cero para que el resultado no dependa de reglas viejas
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw logging low

# SSH primero: si se activa ufw sin esta regla, se pierde el acceso
if [ "$ROL" = ti ]; then
  # Jump host: el NSG (Allow-SSH-Admin) ya filtra por las IPs de los administradores
  ufw allow 22/tcp comment 'SSH admin (filtrado por NSG Allow-SSH-Admin)'
else
  # Al resto solo se entra por SSH desde la subred de TI
  ufw allow from "$NET_TI" to any port 22 proto tcp comment 'SSH solo desde TI'
fi

case "$ROL" in
  dns)
    for net in "$NET_VENTAS" "$NET_TI" "$NET_DC"; do
      ufw allow from "$net" to any port 53 proto udp comment 'DNS interno'
      ufw allow from "$net" to any port 53 proto tcp comment 'DNS interno (TCP)'
    done ;;
  intranet)
    for net in "$NET_VENTAS" "$NET_TI" "$NET_DC"; do
      ufw allow from "$net" to any port 80 proto tcp comment 'Intranet RRHH'
    done ;;
  web)
    # 80 queda abierto: redirige a HTTPS y Let's Encrypt lo usa para renovar (HTTP-01)
    ufw allow 80/tcp  comment 'Web publica HTTP (redirige a HTTPS)'
    ufw allow 443/tcp comment 'Web publica HTTPS'
    ;;
esac

ufw --force enable
ufw status numbered

# ---------------------------------------------------------------------
# 2. SSH
# ---------------------------------------------------------------------
echo ">> sshd"
# En Ubuntu gana el primer valor que se lee, por eso el archivo va con 10-,
# antes que el 50-cloudimg-settings.conf que trae la imagen de Azure.
install -m 644 "$DIR/sshd_hardening.conf" /etc/ssh/sshd_config.d/10-farmaruta-hardening.conf
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/;s/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

if [ "$ROL" = ti ]; then
  # vm-ti-01 es el jump host: ssh -J necesita reenvio TCP para saltar a las demas
  echo "AllowTcpForwarding yes" > /etc/ssh/sshd_config.d/05-farmaruta-jumphost.conf
else
  echo "AllowTcpForwarding no" > /etc/ssh/sshd_config.d/05-farmaruta-jumphost.conf
fi

sshd -t                       # si la configuracion tiene un error, no se reinicia
systemctl restart ssh
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|x11forwarding|allowtcpforwarding|allowagentforwarding|maxauthtries|logingracetime|allowusers) '

# ---------------------------------------------------------------------
# 3. Servicios que no se usan
# ---------------------------------------------------------------------
echo ">> servicios"
# ModemManager: modems 3G/4G       udisks2: montar USB/discos desde escritorio
# fwupd: firmware de hardware fisico multipathd: discos SAN con varias rutas
for s in ModemManager udisks2 fwupd fwupd-refresh.timer multipathd multipathd.socket; do
  if systemctl list-unit-files "$s"* --no-legend 2>/dev/null | grep -q .; then
    systemctl disable --now "$s" >/dev/null 2>&1 && echo "   deshabilitado: $s" || true
  fi
done
# Se dejan: ssh, chrony (hora), systemd-resolved (DNS local), walinuxagent (agente
# de Azure), unattended-upgrades (parches de seguridad) y el servicio del rol.

echo ">> Listo: $(hostname) [$ROL]"
