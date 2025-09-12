{
    "config_version": "2.3",
    "metadata": {
        "generated_at": "{{GENERATED_DATE}}",
        "server_id": "{{SERVER_ID}}",
        "template_version": "1.2.0"
    },
    "connection": {
        "protocol": "vless",
        "transport": "websocket",
        "security": "tls",
        "alpn": ["h2", "http/1.1"],
        "fingerprint": "chrome"
    },
    "server": {
        "address": "{{SERVER_IP}}",
        "sni": "{{SERVER_SNI}}",
        "port": 443,
        "ports": {
            "primary": 443,
            "fallback": 2053,
            "alternative": 2083
        }
    },
    "authentication": {
        "username": "{{USERNAME}}",
        "password": "{{PASSWORD}}",
        "uuid": "{{UUID}}",
        "flow": "xtls-rprx-vision",
        "encryption": "none"
    },
    "network": {
        "path": "/v2ray",
        "headers": {
            "Host": "{{SERVER_SNI}}",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Accept-Encoding": "gzip, deflate, br",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1"
        },
        "early_data": 2048,
        "max_early_data": 4096
    },
    "routing": {
        "domain_strategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "block"
            }
        ]
    },
    "performance": {
        "tcp_fast_open": true,
        "tcp_multi_path": true,
        "udp_fragment": true,
        "max_connections": 1000,
        "buffer_size": 4096
    },
    "services": {
        "ssh": {{SSH_ENABLED}},
        "xray": {{XRAY_ENABLED}},
        "expiry": "{{EXPIRY_DATE}}",
        "bandwidth_limit": "2TB",
        "concurrent_connections": 3
    },
    "advanced": {
        "tls_settings": {
            "allow_insecure": false,
            "disable_sni": false,
            "session_ticket": true,
            "reuse_session": true,
            "fingerprint": "randomized"
        },
        "websocket_settings": {
            "max_early_data": 4096,
            "early_data_header_name": "Sec-WebSocket-Protocol"
        }
    }
}