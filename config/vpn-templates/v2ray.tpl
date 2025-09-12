{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "127.0.0.1"
      },
      "tag": "socks"
    },
    {
      "port": 1081,
      "protocol": "http",
      "settings": {
        "timeout": 3600
      },
      "tag": "http"
    }
  ],
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "{{SERVER_IP}}",
            "port": 443,
            "users": [
              {
                "id": "{{UUID}}",
                "alterId": 0,
                "security": "auto",
                "level": 0
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "{{SERVER_SNI}}",
          "allowInsecure": false,
          "alpn": ["h2", "http/1.1"],
          "fingerprint": "chrome"
        },
        "wsSettings": {
          "path": "/v2ray",
          "headers": {
            "Host": "{{SERVER_SNI}}"
          }
        }
      },
      "mux": {
        "enabled": true,
        "concurrency": 8
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["geosite:cn"],
        "outboundTag": "direct"
      }
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5
      }
    }
  },
  "stats": {},
  "reverse": {},
  "transport": {
    "tcpSettings": {
      "acceptProxyProtocol": false
    }
  },
  "metadata": {
    "generated": "{{GENERATED_DATE}}",
    "expires": "{{EXPIRY_DATE}}",
    "username": "{{USERNAME}}",
    "server": "{{SERVER_ID}}"
  }
}