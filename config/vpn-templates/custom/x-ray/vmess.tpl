{
    "v": "2",
    "ps": "VIP-VMess-{{USERNAME}}",
    "add": "{{SERVER_IP}}",
    "port": "443",
    "id": "{{UUID}}",
    "aid": "0",
    "scy": "auto",
    "net": "ws",
    "type": "none",
    "host": "{{SERVER_SNI}}",
    "path": "/vmess",
    "tls": "tls",
    "sni": "{{SERVER_SNI}}",
    "alpn": "h2,http/1.1",
    "fp": "chrome",
    "flow": "xtls-rprx-vision",
    "allowInsecure": false,
    "v": "2",
    "protocol": "vmess",
    "transport": "websocket",
    "security": "tls",
    "metadata": {
        "generated": "{{GENERATED_DATE}}",
        "expires": "{{EXPIRY_DATE}}",
        "username": "{{USERNAME}}",
        "server": "{{SERVER_ID}}",
        "services": {
            "ssh": {{SSH_ENABLED}},
            "xray": {{XRAY_ENABLED}}
        },
        "bandwidth": {
            "limit": "2TB",
            "used": "0",
            "remaining": "2TB"
        },
        "connections": {
            "max": 3,
            "current": 0
        }
    },
    "performance": {
        "tcpFastOpen": true,
        "udpFragment": true,
        "multipath": true,
        "zeroRtt": true
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "ip": ["geoip:private", "geoip:cn"],
                "outboundTag": "direct"
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
            "fingerprint": "chrome",
            "show": false
        },
        "wsSettings": {
            "path": "/vmess",
            "headers": {
                "Host": "{{SERVER_SNI}}",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            }
        }
    }
}