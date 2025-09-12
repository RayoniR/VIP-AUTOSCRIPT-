[Interface]
# VIP-Autoscript WireGuard Configuration
# Generated: {{GENERATED_DATE}}
# Expires: {{EXPIRY_DATE}}
# User: {{USERNAME}}
# Server: {{SERVER_ID}}

PrivateKey = {{CLIENT_PRIVATE_KEY}}
Address = 10.8.0.{{CLIENT_IP}}/24
DNS = 1.1.1.1, 8.8.8.8
MTU = 1420
Table = auto
PreUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
PreDown = iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
PostDown = iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT

[Peer]
# Server Configuration
PublicKey = {{SERVER_PUBLIC_KEY}}
PresharedKey = {{PSK}}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = {{SERVER_IP}}:51820
PersistentKeepalive = 25

# Advanced Settings
# Traffic Control
TC = off
TCFilter = 

# Multi-hop Routing
# AdditionalPeers = 

# Obfuscation
Obfuscation = wireguard-obfs
ObfuscationKey = {{OBFS_KEY}}

# Performance
RxQueueLen = 5000
TxQueueLen = 5000
FwMark = 51820

# Security
HandshakeTimeout = 180
RekeyTimeout = 120
RekeyAttempts = 3

# Monitoring
MonitorInterval = 30
MonitorTimeout = 10

# Services
# SSH: {{SSH_ENABLED}}
# Xray: {{XRAY_ENABLED}}