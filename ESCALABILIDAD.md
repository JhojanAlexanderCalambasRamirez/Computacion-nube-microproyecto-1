# Escalabilidad — Réplicas por nodo + consul-template

**Microproyecto 1 | Computación en la Nube — Universidad Autónoma de Occidente**

**Integrantes:**
- Jhojan Alexander Calambas
- Oscar Eduardo Portela
- Angelo Parra

---

## ¿Qué es la escalabilidad en este contexto?

Escalar un sistema significa aumentar su capacidad para atender más peticiones. Existen dos formas:

- **Escalabilidad vertical:** darle más CPU/RAM a una sola máquina.
- **Escalabilidad horizontal:** añadir más instancias del servicio que atienden peticiones en paralelo.

En este proyecto se implementa **escalabilidad horizontal dentro de cada nodo**: cada VM corre **dos instancias independientes** del servidor Node.js en puertos distintos (3000 y 3001), y HAProxy distribuye el tráfico entre las 4 réplicas totales.

---

## ¿Por qué Node.js necesita múltiples réplicas?

Node.js es **monohilo**: un solo proceso utiliza únicamente 1 núcleo de CPU. Si la VM tiene 2 núcleos disponibles y solo hay 1 proceso corriendo, el 50% de la capacidad de cómputo queda sin usar.

```
Sin réplicas:         Con réplicas:
┌────────────┐        ┌────────────┐
│  CPU core 0│ ← app  │  CPU core 0│ ← nodeapp-3000
│  CPU core 1│ (idle) │  CPU core 1│ ← nodeapp-3001
└────────────┘        └────────────┘
  throughput: 1x        throughput: ~2x
```

Cada réplica es un proceso Node.js completamente independiente. Si una falla, la otra sigue atendiendo tráfico.

---

## Arquitectura con réplicas y consul-template

```
Mac anfitrión
      │
      ▼ localhost:8080
┌──────────────────┐
│   HAProxy        │  Round Robin — config generada por consul-template
│   consul-template│◄─── consulta Consul cada vez que hay un cambio
└──────┬───────────┘
       │
       ├──► web1-3000  →  192.168.100.11:3000  (nodeapp-3000)
       ├──► web1-3001  →  192.168.100.11:3001  (nodeapp-3001)
       ├──► web2-3000  →  192.168.100.12:3000  (nodeapp-3000)
       └──► web2-3001  →  192.168.100.12:3001  (nodeapp-3001)

Consul Server (web1:8500)
  ├── service: web-3000 en web1  [passing ✓]
  ├── service: web-3001 en web1  [passing ✓]
  ├── service: web-3000 en web2  [passing ✓]
  └── service: web-3001 en web2  [passing ✓]
```

---

## Cómo está implementado

### 1. Variable de entorno `PORT` en Node.js

```javascript
// app/server.js
const PORT = parseInt(process.env.PORT) || 3000;
```

El mismo binario corre en distintos puertos según la variable de entorno que le pase systemd.

### 2. Dos servicios systemd por VM

```ini
# /etc/systemd/system/nodeapp-3000.service
[Service]
Environment=PORT=3000
ExecStart=/usr/bin/node server.js
```

```ini
# /etc/systemd/system/nodeapp-3001.service
[Service]
Environment=PORT=3001
ExecStart=/usr/bin/node server.js
```

### 3. Dos registros de servicio en Consul por VM

Cada réplica tiene su propio archivo de definición con `id` único:

```json
// consul/web-service-3000.json
{ "service": { "id": "web-3000", "name": "web", "port": 3000,
    "check": { "http": "http://localhost:3000/health", "interval": "5s" } } }
```

```json
// consul/web-service-3001.json
{ "service": { "id": "web-3001", "name": "web", "port": 3001,
    "check": { "http": "http://localhost:3001/health", "interval": "5s" } } }
```

Consul hace health checks independientes a cada réplica.

### 4. consul-template genera haproxy.cfg desde Consul

consul-template corre en la VM `haproxy`, escucha el catálogo de Consul y regenera `haproxy.cfg` automáticamente cuando hay cambios:

```
# haproxy/haproxy.cfg.ctmpl  (fragmento clave)
{{range service "web"}}
    server {{.Node}}-{{.Port}} {{.Address}}:{{.Port}} check inter 5s fall 2 rise 2
{{end}}
```

Esto genera las 4 líneas `server` dinámicamente con solo los backends **healthy** en Consul.

---

## Paso a paso para demostrar la escalabilidad

### Paso 1 — Verificar que las VMs están corriendo

```bash
vagrant status
```

---

### Paso 2 — Verificar las 2 réplicas en web1

```bash
vagrant ssh web1 -c "sudo systemctl status nodeapp-3000 nodeapp-3001 --no-pager"
```

```bash
vagrant ssh web1 -c "curl -s http://localhost:3000/health && echo && curl -s http://localhost:3001/health"
```

Salida esperada:
```json
{"status":"ok","host":"web1","ip":"192.168.100.11","port":3000}
{"status":"ok","host":"web1","ip":"192.168.100.11","port":3001}
```

---

### Paso 3 — Verificar las 2 réplicas en web2

```bash
vagrant ssh web2 -c "sudo systemctl status nodeapp-3000 nodeapp-3001 --no-pager"
```

```bash
vagrant ssh web2 -c "curl -s http://localhost:3000/health && echo && curl -s http://localhost:3001/health"
```

---

### Paso 4 — Verificar los 4 servicios en Consul

```bash
vagrant ssh web1 -c "consul catalog services"
vagrant ssh web1 -c "curl -s http://localhost:8500/v1/health/service/web | python3 -m json.tool"
```

Deben aparecer 4 instancias del servicio `web`, todas en estado `passing`.

---

### Paso 5 — Ver el haproxy.cfg generado dinámicamente

```bash
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg" | grep "server w"
```

Salida esperada (generada por consul-template, no escrita a mano):
```
    server web1-3000 192.168.100.11:3000 check inter 5s fall 2 rise 2
    server web1-3001 192.168.100.11:3001 check inter 5s fall 2 rise 2
    server web2-3000 192.168.100.12:3000 check inter 5s fall 2 rise 2
    server web2-3001 192.168.100.12:3001 check inter 5s fall 2 rise 2
```

---

### Paso 6 — Ver los 4 backends en HAProxy stats

```
http://localhost:8404/stats
```

Usuario: `admin` | Contraseña: `admin`

Deben aparecer **4 filas en verde**.

---

### Paso 7 — Demostrar el Round Robin entre las 4 réplicas

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
Peticion 6 -> web1:3001
Peticion 7 -> web2:3000
Peticion 8 -> web2:3001
```

---

### Paso 8 — Simular la caída de una réplica

```bash
# Detener una sola replica
vagrant ssh web1 -c "sudo systemctl stop nodeapp-3000"
```

Esperar ~15 segundos para que Consul detecte el fallo, luego:

```bash
# consul-template debe haber eliminado web1-3000 del config
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg" | grep "server w"
```

Solo deben aparecer **3 servers**. El trafico sigue fluyendo:

```bash
for i in {1..6}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':'+str(d['port']))"
done
```

**Restaurar la réplica:**

```bash
vagrant ssh web1 -c "sudo systemctl start nodeapp-3000"

# Si estuvo caida mas de 1 minuto, Consul la desregistro automaticamente.
# Hay que recargar el agente para que vuelva a registrarse:
vagrant ssh web1 -c "consul reload"
```

Tras ~10 segundos `web1-3000` vuelve al config y al balanceo.

---

### Paso 9 — Prueba de carga Artillery con las 4 réplicas activas

```bash
cd ~/compunube/microproyecto1
artillery run artillery/load-test.yml
```

Abrir **http://localhost:8404/stats** en paralelo para ver los contadores de sesiones subir en los 4 backends simultáneamente.

---

## Resumen de lo que demuestra este punto

| Concepto | Cómo se demuestra |
|----------|-------------------|
| Escalabilidad horizontal | 2 réplicas por VM, 4 backends en total |
| Aprovechamiento de CPU | Cada réplica corre en un proceso/núcleo independiente |
| Integración HAProxy-Consul | consul-template genera haproxy.cfg desde el catalogo de Consul |
| Tolerancia a fallos | Caída de 1 réplica → consul-template la elimina del config automáticamente |
| Distribución de carga | Round Robin visible por réplica con `python3` parseando `/health` |
| Auto-recuperación | Al restaurar una réplica vuelve al pool sin intervención manual en HAProxy |
| Desregistro automático | Si una réplica cae >1 min, Consul la borra del catalogo (`consul reload` para re-registrar) |
