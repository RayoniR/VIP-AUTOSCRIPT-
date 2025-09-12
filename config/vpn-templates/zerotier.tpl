{
    "settings": {
        "allowGlobal": true,
        "allowDefault": false,
        "allowManaged": true,
        "allowDNS": true,
        "allowGlobalDefault": false,
        "allowDefaultDefault": false,
        "allowManagedDefault": true,
        "allowDNSDefault": true,
        "useDefaultRoute": true
    },
    "networks": {
        "{{NETWORK_ID}}": {
            "name": "VIP-ZeroTier-{{USERNAME}}",
            "clientId": "{{CLIENT_ID}}",
            "type": "network",
            "mtu": 2800,
            "routes": [
                {
                    "target": "0.0.0.0/0",
                    "via": null,
                    "flags": 0,
                    "metric": 0
                }
            ],
            "assignedAddresses": [
                "{{ZEROTIER_IP}}/24"
            ],
            "dns": {
                "servers": [
                    "1.1.1.1",
                    "8.8.8.8"
                ],
                "search": [
                    "zt"
                ],
                "domain": "zt"
            },
            "rules": [
                {
                    "type": "MATCH_ETHERTYPE",
                    "etherType": 2048,
                    "not": false,
                    "or": false
                },
                {
                    "type": "MATCH_ETHERTYPE",
                    "etherType": 2054,
                    "not": false,
                    "or": false
                },
                {
                    "type": "ACTION_DROP",
                    "not": false,
                    "or": false
                }
            ],
            "capabilities": [],
            "tags": [],
            "remoteTraceTarget": null,
            "remoteTraceLevel": 0,
            "ssoEnabled": false,
            "clientEnabled": true,
            "authTokens": {
                "{{SERVER_ID}}": "{{AUTH_TOKEN}}"
            }
        }
    },
    "physical": {
        "{{INTERFACE_NAME}}": {
            "bind": [],
            "blacklist": false,
            "mtu": 1500,
            "name": "eth0"
        }
    },
    "dns": {
        "domain": "zt",
        "servers": [
            "1.1.1.1",
            "8.8.8.8"
        ],
        "search": [
            "zt"
        ]
    },
    "virtual": {
        "{{TAP_DEVICE}}": {
            "name": "zt0",
            "type": "network",
            "mtu": 2800
        }
    },
    "security": {
        "certificate": "{{CLIENT_CERT}}",
        "privateKey": "{{PRIVATE_KEY}}",
        "trustedPaths": [
            "{{ROOT_CERT}}"
        ],
        "revocation": {
            "crl": [],
            "ocsp": []
        }
    },
    "metadata": {
        "generated": "{{GENERATED_DATE}}",
        "expires": "{{EXPIRY_DATE}}",
        "username": "{{USERNAME}}",
        "server": "{{SERVER_ID}}",
        "network": "{{NETWORK_ID}}"
    }
}