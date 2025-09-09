#!/bin/bash

# VIP-Autoscript Backup Script

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

BACKUP_DIR="/etc/vip-autoscript/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

print_status "INFO" "Starting backup process..."

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create backup
tar -czf "$BACKUP_FILE" /etc/vip-autoscript/config /etc/vip-autoscript/scripts /etc/systemd/system/{xray,badvpn,sshws,slowdns}.service 2>/dev/null

if [ $? -eq 0 ]; then
    print_status "SUCCESS" "Backup created: $BACKUP_FILE"
    print_status "INFO" "Size: $(du -h "$BACKUP_FILE" | cut -f1)"
else
    print_status "ERROR" "Backup failed!"
    exit 1
fi
