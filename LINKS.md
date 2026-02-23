# Links de acceso rápido

## Desde el navegador (Mac)

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| Aplicación web (HAProxy) | http://localhost:8080 | — |
| HAProxy Stats GUI | http://localhost:8404/stats | admin / admin |
| Consul UI | http://192.168.100.11:8500/ui | — |

## IPs de las VMs

| VM | IP |
|----|----|
| haproxy | 192.168.100.10 |
| web1 | 192.168.100.11 |
| web2 | 192.168.100.12 |

## Endpoints de la app

| Endpoint | Descripción |
|----------|-------------|
| http://localhost:8080/ | Página principal (muestra hostname del servidor) |
| http://localhost:8080/health | Health check en JSON |

## Puertos de Node.js (dentro de las VMs)

| Réplica | Host | Puerto |
|---------|------|--------|
| web1-r1 | 192.168.100.11 | 3000 |
| web1-r2 | 192.168.100.11 | 3001 |
| web2-r1 | 192.168.100.12 | 3000 |
| web2-r2 | 192.168.100.12 | 3001 |
