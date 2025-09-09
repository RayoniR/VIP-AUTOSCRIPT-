#!/bin/bash

# VIP-Autoscript Update Script

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_status "ERROR" "Please run as root or use sudo"
    exit 1
fi

print_status "INFO" "Starting update process..."

# Backup current configuration
print_status "INFO" "Backing up current configuration..."
tar -czf /etc/vip-autoscript/backups/backup_pre_update_$(date +%Y%m%d_%H%M%S).tar.gz /etc/vip-autoscript/config /etc/vip-autoscript/scripts

# Update Xray
print_status "INFO" "Updating Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Update system packages
print_status "INFO" "Updating system packages..."
apt-get update
apt-get upgrade -y

# Restart services
print_status "INFO" "Restarting services..."
systemctl restart xray badvpn sshws slowdns

print_status "SUCCESS" "Update completed successfully!"
