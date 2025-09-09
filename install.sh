#!/bin/bash

# VIP-Autoscript Installation Script
# Installs and configures all required services

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        *) echo -e "[$status] $message" ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_status "ERROR" "Please run as root or use sudo"
    exit 1
fi

# Update system
print_status "INFO" "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required dependencies
print_status "INFO" "Installing dependencies..."
apt-get install -y curl wget git unzip jq systemctl ufw

# Create directories
print_status "INFO" "Creating directories..."
mkdir -p /etc/vip-autoscript/{config,services,scripts,logs,backups}

# Download and install Xray
print_status "INFO" "Installing Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Download and install BadVPN
print_status "INFO" "Installing BadVPN..."
apt-get install -y cmake build-essential
git clone https://github.com/ambrop72/badvpn.git /tmp/badvpn
cd /tmp/badvpn
mkdir build
cd build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make
cp udpgw/badvpn-udpgw /usr/local/bin/
cd /
rm -rf /tmp/badvpn

# Install SSH WebSocket (simplified)
print_status "INFO" "Setting up SSH WebSocket..."
apt-get install -y openssh-server
systemctl enable ssh

# Install SlowDNS (simplified)
print_status "INFO" "Setting up SlowDNS..."
apt-get install -y dnsutils

# Configure firewall
print_status "INFO" "Configuring firewall..."
ufw disable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   # SSH
ufw allow 443/tcp  # Xray
ufw allow 80/tcp   # Xray fallback
ufw allow 7300:7302/udp  # BadVPN
ufw allow 8080:8081/tcp  # SSH WebSocket
ufw allow 53/udp         # SlowDNS
ufw allow 5300/udp       # SlowDNS
ufw --force enable

# Create service files
print_status "INFO" "Creating service files..."

# Xray service file
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/vip-autoscript/config/xray.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# BadVPN service file
cat > /etc/systemd/system/badvpn.service << EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --listen-addr 127.0.0.1:7301 --listen-addr 127.0.0.1:7302
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# SSH WebSocket service file
cat > /etc/systemd/system/sshws.service << EOF
[Unit]
Description=SSH WebSocket Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/ssh -o GatewayPorts=yes -o PermitRootLogin=yes -D 8080 -N -f root@127.0.0.1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# SlowDNS service file
cat > /etc/systemd/system/slowdns.service << EOF
[Unit]
Description=SlowDNS Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/dnsmasq -k --conf-file=/etc/vip-autoscript-/config/slowdns.conf
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Create configuration files
print_status "INFO" "Creating configuration files..."

# Xray configuration
cat > /etc/vip-autoscript/config/xray.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$(cat /proc/sys/kernel/random/uuid)",
            "flow": "xtls-rprx-direct"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 80
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
          "alpn": ["http/1.1"],
          "certificates": [
            {
              "certificateFile": "/etc/ssl/certs/ssl-cert-snakeoil.pem",
              "keyFile": "/etc/ssl/private/ssl-cert-snakeoil.key"
            }
          ]
        }
      }
    },
    {
      "port": 80,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$(cat /proc/sys/kernel/random/uuid)"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {
          "header": {
            "type": "http",
            "response": {
              "version": "1.1",
              "status": "200",
              "reason": "OK",
              "headers": {
                "Content-Type": ["application/octet-stream", "application/x-msdownload", "text/html", "application/x-shockwave-flash"],
                "Transfer-Encoding": ["chunked"],
                "Connection": ["keep-alive"],
                "Pragma": "no-cache"
              }
            }
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# SlowDNS configuration
cat > /etc/vip-autoscript/config/slowdns.conf << EOF
# SlowDNS configuration
listen-address=127.0.0.1,::1
listen-address=0.0.0.0
port=53
bind-interfaces
user=dnsmasq
group=nogroup
EOF

# Reload systemd
print_status "INFO" "Reloading systemd..."
systemctl daemon-reload

# Enable services on boot
print_status "INFO" "Enabling services on boot..."
systemctl enable xray badvpn sshws slowdns

# Start services
print_status "INFO" "Starting services..."
systemctl start xray badvpn sshws slowdns

# Check services status
print_status "INFO" "Checking services status..."
sleep 3
echo "Xray status: $(systemctl is-active xray)"
echo "BadVPN status: $(systemctl is-active badvpn)"
echo "SSHWS status: $(systemctl is-active sshws)"
echo "SlowDNS status: $(systemctl is-active slowdns)"

print_status "SUCCESS" "Installation completed successfully!"
print_status "INFO" "You can manage services using: sudo ./vip-manager.sh"
