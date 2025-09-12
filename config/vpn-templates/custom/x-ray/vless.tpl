{
    "version": "2.0",
    "protocol": "vless",
    "settings": {
        "vnext": [
            {
                "address": "{{SERVER_IP}}",
                "port": 443,
                "users": [
                    {
                        "id": "{{UUID}}",
                        "flow": "xtls-rprx-vision",
                        "encryption": "none",
                        "level": 0,
                        "email": "{{USERNAME}}@vip-autoscript.com"
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
            "fingerprint": "chrome",
            "show": false,
            "certificates": [
                {
                    "usage": "encipherment",
                    "certificateFile": "/etc/ssl/certs/vip-autoscript.crt",
                    "keyFile": "/etc/ssl/private/vip-autoscript.key"
                }
            ],
            "sessionTicket": true,
            "sessionReuse": true,
            "maxEarlyData": 4096,
            "earlyDataHeaderName": "Sec-WebSocket-Protocol"
        },
        "wsSettings": {
            "path": "/vless",
            "headers": {
                "Host": "{{SERVER_SNI}}",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
                "Accept-Language": "en-US,en;q=0.9",
                "Accept-Encoding": "gzip, deflate, br",
                "Connection": "keep-alive",
                "Upgrade": "websocket",
                "Sec-WebSocket-Version": "13",
                "Sec-WebSocket-Key": "{{WEBSOCKET_KEY}}",
                "Sec-WebSocket-Extensions": "permessage-deflate; client_max_window_bits",
                "Pragma": "no-cache",
                "Cache-Control": "no-cache"
            },
            "maxEarlyData": 4096,
            "useBrowserForwarding": true,
            "browserForwarding": {
                "enabled": true,
                "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                "acceptHeader": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            }
        },
        "sockopt": {
            "mark": 255,
            "tcpFastOpen": true,
            "tcpKeepAliveInterval": 30,
            "tcpKeepAliveIdle": 300,
            "tcpNoDelay": true,
            "tcpWindowClamp": 65535,
            "tcpMaxSeg": 1460,
            "tcpCongestion": "bbr",
            "tcpUserTimeout": 60000
        }
    },
    "mux": {
        "enabled": true,
        "concurrency": 8,
        "xudpConcurrency": 16,
        "xudpProxyUDP443": "reject",
        "xudpMaxStreams": 1024,
        "xudpMinStreams": 16,
        "xudpStreamIdleTimeout": 300,
        "xudpMaxIdleTimeout": 600,
        "xudpMaxPacketSize": 1500
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "domainMatcher": "hybrid",
        "rules": [
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outboundTag": "block",
                "enabled": true,
                "priority": 1
            },
            {
                "type": "field",
                "ip": ["geoip:private", "geoip:cn"],
                "outboundTag": "direct",
                "enabled": true,
                "priority": 2
            },
            {
                "type": "field",
                "domain": ["geosite:cn"],
                "outboundTag": "direct",
                "enabled": true,
                "priority": 3
            },
            {
                "type": "field",
                "protocol": ["bittorrent"],
                "outboundTag": "block",
                "enabled": true,
                "priority": 4
            },
            {
                "type": "field",
                "port": "0-65535",
                "outboundTag": "proxy",
                "enabled": true,
                "priority": 5
            }
        ],
        "balancers": [
            {
                "tag": "loadbalancer",
                "selector": ["proxy"],
                "strategy": {
                    "type": "random",
                    "settings": {
                        "checkInterval": "1m",
                        "checkTimeout": "4s",
                        "checkUrl": "https://www.google.com/generate_204",
                        "failureLimit": 3,
                        "successLimit": 1
                    }
                }
            }
        ]
    },
    "outbounds": [
        {
            "tag": "proxy",
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "{{SERVER_IP}}",
                        "port": 443,
                        "users": [
                            {
                                "id": "{{UUID}}",
                                "flow": "xtls-rprx-vision",
                                "encryption": "none",
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
                    "path": "/vless",
                    "headers": {
                        "Host": "{{SERVER_SNI}}"
                    }
                }
            },
            "mux": {
                "enabled": true,
                "concurrency": 8
            }
        },
        {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIP",
                "redirect": ":0"
            }
        },
        {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {
                "response": {
                    "type": "http"
                }
            }
        }
    ],
    "policy": {
        "levels": {
            "0": {
                "handshake": 4,
                "connIdle": 300,
                "uplinkOnly": 2,
                "downlinkOnly": 5,
                "statsUserUplink": true,
                "statsUserDownlink": true,
                "bufferSize": 4096
            }
        },
        "system": {
            "statsInboundUplink": true,
            "statsInboundDownlink": true,
            "statsOutboundUplink": true,
            "statsOutboundDownlink": true
        }
    },
    "stats": {},
    "reverse": {},
    "transport": {
        "tcpSettings": {
            "acceptProxyProtocol": false,
            "header": {
                "type": "none"
            }
        },
        "kcpSettings": {
            "mtu": 1350,
            "tti": 20,
            "uplinkCapacity": 5,
            "downlinkCapacity": 20,
            "congestion": false,
            "readBufferSize": 2,
            "writeBufferSize": 2,
            "header": {
                "type": "none"
            },
            "seed": "{{KCP_SEED}}"
        },
        "wsSettings": {
            "acceptProxyProtocol": false,
            "path": "/vless",
            "headers": {
                "Host": "{{SERVER_SNI}}"
            }
        },
        "httpSettings": {
            "host": ["{{SERVER_SNI}}"],
            "path": "/vless"
        },
        "quicSettings": {
            "security": "none",
            "key": "",
            "header": {
                "type": "none"
            }
        },
        "dsSettings": {
            "path": "/var/run/xray/ds.sock",
            "abstract": false,
            "padding": false
        },
        "grpcSettings": {
            "serviceName": "vless-service",
            "multiMode": true,
            "idle_timeout": 60,
            "health_check_timeout": 20,
            "permit_without_stream": false,
            "initial_windows_size": 0
        }
    },
    "observatory": {
        "subjectSelector": ["proxy"],
        "probeURL": "https://www.google.com/generate_204",
        "probeInterval": "1m",
        "enableConcurrency": true
    },
    "api": {
        "tag": "api",
        "services": [
            "StatsService",
            "HandlerService",
            "LoggerService",
            "ObservatoryService"
        ]
    },
    "log": {
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log",
        "loglevel": "warning",
        "dnsLog": false
    },
    "dns": {
        "servers": [
            "1.1.1.1",
            "8.8.8.8",
            {
                "address": "localhost",
                "port": 53,
                "domains": ["geosite:cn"]
            }
        ],
        "queryStrategy": "UseIP",
        "disableCache": false,
        "disableFallback": false,
        "tag": "dns"
    },
    "fakeDns": {
        "ipPool": "198.18.0.0/15",
        "poolSize": 65535
    },
    "metadata": {
        "generated": "{{GENERATED_DATE}}",
        "expires": "{{EXPIRY_DATE}}",
        "username": "{{USERNAME}}",
        "server": "{{SERVER_ID}}",
        "services": {
            "ssh": {{SSH_ENABLED}},
            "xray": {{XRAY_ENABLED}},
            "bandwidth": {
                "limit": 2147483648000,
                "used": 0,
                "remaining": 2147483648000,
                "reset": "{{EXPIRY_DATE}}"
            },
            "connections": {
                "max": 3,
                "current": 0,
                "history": 0
            },
            "quota": {
                "upload": 1073741824000,
                "download": 1073741824000,
                "total": 2147483648000
            }
        },
        "performance": {
            "latency": 0,
            "jitter": 0,
            "packet_loss": 0,
            "throughput": 0,
            "quality": 100
        },
        "security": {
            "tls_version": "1.3",
            "cipher": "TLS_AES_128_GCM_SHA256",
            "forward_secrecy": true,
            "certificate_verified": true,
            "ocsp_stapling": true,
            "hsts": true
        },
        "network": {
            "ip": "{{SERVER_IP}}",
            "sni": "{{SERVER_SNI}}",
            "port": 443,
            "protocol": "vless",
            "transport": "websocket",
            "security": "tls",
            "obfuscation": "tls+websocket",
            "fingerprint": "chrome"
        },
        "client": {
            "version": "1.8.4",
            "build": "2023120100",
            "platform": "linux",
            "architecture": "amd64",
            "features": [
                "vless",
                "xtls",
                "vision",
                "websocket",
                "tls1.3",
                "multi-path",
                "zero-rtt"
            ]
        },
        "server": {
            "version": "1.8.4",
            "region": "global",
            "location": "{{SERVER_LOCATION}}",
            "provider": "VIP-Autoscript",
            "uptime": "{{SERVER_UPTIME}}",
            "load": "{{SERVER_LOAD}}",
            "memory": "{{SERVER_MEMORY}}",
            "storage": "{{SERVER_STORAGE}}"
        },
        "config_version": "3.2.0",
        "compatibility": {
            "min_client_version": "1.8.0",
            "max_client_version": "2.0.0",
            "recommended_version": "1.8.4"
        }
    }
}