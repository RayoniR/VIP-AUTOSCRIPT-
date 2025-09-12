version: "2.1"
metadata:
  generated: "{{GENERATED_DATE}}"
  expires: "{{EXPIRY_DATE}}"
  server: "{{SERVER_ID}}"
  user: "{{USERNAME}}"

connection:
  protocol: "vless"
  transport: "websocket"
  security: "tls"
  
  server:
    address: "{{SERVER_IP}}"
    port: 443
    sni: "{{SERVER_SNI}}"
    alpn: ["h2", "http/1.1"]

  authentication:
    username: "{{USERNAME}}"
    password: "{{PASSWORD}}"
    uuid: "{{UUID}}"
    flow: "xtls-rprx-vision"
    encryption: "none"

  network:
    path: "/darktunnel"
    headers:
      Host: "{{SERVER_SNI}}"
      User-Agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
      Upgrade: "websocket"
      Connection: "Upgrade"
      Sec-WebSocket-Version: "13"
      Sec-WebSocket-Key: "{{WEBSOCKET_KEY}}"

  performance:
    tcp_fast_open: true
    udp_fragment: true
    max_early_data: 4096
    early_data_header_name: "Sec-WebSocket-Protocol"

security:
  tls:
    enable: true
    allow_insecure: false
    server_name: "{{SERVER_SNI}}"
    fingerprint: "chrome"
    session_ticket: true
    reuse_session: true

  firewall:
    bypass_local: true
    bypass_china: true
    block_ads: true
    domain_strategy: "IPIfNonMatch"

services:
  ssh: {{SSH_ENABLED}}
  xray: {{XRAY_ENABLED}}
  bandwidth_limit: "2147483648000"  # 2TB in bytes
  concurrent_connections: 3

advanced:
  obfuscation:
    enabled: true
    method: "websocket"
    parameters:
      path: "/darktunnel"
      headers:
        Host: "{{SERVER_SNI}}"
        User-Agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

  routing:
    rules:
      - type: "field"
        domain: ["geosite:category-ads-all"]
        outboundTag: "block"
      - type: "field"
        ip: ["geoip:private", "geoip:cn"]
        outboundTag: "block"