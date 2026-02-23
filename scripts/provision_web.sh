#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

HOSTNAME=$(hostname)
CONSUL_VERSION="1.17.1"

echo ""
echo "================================================"
echo " Aprovisionando: $HOSTNAME"
echo "================================================"

# ── 1. Actualizar sistema ─────────────────────────
echo ">>> [1/6] Actualizando paquetes..."
apt-get update -y -q
apt-get install -y -q curl wget unzip gnupg lsb-release

# ── 2. Instalar Node.js 20 LTS ───────────────────
echo ">>> [2/6] Instalando Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
apt-get install -y -q nodejs

# ── 3. Instalar Consul (binario) ──────────────────
echo ">>> [3/6] Instalando Consul ${CONSUL_VERSION}..."
ARCH=$(dpkg --print-architecture)   # detecta: amd64 o arm64
echo "    Arquitectura detectada: ${ARCH}"
wget -q "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_${ARCH}.zip" \
     -O /tmp/consul.zip
unzip -q /tmp/consul.zip -d /tmp/consul_bin
mv /tmp/consul_bin/consul /usr/local/bin/consul
chmod +x /usr/local/bin/consul
rm -rf /tmp/consul.zip /tmp/consul_bin

# ── 4. Crear directorios ──────────────────────────
echo ">>> [4/6] Creando directorios..."
mkdir -p /opt/consul/data
mkdir -p /etc/consul.d
mkdir -p /opt/app

# ── 5. Copiar archivos ────────────────────────────
echo ">>> [5/6] Copiando archivos de /vagrant..."

# App NodeJS
cp /vagrant/app/server.js    /opt/app/server.js
cp /vagrant/app/package.json /opt/app/package.json

# Config Consul segun el rol del nodo
if [ "$HOSTNAME" = "web1" ]; then
  echo "    Rol: Consul SERVER"
  cp /vagrant/consul/server.json /etc/consul.d/consul.json
else
  echo "    Rol: Consul AGENT"
  cp /vagrant/consul/client.json /etc/consul.d/consul.json
fi

# Definicion del servicio web (ambos nodos)
cp /vagrant/consul/web-service.json /etc/consul.d/web-service.json

# ── 6. Crear servicios systemd ────────────────────
echo ">>> [6/6] Configurando servicios systemd..."

# ── Consul service ──
cat > /etc/systemd/system/consul.service <<'EOF'
[Unit]
Description=HashiCorp Consul - Service Mesh
Documentation=https://www.consul.io/
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# ── NodeJS replica 1 (puerto 3000) ──
cat > /etc/systemd/system/nodeapp-3000.service <<'EOF'
[Unit]
Description=NodeJS Web Server - Replica 3000
After=network.target consul.service
Wants=consul.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
Environment=PORT=3000
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nodeapp-3000

[Install]
WantedBy=multi-user.target
EOF

# ── NodeJS replica 2 (puerto 3001) ──
cat > /etc/systemd/system/nodeapp-3001.service <<'EOF'
[Unit]
Description=NodeJS Web Server - Replica 3001
After=network.target consul.service
Wants=consul.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
Environment=PORT=3001
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nodeapp-3001

[Install]
WantedBy=multi-user.target
EOF

# ── Recargar e iniciar ──
systemctl daemon-reload

systemctl enable consul
systemctl start consul

echo "    Esperando que Consul estabilice..."
sleep 6

systemctl enable nodeapp-3000
systemctl start nodeapp-3000

systemctl enable nodeapp-3001
systemctl start nodeapp-3001

echo ""
echo "================================================"
echo " $HOSTNAME aprovisionado exitosamente"
echo "  Node.js : $(node --version)"
echo "  Consul  : $(consul --version | head -1)"
echo "  Replicas: :3000 y :3001"
echo "================================================"
