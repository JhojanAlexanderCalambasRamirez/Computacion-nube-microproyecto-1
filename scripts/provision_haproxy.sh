#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

CONSUL_TEMPLATE_VERSION="0.37.4"

echo ""
echo "================================================"
echo " Aprovisionando: HAProxy + consul-template"
echo "================================================"

# ── 1. Actualizar sistema ─────────────────────────
echo ">>> [1/5] Actualizando paquetes..."
apt-get update -y -q
apt-get install -y -q wget unzip

# ── 2. Instalar HAProxy ───────────────────────────
echo ">>> [2/5] Instalando HAProxy..."
apt-get install -y -q haproxy

# ── 3. Instalar consul-template ───────────────────
echo ">>> [3/5] Instalando consul-template ${CONSUL_TEMPLATE_VERSION}..."
ARCH=$(dpkg --print-architecture)   # detecta: amd64 o arm64
echo "    Arquitectura detectada: ${ARCH}"
wget -q "https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_${ARCH}.zip" \
     -O /tmp/ct.zip
unzip -q /tmp/ct.zip -d /tmp/ct_bin
mv /tmp/ct_bin/consul-template /usr/local/bin/consul-template
chmod +x /usr/local/bin/consul-template
rm -rf /tmp/ct.zip /tmp/ct_bin

# ── 4. Copiar configuracion ───────────────────────
echo ">>> [4/5] Copiando configuracion..."
mkdir -p /etc/haproxy/errors
mkdir -p /etc/consul-template

# Config estatica inicial (respaldo si consul-template aun no arranco)
cp /vagrant/haproxy/haproxy.cfg           /etc/haproxy/haproxy.cfg
cp /vagrant/haproxy/errors/503.http       /etc/haproxy/errors/503.http

# Template dinamico y config de consul-template
cp /vagrant/haproxy/haproxy.cfg.ctmpl     /etc/haproxy/haproxy.cfg.ctmpl
cp /vagrant/haproxy/consul-template.hcl   /etc/consul-template/consul-template.hcl

echo "    Validando haproxy.cfg estatico..."
haproxy -c -f /etc/haproxy/haproxy.cfg

# ── 5. Crear servicios systemd ────────────────────
echo ">>> [5/5] Configurando servicios systemd..."

# ── HAProxy service ──
# HAProxy lo inicia consul-template la primera vez que renderiza el template.
# Se define el servicio aqui para que systemctl reload/start funcione desde
# el comando en consul-template.hcl.
systemctl enable haproxy

# ── consul-template service ──
cat > /etc/systemd/system/consul-template.service <<'EOF'
[Unit]
Description=consul-template - Generador dinamico de haproxy.cfg desde Consul
Documentation=https://github.com/hashicorp/consul-template
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/consul-template -config=/etc/consul-template/consul-template.hcl
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=consul-template

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable consul-template
systemctl start consul-template

echo ""
echo "================================================"
echo " HAProxy + consul-template aprovisionados"
echo "  HAProxy          : $(haproxy -v 2>&1 | head -1)"
echo "  consul-template  : $(consul-template -version 2>&1 | head -1)"
echo "  Balanceador      : http://192.168.100.10  (Mac: http://localhost:8080)"
echo "  Estadisticas     : http://localhost:8404/stats"
echo "  Credenciales     : admin / admin"
echo "================================================"
