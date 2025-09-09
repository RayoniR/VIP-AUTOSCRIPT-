#!/bin/bash

# VIP-Autoscript User Management
# Manages users for various services

# Configuration
CONFIG_DIR="/etc/vip-autoscript/config"
BACKUP_DIR="/etc/vip-autoscript/backups"
USER_DB="$CONFIG_DIR/users.json"

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

# Function to initialize user database
init_user_db() {
    if [ ! -f "$USER_DB" ]; then
        echo '{"xray": {}, "ssh": {}, "badvpn": {}}' > "$USER_DB"
        print_status "INFO" "User database initialized: $USER_DB"
    fi
}

# Function to generate UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Function to add Xray user
add_xray_user() {
    local email=$1
    local level=${2:-0}
    local uuid=$(generate_uuid)
    
    if [ -z "$email" ]; then
        print_status "ERROR" "Email is required for Xray user"
        return 1
    fi
    
    # Add user to Xray config
    jq --arg email "$email" --arg uuid "$uuid" --argjson level $level \
        '.inbounds[0].settings.clients += [{"id": $uuid, "email": $email, "level": $level}]' \
        "$CONFIG_DIR/xray.json" > "$CONFIG_DIR/xray.json.tmp" \
        && mv "$CONFIG_DIR/xray.json.tmp" "$CONFIG_DIR/xray.json"
    
    if [ $? -eq 0 ]; then
        # Add to user database
        jq --arg email "$email" --arg uuid "$uuid" --argjson level $level \
            '.xray[$email] = {"uuid": $uuid, "level": $level, "created": "'$(date +%Y-%m-%d)'"}' \
            "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
        
        print_status "SUCCESS" "Xray user added: $email"
        echo "UUID: $uuid"
        restart_xray
    else
        print_status "ERROR" "Failed to add Xray user"
        return 1
    fi
}

# Function to remove Xray user
remove_xray_user() {
    local email=$1
    
    if [ -z "$email" ]; then
        print_status "ERROR" "Email is required to remove Xray user"
        return 1
    fi
    
    # Remove user from Xray config
    jq --arg email "$email" \
        'del(.inbounds[0].settings.clients[] | select(.email == $email))' \
        "$CONFIG_DIR/xray.json" > "$CONFIG_DIR/xray.json.tmp" \
        && mv "$CONFIG_DIR/xray.json.tmp" "$CONFIG_DIR/xray.json"
    
    if [ $? -eq 0 ]; then
        # Remove from user database
        jq --arg email "$email" 'del(.xray[$email])' \
            "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
        
        print_status "SUCCESS" "Xray user removed: $email"
        restart_xray
    else
        print_status "ERROR" "Failed to remove Xray user"
        return 1
    fi
}

# Function to list Xray users
list_xray_users() {
    echo -e "\n${BLUE}===== Xray Users =====${NC}"
    jq -r '.xray | to_entries[] | "Email: \(.key), UUID: \(.value.uuid), Level: \(.value.level), Created: \(.value.created)"' "$USER_DB"
    echo -e "${BLUE}=====================${NC}"
}

# Function to restart Xray service
restart_xray() {
    print_status "INFO" "Restarting Xray service..."
    systemctl restart xray
    sleep 2
    
    if systemctl is-active --quiet xray; then
        print_status "SUCCESS" "Xray service restarted successfully"
    else
        print_status "ERROR" "Failed to restart Xray service"
        return 1
    fi
}

# Function to add SSH user
add_ssh_user() {
    local username=$1
    local password=$2
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        print_status "ERROR" "Username and password are required for SSH user"
        return 1
