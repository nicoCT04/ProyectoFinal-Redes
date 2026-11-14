# DNS interno con BIND9 (Daniela)

> Sección para el reporte de la Fase 2. Pasar a Word junto con las capturas de `capturas/fase2/dns/`.

## Qué se implementó

Un servidor DNS interno en `vm-dns` (10.10.0.132, subred Data Center 10.10.0.128/28, sin IP pública) con **BIND9** (Berkeley Internet Name Domain), el servidor DNS más usado en Linux. El servidor cumple dos papeles:

- **Autoritativo** para la zona privada `farmaruta.local` y para su zona inversa `0.10.10.in-addr.arpa`: él es la fuente oficial de esos nombres.
- **Recursivo con forwarder** para todo lo demás (google.com, ubuntu.com…): no resuelve desde la raíz, sino que reenvía la consulta al DNS de la plataforma Azure (168.63.129.16).

Las VMs internas lo usan sin configurar nada a mano: la VNet `vnet-farmaruta` anuncia `10.10.0.132` como servidor DNS por el **DHCP de Azure**. Visitas y DMZ tienen 168.63.129.16 fijo en su NIC, porque el firewall no las deja llegar al DNS interno.

## Archivos de configuración (`config/fase2/dns/`)

| Archivo | Qué contiene |
|---|---|
| `named.conf.options` | Opciones globales: escucha solo en 10.10.0.132 y 127.0.0.1, ACL `internas`, `allow-query` y `allow-recursion` solo para las redes internas, `allow-transfer { none; }`, forwarder 168.63.129.16 |
| `named.conf.local` | Declara las dos zonas de tipo `master` y el archivo de cada una |
| `db.farmaruta.local` | Zona directa: SOA, NS, registros A y CNAME |
| `db.10.10.0` | Zona inversa: SOA, NS y registros PTR |

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

## Consideraciones de firewall (NSG)

- `nsg-datacenter` regla **Allow-DNS-Interno** (prioridad 120): permite UDP y TCP 53 desde Ventas hacia 10.10.0.132. TI entra por **Allow-TI** (100) y la intranet por **Allow-Propia-Subred** (110).
- **Deny-VNet** (4000) bloquea a Visitas y DMZ: por eso su consulta da *timeout* (el paquete se descarta, no hay respuesta).
- El DNS usa el puerto **53**: UDP para consultas normales y TCP para respuestas grandes y transferencias de zona.

## Capturas

| # | Captura | Resultado esperado |
|---|---|---|
| 1 | `named-checkconf` y `named-checkzone` en vm-dns | `OK` en ambas zonas |
| 2 | `systemctl status named` | `active (running)` |
| 3 | `nslookup rrhh.farmaruta.local` desde vm-ventas-01 | `10.10.0.133`, servidor 10.10.0.132 |
| 4 | `nslookup intranet.farmaruta.local` desde vm-ventas-01 | `canonical name = rrhh.farmaruta.local` |
| 5 | `nslookup 10.10.0.133` desde vm-ventas-01 | `name = rrhh.farmaruta.local` |
| 6 | `nslookup google.com` desde vm-ventas-01 | Respuesta gracias al forwarder |
| 7 | `nslookup rrhh.farmaruta.local 10.10.0.132` desde vm-visitas-01 | `connection timed out` |
| 8 | Portal: VNet → DNS servers = Custom 10.10.0.132 | Configuración de DHCP |

## Tiempo de implementación

| Tarea | Tiempo |
|---|---|
| Crear vm-dns (IP fija, sin IP pública) | _completar_ |
| Instalar y configurar BIND9 (opciones, zonas) | _completar_ |
| Configurar DNS de la VNet y reiniciar VMs | _completar_ |
| Pruebas y capturas | _completar_ |
| **Total** | _completar_ |
