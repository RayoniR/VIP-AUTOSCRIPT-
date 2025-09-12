#!/bin/bash

# VIP-Autoscript User Management Panel with Config Generation
# Advanced panel with VPN config file creation and phone storage support

set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly CONFIG_DIR="/etc/vip-autoscript-/config"
readonly USER_DIR="/etc/vip-autoscript-/users"
readonly CONFIG_OUTPUT_DIR="/etc/vip-autoscript/generated_configs"
readonly USER_DB="$USER_DIR/users.json"
readonly PANEL_LOG="/etc/vip-autoscript-/logs/panel.log"

# VPN Client Types and File Extensions
declare -A VPN_EXTENSIONS=(
    ["HTTPCustom"]=".hc"
    ["HTTPInjector"]=".ehi"
    ["DarkTunnel"]=".dark"
    ["ShadowSocks"]=".ss"
    ["OpenVPN"]=".ovpn"
    ["WireGuard"]=".conf"
    ["L2TP"]=".l2tp"
    ["SSTP"]=".sstp"
    ["V2Ray"]=".json"
    ["Trojan"]=".trojan"
)

# Colors for UI
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly BG_BLUE='\033[44m'
readonly BG_GREEN='\033[42m'
readonly BG_RED='\033[41m'
readonly NC='\033[0m'

# Panel dimensions
readonly PANEL_WIDTH=80
readonly PANEL_HEIGHT=25

# Initialize system - REMOVED READFROM FROM PHONE_STORAGE_DIR
PHONE_STORAGE_DIR="/mnt/phone/Configs"  # This can be modified now

init_system() {
    mkdir -p "$USER_DIR" "$CONFIG_OUTPUT_DIR" "$(dirname "$PANEL_LOG")"
    if [[ ! -f "$USER_DB" ]]; then
        echo '{"users":{},"metadata":{"total_users":0,"active_users":0}}' > "$USER_DB"
    fi
    setup_phone_storage
}

# Phone Storage Setup - FIXED VERSION
setup_phone_storage() {
    # Try common phone mount points
    local phone_mounts=(
        "/run/user/1000/gvfs/*"  # GNOME
        "/media/$USER/*"         # Generic
        "/mnt/*"                 # Manual mounts
        "/tmp/phone*"            # Test directory
    )
    
    local found_mount=""
    for mount_pattern in "${phone_mounts[@]}"; do
        for mount_point in $mount_pattern; do
            if [[ -d "$mount_point" ]]; then
                found_mount="$mount_point"
                break 2
            fi
        done
    done
    
    if [[ -n "$found_mount" ]]; then
        PHONE_STORAGE_DIR="$found_mount/Configs"
        mkdir -p "$PHONE_STORAGE_DIR"
    else
        # Create local storage if phone not connected
        PHONE_STORAGE_DIR="$HOME/Phone_Configs"
        mkdir -p "$PHONE_STORAGE_DIR"
    fi
    
    echo "Using storage directory: $PHONE_STORAGE_DIR"
}

# ... [REST OF THE SCRIPT REMAINS EXACTLY THE SAME - JUST REMOVED readonly FROM PHONE_STORAGE_DIR] ...

# UI Functions
draw_box() {
    local width="$1"
    local title="$2"
    local color="${3:-$BLUE}"
    
    echo -e "${color}"
    echo "╔$(printf '═%.0s' $(seq 1 $((width-2))))╗"
    echo "║$(printf ' %-.0s' $(seq 1 $((width-4))))║" | sed "s/^║ /║ ${title} /"
    echo "╚$(printf '═%.0s' $(seq 1 $((width-2))))╝"
    echo -e "${NC}"
}

print_center() {
    local text="$1"
    local color="${2:-$WHITE}"
    local width="${3:-$PANEL_WIDTH}"
    
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s" ""
    echo -e "${color}${text}${NC}"
}

print_header() {
    clear
    echo -e "${BG_BLUE}${WHITE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                VIP-AUTOSCRIPT USER & CONFIG MANAGEMENT PANEL                ║"
    echo "║             Advanced User Accounts + VPN Config Generation                  ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_footer() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║ [N]ew User  [E]dit  [D]elete  [G]enerate Config  [S]tats  [Q]uit            ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_stats() {
    local total_users=$(jq '.metadata.total_users' "$USER_DB")
    local active_users=$(jq '.metadata.active_users' "$USER_DB")
    local expired_users=$((total_users - active_users))
    local config_count=$(find "$CONFIG_OUTPUT_DIR" -name "*.*" 2>/dev/null | wc -l)
    
    draw_box 60 "📊 SYSTEM STATISTICS" "$MAGENTA"
    echo -e " ${GREEN}• Total Users:${NC}      $total_users"
    echo -e " ${GREEN}• Active Users:${NC}     $active_users"
    echo -e " ${RED}• Expired Users:${NC}    $expired_users"
    echo -e " ${CYAN}• Config Files:${NC}     $config_count"
    echo -e " ${YELLOW}• Storage Directory:${NC}   ${PHONE_STORAGE_DIR/#$HOME/\~}"
    echo -e " ${BLUE}• Server Time:${NC}      $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

# User Operations
create_user_dialog() {
    local username
    local service
    local expiry_days
    local vpn_client
    local generate_config
    
    print_header
    draw_box 60 "➕ CREATE NEW USER" "$GREEN"
    
    read -p " Enter username: " username
    if [[ -z "$username" ]]; then
        show_error "Username cannot be empty!"
        return 1
    fi
    
    echo " Select service type:"
    echo "  1) SSH Only"
    echo "  2) Xray Only" 
    echo "  3) Both SSH & Xray"
    read -p " Enter choice [1-3]: " service_choice
    
    case $service_choice in
        1) service="ssh" ;;
        2) service="xray" ;;
        3) service="both" ;;
        *) service="ssh" ;;
    esac
    
    echo " Expiry options:"
    echo "  1) 7 days"
    echo "  2) 30 days"
    echo "  3) 90 days"
    echo "  4) Never expire"
    read -p " Enter choice [1-4]: " expiry_choice
    
    case $expiry_choice in
        1) expiry_days=7 ;;
        2) expiry_days=30 ;;
        3) expiry_days=90 ;;
        4) expiry_days="never" ;;
        *) expiry_days=30 ;;
    esac
    
    echo " Generate config file?"
    echo "  1) Yes, generate config"
    echo "  2) No, just create user"
    read -p " Enter choice [1-2]: " config_choice
    
    if [[ "$config_choice" == "1" ]]; then
        vpn_client=$(select_vpn_client)
        generate_config=true
    else
        generate_config=false
    fi
    
    # Create user
    if /etc/vip-autoscript-/scripts/user-managers.sh create "$username" "$service" "$expiry_days"; then
        show_success "User $username created successfully!"
        
        # Generate config if requested
        if [[ "$generate_config" == "true" ]]; then
            generate_config_file "$username" "$vpn_client"
        fi
    else
        show_error "Failed to create user $username"
    fi
}

select_vpn_client() {
    print_header
    draw_box 60 "📱 SELECT VPN CLIENT" "$CYAN"
    
    echo " Available VPN Clients:"
    local i=1
    local clients=()
    for client in "${!VPN_EXTENSIONS[@]}"; do
        echo "  $i) $client (${VPN_EXTENSIONS[$client]})"
        clients+=("$client")
        ((i++))
    done
    
    read -p " Select client [1-${#VPN_EXTENSIONS[@]}]: " choice
    if [[ "$choice" -ge 1 && "$choice" -le ${#clients[@]} ]]; then
        echo "${clients[$((choice-1))]}"
    else
        echo "HTTPCustom"  # Default
    fi
}

generate_config_file() {
    local username="$1"
    local vpn_client="$2"
    local extension="${VPN_EXTENSIONS[$vpn_client]}"
    local config_file="$CONFIG_OUTPUT_DIR/${username}_${vpn_client}${extension}"
    local phone_file="$PHONE_STORAGE_DIR/${username}_${vpn_client}${extension}"
    
    # Get user details for config
    local user_data=$(jq -r ".users[\"$username\"]" "$USER_DB")
    local expiry_date=$(jq -r '.expiry_date' <<< "$user_data")
    local services=$(jq -r '.services | join(",")' <<< "$user_data")
    
    # Generate config content based on VPN client
    local config_content=$(generate_config_content "$username" "$vpn_client" "$expiry_date" "$services")
    
    # Save config file
    echo "$config_content" > "$config_file"
    
    # Copy to phone storage
    if [[ -d "$(dirname "$phone_file")" ]]; then
        cp "$config_file" "$phone_file"
        show_success "Config saved to: $(basename "$phone_file")"
    else
        show_warning "Phone storage not available. Config saved locally: $(basename "$config_file")"
    fi
    
    show_info "Config generated: $config_file"
}

generate_config_content() {
    local username="$1"
    local vpn_client="$2"
    local expiry_date="$3"
    local services="$4"
    local server_ip=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
    
    case "$vpn_client" in
        "HTTPCustom")
            cat << EOF
[CONFIG]
server=$server_ip
username=$username
password=$(generate_password 12)
expiry=$expiry_date
services=$services
protocol=SSL
port=443
mode=websocket
EOF
            ;;
        "HTTPInjector")
            cat << EOF
# HTTP Injector Config
host: $server_ip
username: $username
uuid: $(generate_uuid)
expiry: $expiry_date
services: $services
path: /ws
tls: true
sni: $server_ip
EOF
            ;;
        "DarkTunnel")
            cat << EOF
{
    "config": {
        "server": "$server_ip",
        "username": "$username",
        "password": "$(generate_password 12)",
        "expiry": "$expiry_date",
        "services": "$services",
        "protocol": "vless",
        "port": 443
    }
}
EOF
            ;;
        "ShadowSocks")
            cat << EOF
{
    "server": "$server_ip",
    "server_port": 8388,
    "password": "$(generate_password 16)",
    "method": "aes-256-gcm",
    "plugin": "v2ray-plugin",
    "plugin_opts": "server;tls;host=$server_ip"
}
EOF
            ;;
        "OpenVPN")
            cat << EOF
client
dev tun
proto tcp
remote $server_ip 443
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
auth-user-pass
auth-nocache
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3
EOF
            ;;
        *)
            # Default config
            cat << EOF
# VPN Configuration for $username
Server: $server_ip
Username: $username
Password: $(generate_password 12)
Expiry: $expiry_date
Services: $services
Client: $vpn_client
Generated: $(date)
EOF
            ;;
    esac
}

# Enhanced utility functions
generate_password() {
    local length="${1:-16}"
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

show_users_table() {
    local users=()
    local statuses=()
    local expiries=()
    local services=()
    local configs=()
    
    # Get user data
    while IFS= read -r user; do
        users+=("$user")
        statuses+=("$(jq -r ".users[\"$user\"].status" "$USER_DB")")
        expiries+=("$(jq -r ".users[\"$user\"].expiry_date" "$USER_DB")")
        services+=("$(jq -r ".users[\"$user\"].services | join(\",\")" "$USER_DB")")
        
        # Check if config exists
        local config_count=$(find "$CONFIG_OUTPUT_DIR" -name "${user}_*" 2>/dev/null | wc -l)
        configs+=("$config_count")
    done < <(jq -r '.users | keys[]' "$USER_DB")
    
    draw_box 80 "👥 USER ACCOUNTS & CONFIGS" "$BLUE"
    
    if [[ ${#users[@]} -eq 0 ]]; then
        print_center "No users found" "$YELLOW"
        return
    fi
    
    # Table header
    echo -e " ${GREEN}Username       Status     Expiry Date     Services     Configs${NC}"
    echo -e " ${GREEN}-------------- ---------- --------------- ------------ -------${NC}"
    
    # Table rows
    for i in "${!users[@]}"; do
        local user="${users[$i]}"
        local status="${statuses[$i]}"
        local expiry="${expiries[$i]}"
        local service="${services[$i]}"
        local config_count="${configs[$i]}"
        
        # Color coding
        local status_color=$GREEN
        [[ "$status" == "expired" ]] && status_color=$RED
        [[ "$status" == "disabled" ]] && status_color=$YELLOW
        
        local config_color=$CYAN
        [[ "$config_count" -eq 0 ]] && config_color=$YELLOW
        
        printf " %-14s ${status_color}%-10s${NC} %-15s %-12s ${config_color}%7s${NC}\n" \
               "$user" "$status" "$expiry" "$service" "$config_count"
    done
    echo ""
}

generate_config_dialog() {
    local username
    local vpn_client
    
    print_header
    draw_box 60 "⚙️ GENERATE CONFIG" "$MAGENTA"
    
    read -p " Enter username: " username
    
    if ! user_exists "$username"; then
        show_error "User $username not found!"
        return 1
    fi
    
    show_user_details "$username"
    echo ""
    
    vpn_client=$(select_vpn_client)
    
    if generate_config_file "$username" "$vpn_client"; then
        show_success "Config generated successfully for $username!"
    else
        show_error "Failed to generate config for $username"
    fi
}

# Enhanced main panel loop
main_panel() {
    init_system
    
    while true; do
        print_header
        show_stats
        show_users_table
        print_footer
        
        read -n 1 -p " Select option: " choice
        echo ""
        
        case $choice in
            n|N) create_user_dialog ;;
            e|E) edit_user_dialog ;;
            d|D) delete_user_dialog ;;
            g|G) generate_config_dialog ;;
            s|S) show_stats
                 read -n 1 -p " Press any key to continue..." ;;
            q|Q) echo "Goodbye!"; exit 0 ;;
            *) show_error "Invalid option: $choice" ;;
        esac
    done
}

# Enhanced footer
print_footer() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║ [N]ew User  [E]dit  [D]elete  [G]enerate Config  [S]tats  [Q]uit            ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Add these missing functions for completeness
edit_user_dialog() {
    local username
    local new_expiry
    
    print_header
    draw_box 60 "✏️ EDIT USER" "$YELLOW"
    
    read -p " Enter username to edit: " username
    
    if ! user_exists "$username"; then
        show_error "User $username not found!"
        return 1
    fi
    
    show_user_details "$username"
    echo ""
    
    echo " New expiry options:"
    echo "  1) 7 days"
    echo "  2) 30 days"
    echo "  3) 90 days"
    echo "  4) Never expire"
    echo "  5) Custom days"
    read -p " Enter choice [1-5]: " expiry_choice
    
    case $expiry_choice in
        1) new_expiry=7 ;;
        2) new_expiry=30 ;;
        3) new_expiry=90 ;;
        4) new_expiry="never" ;;
        5) read -p " Enter custom days: " new_expiry ;;
        *) return 1 ;;
    esac
    
    if /etc/vip-autoscript-/scripts/user-managers.sh update-expiry "$username" "$new_expiry"; then
        show_success "User $username updated successfully!"
    else
        show_error "Failed to update user $username"
    fi
}

delete_user_dialog() {
    local username
    
    print_header
    draw_box 60 "🗑️ DELETE USER" "$RED"
    
    read -p " Enter username to delete: " username
    
    if ! user_exists "$username"; then
        show_error "User $username not found!"
        return 1
    fi
    
    show_user_details "$username"
    echo ""
    
    read -p " Are you sure you want to delete $username? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        show_info "Deletion cancelled"
        return 0
    fi
    
    if /etc/vip-autoscript-/scripts/user-managers.sh delete "$username"; then
        # Also delete config files
        find "$CONFIG_OUTPUT_DIR" -name "${username}_*" -delete
        find "$PHONE_STORAGE_DIR" -name "${username}_*" -delete 2>/dev/null || true
        
        show_success "User $username and associated configs deleted successfully!"
    else
        show_error "Failed to delete user $username"
    fi
}

user_exists() {
    local username="$1"
    jq -e ".users[\"$username\"]" "$USER_DB" >/dev/null 2>&1
}

show_user_details() {
    local username="$1"
    
    if ! user_exists "$username"; then
        show_error "User not found: $username"
        return 1
    fi
    
    local status=$(jq -r ".users[\"$username\"].status" "$USER_DB")
    local expiry=$(jq -r ".users[\"$username\"].expiry_date" "$USER_DB")
    local services=$(jq -r ".users[\"$username\"].services | join(\", \")" "$USER_DB")
    local created=$(jq -r ".users[\"$username\"].created" "$USER_DB")
    
    echo -e " ${CYAN}Username:${NC}    $username"
    echo -e " ${CYAN}Status:${NC}      $status"
    echo -e " ${CYAN}Expiry:${NC}      $expiry"
    echo -e " ${CYAN}Services:${NC}    $services"
    echo -e " ${CYAN}Created:${NC}     $created"
}

show_error() {
    echo -e "${RED}❌ Error: $1${NC}"
    sleep 2
}

show_success() {
    echo -e "${GREEN}✅ Success: $1${NC}"
    sleep 2
}

show_info() {
    echo -e "${BLUE}ℹ️ Info: $1${NC}"
    sleep 1
}

show_warning() {
    echo -e "${YELLOW}⚠️ Warning: $1${NC}"
    sleep 1
}

# Quick actions from command line
quick_action() {
    local action="$1"
    local username="$2"
    local service="$3"
    local expiry="$4"
    
    case $action in
        "create")
            /etc/vip-autoscript-/scripts/user-managers.sh create "$username" "$service" "$expiry"
            ;;
        "delete")
            /etc/vip-autoscript-/scripts/user-managers.sh delete "$username"
            ;;
        "list")
            /etc/vip-autoscript-/scripts/user-managers.sh list
            ;;
        "stats")
            show_stats
            ;;
        "panel")
            main_panel
            ;;
        *)
            echo "Usage: $0 [create|delete|list|stats|panel] [username] [service] [expiry]"
            exit 1
            ;;
    esac
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        main_panel
    else
        quick_action "$@"
    fi
fi