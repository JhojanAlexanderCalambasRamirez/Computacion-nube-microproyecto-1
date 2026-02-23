#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo ""
echo "================================================"
echo " Aprovisionando: HAProxy"
echo "================================================"

# ── 1. Actualizar sistema ─────────────────────────
echo ">>> [1/4] Actualizando paquetes..."
apt-get update -y -q

# ── 2. Instalar HAProxy ───────────────────────────
echo ">>> [2/4] Instalando HAProxy..."
apt-get install -y -q haproxy

# ── 3. Copiar configuracion ───────────────────────
echo ">>> [3/4] Copiando configuracion..."
mkdir -p /etc/haproxy/errors
cp /vagrant/haproxy/haproxy.cfg       /etc/haproxy/haproxy.cfg
cp /vagrant/haproxy/errors/503.http   /etc/haproxy/errors/503.http

echo "    Validando haproxy.cfg..."
haproxy -c -f /etc/haproxy/haproxy.cfg

# ── 4. Iniciar HAProxy ────────────────────────────
echo ">>> [4/4] Iniciando HAProxy..."
systemctl enable haproxy
systemctl restart haproxy

echo ""
echo "================================================"
echo " HAProxy aprovisionado exitosamente"
echo "  Version      : $(haproxy -v 2>&1 | head -1)"
echo "  Balanceador  : http://192.168.100.10  (Mac: http://localhost:8080)"
echo "  Estadisticas : http://192.168.100.10:8404/stats  (Mac: http://localhost:8404/stats)"
echo "  Credenciales : admin / admin"
echo "================================================"
