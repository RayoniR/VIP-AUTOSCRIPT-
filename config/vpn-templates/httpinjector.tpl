[Proxy]
Mode = Websocket
TLS = True
SNI = {{SERVER_SNI}}
Host = {{SERVER_SNI}}
Port = 443
Path = /ws
Username = {{USERNAME}}
Password = {{PASSWORD}}
UUID = {{UUID}}
Security = auto
Flow = xtls-rprx-vision

[Settings]
ConfigVersion = 3.0
Generated = {{GENERATED_DATE}}
Expiry = {{EXPIRY_DATE}}
ServerID = {{SERVER_ID}}

[Headers]
Host = {{SERVER_SNI}}
User-Agent = Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36
Accept = text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
Accept-Language = en-US,en;q=0.5
Accept-Encoding = gzip, deflate, br
Connection = keep-alive
Upgrade-Insecure-Requests = 1
Sec-WebSocket-Version = 13
Sec-WebSocket-Key = {{WEBSOCKET_KEY}}
Sec-WebSocket-Extensions = permessage-deflate; client_max_window_bits

[Advanced]
TCPFastOpen = True
MPTCP = True
UDPRelay = True
BufferSize = 4096
MaxConnections = 5
ALPN = h2,http/1.1
Fingerprint = chrome

[Routing]
BypassLAN = True
BypassChina = True
BlockAds = True
DomainStrategy = IPIfNonMatch

[Services]
SSH = {{SSH_ENABLED}}
Xray = {{XRAY_ENABLED}}
Bandwidth = 2TB
Concurrent = 3