# Microproyecto 1 — Service Mesh con Consul + HAProxy + Artillery

**Computación en la Nube — Universidad Autónoma de Occidente**

**Integrantes:**
- Jhojan Alexander Calambas
- Oscar Eduardo Portela
- Angelo Parra

---

## Tabla de Contenidos

1. [¿Qué hace este proyecto?](#1-qué-hace-este-proyecto)
2. [Arquitectura](#2-arquitectura)
3. [Escalabilidad — Réplicas por nodo](#3-escalabilidad--réplicas-por-nodo)
4. [Estructura de archivos](#4-estructura-de-archivos)
5. [Requisitos previos](#5-requisitos-previos)
6. [Levantar el entorno](#6-levantar-el-entorno)
7. [Verificar que todo funciona](#7-verificar-que-todo-funciona)
8. [Guía de demostración para el docente](#8-guía-de-demostración-para-el-docente)
9. [Comandos de referencia rápida](#9-comandos-de-referencia-rápida)
10. [Explicación de cada archivo](#10-explicación-de-cada-archivo)

---

## 1. ¿Qué hace este proyecto?

Se despliegan **3 máquinas virtuales** con Vagrant + VirtualBox que conforman un entorno de producción mínimo:

| VM | IP | Rol |
|----|----|-----|
| `web1` | 192.168.100.11 | Node.js x2 + Consul Server |
| `web2` | 192.168.100.12 | Node.js x2 + Consul Agent |
| `haproxy` | 192.168.100.10 | HAProxy + consul-template |

El flujo de una petición es:

```
Tu navegador (Mac)
      │
      ▼ localhost:8080
┌─────────────┐
│   HAProxy   │  ← balancea en Round Robin (4 backends)
└──────┬──────┘   config generada dinamicamente por consul-template
       ├──► web1:3000  (Node.js réplica 1)
       ├──► web1:3001  (Node.js réplica 2)
       ├──► web2:3000  (Node.js réplica 1)
       └──► web2:3001  (Node.js réplica 2)
```

**Consul** actúa como Service Mesh: registra los servicios y hace health checks cada 5s. **consul-template** escucha esos cambios y regenera la configuración de HAProxy automáticamente. **Artillery** genera carga de prueba desde el Mac.

---

## 2. Arquitectura

```
Mac anfitrión (Apple Silicon)
│
│  localhost:8080  ──────────────────────────────────┐
│  localhost:8404  ──────────────────┐               │
│                                    │               │
│          Red privada: 192.168.100.0/24             │
│                        │                           │
│         ┌──────────────┴──────────────────────┐   │
│         │                                     │   │
│    192.168.100.10                              │   │
│    ┌──────────────────┐  port :80              │   │
│    │  HAProxy         │◄───────────────────────────◄─┘
│    │  consul-template │  port :8404 (stats)◄───────◄─┘
│    └────────┬─────────┘
│             │ consulta catalogo      Round Robin
│             ▼                     ┌──────────────┐
│    192.168.100.11:8500 (Consul)   │  4 backends  │
│             │                     └──────────────┘
│    ┌────────┴──────────────────────────────┐
│    │                                       │
│  192.168.100.11                       192.168.100.12
│  ┌──────────────┐                    ┌──────────────┐
│  │    web1      │                    │    web2      │
│  │ Node.js:3000 │                    │ Node.js:3000 │
│  │ Node.js:3001 │                    │ Node.js:3001 │
│  │ Consul Server│                    │ Consul Agent │
│  └──────────────┘                    └──────────────┘
│         ▲                                   ▲
│         └──────────── Consul RPC ───────────┘
│                  (service discovery
│                   + health checks)
```

**Flujo cuando una réplica cae:**
```
Consul detecta fallo en web1:3000
       │
       ▼
consul-template regenera haproxy.cfg (sin web1:3000)
       │
       ▼
HAProxy se recarga automaticamente
       │
       ▼
El trafico se redistribuye entre las 3 replicas restantes
```

---

## 3. Escalabilidad — Réplicas por nodo

Cada VM corre **dos instancias independientes** del servidor Node.js en puertos distintos. HAProxy distribuye el tráfico entre las 4 réplicas en total.

### ¿Por qué esto es escalabilidad?

Node.js es monohilo: un solo proceso usa únicamente 1 núcleo de CPU. Con 2 réplicas por VM se aprovechan ambos núcleos, duplicando el throughput sin añadir hardware.

### Cómo está implementado

| Réplica | VM | Puerto | Servicio systemd |
|---------|----|--------|-----------------|
| web1-3000 | web1 | 3000 | `nodeapp-3000` |
| web1-3001 | web1 | 3001 | `nodeapp-3001` |
| web2-3000 | web2 | 3000 | `nodeapp-3000` |
| web2-3001 | web2 | 3001 | `nodeapp-3001` |

Cada servicio systemd pasa la variable de entorno `PORT`:

```ini
Environment=PORT=3001
ExecStart=/usr/bin/node server.js
```

consul-template genera el backend dinámicamente desde el catálogo de Consul:

```
server web1-3000 192.168.100.11:3000 check inter 5s fall 2 rise 2
server web1-3001 192.168.100.11:3001 check inter 5s fall 2 rise 2
server web2-3000 192.168.100.12:3000 check inter 5s fall 2 rise 2
server web2-3001 192.168.100.12:3001 check inter 5s fall 2 rise 2
```

### Verificar las réplicas

```bash
# Ver los 2 servicios corriendo en web1
vagrant ssh web1 -c "sudo systemctl status nodeapp-3000 --no-pager && sudo systemctl status nodeapp-3001 --no-pager"

# Verificar que ambos puertos responden
vagrant ssh web1 -c "curl -s http://localhost:3000/health && echo && curl -s http://localhost:3001/health"
```

### Demostrar el Round Robin entre las 4 réplicas

```bash
for i in {1..8}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':'+str(d['port']))"
done
```

Salida esperada:
```
Peticion 1 -> web1:3000
Peticion 2 -> web1:3001
Peticion 3 -> web2:3000
Peticion 4 -> web2:3001
Peticion 5 -> web1:3000
...
```

---

## 4. Estructura de archivos

```
microproyecto1/
├── Vagrantfile                        # Define las 3 VMs
├── app/
│   ├── server.js                      # Servidor HTTP Node.js (sin dependencias)
│   └── package.json                   # Metadatos del app
├── consul/
│   ├── server.json                    # Config Consul para web1 (modo server)
│   ├── client.json                    # Config Consul para web2 (modo agent)
│   ├── web-service-3000.json          # Registro replica puerto 3000 en Consul
│   └── web-service-3001.json          # Registro replica puerto 3001 en Consul
├── haproxy/
│   ├── haproxy.cfg                    # Config estatica (respaldo inicial)
│   ├── haproxy.cfg.ctmpl              # Template dinamico para consul-template
│   ├── consul-template.hcl            # Config de consul-template
│   └── errors/
│       └── 503.http                   # Pagina de error personalizada
├── scripts/
│   ├── provision_web.sh               # Instala Node.js + Consul en web1/web2
│   └── provision_haproxy.sh           # Instala HAProxy + consul-template
├── artillery/
│   └── load-test.yml                  # Escenarios de prueba de carga
└── Documents/
    ├── Microproyecto1.pdf
    ├── Practica Aprovisionamiento.pdf
    ├── Practica Balanceo de Carga.pdf
    └── Practica ServiceMesh.pdf
```

---

## 5. Requisitos previos

```bash
vagrant --version     # >= 2.3
VBoxManage --version  # VirtualBox >= 6.1
node --version        # para Artillery
artillery --version   # >= 2.0
```

Instalar Artillery si no está:

```bash
npm install -g artillery
```

---

## 6. Levantar el entorno

```bash
cd ~/compunube/microproyecto1

# Primera vez (~10-15 min)
vagrant up

# Ver estado
vagrant status
```

Salida esperada:
```
web1     running (virtualbox)
web2     running (virtualbox)
haproxy  running (virtualbox)
```

---

## 7. Verificar que todo funciona

### 7.1 Round Robin entre las 4 réplicas

```bash
for i in {1..8}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':'+str(d['port']))"
done
```

### 7.2 Health check directo

```bash
curl http://localhost:8080/health
```

Respuesta esperada:
```json
{"status":"ok","host":"web1","ip":"192.168.100.11","port":3000}
```

### 7.3 Consul cluster

```bash
vagrant ssh web1 -c "consul members"
```

Salida esperada:
```
Node   Address                Status  Type    Build
web1   192.168.100.11:8301    alive   server  1.17.1
web2   192.168.100.12:8301    alive   client  1.17.1
```

### 7.4 Servicios registrados en Consul

```bash
vagrant ssh web1 -c "curl -s http://localhost:8500/v1/health/service/web | python3 -m json.tool"
```

Deben aparecer 4 instancias del servicio `web` (2 por nodo).

### 7.5 consul-template activo

```bash
vagrant ssh haproxy -c "sudo systemctl status consul-template --no-pager"
```

### 7.6 haproxy.cfg generado dinamicamente

```bash
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg" | grep "server w"
```

Salida esperada (4 backends con nombres generados por consul-template):
```
    server web1-3000 192.168.100.11:3000 check inter 5s fall 2 rise 2
    server web1-3001 192.168.100.11:3001 check inter 5s fall 2 rise 2
    server web2-3000 192.168.100.12:3000 check inter 5s fall 2 rise 2
    server web2-3001 192.168.100.12:3001 check inter 5s fall 2 rise 2
```

### 7.7 GUI de estadísticas HAProxy

Abrir: **http://localhost:8404/stats** — usuario: `admin` / contraseña: `admin`

Deben aparecer los 4 backends en **verde**.

### 7.8 Consul UI

Abrir: **http://192.168.100.11:8500/ui**

---

## 8. Guía de demostración para el docente

---

### DEMO 1: Infraestructura levantada

```bash
vagrant status
```

```bash
# Servicios en web1: consul + 2 replicas Node.js
vagrant ssh web1 -c "systemctl status consul nodeapp-3000 nodeapp-3001 --no-pager"
```

```bash
# Servicios en web2
vagrant ssh web2 -c "systemctl status consul nodeapp-3000 nodeapp-3001 --no-pager"
```

```bash
# Servicios en haproxy: haproxy + consul-template
vagrant ssh haproxy -c "systemctl status haproxy consul-template --no-pager"
```

---

### DEMO 2: Service Mesh con Consul

```bash
# Ver el cluster de Consul
vagrant ssh web1 -c "consul members"
```

```bash
# Ver los 4 servicios registrados con su estado de salud
vagrant ssh web1 -c "curl -s http://localhost:8500/v1/health/service/web | python3 -m json.tool"
```

**Puntos a resaltar:**
- web1 es **Consul Server**, web2 es **Consul Agent**
- Consul hace health checks a `/health` cada 5 segundos en cada réplica
- Los servicios se registran via archivos JSON en `/etc/consul.d/`

---

### DEMO 3: consul-template conecta HAProxy con Consul

```bash
# Ver el haproxy.cfg generado dinamicamente (nota los nombres web1-3000 etc.)
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg"
```

```bash
# Ver los logs de consul-template
vagrant ssh haproxy -c "sudo journalctl -u consul-template --no-pager -n 20"
```

**Puntos a resaltar:**
- `haproxy.cfg` es generado por consul-template, no es un archivo estático
- consul-template consulta la API de Consul (`192.168.100.11:8500`)
- Solo incluye replicas con health check **passing** en Consul

---

### DEMO 4: Round Robin entre las 4 réplicas

```bash
for i in {1..8}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':'+str(d['port']))"
done
```

---

### DEMO 5: Alta disponibilidad — consul-template reacciona automáticamente

```bash
# Detener una replica
vagrant ssh web1 -c "sudo systemctl stop nodeapp-3000"
```

```bash
# Esperar ~15 segundos y ver como consul-template borra la replica del config
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg" | grep "server w"
# web1-3000 ya no aparece
```

```bash
# El trafico sigue fluyendo hacia las 3 replicas restantes
for i in {1..6}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':'+str(d['port']))"
done
```

```bash
# Restaurar la replica
vagrant ssh web1 -c "sudo systemctl start nodeapp-3000"
consul reload  # solo si estuvo caida mas de 1 minuto
```

---

### DEMO 6: Página de error 503 personalizada

```bash
# Detener las 4 replicas
vagrant ssh web1 -c "sudo systemctl stop nodeapp-3000 nodeapp-3001"
vagrant ssh web2 -c "sudo systemctl stop nodeapp-3000 nodeapp-3001"
sleep 15
```

```bash
curl http://localhost:8080
# O abrir en navegador: http://localhost:8080
```

```bash
# Restaurar
vagrant ssh web1 -c "sudo systemctl start nodeapp-3000 nodeapp-3001"
vagrant ssh web2 -c "sudo systemctl start nodeapp-3000 nodeapp-3001"
vagrant ssh web1 -c "consul reload"
vagrant ssh web2 -c "consul reload"
```

---

### DEMO 7: Prueba de carga con Artillery

```bash
cd ~/compunube/microproyecto1
artillery run artillery/load-test.yml
```

| Fase | Duración | Tasa |
|------|----------|------|
| Calentamiento | 30 s | 5 req/s |
| Normal | 60 s | 20 req/s |
| Alta | 60 s | 50 req/s |
| Pico | 30 s | 100 req/s |

Abrir **http://localhost:8404/stats** en paralelo para ver el tráfico distribuido entre los 4 backends.

---

## 9. Comandos de referencia rápida

### Vagrant

```bash
vagrant up              # Levantar todas las VMs
vagrant halt            # Apagar todas las VMs
vagrant destroy -f      # Eliminar todas las VMs
vagrant status          # Ver estado
vagrant ssh web1        # Conectarse a web1
vagrant provision       # Re-provisionar
```

### Dentro de web1 / web2

```bash
# Estado
sudo systemctl status consul
sudo systemctl status nodeapp-3000
sudo systemctl status nodeapp-3001

# Reiniciar
sudo systemctl restart nodeapp-3000 nodeapp-3001

# Logs en tiempo real
sudo journalctl -fu nodeapp-3000
sudo journalctl -fu consul

# Consul
consul members
consul reload                          # re-registra servicios del catalogo

# Verificar replicas localmente
curl http://localhost:3000/health
curl http://localhost:3001/health
```

### Dentro de haproxy

```bash
# Estado
sudo systemctl status haproxy
sudo systemctl status consul-template

# Logs de consul-template (ver cuando regenera el config)
sudo journalctl -fu consul-template

# Ver el config actual generado
cat /etc/haproxy/haproxy.cfg

# Validar config manualmente
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

### Desde el Mac

```bash
# Ver que replica responde cada peticion
for i in {1..8}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':'+str(d['port']))"
done

# Abrir GUI de HAProxy
open http://localhost:8404/stats

# Prueba de carga
artillery run artillery/load-test.yml
```

---

## 10. Explicación de cada archivo

### `Vagrantfile`
Define las 3 VMs. Box `bento/ubuntu-22.04` (compatible ARM64). Solo `haproxy` expone puertos al Mac (8080 y 8404).

---

### `app/server.js`
Servidor HTTP con módulos nativos de Node.js. Lee `PORT` desde variable de entorno. Rutas:
- `GET /` — página HTML con hostname, IP y puerto
- `GET /health` — JSON `{"status":"ok","host":"...","ip":"...","port":...}` usado por Consul y HAProxy

---

### `consul/server.json`
Config de Consul para web1 en modo **server**: `bootstrap_expect:1`, UI habilitada en puerto 8500.

### `consul/client.json`
Config de Consul para web2 en modo **agent**: `retry_join` apunta a web1 para unirse automáticamente.

### `consul/web-service-3000.json` y `web-service-3001.json`
Registran las 2 réplicas por nodo en el catálogo de Consul con `id` único (`web-3000`, `web-3001`). Consul hace health checks HTTP a cada puerto cada 5 segundos. Si el servicio está crítico más de 1 minuto, lo desregistra automáticamente.

---

### `haproxy/haproxy.cfg`
Config estática usada como respaldo inicial. Una vez que consul-template arranca, este archivo es sobreescrito por la versión dinámica.

### `haproxy/haproxy.cfg.ctmpl`
Template que consul-template usa para generar `haproxy.cfg`. La sección clave:
```
{{range service "web"}}
    server {{.Node}}-{{.Port}} {{.Address}}:{{.Port}} check inter 5s fall 2 rise 2
{{end}}
```
Solo incluye réplicas con health check **passing** en Consul.

### `haproxy/consul-template.hcl`
Config de consul-template: dirección del servidor Consul (`192.168.100.11:8500`), archivo template, destino y comando a ejecutar tras cada regeneración (`systemctl reload haproxy`).

### `haproxy/errors/503.http`
Página de error personalizada que HAProxy sirve cuando todos los backends están caídos.

---

### `scripts/provision_web.sh`
Aprovisionamiento de web1 y web2:
1. Instala Node.js 20 LTS
2. Descarga Consul (detecta arquitectura ARM64/AMD64 automáticamente)
3. Copia config Consul según el rol (server en web1, agent en web2)
4. Registra las 2 réplicas en Consul (`web-service-3000.json` y `web-service-3001.json`)
5. Crea servicios systemd `nodeapp-3000` y `nodeapp-3001`

### `scripts/provision_haproxy.sh`
Aprovisionamiento de haproxy:
1. Instala HAProxy
2. Descarga consul-template (detecta arquitectura)
3. Copia `haproxy.cfg.ctmpl` y `consul-template.hcl`
4. Crea servicio systemd para consul-template
5. consul-template arranca, consulta a Consul y genera `haproxy.cfg` dinámicamente

---

### `artillery/load-test.yml`
Prueba de carga con 4 fases progresivas (5→20→50→100 req/s). Sintaxis Artillery 2.x con `flow:`.

---

## Notas técnicas

**¿Por qué `grep -oP` no funciona en Mac?**
macOS usa BSD grep que no soporta `-P` (Perl regex). Usar `python3` para parsear el JSON de `/health`.

**¿Qué es `consul reload`?**
Si una réplica estuvo caída más de 1 minuto, Consul la desregistra automáticamente (`deregistercriticalserviceafter: 1m`). Al volver a levantar el proceso, hay que ejecutar `consul reload` para que Consul re-lea los archivos de definición y vuelva a registrar el servicio.

**¿Por qué el navegador siempre muestra el mismo servidor?**
HTTP keep-alive mantiene la conexión TCP abierta. El Round Robin opera por conexión, no por petición. Usar `curl` en loop para verificar el balanceo.

**¿Por qué `Type=simple` en systemd para Consul?**
`Type=notify` espera una señal `sd_notify` que Consul no enviaba correctamente en Vagrant, causando timeout. `Type=simple` arranca el proceso sin esperar esa señal.

**¿Por qué detectar arquitectura en los scripts?**
Las VMs corren sobre Mac Apple Silicon (ARM64). Los binarios `amd64` no son compatibles. `dpkg --print-architecture` detecta automáticamente `arm64` o `amd64`.
