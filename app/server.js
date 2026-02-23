'use strict';

const http = require('http');
const os   = require('os');

const PORT = 3000;

function getPrivateIP() {
  const interfaces = os.networkInterfaces();
  for (const iface of Object.values(interfaces)) {
    for (const alias of iface) {
      if (alias.family === 'IPv4' && !alias.internal && alias.address.startsWith('192.168')) {
        return alias.address;
      }
    }
  }
  return '127.0.0.1';
}

const HOSTNAME = os.hostname();
const IP       = getPrivateIP();

const server = http.createServer((req, res) => {

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', host: HOSTNAME, ip: IP }));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Servidor - ${HOSTNAME}</title>
  <style>
    body { font-family: Arial, sans-serif; text-align: center; padding: 60px; background: #f0f4f8; }
    .card { background: white; border-radius: 12px; padding: 40px; max-width: 420px;
            margin: 0 auto; box-shadow: 0 4px 16px rgba(0,0,0,0.12); }
    h1   { color: #2d3748; margin-bottom: 20px; }
    p    { color: #718096; margin: 8px 0; }
    .badge { background: #48bb78; color: white; padding: 4px 14px;
             border-radius: 20px; font-size: 13px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Hola desde <strong>${HOSTNAME}</strong></h1>
    <p><strong>IP:</strong> ${IP}</p>
    <p><strong>Puerto:</strong> ${PORT}</p>
    <p><strong>Hora:</strong> ${new Date().toLocaleString('es-CO')}</p>
    <p><span class="badge">online</span></p>
  </div>
</body>
</html>
  `);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[${HOSTNAME}] Servidor corriendo en ${IP}:${PORT}`);
});
