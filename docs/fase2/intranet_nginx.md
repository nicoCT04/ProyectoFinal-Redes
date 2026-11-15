# Intranet de RRHH con nginx (Andrés)

> Sección para el reporte de la Fase 2. Pasar a Word junto con las capturas de `capturas/fase2/intranet/`.

**Tiempo invertido:** 1 hora.

## Qué se implementó

Una intranet de Recursos Humanos en `vm-intranet` (10.10.0.133, subred Data Center 10.10.0.128/28, **sin IP pública**) con **nginx**, que sirve una página HTML estática con avisos, vacaciones, planilla y contactos.

- Se accede por nombre: `http://rrhh.farmaruta.local` o su alias `http://intranet.farmaruta.local` (registro A y CNAME en el DNS interno de Daniela).
- **Accesible** desde Ventas, TI y el Data Center.
- **No accesible** desde Visitas, la DMZ ni internet.

La VM se creó en el portal (Ubuntu 24.04, `Standard_B2ats_v2`, llave `farmaruta-key`, NIC NSG = None, IP privada estática) y se configuró por SSH saltando por el jump host de TI:

```bash
ssh -i farmaruta-key.pem -J azureuser@158.23.161.215 azureuser@10.10.0.133
```

## Archivos de configuración (`config/fase2/intranet/`)

| Archivo | En la VM | Qué contiene |
|---|---|---|
| `rrhh.conf` | `/etc/nginx/sites-available/rrhh` (enlazado en `sites-enabled`) | Sitio de nginx: `listen 10.10.0.133:80`, `server_name rrhh.farmaruta.local intranet.farmaruta.local`, `root /var/www/rrhh`, `allow`/`deny` por subred, `server_tokens off` |
| `index.html` | `/var/www/rrhh/index.html` | Página de RRHH, con el CSS adentro (no depende de internet) |

El sitio por defecto de nginx (`sites-enabled/default`) se eliminó. El script `config/fase2/06_intranet.sh` reproduce toda la instalación y las pruebas desde Cloud Shell.

## Por qué no se llega desde fuera (defensa en profundidad)

| Capa | Qué hace | Bloquea a |
|---|---|---|
| Sin IP pública | La VM no tiene dirección enrutable en internet | Internet |
| NSG `nsg-datacenter` | Solo permite 80/443 desde Ventas (regla 130) y todo desde TI (regla 100); `Deny-VNet` (4000) y `DenyAllInBound` | Visitas, DMZ, internet |
| NSG `nsg-visitas` | Visitas no puede salir hacia `VirtualNetwork` (regla 4000) | Visitas |
| nginx `listen` | Escucha solo en 10.10.0.133 | Otras interfaces |
| nginx `allow`/`deny` | Solo 10.10.0.64/27, 10.10.0.96/27, 10.10.0.128/28 y 127.0.0.1; el resto recibe 403 | Visitas y DMZ, aunque se abriera el NSG por error |

## Problema encontrado: la VM no salía a internet

En el primer intento `apt-get install nginx` falló con `Could not connect to azure.archive.ubuntu.com:80 ... connection timed out`. Las subredes se habían creado en el portal como **subredes privadas** (`defaultOutboundAccess = false`), y una VM sin IP pública en una subred privada no tiene ruta de salida a internet. El script `01_red_base.sh` sí las define con `--default-outbound-access true`.

Solución: se activó el acceso de salida en `snet-datacenter` y se apagó/encendió la VM para que tomara el cambio:

```bash
az network vnet subnet update -g rg-farmaruta --vnet-name vnet-farmaruta -n snet-datacenter --default-outbound-access true
az vm deallocate -g rg-farmaruta -n vm-intranet && az vm start -g rg-farmaruta -n vm-intranet
```

Esto solo permite **salir** (para descargar paquetes); no abre ninguna entrada desde internet: la VM sigue sin IP pública y el NSG sigue con `DenyAllInBound`.

## Pruebas y capturas (`capturas/fase2/intranet/`)

| # | Desde | Comando | Resultado | Captura |
|---|---|---|---|---|
| 1 | vm-intranet | `nginx -t` + `ss -tlnp` | ✅ `test is successful`, escucha solo en `10.10.0.133:80`, `HTTP 200` | `01_nginx_t_instalacion.jpg` |
| 2 | vm-ventas-01 | `nslookup` + `curl http://rrhh.farmaruta.local` y `http://intranet.farmaruta.local` | ✅ el DNS interno resuelve a 10.10.0.133, devuelve el HTML de RRHH con `HTTP 200`; el alias también da `HTTP 200` | `02_curl_desde_ventas.jpg` |
| 3 | vm-ti-01 | `nslookup` + `curl http://rrhh.farmaruta.local` y `http://intranet.farmaruta.local` | ✅ resuelve a 10.10.0.133, HTML de RRHH con `HTTP 200`; el alias también da `HTTP 200` | `03_curl_desde_ti.jpg` |
| 4 | vm-visitas-01 | `curl -m 5 http://10.10.0.133` y `http://rrhh.farmaruta.local` | ✅ bloqueado: por IP da *timeout* (`exit 28`, el NSG descarta el paquete); por nombre ni siquiera resuelve (`exit 6`, Visitas no llega al DNS interno) | `04_curl_desde_visitas_bloqueado.jpg` |
| 5 | Cloud Shell | `az vm list-ip-addresses` | ✅ vm-intranet solo tiene 10.10.0.133, sin IP pública | `05_vm_intranet_sin_ip_publica.jpg` |
| 5b | Portal | vm-intranet → Información general → Redes | ✅ *Dirección IP pública: -*, *Dirección IP privada: 10.10.0.133* | `05b_portal_sin_ip_publica.jpg` |

Las pruebas 2 y 4 se corrieron desde Cloud Shell con `az vm run-command invoke` (lo mismo que hace `bash 06_intranet.sh probar`).
