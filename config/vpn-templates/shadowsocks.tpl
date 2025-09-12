{
    "version": "2.0",
    "server": "{{SERVER_IP}}",
    "server_port": 8388,
    "method": "chacha20-ietf-poly1305",
    "password": "{{PASSWORD}}",
    "mode": "tcp_and_udp",
    "plugin": "v2ray-plugin",
    "plugin_opts": "server;tls;host={{SERVER_SNI}};path=/ss;loglevel=none",
    "remarks": "VIP-Autoscript SS User: {{USERNAME}}",
    "timeout": 300,
    "fast_open": true,
    "reuse_port": true,
    "no_delay": true,
    "dns": "1.1.1.1,8.8.8.8",
    "metadata": {
        "generated": "{{GENERATED_DATE}}",
        "expires": "{{EXPIRY_DATE}}",
        "username": "{{USERNAME}}",
        "server_id": "{{SERVER_ID}}"
    },
    "advanced": {
        "tcp": {
            "fast_open": true,
            "no_delay": true,
            "keep_alive": true,
            "reuse_port": true
        },
        "udp": {
            "timeout": 300,
            "buffer_size": 4096
        },
        "security": {
            "aead": true,
            "ota": false
        }
    },
    "routing": {
        "domain_strategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outboundTag": "block"
            }
        ]
    }
}