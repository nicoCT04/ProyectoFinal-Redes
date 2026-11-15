# DNS interno con BIND9 (Daniela)

> Sección para el reporte de la Fase 2. Pasar a Word junto con las capturas de `capturas/fase2/dns/`.

## Qué se implementó

Un servidor DNS interno en `vm-dns` (10.10.0.132 estática, subred Data Center 10.10.0.128/28, sin IP pública, Ubuntu 24.04, `Standard_B1s`) con **BIND9** (Berkeley Internet Name Domain), el servidor DNS más usado en Linux. El servidor cumple dos papeles:

- **Autoritativo** para la zona privada `farmaruta.local` y para su zona inversa `0.10.10.in-addr.arpa`: él es la fuente oficial de esos nombres.
- **Recursivo con forwarder** para todo lo demás (google.com, ubuntu.com…): no resuelve desde la raíz, sino que reenvía la consulta al DNS de la plataforma Azure (168.63.129.16).

Las VMs internas lo usan sin configurar nada a mano: la VNet `vnet-farmaruta` anuncia `10.10.0.132` como servidor DNS por el **DHCP de Azure**. Visitas y DMZ tienen 168.63.129.16 fijo en su NIC, porque el firewall no las deja llegar al DNS interno.

La VM se creó en el portal con tamaño `Standard_B1s` (1 vCPU, 1 GiB) en vez de `Standard_B2ats_v2`: la suscripción Azure for Students tiene un límite de 6 vCPUs por región y ya quedaba solo 1 libre. A BIND9 le sobra con eso. No tiene IP pública ni NSG en la NIC: el filtrado lo hace `nsg-datacenter` a nivel de subred, y se administra por SSH saltando por `vm-ti-01`.

## Archivos de configuración (`config/fase2/dns/`)

| Archivo | Qué contiene |
|---|---|
| `named.conf.options` | Opciones globales: escucha solo en 10.10.0.132 y 127.0.0.1, ACL `internas`, `allow-query` y `allow-recursion` solo para las redes internas, `allow-transfer { none; }`, forwarder 168.63.129.16 |
| `named.conf.local` | Declara las dos zonas de tipo `master` y el archivo de cada una |
| `db.farmaruta.local` | Zona directa: SOA, NS, registros A y CNAME |
| `db.10.10.0` | Zona inversa: SOA, NS y registros PTR |
| `resolved-farmaruta.conf` | Cliente: `/etc/systemd/resolved.conf.d/farmaruta.conf` en ventas, TI e intranet |

El script `config/fase2/05_dns.sh` reproduce toda la instalación desde Cloud Shell.

### ACL de BIND

| Red | Prefijo | ¿Puede consultar? |
|---|---|---|
| Ventas | 10.10.0.64/27 | Sí |
| TI | 10.10.0.96/27 | Sí |
| Data Center | 10.10.0.128/28 | Sí |
| Loopback | 127.0.0.1 | Sí |
| Visitas | 10.10.0.0/26 | No (también la bloquea el NSG) |
| DMZ | 10.10.0.144/28 | No (también la bloquea el NSG) |

Es defensa en profundidad: aunque alguien abriera el NSG por error, BIND seguiría rechazando las consultas. Limitar la recursión a las redes internas evita que el servidor sea un *open resolver*, que se usa en ataques de amplificación DNS.

## Tabla de registros

### Zona directa `farmaruta.local`

| Nombre | Tipo | Valor | Uso |
|---|---|---|---|
| `@` | SOA | `ns1.farmaruta.local. admin.farmaruta.local.` serial `2026111401` | Autoridad de la zona |
| `@` | NS | `ns1.farmaruta.local.` | Servidor de nombres de la zona |
| `ns1` | A | 10.10.0.132 | Servidor DNS |
| `dns` | A | 10.10.0.132 | Servidor DNS (nombre corto) |
| `rrhh` | A | 10.10.0.133 | Intranet de Recursos Humanos |
| `ti01` | A | 10.10.0.100 | Estación de TI (jump host) |
| `ventas01` | A | 10.10.0.68 | Estación de Ventas |
| `intranet` | CNAME | `rrhh` | Alias de la intranet |

### Zona inversa `0.10.10.in-addr.arpa`

| IP | Tipo | Nombre |
|---|---|---|
| 10.10.0.132 | PTR | `ns1.farmaruta.local.` |
| 10.10.0.133 | PTR | `rrhh.farmaruta.local.` |
| 10.10.0.100 | PTR | `ti01.farmaruta.local.` |
| 10.10.0.68 | PTR | `ventas01.farmaruta.local.` |

### Valores del SOA

| Campo | Valor | Significado |
|---|---|---|
| Serial | 2026111401 | Fecha + número de cambio (AAAAMMDDnn). Se aumenta en cada edición |
| Refresh | 3600 s | Cada cuánto un secundario revisa el serial |
| Retry | 900 s | Reintento si falla el refresh |
| Expire | 604800 s | Un secundario deja de responder tras 1 semana sin contactar al primario |
| TTL negativo | 300 s | Cuánto se recuerda una respuesta "no existe" (NXDOMAIN) |

### Problema encontrado: `.local` y systemd-resolved

Después de que la VNet anunció 10.10.0.132, `nslookup rrhh.farmaruta.local` en las VMs devolvía `SERVFAIL` y `resolvectl` decía *"No appropriate name servers or networks for name found"*, aunque `nslookup rrhh.farmaruta.local 10.10.0.132` sí funcionaba. El resolver de Ubuntu (`systemd-resolved`) reserva el sufijo `.local` para **Multicast DNS** (mDNS, RFC 6762) y no lo manda al DNS normal. Se resolvió con un **dominio de enrutamiento** (`Domains=~farmaruta.local`) que le indica que esos nombres, y la zona inversa, se pregunten a 10.10.0.132. En una red real se elegiría un dominio que no termine en `.local` (por ejemplo `corp.farmaruta.com`) para evitar este conflicto.

## Consideraciones de firewall (NSG)

- `nsg-datacenter` regla **Allow-DNS-Interno** (prioridad 120): permite UDP y TCP 53 desde Ventas hacia 10.10.0.132. TI entra por **Allow-TI** (100) y la intranet por **Allow-Propia-Subred** (110).
- **Deny-VNet** (4000) bloquea a Visitas y DMZ: por eso su consulta da *timeout* (el paquete se descarta, no hay respuesta).
- El DNS usa el puerto **53**: UDP para consultas normales y TCP para respuestas grandes y transferencias de zona.

## Capturas

Todas en `capturas/fase2/dns/`.

| Archivo | Qué muestra | Resultado |
|---|---|---|
| `01`–`03_vm_dns_review_*.png` | Resumen de creación de vm-dns | B1s, Ubuntu 24.04, snet-datacenter, sin IP pública ni NSG en la NIC |
| `04_vm_dns_deployment_completo.png` | Deployment | Completado |
| `05_vm_dns_overview_ip_132.png` | Overview de la VM | Running, IP privada 10.10.0.132 |
| `06_vm_dns_nsg_datacenter_regla_dns.png` | Reglas efectivas sobre la NIC | Allow-DNS-Interno (120): 53 desde Ventas |
| `07_vm_dns_ip_estatica.png` | IP configurations | 10.10.0.132 (Static) |
| `10_vnet_dns_custom_10.10.0.132.png` | VNet → DNS servers | Custom 10.10.0.132 (DHCP) |
| `13_ssh_vm_dns_por_jump_host.png` | SSH saltando por vm-ti-01 | Acceso a vm-dns |
| `14_vm_dns_named_checkzone_ok.png` | `named-checkconf` y `named-checkzone` | OK en ambas zonas |
| `15_vm_dns_named_activo_puerto_53.png` | `systemctl status named` y `ss` | active (running), 10.10.0.132:53 UDP/TCP |
| `16_vm_dns_zona_directa.png` | `db.farmaruta.local` | SOA, NS, A y CNAME |
| `17_vm_dns_acl_y_forwarder.png` | `named.conf.options` | ACL internas, recursión limitada, forwarder |
| `18_ventas_nslookup_rrhh.png` | `nslookup rrhh.farmaruta.local` desde vm-ventas-01 | 10.10.0.133 |
| `19_ventas_nslookup_cname_y_ptr.png` | `intranet` (CNAME) y `nslookup 10.10.0.133` (PTR) | rrhh.farmaruta.local |
| `20_ventas_nslookup_google_forwarder.png` | `nslookup google.com` desde vm-ventas-01 | Resuelve gracias al forwarder |
| `21_visitas_nslookup_timeout.png` | `nslookup rrhh.farmaruta.local 10.10.0.132` desde vm-visitas-01 | Timeout: el NSG bloquea el puerto 53 |

Salidas completas en texto: `08_*` (validación y arranque), `09_*` (consulta directa antes del cambio de la VNet), `11_*` (pruebas finales desde ventas) y `12_*` (bloqueo desde visitas).

## Tiempo de implementación

Estimado a partir de las marcas de tiempo del portal y de las VMs (15/11/2026, hora de Guatemala).

| Tarea | Tiempo |
|---|---|
| Preparar los archivos de configuración (`named.conf.*`, zonas) y el script `05_dns.sh` | 25 min |
| Crear vm-dns en el portal (incluye cambiar a `Standard_B1s` por la cuota de vCPUs) y fijar la IP 10.10.0.132 | 35 min |
| Acceso SSH por jump host (agregar el rango de IP a `Allow-SSH-Admin`) | 10 min |
| Instalar BIND9, copiar la configuración, validar y arrancar `named` | 10 min |
| Configurar el DNS de la VNet, reiniciar VMs y corregir `.local` en systemd-resolved | 15 min |
| Pruebas y capturas | 15 min |
| **Total** | **1 h 50 min** |
