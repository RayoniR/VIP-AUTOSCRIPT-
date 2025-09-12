{
    "apiUrl": "https://{{SERVER_IP}}/{{API_TOKEN}}",
    "certSha256": "{{CERT_SHA256}}",
    "transport": "https",
    "proxy": {
        "host": "{{SERVER_IP}}",
        "port": 443,
        "method": "chacha20-ietf-poly1305",
        "password": "{{PASSWORD}}",
        "prefix": "",
        "udp": true,
        "tcp": true
    },
    "metrics": {
        "enabled": true,
        "interval": 300,
        "url": "https://metrics.outline.io/report"
    },
    "session": {
        "id": "{{SESSION_ID}}",
        "created": "{{GENERATED_DATE}}",
        "expires": "{{EXPIRY_DATE}}",
        "bandwidth_limit": 2147483648000,
        "bandwidth_used": 0
    },
    "network": {
        "timeout": 30,
        "keepalive": 30,
        "retries": 3,
        "proxy_protocol": false
    },
    "security": {
        "tls": {
            "enabled": true,
            "sni": "{{SERVER_SNI}}",
            "alpn": ["h2", "http/1.1"],
            "fingerprint": "chrome",
            "session_ticket": true
        },
        "firewall": {
            "bypass_china": true,
            "block_ads": true,
            "block_malware": true
        }
    },
    "routing": {
        "strategy": "ip_if_nonmatch",
        "rules": [
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outbound_tag": "block"
            },
            {
                "type": "field",
                "ip": ["geoip:private", "geoip:cn"],
                "outbound_tag": "direct"
            }
        ]
    },
    "access_keys": {
        "id": "{{ACCESS_KEY_ID}}",
        "name": "{{USERNAME}}",
        "password": "{{PASSWORD}}",
        "data_limit": {
            "bytes": 2147483648000
        },
        "access_url": "ss://{{BASE64_CONFIG}}@{{SERVER_IP}}:443?outline=1"
    },
    "metadata": {
        "generated": "{{GENERATED_DATE}}",
        "server_id": "{{SERVER_ID}}",
        "user_id": "{{USER_ID}}",
        "version": "2.0.0"
    }
}