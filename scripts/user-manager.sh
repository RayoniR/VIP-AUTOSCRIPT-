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
    fi
    
    # Create SSH user
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    
    if [ $? -eq 0 ]; then
        # Add to user database
        jq --arg username "$username" \
            --arg created "$(date +%Y-%m-%d)" \
            '.ssh[$username] = {"created": $created, "last_login": "never"}' \
            "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
        
        print_status "SUCCESS" "SSH user added: $username"
    else
        print_status "ERROR" "Failed to add SSH user"
        return 1
    fi
}

# Function to remove SSH user
remove_ssh_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        print_status "ERROR" "Username is required to remove SSH user"
        return 1
    fi
    
    # Remove SSH user
    userdel -r "$username" 2>/dev/null
    
    # Remove from user database
    jq --arg username "$username" 'del(.ssh[$username])' \
        "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
    
    print_status "SUCCESS" "SSH user removed: $username"
}

# Function to list SSH users
list_ssh_users() {
    echo -e "\n${BLUE}===== SSH Users =====${NC}"
    jq -r '.ssh | to_entries[] | "Username: \(.key), Created: \(.value.created), Last Login: \(.value.last_login)"' "$USER_DB"
    echo -e "${BLUE}====================${NC}"
}

# Function to generate user configuration
generate_user_config() {
    local email=$1
    local protocol=${2:-"vless"}
    
    if [ -z "$email" ]; then
        print_status "ERROR" "Email is required to generate configuration"
        return 1
    fi
    
    local user_data=$(jq -r ".xray[\"$email\"]" "$USER_DB")
    if [ "$user_data" = "null" ]; then
        print_status "ERROR" "User not found: $email"
        return 1
    fi
    
    local uuid=$(echo "$user_data" | jq -r '.uuid')
    local server_ip=$(curl -s https://api.ipify.org)
    
    echo -e "\n${BLUE}===== User Configuration: $email =====${NC}"
    
    case $protocol in
        "vless")
            echo "Protocol: VLESS + XTLS"
            echo "Server: $server_ip"
            echo "Port: 443"
            echo "User ID: $uuid"
            echo "Flow: xtls-rprx-direct"
            echo "Encryption: none"
            echo "Transport: tcp"
            echo "TLS: true"
            echo "SNI: $server_ip"
            ;;
        "vmess")
            echo "Protocol: VMESS"
            echo "Server: $server_ip"
            echo "Port: 80"
            echo "User ID: $uuid"
            echo "Alter ID: 0"
            echo "Security: auto"
            echo "Transport: tcp"
            echo "TLS: false"
            ;;
        *)
            print_status "ERROR" "Unknown protocol: $protocol"
            return 1
            ;;
    esac
    
    echo -e "${BLUE}======================================${NC}"
}

# Function to show user menu
show_user_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         VIP-Autoscript User Manager    ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "1)  Add Xray user"
    echo -e "2)  Remove Xray user"
    echo -e "3)  List Xray users"
    echo -e "4)  Add SSH user"
    echo -e "5)  Remove SSH user"
    echo -e "6)  List SSH users"
    echo -e "7)  Generate user config"
    echo -e "8)  Backup user database"
    echo -e "9)  Restore user database"
    echo -e "10) Back to main menu"
    echo -e "${BLUE}========================================${NC}"
}

# Function to backup user database
backup_user_db() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/user_db_$timestamp.json"
    
    cp "$USER_DB" "$backup_file"
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "User database backed up: $backup_file"
    else
        print_status "ERROR" "Failed to backup user database"
        return 1
    fi
}

# Function to restore user database
restore_user_db() {
    local backup_file=$1
    
    if [ -z "$backup_file" ]; then
        print_status "ERROR" "Backup file is required"
        return 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_status "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    cp "$backup_file" "$USER_DB"
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "User database restored from: $backup_file"
        restart_xray
    else
        print_status "ERROR" "Failed to restore user database"
        return 1
    fi
}

# Main user function
main_user() {
    init_user_db
    
    local option=$1
    local param1=$2
    local param2=$3
    
    case $option in
        "add-xray")
            add_xray_user "$param1" "$param2"
            ;;
        "remove-xray")
            remove_xray_user "$param1"
            ;;
        "list-xray")
            list_xray_users
            ;;
        "add-ssh")
            add_ssh_user "$param1" "$param2"
            ;;
        "remove-ssh")
            remove_ssh_user "$param1"
            ;;
        "list-ssh")
            list_ssh_users
            ;;
        "generate-config")
            generate_user_config "$param1" "$param2"
            ;;
        "backup")
            backup_user_db
            ;;
        "restore")
            restore_user_db "$param1"
            ;;
        *)
            while true; do
                show_user_menu
                read -p "Choose an option: " choice
                
                case $choice in
                    1) read -p "Enter user email: " email
                       read -p "Enter user level [0]: " level
                       add_xray_user "$email" "${level:-0}"
                       read -p "Press Enter to continue..." ;;
                    2) read -p "Enter user email to remove: " email
                       remove_xray_user "$email"
                       read -p "Press Enter to continue..." ;;
                    3) list_xray_users
                       read -p "Press Enter to continue..." ;;
                    4) read -p "Enter SSH username: " username
                       read -s -p "Enter SSH password: " password
                       echo
                       add_ssh_user "$username" "$password"
                       read -p "Press Enter to continue..." ;;
                    5) read -p "Enter SSH username to remove: " username
                       remove_ssh_user "$username"
                       read -p "Press Enter to continue..." ;;
                    6) list_ssh_users
                       read -p "Press Enter to continue..." ;;
                    7) read -p "Enter user email: " email
                       read -p "Enter protocol [vless]: " protocol
                       generate_user_config "$email" "${protocol:-vless}"
                       read -p "Press Enter to continue..." ;;
                    8) backup_user_db
                       read -p "Press Enter to continue..." ;;
                    9) echo "Available backups:"
                       ls -1t "$BACKUP_DIR"/user_db_*.json 2>/dev/null | head -5
                       read -p "Enter backup file to restore: " backup_file
                       if [ -n "$backup_file" ]; then
                           restore_user_db "$backup_file"
                       fi
                       read -p "Press Enter to continue..." ;;
                    10) break ;;
                    *) print_status "ERROR" "Invalid option!"
                       sleep 1 ;;
                esac
            done
            ;;
    esac
}

# Parse command line arguments
if [ $# -gt 0 ]; then
    case $1 in
        -a|--add-xray)
            main_user "add-xray" "$2" "$3"
            exit 0
            ;;
        -r|--remove-xray)
            main_user "remove-xray" "$2"
            exit 0
            ;;
        -l|--list-xray)
            main_user "list-xray"
            exit 0
            ;;
        -A|--add-ssh)
            main_user "add-ssh" "$2" "$3"
            exit 0
            ;;
        -R|--remove-ssh)
            main_user "remove-ssh" "$2"
            exit 0
            ;;
        -L|--list-ssh)
            main_user "list-ssh"
            exit 0
            ;;
        -g|--generate-config)
            main_user "generate-config" "$2" "$3"
            exit 0
            ;;
        -b|--backup)
            main_user "backup"
            exit 0
            ;;
        -u|--restore)
            main_user "restore" "$2"
            exit 0
            ;;
        *)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -a, --add-xray [email] [level]     Add Xray user"
            echo "  -r, --remove-xray [email]          Remove Xray user"
            echo "  -l, --list-xray                    List Xray users"
            echo "  -A, --add-ssh [user] [pass]        Add SSH user"
            echo "  -R, --remove-ssh [user]            Remove SSH user"
            echo "  -L, --list-ssh                     List SSH users"
            echo "  -g, --generate-config [email] [proto] Generate user config"
            echo "  -b, --backup                       Backup user database"
            echo "  -u, --restore [file]               Restore user database"
            exit 1
            ;;
    esac
else
    # Start interactive mode if no arguments provided
    main_user
fi