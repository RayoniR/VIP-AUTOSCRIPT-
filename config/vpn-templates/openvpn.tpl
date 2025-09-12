# VIP-Autoscript OpenVPN Configuration
# Generated: {{GENERATED_DATE}}
# Expires: {{EXPIRY_DATE}}
# User: {{USERNAME}}
# Server: {{SERVER_ID}}

client
dev tun
proto tcp-client
remote {{SERVER_IP}} 443
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server

# Cipher settings
cipher AES-256-GCM
auth SHA256
auth-nocache
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384

# Performance
comp-lzo
tun-mtu 1500
mssfix 1450
sndbuf 393216
rcvbuf 393216
push "sndbuf 393216"
push "rcvbuf 393216"

# Security
reneg-sec 0
remote-cert-eku "TLS Web Server Authentication"
verify-x509-name {{SERVER_SNI}} name

# TLS Crypt
<tls-crypt>
-----BEGIN OpenVPN Static key V1-----
{{TLS_CRYPT_KEY}}
-----END OpenVPN Static key V1-----
</tls-crypt>

# Certificate
<ca>
-----BEGIN CERTIFICATE-----
{{CA_CERT}}
-----END CERTIFICATE-----
</ca>

# Authentication
<auth-user-pass>
{{USERNAME}}
{{PASSWORD}}
</auth-user-pass>

# HTTP Proxy
http-proxy {{SERVER_IP}} 80
http-proxy-option VERSION 1.1
http-proxy-option CUSTOM-HEADER Host {{SERVER_SNI}}
http-proxy-option CUSTOM-HEADER Upgrade $http_upgrade
http-proxy-option CUSTOM-HEADER Connection upgrade
http-proxy-option CUSTOM-HEADER Sec-WebSocket-Key $http_sec_websocket_key
http-proxy-option CUSTOM-HEADER Sec-WebSocket-Version 13

# Custom settings
script-security 2
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf

# Routing
route-metric 1
route-delay 5

# Keepalive
keepalive 10 30

# Logging
verb 3
mute 20
status /var/log/openvpn-status.log

# Services
# SSH: {{SSH_ENABLED}}
# Xray: {{XRAY_ENABLED}}