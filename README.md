# Microproyecto 1 — Service Mesh con Consul + HAProxy + Artillery

**Computación en la Nube — Universidad Autónoma de Occidente**

---

## Tabla de Contenidos

1. [¿Qué hace este proyecto?](#1-qué-hace-este-proyecto)
2. [Arquitectura](#2-arquitectura)
3. [Estructura de archivos](#3-estructura-de-archivos)
4. [Requisitos previos](#4-requisitos-previos)
5. [Levantar el entorno](#5-levantar-el-entorno)
6. [Verificar que todo funciona](#6-verificar-que-todo-funciona)
7. [Guía de demostración para el docente](#7-guía-de-demostración-para-el-docente)
8. [Comandos de referencia rápida](#8-comandos-de-referencia-rápida)
9. [Explicación de cada archivo](#9-explicación-de-cada-archivo)

---

## 1. ¿Qué hace este proyecto?

Se despliegan **3 máquinas virtuales** con Vagrant + VirtualBox que conforman un entorno de producción mínimo:

| VM | IP | Rol |
|----|----|-----|
| `web1` | 192.168.100.11 | Servidor Node.js + **Consul Server** |
| `web2` | 192.168.100.12 | Servidor Node.js + Consul Agent |
| `haproxy` | 192.168.100.10 | Balanceador de carga HAProxy |

El flujo de una petición es:

```
Tu navegador (Mac)
      │
      ▼ localhost:8080
┌─────────────┐
│   HAProxy   │  ← balancea en Round Robin
└──────┬──────┘
       ├──► web1:3000  (Node.js)
       └──► web2:3000  (Node.js)
```

**Consul** actúa como Service Mesh: registra automáticamente el servicio `web` en ambas VMs y hace health checks cada 5 segundos. Si un nodo cae, Consul lo detecta.

**Artillery** genera carga de prueba desde tu Mac contra `localhost:8080`, midiendo el rendimiento del sistema bajo tráfico real.

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
│    ┌────────────┐   port :80                  │   │
│    │  HAProxy   │◄──────────────────────────────◄─┘
│    │            │   port :8404 (stats)◄──────────◄─┘
│    └─────┬──────┘
│          │ Round Robin
│    ┌─────┴──────────────────┐
│    │                        │
│  192.168.100.11           192.168.100.12
│  ┌──────────────┐         ┌──────────────┐
│  │    web1      │         │    web2      │
│  │ Node.js:3000 │         │ Node.js:3000 │
│  │ Consul Server│         │ Consul Agent │
│  └──────────────┘         └──────────────┘
│         ▲                        ▲
│         └────── Consul RPC ──────┘
│                 (service discovery
│                  + health checks)
```

---

## 3. Estructura de archivos

```
microproyecto1/
├── Vagrantfile                   # Define las 3 VMs
├── app/
│   ├── server.js                 # Servidor HTTP Node.js (sin dependencias)
│   └── package.json              # Metadatos del app
├── consul/
│   ├── server.json               # Config Consul para web1 (modo server)
│   ├── client.json               # Config Consul para web2 (modo agent)
│   └── web-service.json          # Registro del servicio "web" en Consul
├── haproxy/
│   ├── haproxy.cfg               # Configuración del balanceador
│   └── errors/
│       └── 503.http              # Página de error personalizada
├── scripts/
│   ├── provision_web.sh          # Instala Node.js + Consul en web1/web2
│   └── provision_haproxy.sh      # Instala y configura HAProxy
├── artillery/
│   └── load-test.yml             # Escenarios de prueba de carga
└── Documents/
    ├── Microproyecto1.pdf        # Guía oficial del proyecto
    ├── Practica Aprovisionamiento.pdf
    ├── Practica Balanceo de Carga.pdf
    └── Practica ServiceMesh.pdf
```

---

## 4. Requisitos previos

Verificar que tienes instalado en el Mac:

```bash
vagrant --version     # >= 2.3
VBoxManage --version  # VirtualBox >= 6.1
node --version        # cualquier versión (para Artillery)
artillery --version   # >= 2.0
```

Instalar Artillery si no está:

```bash
npm install -g artillery
```

---

## 5. Levantar el entorno

Desde la carpeta raíz del proyecto:

```bash
cd ~/compunube/microproyecto1

# Levantar y provisionar las 3 VMs (primera vez ~5-10 min)
vagrant up

# Si las VMs ya existen y quieres re-provisionar
vagrant provision

# Para ver el estado de las VMs
vagrant status
```

Salida esperada después de `vagrant up`:

```
web1: aprovisionado exitosamente
  Node.js : v20.x.x
  Consul  : Consul v1.17.1

web2: aprovisionado exitosamente
  Node.js : v20.x.x
  Consul  : Consul v1.17.1

haproxy: aprovisionado exitosamente
  HAProxy  : HAProxy version 2.x
  Balanceador  : http://192.168.100.10
```

---

## 6. Verificar que todo funciona

### 6.1 Balanceo de carga (Round Robin)

Desde tu Mac, abrir la terminal y ejecutar:

```bash
for i in {1..8}; do curl -s http://localhost:8080 | grep "<h1>"; done
```

Debes ver que alterna entre `web1` y `web2`:

```
  <h1>Hola desde <strong>web1</strong></h1>
  <h1>Hola desde <strong>web2</strong></h1>
  <h1>Hola desde <strong>web1</strong></h1>
  <h1>Hola desde <strong>web2</strong></h1>
```

> **Nota:** El navegador usa HTTP keep-alive, por lo que siempre mostrará el mismo servidor. Usar `curl` es la forma correcta de verificar el Round Robin.

### 6.2 Health check de los nodos

```bash
curl http://localhost:8080/health
```

Respuesta JSON esperada:

```json
{"status":"ok","host":"web1","ip":"192.168.100.11"}
```

### 6.3 Consul Service Mesh

Conectarse a web1 y verificar el cluster:

```bash
vagrant ssh web1 -c "consul members"
```

Salida esperada:

```
Node   Address                Status  Type    Build    Protocol  DC   Partition  Segment
web1   192.168.100.11:8301    alive   server  1.17.1   2         dc1  default    <all>
web2   192.168.100.12:8301    alive   client  1.17.1   2         dc1  default    <default>
```

Verificar el servicio registrado en Consul:

```bash
vagrant ssh web1 -c "curl -s http://localhost:8500/v1/health/service/web | python3 -m json.tool"
```

### 6.4 GUI de estadísticas HAProxy

Abrir en el navegador: **http://localhost:8404/stats**

- Usuario: `admin`
- Contraseña: `admin`

Debes ver `web1` y `web2` en estado **verde (UP)**.

### 6.5 Consul UI

Abrir en el navegador (desde web1): **http://192.168.100.11:8500/ui**

Muestra los servicios registrados y su estado de salud.

---

## 7. Guía de demostración para el docente

Seguir este orden para una demostración completa y clara.

---

### DEMO 1: Infraestructura levantada (Aprovisionamiento)

```bash
# Mostrar que las 3 VMs están corriendo
vagrant status
```

```bash
# Mostrar servicios activos en web1
vagrant ssh web1 -c "systemctl status consul --no-pager && systemctl status nodeapp --no-pager"
```

```bash
# Mostrar servicios activos en web2
vagrant ssh web2 -c "systemctl status consul --no-pager && systemctl status nodeapp --no-pager"
```

```bash
# Mostrar servicios activos en haproxy
vagrant ssh haproxy -c "systemctl status haproxy --no-pager"
```

---

### DEMO 2: Service Mesh con Consul

```bash
# Ver todos los nodos del cluster Consul
vagrant ssh web1 -c "consul members"
```

```bash
# Ver los servicios registrados y su health check
vagrant ssh web1 -c "curl -s http://localhost:8500/v1/health/service/web?pretty"
```

**Puntos a resaltar:**
- web1 actúa como **Consul Server** (bootstrap_expect: 1)
- web2 actúa como **Consul Agent** y se une automáticamente al server via `retry_join`
- Consul hace health checks HTTP a `/health` cada 5 segundos
- Si el health check falla 2 veces seguidas, marca el servicio como crítico

---

### DEMO 3: Balanceo de carga Round Robin

```bash
# Demostrar que las peticiones se distribuyen entre web1 y web2
for i in {1..10}; do
  echo -n "Peticion $i: "
  curl -s http://localhost:8080 | grep -oP 'desde <strong>\K[^<]+'
done
```

**Puntos a resaltar:**
- HAProxy balancea en **Round Robin**: petición 1 → web1, petición 2 → web2, etc.
- El balanceo es transparente: el cliente solo conoce `localhost:8080`
- HAProxy hace health checks propios a `/health` cada 5 segundos (independiente de Consul)

---

### DEMO 4: Alta disponibilidad — simulación de fallo de un nodo

```bash
# Detener el servicio Node.js en web1
vagrant ssh web1 -c "sudo systemctl stop nodeapp"
```

```bash
# Verificar que TODAS las peticiones van ahora a web2
for i in {1..6}; do
  echo -n "Peticion $i: "
  curl -s http://localhost:8080 | grep -oP 'desde <strong>\K[^<]+'
done
```

```bash
# Ver el estado en HAProxy stats (web1 debe aparecer en ROJO)
# Abrir en navegador: http://localhost:8404/stats
```

```bash
# Restaurar el servicio
vagrant ssh web1 -c "sudo systemctl start nodeapp"
```

Después de ~10 segundos, web1 vuelve a recibir tráfico automáticamente.

---

### DEMO 5: Página de error 503 personalizada

```bash
# Detener Node.js en AMBOS servidores
vagrant ssh web1 -c "sudo systemctl stop nodeapp"
vagrant ssh web2 -c "sudo systemctl stop nodeapp"

# Esperar 15 segundos para que HAProxy detecte que ambos fallen
sleep 15
```

```bash
# Acceder al balanceador — debe mostrar la página 503 personalizada
curl http://localhost:8080
# O abrir en el navegador: http://localhost:8080
```

La página mostrará: **"503 — Servicio No Disponible"** con diseño personalizado.

```bash
# Restaurar los servidores
vagrant ssh web1 -c "sudo systemctl start nodeapp"
vagrant ssh web2 -c "sudo systemctl start nodeapp"
```

---

### DEMO 6: Prueba de carga con Artillery

```bash
# Desde la carpeta raíz del proyecto (en el Mac, NO dentro de una VM)
cd ~/compunube/microproyecto1

artillery run artillery/load-test.yml
```

La prueba tiene 4 fases:

| Fase | Duración | Tasa de llegada |
|------|----------|-----------------|
| Calentamiento | 30 s | 5 req/s |
| Carga normal | 60 s | 20 req/s |
| Carga alta | 60 s | 50 req/s |
| Pico de tráfico | 30 s | 100 req/s |

Durante la prueba, abrir en paralelo la GUI de HAProxy para ver el tráfico en tiempo real:
**http://localhost:8404/stats**

**Puntos a resaltar del reporte Artillery:**
- `http.response_time` — latencia de respuesta
- `http.codes.200` — peticiones exitosas
- `vusers.completed` — usuarios virtuales completados
- Tasa de errores (debe ser ~0% en condiciones normales)

---

## 8. Comandos de referencia rápida

### Vagrant

```bash
vagrant up              # Levantar todas las VMs
vagrant halt            # Apagar todas las VMs
vagrant destroy -f      # Eliminar todas las VMs
vagrant status          # Ver estado de las VMs
vagrant ssh web1        # Conectarse a web1
vagrant ssh web2        # Conectarse a web2
vagrant ssh haproxy     # Conectarse a haproxy
vagrant provision       # Re-ejecutar scripts de aprovisionamiento
```

### Dentro de las VMs (web1 / web2)

```bash
# Estado de servicios
sudo systemctl status consul
sudo systemctl status nodeapp

# Reiniciar servicios
sudo systemctl restart consul
sudo systemctl restart nodeapp

# Ver logs en tiempo real
sudo journalctl -fu consul
sudo journalctl -fu nodeapp

# Ver cluster Consul
consul members
consul catalog services

# Verificar app local
curl http://localhost:3000
curl http://localhost:3000/health
```

### Dentro de la VM (haproxy)

```bash
# Estado de HAProxy
sudo systemctl status haproxy

# Validar configuración
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Ver logs
sudo journalctl -fu haproxy
```

### Desde el Mac (sin entrar a VMs)

```bash
# Probar balanceo
curl http://localhost:8080
curl http://localhost:8080/health

# Loop para ver Round Robin
for i in {1..10}; do curl -s http://localhost:8080 | grep -oP 'desde <strong>\K[^<]+'; done

# GUI HAProxy
open http://localhost:8404/stats     # macOS

# Prueba de carga
artillery run artillery/load-test.yml

# Prueba rápida con Artillery (solo 10 segundos)
artillery quick --count 20 --num 2 http://localhost:8080
```

---

## 9. Explicación de cada archivo

### `Vagrantfile`

Define las 3 VMs con VirtualBox. Cada VM tiene:
- Box: `bento/ubuntu-22.04` (compatible con Apple Silicon ARM64)
- Red privada: `192.168.100.0/24` para comunicación entre VMs
- Script de aprovisionamiento propio

Solo `haproxy` expone puertos al Mac anfitrión (8080 y 8404).

---

### `app/server.js`

Servidor HTTP escrito con módulos nativos de Node.js (sin `npm install`). Expone dos rutas:

- `GET /` — página HTML con el hostname y la IP del servidor
- `GET /health` — JSON `{"status":"ok","host":"...","ip":"..."}` usado por Consul y HAProxy para health checks

---

### `consul/server.json`

Configuración de Consul para `web1` en modo **server**:
- `bootstrap_expect: 1` — arranca el cluster con 1 servidor
- `bind_addr: 192.168.100.11` — escucha en la IP de web1
- `ui_config.enabled: true` — habilita la interfaz web en puerto 8500

---

### `consul/client.json`

Configuración de Consul para `web2` en modo **agent (cliente)**:
- `retry_join: ["192.168.100.11"]` — se une automáticamente al server de web1

---

### `consul/web-service.json`

Registra el servicio `web` en Consul. Consul hace un health check HTTP a `localhost:3000/health` cada 5 segundos. Si falla, marca el servicio como crítico y lo registra en el catálogo para que otros servicios lo vean.

---

### `haproxy/haproxy.cfg`

Configuración completa de HAProxy:
- **Frontend** en puerto 80: recibe todo el tráfico entrante
- **Backend** `web_servers`: balancea en Round Robin entre web1:3000 y web2:3000
- Health checks propios cada 5s: si un servidor falla 2 veces, lo saca del pool
- **Stats** en puerto 8404: GUI de monitoreo con usuario/contraseña `admin/admin`
- **errorfile 503**: apunta a la página personalizada cuando todos los backends caen

---

### `haproxy/errors/503.http`

Respuesta HTTP completa (con headers + body HTML) que HAProxy sirve cuando todos los backends están caídos. Muestra una página de error con diseño personalizado en español.

---

### `scripts/provision_web.sh`

Script de aprovisionamiento que se ejecuta automáticamente en `web1` y `web2` al hacer `vagrant up`:

1. Actualiza paquetes del sistema
2. Instala Node.js 20 LTS (via NodeSource)
3. Descarga el binario de Consul detectando la arquitectura automáticamente (`amd64` o `arm64`)
4. Detecta el hostname para asignar el rol de Consul (web1=server, web2=agent)
5. Crea servicios **systemd** para Consul y Node.js
6. Inicia Consul, espera 6 segundos, luego inicia Node.js

---

### `scripts/provision_haproxy.sh`

Script de aprovisionamiento para la VM `haproxy`:

1. Instala HAProxy via apt
2. Copia `haproxy.cfg` y la página de error 503
3. Valida la configuración con `haproxy -c -f`
4. Inicia y habilita el servicio

---

### `artillery/load-test.yml`

Define los escenarios de prueba de carga. Usa la sintaxis de **Artillery 2.x** (`flow:` en lugar de `requests:`):

- 4 fases de carga progresiva (5 → 20 → 50 → 100 req/s)
- 2 escenarios con pesos: 80% peticiones a `/`, 20% a `/health`
- Target: `http://localhost:8080` (el balanceador HAProxy)

---

## Notas técnicas importantes

**¿Por qué el navegador siempre muestra el mismo servidor?**
Los navegadores usan HTTP keep-alive (conexión persistente), lo que hace que todas las peticiones de una misma pestaña vayan al mismo servidor. El Round Robin funciona a nivel de conexión TCP, no de petición HTTP. Usa `curl` en un loop para verificar correctamente el balanceo.

**¿Por qué `Type=simple` en el servicio systemd de Consul?**
`Type=notify` espera que el proceso envíe una señal de "listo" via `sd_notify`. En este entorno Vagrant, Consul no enviaba esa señal correctamente causando timeout. `Type=simple` funciona correctamente porque systemd considera el proceso como iniciado en cuanto arranca.

**¿Por qué se detecta la arquitectura en provision_web.sh?**
Las VMs corren sobre un Mac Apple Silicon (ARM64). El binario de Consul `amd64` no es compatible. El script usa `dpkg --print-architecture` para detectar automáticamente si debe descargar `amd64` o `arm64`.
