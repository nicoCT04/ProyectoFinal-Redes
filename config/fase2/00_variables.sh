#!/usr/bin/env bash
# =====================================================================
# FarmaRuta - Proyecto Final Fase 2 (CC3067 Redes, UVG)
# Variables comunes. Los demas scripts hacen:  source 00_variables.sh
#
# La infraestructura se creo a mano en el portal de Azure (ver capturas del
# reporte). Estos scripts reproducen exactamente la misma configuracion y
# quedan como archivo de configuracion / evidencia.
# =====================================================================

RG="rg-farmaruta"
LOC="mexicocentral"
VNET="vnet-farmaruta"
# Azure for Students: 6 vCPU por region, y las VMs apagadas (deallocated) TAMBIEN
# cuentan. Con 6 VMs de 2 vCPU no alcanza, asi que los servidores van en B1s
# (1 vCPU, 1 GiB; familia BS, limite 4 vCPU) y los clientes de prueba en B2ats_v2.
#   ti, dns, intranet, web  B1s       4 vCPU  (BS 4/4)
#   ventas                  B2ats_v2  Spot: cuota aparte "Low-priority" (2/3)
#   visitas                 B2ats_v2  2 vCPU  -> total regional 6/6
SIZE_SRV="Standard_B1s"      # Servidores y jump host
SIZE="Standard_B2ats_v2"     # Clientes de prueba. Si falla por capacidad, probar otra zona
ZONE="2"                     # En la Fase 1 la zona 1 se quedo sin capacidad
ZONE_ALT="3"                 # B2ats_v2 se quedo sin capacidad en la zona 2 (vm-visitas-01)
IMAGE="Ubuntu2404"           # Imagen oficial de Canonical (gratuita)
ADMIN="azureuser"
SSH_KEY_NAME="farmaruta-key"   # Una sola llave SSH para todas las VMs
DISK_SKU="StandardSSD_LRS"     # Mas barato que Premium y suficiente
AUTO_SHUTDOWN_UTC="0500"       # 23:00 GT. Mexico Central NO soporta auto-shutdown: apagar a mano

# IPs publicas desde las que se permite SSH a vm-ti-01 (jump host de TI).
# Ej: ADMIN_IPS="190.56.10.20 181.174.5.7"  (vacio = no se crea la regla)
ADMIN_IPS="${ADMIN_IPS:-}"

# ---------- Subredes (VLSM sobre 10.10.0.0/24) ----------
NET_VISITAS="10.10.0.0/26"
NET_VENTAS="10.10.0.64/27"
NET_TI="10.10.0.96/27"
NET_DC="10.10.0.128/28"
NET_DMZ="10.10.0.144/28"     # Nueva en Fase 2: primer bloque libre despues del DC

# ---------- IPs fijas ----------
# Azure reserva las 4 primeras IPs y la ultima de cada subred
IP_VISITAS_01="10.10.0.4"
IP_VENTAS_01="10.10.0.68"
IP_TI_01="10.10.0.100"
IP_DNS="10.10.0.132"         # Servidor DNS interno (BIND9)
IP_INTRANET="10.10.0.133"    # Intranet de RRHH (rrhh.farmaruta.local)
IP_WEB_DMZ="10.10.0.148"     # Web publica de Ventas (DMZ)

# DNS de la plataforma Azure (para las VMs que no usan el DNS interno)
AZURE_DNS="168.63.129.16"
