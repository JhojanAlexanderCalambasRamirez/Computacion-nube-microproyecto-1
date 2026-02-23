# Escalabilidad — Réplicas por nodo

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

Al lanzar 2 réplicas por VM:

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

## Arquitectura con réplicas

```
Mac anfitrión
      │
      ▼ localhost:8080
┌──────────────┐
│   HAProxy    │  Round Robin entre 4 backends
└──────┬───────┘
       │
       ├──► web1-r1  →  192.168.100.11:3000  (nodeapp-3000)
       ├──► web1-r2  →  192.168.100.11:3001  (nodeapp-3001)
       ├──► web2-r1  →  192.168.100.12:3000  (nodeapp-3000)
       └──► web2-r2  →  192.168.100.12:3001  (nodeapp-3001)
```

---

## Cómo está implementado

### 1. Variable de entorno `PORT` en Node.js

El servidor lee el puerto desde la variable de entorno en lugar de tenerlo fijo:

```javascript
// app/server.js
const PORT = parseInt(process.env.PORT) || 3000;
```

Esto permite lanzar el mismo binario en distintos puertos sin modificar el código.

### 2. Dos servicios systemd por VM

Cada VM tiene dos servicios systemd que lanzan el mismo `server.js` con distinto `PORT`:

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

### 3. Cuatro backends en HAProxy

```
# haproxy/haproxy.cfg
backend web_servers
    balance roundrobin
    option  httpchk GET /health
    server  web1-r1 192.168.100.11:3000 check inter 5s fall 2 rise 2
    server  web1-r2 192.168.100.11:3001 check inter 5s fall 2 rise 2
    server  web2-r1 192.168.100.12:3000 check inter 5s fall 2 rise 2
    server  web2-r2 192.168.100.12:3001 check inter 5s fall 2 rise 2
```

HAProxy hace health checks a `/health` en cada réplica cada 5 segundos. Si una falla 2 veces seguidas, la saca del pool automáticamente.

---

## Paso a paso para demostrar la escalabilidad

### Paso 1 — Verificar que las VMs están corriendo

```bash
vagrant status
```

Salida esperada:
```
web1     running (virtualbox)
web2     running (virtualbox)
haproxy  running (virtualbox)
```

---

### Paso 2 — Verificar las 2 réplicas en web1

```bash
vagrant ssh web1 -c "sudo systemctl status nodeapp-3000 --no-pager"
vagrant ssh web1 -c "sudo systemctl status nodeapp-3001 --no-pager"
```

Ambos deben mostrar `Active: active (running)`.

También confirmar que los dos puertos responden:

```bash
vagrant ssh web1 -c "curl -s http://localhost:3000/health && echo && curl -s http://localhost:3001/health"
```

Salida esperada:
```
{"status":"ok","host":"web1","ip":"192.168.100.11"}
{"status":"ok","host":"web1","ip":"192.168.100.11"}
```

---

### Paso 3 — Verificar las 2 réplicas en web2

```bash
vagrant ssh web2 -c "sudo systemctl status nodeapp-3000 --no-pager"
vagrant ssh web2 -c "sudo systemctl status nodeapp-3001 --no-pager"
```

```bash
vagrant ssh web2 -c "curl -s http://localhost:3000/health && echo && curl -s http://localhost:3001/health"
```

---

### Paso 4 — Ver los 4 backends en HAProxy

Abrir en el navegador:

```
http://localhost:8404/stats
```

Usuario: `admin` | Contraseña: `admin`

Deben aparecer **4 filas en verde**: `web1-r1`, `web1-r2`, `web2-r1`, `web2-r2`.

---

### Paso 5 — Demostrar el Round Robin entre las 4 réplicas

Desde el Mac, ejecutar un loop de 8 peticiones:

```bash
for i in {1..8}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080 | grep -oP 'desde <strong>\K[^<]+'
done
```

Salida esperada (las peticiones rotan entre las 4 réplicas):
```
Peticion 1 -> web1
Peticion 2 -> web1
Peticion 3 -> web2
Peticion 4 -> web2
Peticion 5 -> web1
Peticion 6 -> web1
Peticion 7 -> web2
Peticion 8 -> web2
```

> **Nota:** El hostname no incluye el puerto porque el HTML solo muestra el nombre del servidor. Lo que importa es que HAProxy está distribuyendo entre los 4 procesos — visible en la columna "Sessions" de la GUI de stats.

---

### Paso 6 — Simular la caída de una réplica (alta disponibilidad)

Detener solo la réplica en puerto 3000 de web1:

```bash
vagrant ssh web1 -c "sudo systemctl stop nodeapp-3000"
```

Esperar ~10 segundos y volver a hacer peticiones:

```bash
for i in {1..6}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080 | grep -oP 'desde <strong>\K[^<]+'
done
```

El sistema sigue respondiendo con las **3 réplicas restantes** (`web1-r2`, `web2-r1`, `web2-r2`). En HAProxy stats, `web1-r1` aparece en rojo.

Restaurar:

```bash
vagrant ssh web1 -c "sudo systemctl start nodeapp-3000"
```

Tras ~10 segundos, `web1-r1` vuelve a aparecer en verde y recibe tráfico nuevamente.

---

### Paso 7 — Prueba de carga Artillery con las 4 réplicas activas

```bash
cd ~/compunube/microproyecto1
artillery run artillery/load-test.yml
```

Con 4 réplicas activas, el sistema puede absorber hasta **100 req/s** (fase pico) distribuyendo la carga entre los 4 procesos Node.js. Observar en la GUI de HAProxy cómo los contadores de sesiones suben en los 4 backends simultáneamente.

---

## Resumen de lo que demuestra este punto

| Concepto | Cómo se demuestra |
|----------|-------------------|
| Escalabilidad horizontal | 2 réplicas por VM, 4 backends en total |
| Tolerancia a fallos | Caída de 1 réplica no interrumpe el servicio |
| Distribución de carga | Round Robin visible en HAProxy stats |
| Configuración dinámica | Variable `PORT` en systemd, mismo binario distintos puertos |
| Health checks automáticos | HAProxy detecta caídas y las excluye del pool |
