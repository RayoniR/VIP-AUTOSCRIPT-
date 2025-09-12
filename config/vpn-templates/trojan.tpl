{
  "run_type": "client",
  "local_addr": "127.0.0.1",
  "local_port": 1080,
  "remote_addr": "{{SERVER_IP}}",
  "remote_port": 443,
  "password": ["{{PASSWORD}}"],
  "log_level": 2,
  "ssl": {
    "verify": true,
    "verify_hostname": true,
    "cert": "",
    "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA:AES128-SHA:AES256-SHA:DES-CBC3-SHA",
    "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
    "sni": "{{SERVER_SNI}}",
    "alpn": ["h2", "http/1.1"],
    "reuse_session": true,
    "session_ticket": false,
    "curves": "",
    "fingerprint": "chrome"
  },
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "reuse_port": false,
    "fast_open": true,
    "fast_open_qlen": 20
  },
  "websocket": {
    "enabled": true,
    "path": "/trojan",
    "host": "{{SERVER_SNI}}",
    "headers": {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.5",
      "Accept-Encoding": "gzip, deflate, br",
      "Connection": "keep-alive",
      "Upgrade": "websocket",
      "Sec-WebSocket-Version": "13",
      "Sec-WebSocket-Key": "{{WEBSOCKET_KEY}}",
      "Sec-WebSocket-Extensions": "permessage-deflate; client_max_window_bits"
    }
  },
  "mux": {
    "enabled": true,
    "concurrency": 8,
    "idle_timeout": 60
  },
  "router": {
    "enabled": true,
    "bypass": [
      "geoip:private",
      "geoip:cn"
    ],
    "block": [
      "geosite:category-ads-all"
    ],
    "proxy": [
      "geosite:geolocation-!cn"
    ],
    "default_policy": "proxy",
    "domain_strategy": "IPIfNonMatch"
  },
  "shadowsocks": {
    "enabled": false,
    "method": "AES-128-GCM",
    "password": ""
  },
  "transport_plugin": {
    "enabled": false,
    "type": "plaintext",
    "command": "",
    "option": "",
    "arg": [],
    "env": []
  },
  "metadata": {
    "generated": "{{GENERATED_DATE}}",
    "expires": "{{EXPIRY_DATE}}",
    "username": "{{USERNAME}}",
    "server": "{{SERVER_ID}}",
    "services": {
      "ssh": {{SSH_ENABLED}},
      "xray": {{XRAY_ENABLED}}
    }
  }
}