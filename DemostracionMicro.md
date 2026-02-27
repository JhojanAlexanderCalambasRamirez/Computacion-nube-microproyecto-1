# Guía de Demostración — Microproyecto 1

**Computación en la Nube — Universidad Autónoma de Occidente**

**Integrantes:**
- Jhojan Alexander Calambas
- Oscar Eduardo Portela
- Angelo Parra

---

## Antes de empezar

```bash
cd ~/compunube/microproyecto1
vagrant up
vagrant status
```

---

## DEMO 1 — Infraestructura levantada

```bash
# Ver las 3 VMs corriendo
vagrant status

# Servicios en web1
vagrant ssh web1 -c "systemctl status consul nodeapp-3000 nodeapp-3001 --no-pager"

# Servicios en web2
vagrant ssh web2 -c "systemctl status consul nodeapp-3000 nodeapp-3001 --no-pager"

# Servicios en haproxy
vagrant ssh haproxy -c "systemctl status haproxy consul-template --no-pager"
```

---

## DEMO 2 — Service Mesh con Consul

```bash
# Cluster de Consul (web1=server, web2=agent)
vagrant ssh web1 -c "consul members"

# 4 servicios registrados con health checks passing
vagrant ssh web1 -c "curl -s http://localhost:8500/v1/health/service/web | python3 -m json.tool"

# Consul UI
open http://192.168.100.11:8500/ui
```

---

## DEMO 3 — consul-template genera haproxy.cfg desde Consul

```bash
# Ver el config generado dinamicamente (no escrito a mano)
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg"

# Ver logs de consul-template
vagrant ssh haproxy -c "sudo journalctl -u consul-template --no-pager -n 20"

# HAProxy Stats GUI
open http://localhost:8404/stats
# usuario: admin | contrasena: admin
```

---

## DEMO 4 — Balanceo Round Robin entre 4 replicas

```bash
# Ver los 4 backends en verde en HAProxy stats
open http://localhost:8404/stats
# usuario: admin | contrasena: admin
```

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
```

---

## DEMO 5 — Alta disponibilidad: Consul detecta caida y consul-template actualiza HAProxy

```bash
# 1. Detener una replica
vagrant ssh web1 -c "sudo systemctl stop nodeapp-3000"

# 2. Esperar ~15 segundos y verificar que desaparecio del config
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg" | grep "server w"
# web1-3000 ya no aparece

# 3. El trafico sigue con las 3 replicas restantes
for i in {1..6}; do
  echo -n "Peticion $i -> "
  curl -s http://localhost:8080/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':'+str(d['port']))"
done

# 4. Restaurar
vagrant ssh web1 -c "sudo systemctl start nodeapp-3000"
vagrant ssh web1 -c "consul reload"
```

---

## DEMO 6 — Pagina 503 personalizada

```bash
# 1. Caer todas las replicas
vagrant ssh web1 -c "sudo systemctl stop nodeapp-3000 nodeapp-3001"
vagrant ssh web2 -c "sudo systemctl stop nodeapp-3000 nodeapp-3001"

# 2. Esperar 15 segundos
sleep 15

# 3. Verificar backend vacio
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg" | grep "server w"

# 4. Ver la pagina 503 personalizada
curl -i http://localhost:8080
# O abrir en navegador: http://localhost:8080

# 5. Restaurar
vagrant ssh web1 -c "sudo systemctl start nodeapp-3000 nodeapp-3001"
vagrant ssh web2 -c "sudo systemctl start nodeapp-3000 nodeapp-3001"
vagrant ssh web1 -c "consul reload"
vagrant ssh web2 -c "consul reload"
```

---

## DEMO 7 — Prueba de carga con Artillery

```bash
# Asegurarse de estar en la carpeta del proyecto (Mac, no dentro de VM)
cd ~/compunube/microproyecto1

# Correr la prueba (duracion total ~3 minutos)
artillery run artillery/load-test.yml

# Ver trafico en tiempo real durante la prueba
open http://localhost:8404/stats
```

| Fase | Duracion | Tasa |
|------|----------|------|
| Calentamiento | 30 s | 5 req/s |
| Normal | 60 s | 20 req/s |
| Alta | 60 s | 50 req/s |
| Pico | 30 s | 100 req/s |
