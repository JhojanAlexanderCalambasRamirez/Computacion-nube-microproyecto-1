# Conexion al agente Consul (servidor en web1)
consul {
  address = "192.168.100.11:8500"
  retry {
    enabled  = true
    attempts = 12
    backoff  = "250ms"
  }
}

# Template: genera haproxy.cfg desde el catalogo de Consul
# El comando se ejecuta cada vez que el archivo cambia:
#   - Si haproxy ya corre  → systemctl reload (recarga sin downtime)
#   - Si haproxy no corre  → systemctl start
template {
  source      = "/etc/haproxy/haproxy.cfg.ctmpl"
  destination = "/etc/haproxy/haproxy.cfg"
  command     = "haproxy -c -f /etc/haproxy/haproxy.cfg && (systemctl is-active --quiet haproxy && systemctl reload haproxy || systemctl start haproxy)"
  command_timeout = "30s"
}
