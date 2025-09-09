#!/bin/bash

# VIP-Autoscript User Account Management with Expiry
# Complete user management with automatic expiry and cleanup

set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly CONFIG_DIR="/etc/vip-autoscript/config"
readonly USER_DIR="/etc/vip-autoscript/users"
readonly LOG_DIR="/etc/vip-autoscript/logs"
readonly BACKUP_DIR="/etc/vip-autoscript/backups"
readonly LOCK_DIR="/tmp/vip-users"
readonly USER_DB="$USER_DIR/users.json"
readonly EXPIRY_LOG="$LOG_DIR/expiry.log"
readonly CRON_JOB="/etc/cron.d/vip-user-expiry"

# Service configurations
readonly SERVICES=("ssh" "xray" "badvpn" "slowdns")
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly SSH_USER_DIR="/home"
readonly XRAY_CONFIG="$CONFIG_DIR/xray.json"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Initialize system
init_system() {
    mkdir -p "$USER_DIR" "$LOG_DIR" "$BACKUP_DIR" "$LOCK_DIR"
    setup_logging
    setup_traps
    init_database
    setup_cron
}

# Setup logging
setup_logging() {
    exec 3>>"$EXPIRY_LOG"
}

setup_traps() {
    trap 'cleanup_lock; exit' INT TERM EXIT
}

# Database management
init_database() {
    if [[ ! -f "$USER_DB" ]]; then
        cat > "$USER_DB" << EOF
{
    "version": "1.0.0",
    "users": {},
    "metadata": {
        "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "last_modified": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "total_users": 0,
        "active_users": 0,
        "expired_users": 0
    },
    "settings": {
        "default_expiry_days": 30,
        "auto_cleanup": true,
        "notify_before_expiry": true,
        "notify_days_before": 7,
        "backup_before_delete": true
    }
}
EOF
    fi
}

# Setup cron job for expiry checking
setup_cron() {
    if [[ ! -f "$CRON_JOB" ]]; then
        cat > "$CRON_JOB" << EOF
# VIP User Expiry Management
# Check for expired users every hour
0 * * * * root /etc/vip-autoscript/scripts/user-manager.sh check-expiry
# Daily cleanup at 2 AM
0 2 * * * root /etc/vip-autoscript/scripts/user-manager.sh cleanup-expired
# Backup user database every Sunday
0 3 * * 0 root /etc/vip-autoscript/scripts/user-manager.sh backup
EOF
        chmod 644 "$CRON_JOB"
    fi
}

# Locking mechanism
acquire_lock() {
    local lock_file="$LOCK_DIR/user.lock"
    if ! mkdir "$lock_file" 2>/dev/null; then
        log_error "Could not acquire lock. Another operation may be in progress."
        exit 1
    fi
    echo $$ > "$lock_file/pid"
}

cleanup_lock() {
    rm -rf "$LOCK_DIR/user.lock"
}

# User creation with expiry
create_user() {
    local username="$1"
    local service="$2"
    local expiry_days="${3:-30}"
    
    acquire_lock
    
    if ! validate_username "$username"; then
        return 1
    fi

    if user_exists "$username"; then
        log_error "User already exists: $username"
        return 1
    fi

    local expiry_date=$(calculate_expiry_date "$expiry_days")
    local user_config=$(build_user_config "$username" "$service" "$expiry_date")
    
    case "$service" in
        "ssh")
            create_ssh_user "$username" "$expiry_date"
            ;;
        "xray")
            create_xray_user "$username" "$expiry_date"
            ;;
        "both")
            create_ssh_user "$username" "$expiry_date"
            create_xray_user "$username" "$expiry_date"
            ;;
        *)
            log_error "Unknown service: $service"
            return 1
            ;;
    esac

    if ! update_database "$username" "$user_config"; then
        log_error "Failed to update database for user: $username"
        rollback_user_creation "$username" "$service"
        return 1
    fi

    log_audit "USER_CREATE" "Created user: $username" "$user_config"
    print_success "User created successfully: $username (Expires: $expiry_date)"
    
    cleanup_lock
    return 0
}

# Create SSH user with expiry
create_ssh_user() {
    local username="$1"
    local expiry_date="$2"
    
    # Generate secure random password
    local password=$(generate_password)
    
    # Create user account
    if ! useradd -m -s /bin/bash "$username"; then
        log_error "Failed to create system user: $username"
        return 1
    fi
    
    # Set password
    echo "$username:$password" | chpasswd
    
    # Set account expiry
    chage -E "$(date -d "$expiry_date" +%Y-%m-%d)" "$username"
    
    # Configure SSH restrictions
    configure_ssh_restrictions "$username"
    
    print_info "SSH User: $username, Password: $password"
}

# Create Xray user with expiry
create_xray_user() {
    local username="$1"
    local expiry_date="$2"
    local uuid=$(generate_uuid)
    
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log_error "Xray configuration not found"
        return 1
    fi

    # Backup current config
    cp "$XRAY_CONFIG" "$XRAY_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add user to Xray config
    jq --arg username "$username" --arg uuid "$uuid" --arg expiry "$expiry_date" \
        '.inbounds[0].settings.clients += [{
            "id": $uuid,
            "email": $username,
            "expiry": $expiry,
            "level": 0,
            "flow": "xtls-rprx-direct"
        }]' "$XRAY_CONFIG" > "$XRAY_CONFIG.tmp"
    
    if [[ $? -eq 0 ]]; then
        mv "$XRAY_CONFIG.tmp" "$XRAY_CONFIG"
        
        # Restart Xray service
        if systemctl is-active --quiet xray; then
            systemctl restart xray
        fi
        
        print_info "Xray User: $username, UUID: $uuid, Expiry: $expiry_date"
    else
        log_error "Failed to add user to Xray configuration"
        return 1
    fi
}

# Check for expired users
check_expiry() {
    acquire_lock
    
    local current_date=$(date +%Y-%m-%d)
    local expired_users=()
    
    while read -r user; do
        local expiry_date=$(jq -r ".users[\"$user\"].expiry_date" "$USER_DB")
        
        if [[ "$expiry_date" != "never" && "$(date -d "$expiry_date" +%Y%m%d)" -lt "$(date -d "$current_date" +%Y%m%d)" ]]; then
            expired_users+=("$user")
            disable_user "$user"
        fi
    done < <(jq -r '.users | keys[]' "$USER_DB")
    
    if [[ ${#expired_users[@]} -gt 0 ]]; then
        log_audit "USERS_EXPIRED" "Found expired users" "$(printf '%s\n' "${expired_users[@]}")"
        print_info "Found ${#expired_users[@]} expired users"
    fi
    
    cleanup_lock
}

# Cleanup expired users
cleanup_expired() {
    acquire_lock
    
    local current_date=$(date +%Y-%m-%d)
    local cleaned_users=()
    
    while read -r user; do
        local expiry_date=$(jq -r ".users[\"$user\"].expiry_date" "$USER_DB")
        local services=$(jq -r ".users[\"$user\"].services | join(\",\")" "$USER_DB")
        
        if [[ "$expiry_date" != "never" && "$(date -d "$expiry_date" +%Y%m%d)" -lt "$(date -d "$current_date" +%Y%m%d)" ]]; then
            if delete_user "$user" "$services"; then
                cleaned_users+=("$user")
            fi
        fi
    done < <(jq -r '.users | keys[]' "$USER_DB")
    
    if [[ ${#cleaned_users[@]} -gt 0 ]]; then
        log_audit "USERS_CLEANED" "Cleaned expired users" "$(printf '%s\n' "${cleaned_users[@]}")"
        print_info "Cleaned ${#cleaned_users[@]} expired users"
    fi
    
    cleanup_lock
}

# Delete user completely
delete_user() {
    local username="$1"
    local services="$2"
    
    # Remove from services
    if [[ "$services" == *"ssh"* ]]; then
        delete_ssh_user "$username"
    fi
    
    if [[ "$services" == *"xray"* ]]; then
        delete_xray_user "$username"
    fi
    
    # Remove from database
    jq --arg username "$username" 'del(.users[$username])' "$USER_DB" > "$USER_DB.tmp"
    mv "$USER_DB.tmp" "$USER_DB"
    
    log_audit "USER_DELETED" "Deleted user: $username" "{\"services\": \"$services\"}"
    return 0
}

# Delete SSH user
delete_ssh_user() {
    local username="$1"
    
    # Kill user processes
    pkill -u "$username" 2>/dev/null || true
    
    # Remove user account
    userdel -r "$username" 2>/dev/null || true
    
    # Remove from SSH config if any
    sed -i "/^Match User $username$/,/^$/d" "$SSH_CONFIG" 2>/dev/null || true
}

# Delete Xray user
delete_xray_user() {
    local username="$1"
    
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        return 1
    fi

    # Backup current config
    cp "$XRAY_CONFIG" "$XRAY_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove user from Xray config
    jq --arg username "$username" \
        'del(.inbounds[0].settings.clients[] | select(.email == $username))' \
        "$XRAY_CONFIG" > "$XRAY_CONFIG.tmp"
    
    if [[ $? -eq 0 ]]; then
        mv "$XRAY_CONFIG.tmp" "$XRAY_CONFIG"
        
        # Restart Xray service
        if systemctl is-active --quiet xray; then
            systemctl restart xray
        fi
    else
        log_error "Failed to remove user from Xray configuration: $username"
        return 1
    fi
}

# Disable user (mark as expired but don't delete)
disable_user() {
    local username="$1"
    
    # Disable SSH access
    if id "$username" &>/dev/null; then
        usermod -L "$username" 2>/dev/null || true
        chage -E 1 "$username" 2>/dev/null || true
    fi
    
    # Update database
    jq --arg username "$username" \
        '.users[$username].enabled = false | 
         .users[$username].status = "expired"' \
        "$USER_DB" > "$USER_DB.tmp"
    
    mv "$USER_DB.tmp" "$USER_DB"
    
    log_audit "USER_DISABLED" "Disabled expired user: $username"
}

# Update user expiry
update_expiry() {
    local username="$1"
    local expiry_days="$2"
    
    acquire_lock
    
    if ! user_exists "$username"; then
        log_error "User does not exist: $username"
        return 1
    fi

    local expiry_date=$(calculate_expiry_date "$expiry_days")
    
    # Update SSH account expiry
    if id "$username" &>/dev/null; then
        chage -E "$(date -d "$expiry_date" +%Y-%m-%d)" "$username"
    fi
    
    # Update Xray configuration
    if [[ -f "$XRAY_CONFIG" ]]; then
        jq --arg username "$username" --arg expiry "$expiry_date" \
            '(.inbounds[0].settings.clients[] | select(.email == $username)).expiry = $expiry' \
            "$XRAY_CONFIG" > "$XRAY_CONFIG.tmp"
        
        if [[ $? -eq 0 ]]; then
            mv "$XRAY_CONFIG.tmp" "$XRAY_CONFIG"
            
            # Restart Xray service
            if systemctl is-active --quiet xray; then
                systemctl restart xray
            fi
        fi
    fi
    
    # Update database
    jq --arg username "$username" --arg expiry_date "$expiry_date" \
        '.users[$username].expiry_date = $expiry_date |
         .users[$username].status = "active"' \
        "$USER_DB" > "$USER_DB.tmp"
    
    mv "$USER_DB.tmp" "$USER_DB"
    
    log_audit "EXPIRY_UPDATED" "Updated user expiry: $username" "{\"new_expiry\": \"$expiry_date\"}"
    print_success "Updated expiry for $username: $expiry_date"
    
    cleanup_lock
    return 0
}

# Utility functions
validate_username() {
    local username="$1"
    
    # Username validation rules
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        log_error "Invalid username format: $username"
        return 1
    fi
    
    if [[ "$username" == "root" || "$username" == "admin" ]]; then
        log_error "Cannot use reserved username: $username"
        return 1
    fi
    
    return 0
}

user_exists() {
    local username="$1"
    jq -e ".users[\"$username\"]" "$USER_DB" >/dev/null 2>&1
}

calculate_expiry_date() {
    local days="$1"
    if [[ "$days" == "never" ]]; then
        echo "never"
    else
        date -d "+$days days" +%Y-%m-%d
    fi
}

generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*()' < /dev/urandom | head -c 16
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

configure_ssh_restrictions() {
    local username="$1"
    
    # Add SSH configuration restrictions
    cat >> "$SSH_CONFIG" << EOF

# Restrictions for user $username
Match User $username
    PasswordAuthentication yes
    PermitTTY no
    X11Forwarding no
    AllowTcpForwarding yes
    PermitTunnel yes
    AllowAgentForwarding no
EOF
    
    # Reload SSH service
    systemctl reload ssh
}

build_user_config() {
    local username="$1"
    local service="$2"
    local expiry_date="$3"
    
    cat << EOF
{
    "username": "$username",
    "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "expiry_date": "$expiry_date",
    "status": "active",
    "enabled": true,
    "services": ["$service"],
    "last_modified": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

update_database() {
    local username="$1"
    local config="$2"
    
    local temp_db="$USER_DB.tmp"
    
    jq --arg username "$username" --argjson config "$config" \
        '.users[$username] = $config |
         .metadata.last_modified = "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'" |
         .metadata.total_users = (.users | length) |
         .metadata.active_users = (.users | to_entries | map(select(.value.enabled == true)) | length)' \
        "$USER_DB" > "$temp_db"
    
    if jq -e . >/dev/null 2>&1 < "$temp_db"; then
        mv "$temp_db" "$USER_DB"
        return 0
    else
        rm -f "$temp_db"
        return 1
    fi
}

# Logging functions
log_audit() {
    local action="$1"
    local message="$2"
    local data="${3:-}"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $action: $message - $data" >&3
}

log_error() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $message" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Backup and restore
backup_database() {
    local backup_file="$BACKUP_DIR/user-db-$(date +%Y%m%d_%H%M%S).json"
    cp "$USER_DB" "$backup_file"
    gzip "$backup_file"
    print_success "Database backed up: ${backup_file}.gz"
}

restore_database() {
    local backup_file="$1"
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    if gunzip -c "$backup_file" | jq -e . >/dev/null 2>&1; then
        gunzip -c "$backup_file" > "$USER_DB"
        print_success "Database restored from: $backup_file"
        return 0
    else
        log_error "Invalid backup file: $backup_file"
        return 1
    fi
}

# List users with expiry info
list_users() {
    echo -e "\n${BLUE}===== User Accounts =====${NC}"
    jq -r '.users | to_entries[] | 
        "\(.key): \(.value.status) | Expires: \(.value.expiry_date) | Services: \(.value.services | join(\", \"))"' \
        "$USER_DB"
    echo -e "${BLUE}=========================${NC}"
}

# Show user details
show_user() {
    local username="$1"
    
    if ! user_exists "$username"; then
        log_error "User does not exist: $username"
        return 1
    fi
    
    echo -e "\n${BLUE}===== User Details: $username =====${NC}"
    jq -r ".users[\"$username\"]" "$USER_DB"
    echo -e "${BLUE}===============================${NC}"
}

# Main execution
main() {
    init_system
    
    local action="${1:-}"
    local username="${2:-}"
    local service="${3:-}"
    local expiry_days="${4:-}"
    
    case "$action" in
        "create")
            create_user "$username" "$service" "$expiry_days"
            ;;
        "delete")
            delete_user "$username" "$(jq -r ".users[\"$username\"].services | join(\",\")" "$USER_DB")"
            ;;
        "update-expiry")
            update_expiry "$username" "$expiry_days"
            ;;
        "check-expiry")
            check_expiry
            ;;
        "cleanup-expired")
            cleanup_expired
            ;;
        "list")
            list_users
            ;;
        "show")
            show_user "$username"
            ;;
        "backup")
            backup_database
            ;;
        "restore")
            restore_database "$username"
            ;;
        "disable")
            disable_user "$username"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

show_usage() {
    cat << EOF
VIP User Account Management with Expiry

Usage: $0 <action> [username] [service] [expiry_days]

Actions:
  create <user> <service> [days]     Create user with expiry (ssh, xray, both)
  delete <user>                      Delete user completely
  update-expiry <user> <days>        Update user expiry (days or "never")
  check-expiry                       Check for expired users
  cleanup-expired                    Delete expired users
  list                               List all users
  show <user>                        Show user details
  backup                             Backup user database
  restore <file>                     Restore from backup
  disable <user>                     Disable user account

Examples:
  $0 create john ssh 30             # SSH user expires in 30 days
  $0 create jane xray never         # Xray user never expires
  $0 create bob both 90             # Both services, 90 days
  $0 update-expiry john 60          # Extend to 60 days
  $0 check-expiry                   # Check for expired users
  $0 cleanup-expired                # Delete expired users
EOF
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi