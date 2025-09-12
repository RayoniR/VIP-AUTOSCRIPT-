#!/bin/bash
# VIP-Autoscript Advanced User Manager
# Enterprise-grade user management system with atomic operations

set -euo pipefail
IFS=$'\n\t'

# Load configuration and libraries
readonly PANEL_ROOT="/etc/vip-autoscript-"
readonly CONFIG_DIR="${PANEL_ROOT}/config"
readonly LIB_DIR="${PANEL_ROOT}/lib"
readonly SCRIPTS_DIR="${PANEL_ROOT}/scripts"

source "${CONFIG_DIR}/panel.conf"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/validation.sh"
source "${LIB_DIR}/database.sh"
source "${LIB_DIR}/audit.sh"
source "${LIB_DIR}/lock.sh"

# Service configuration
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly SSH_USERS_DIR="/etc/ssh/authorized_users"
readonly XRAY_CONFIG="/usr/local/etc/xray/config.json"
readonly SERVICE_MANAGER="systemctl"
readonly USER_SHELL="/usr/sbin/nologin"
readonly USER_HOME_BASE="/home/vpn_users"
readonly MAX_USER_HOME_SIZE="100M"

# Security settings
readonly PASSWORD_HASH_ROUNDS=12
readonly MIN_UID=5000
readonly MAX_UID=10000
readonly DEFAULT_GID=100

# Rate limiting
readonly RATE_LIMIT_CREATE=10
readonly RATE_LIMIT_DELETE=5
readonly RATE_LIMIT_WINDOW=60

# External dependencies
readonly JQ_BIN=$(command -v jq || exit 1)
readonly AWK_BIN=$(command -v awk || exit 1)
readonly USERADD_BIN=$(command -v useradd || exit 1)
readonly USERDEL_BIN=$(command -v userdel || exit 1)
readonly PASSWD_BIN=$(command -v passwd || exit 1)
readonly CHAGE_BIN=$(command -v chage || exit 1)
readonly SETQUOTA_BIN=$(command -v setquota || exit 1)
readonly REPQUOTA_BIN=$(command -v repquota || exit 1)

declare -A RATE_LIMITS
declare -A USER_CACHE

umask 0077

user_manager::init() {
    utils::log "INFO" "User Manager initialized"
    mkdir -p "$USER_HOME_BASE"
    chmod 751 "$USER_HOME_BASE"
    user_manager::_check_dependencies
    user_manager::_setup_quotas
}

user_manager::_check_dependencies() {
    local deps=("$JQ_BIN" "$AWK_BIN" "$USERADD_BIN" "$USERDEL_BIN" "$PASSWD_BIN")
    
    for dep in "${deps[@]}"; do
        if [[ ! -x "$dep" ]]; then
            utils::log "ERROR" "Missing dependency: $dep"
            exit $EXIT_SERVICE_ERROR
        fi
    done
}

user_manager::_setup_quotas() {
    if [[ -x "$SETQUOTA_BIN" ]]; then
        local device=$(df "$USER_HOME_BASE" | awk 'NR==2 {print $1}')
        if [[ -n "$device" ]]; then
            quotacheck -cum "$USER_HOME_BASE" 2>/dev/null || true
            quotaon "$USER_HOME_BASE" 2>/dev/null || true
        fi
    fi
}

user_manager::_check_rate_limit() {
    local action="$1"
    local current_time=$(date +%s)
    local key="rate_${action}"
    
    if [[ -z "${RATE_LIMITS[$key]}" ]]; then
        RATE_LIMITS[$key]="$current_time:$RATE_LIMIT_CREATE"
        return 0
    fi
    
    IFS=':' read -r last_time count <<< "${RATE_LIMITS[$key]}"
    
    if [[ $((current_time - last_time)) -gt $RATE_LIMIT_WINDOW ]]; then
        RATE_LIMITS[$key]="$current_time:1"
        return 0
    fi
    
    if [[ $count -ge $RATE_LIMIT_CREATE ]]; then
        utils::log "WARN" "Rate limit exceeded for action: $action"
        return 1
    fi
    
    RATE_LIMITS[$key]="$last_time:$((count + 1))"
    return 0
}

user_manager::_get_next_uid() {
    local last_uid=$(getent passwd | awk -F: '$3 >= '$MIN_UID' && $3 <= '$MAX_UID' {print $3}' | sort -n | tail -1)
    local next_uid=$((last_uid + 1))
    
    if [[ $next_uid -gt $MAX_UID ]]; then
        utils::log "ERROR" "UID pool exhausted ($MIN_UID-$MAX_UID)"
        return $EXIT_SERVICE_ERROR
    fi
    
    echo $next_uid
}

user_manager::_create_system_user() {
    local username="$1"
    local password="$2"
    local uid="$3"
    
    # Create user with specific UID and home directory
    if ! $USERADD_BIN \
        --system \
        --shell "$USER_SHELL" \
        --home-dir "${USER_HOME_BASE}/${username}" \
        --uid "$uid" \
        --gid "$DEFAULT_GID" \
        --password "$(openssl passwd -6 "$password")" \
        "$username" 2>/dev/null; then
        utils::log "ERROR" "Failed to create system user: $username"
        return $EXIT_SERVICE_ERROR
    fi
    
    # Create and secure home directory
    mkdir -p "${USER_HOME_BASE}/${username}"
    chmod 700 "${USER_HOME_BASE}/${username}"
    chown "${username}:${DEFAULT_GID}" "${USER_HOME_BASE}/${username}"
    
    # Set disk quota
    if [[ -x "$SETQUOTA_BIN" ]]; then
        $SETQUOTA_BIN -u "$username" 0 "$MAX_USER_HOME_SIZE" 0 0 "$USER_HOME_BASE" 2>/dev/null || true
    fi
    
    return 0
}

user_manager::_delete_system_user() {
    local username="$1"
    
    # Remove user and home directory
    if ! $USERDEL_BIN -r "$username" 2>/dev/null; then
        utils::log "WARN" "Failed to delete system user completely: $username"
        # Force remove if necessary
        pkill -9 -u "$username" 2>/dev/null || true
        $USERDEL_BIN -f "$username" 2>/dev/null || true
        rm -rf "${USER_HOME_BASE}/${username}" 2>/dev/null || true
    fi
    
    return 0
}

user_manager::_configure_ssh_access() {
    local username="$1"
    local password="$2"
    
    # Create SSH authorized_keys directory if needed
    mkdir -p "$SSH_USERS_DIR"
    chmod 755 "$SSH_USERS_DIR"
    
    # Generate SSH key pair for user
    local ssh_dir="${USER_HOME_BASE}/${username}/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    ssh-keygen -t ed25519 -f "${ssh_dir}/id_ed25519" -N "$password" -q
    cat "${ssh_dir}/id_ed25519.pub" > "${SSH_USERS_DIR}/${username}"
    chmod 644 "${SSH_USERS_DIR}/${username}"
    
    # Update SSH configuration to include the user
    if ! grep -q "AuthorizedKeysFile.*${SSH_USERS_DIR}" "$SSH_CONFIG"; then
        sed -i "s|AuthorizedKeysFile.*|& ${SSH_USERS_DIR}/%u|" "$SSH_CONFIG"
        $SERVICE_MANAGER reload sshd 2>/dev/null
    fi
    
    utils::log "INFO" "SSH access configured for user: $username"
}

user_manager::_configure_xray_access() {
    local username="$1"
    local password="$2"
    
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        utils::log "WARN" "Xray configuration not found, skipping Xray setup"
        return 0
    fi
    
    # Generate UUID for Xray user
    local uuid=$(utils::generate_uuid)
    
    # Temporary configuration update
    local temp_config="${XRAY_CONFIG}.tmp"
    
    $JQ_BIN --arg user "$username" --arg uuid "$uuid" --arg pass "$password" \
        '.inbounds[].settings.clients += [{"id": $uuid, "email": $user, "password": $pass}]' \
        "$XRAY_CONFIG" > "$temp_config"
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_config" "$XRAY_CONFIG"
        chmod 600 "$XRAY_CONFIG"
        $SERVICE_MANAGER reload xray 2>/dev/null
        utils::log "INFO" "Xray access configured for user: $username"
    else
        rm -f "$temp_config"
        utils::log "ERROR" "Failed to update Xray configuration for user: $username"
        return $EXIT_SERVICE_ERROR
    fi
    
    return 0
}

user_manager::_remove_ssh_access() {
    local username="$1"
    
    # Remove SSH authorized key
    rm -f "${SSH_USERS_DIR}/${username}" 2>/dev/null
    
    # Clean up SSH configuration if no users left
    if [[ -z "$(ls -A "$SSH_USERS_DIR" 2>/dev/null)" ]]; then
        sed -i "s| ${SSH_USERS_DIR}/%u||" "$SSH_CONFIG" 2>/dev/null
        $SERVICE_MANAGER reload sshd 2>/dev/null
    fi
    
    utils::log "INFO" "SSH access removed for user: $username"
}

user_manager::_remove_xray_access() {
    local username="$1"
    
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        return 0
    fi
    
    local temp_config="${XRAY_CONFIG}.tmp"
    
    $JQ_BIN --arg user "$username" \
        'del(.inbounds[].settings.clients[] | select(.email == $user))' \
        "$XRAY_CONFIG" > "$temp_config"
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_config" "$XRAY_CONFIG"
        chmod 600 "$XRAY_CONFIG"
        $SERVICE_MANAGER reload xray 2>/dev/null
        utils::log "INFO" "Xray access removed for user: $username"
    else
        rm -f "$temp_config"
        utils::log "ERROR" "Failed to remove user from Xray configuration: $username"
        return $EXIT_SERVICE_ERROR
    fi
    
    return 0
}

user_manager::_set_expiry() {
    local username="$1"
    local expiry_days="$2"
    
    if [[ "$expiry_days" == "never" ]]; then
        $CHAGE_BIN -E -1 "$username" 2>/dev/null || true
        return 0
    fi
    
    local expiry_date=$(date -d "+$expiry_days days" +%Y-%m-%d 2>/dev/null || \
                       date -v+${expiry_days}d +%Y-%m-%d 2>/dev/null)
    
    if [[ -n "$expiry_date" ]]; then
        $CHAGE_BIN -E "$expiry_date" "$username" 2>/dev/null || true
    fi
    
    return 0
}

user_manager::create_user() {
    local username="$1"
    local service="$2"
    local expiry_days="$3"
    local password="${4:-}"
    
    if ! user_manager::_check_rate_limit "create"; then
        utils::log "ERROR" "Create rate limit exceeded"
        return $EXIT_SERVICE_ERROR
    fi
    
    # Validate input
    validation::clear_errors
    username=$(validation::validate_username "$username") || {
        utils::log "ERROR" "Username validation failed: $(validation::get_errors)"
        return $EXIT_VALIDATION_ERROR
    }
    
    service=$(validation::validate_service "$service") || {
        utils::log "ERROR" "Service validation failed: $(validation::get_errors)"
        return $EXIT_VALIDATION_ERROR
    }
    
    expiry_days=$(validation::validate_expiry "$expiry_days") || {
        utils::log "ERROR" "Expiry validation failed: $(validation::get_errors)"
        return $EXIT_VALIDATION_ERROR
    }
    
    # Generate password if not provided
    if [[ -z "$password" ]]; then
        password=$(utils::generate_password 16)
    else
        password=$(validation::validate_password "$password") || {
            utils::log "ERROR" "Password validation failed: $(validation::get_errors)"
            return $EXIT_VALIDATION_ERROR
        }
    fi
    
    # Get next available UID
    local uid=$(user_manager::_get_next_uid) || return $?
    
    # Create database entry first (atomic operation)
    if ! db::create_user "$username" "$service" "$expiry_days"; then
        utils::log "ERROR" "Failed to create database entry for user: $username"
        return $EXIT_DB_ERROR
    fi
    
    # Create system user
    if ! user_manager::_create_system_user "$username" "$password" "$uid"; then
        db::delete_user "$username"  # Rollback database entry
        return $EXIT_SERVICE_ERROR
    fi
    
    # Configure services based on selection
    case "$service" in
        "ssh")
            user_manager::_configure_ssh_access "$username" "$password"
            ;;
        "xray")
            user_manager::_configure_xray_access "$username" "$password"
            ;;
        "both")
            user_manager::_configure_ssh_access "$username" "$password"
            user_manager::_configure_xray_access "$username" "$password"
            ;;
    esac
    
    # Set account expiry
    user_manager::_set_expiry "$username" "$expiry_days"
    
    utils::log "INFO" "User created successfully: $username (service: $service, expiry: $expiry_days)"
    audit::log "USER_CREATE_COMPLETE" "User $username created with UID: $uid"
    
    # Return user information
    cat <<EOF
{
    "username": "$username",
    "password": "$password",
    "uid": "$uid",
    "service": "$service",
    "expiry_days": "$expiry_days",
    "status": "active"
}
EOF
    
    return $EXIT_SUCCESS
}

user_manager::delete_user() {
    local username="$1"
    local force="${2:-false}"
    
    if ! user_manager::_check_rate_limit "delete"; then
        utils::log "ERROR" "Delete rate limit exceeded"
        return $EXIT_SERVICE_ERROR
    fi
    
    # Validate user exists
    if ! db::user_exists "$username"; then
        utils::log "ERROR" "Cannot delete non-existent user: $username"
        return $EXIT_VALIDATION_ERROR
    fi
    
    # Get user data for service cleanup
    local user_data=$(db::get_user "$username")
    local service=$(echo "$user_data" | jq -r '.services | join(",")')
    
    # Remove service access
    case "$service" in
        "ssh"|"both")
            user_manager::_remove_ssh_access "$username"
            ;;
        "xray")
            user_manager::_remove_xray_access "$username"
            ;;
    esac
    
    # Delete system user
    if ! user_manager::_delete_system_user "$username"; then
        if [[ "$force" != "true" ]]; then
            utils::log "ERROR" "Failed to delete system user: $username"
            return $EXIT_SERVICE_ERROR
        fi
        utils::log "WARN" "Force deletion completed with errors for user: $username"
    fi
    
    # Remove from database
    if ! db::delete_user "$username"; then
        utils::log "ERROR" "Failed to delete database entry for user: $username"
        return $EXIT_DB_ERROR
    fi
    
    utils::log "INFO" "User deleted successfully: $username"
    audit::log "USER_DELETE_COMPLETE" "User $username deleted"
    
    return $EXIT_SUCCESS
}

user_manager::update_user() {
    local username="$1"
    local field="$2"
    local value="$3"
    
    if ! db::user_exists "$username"; then
        utils::log "ERROR" "Cannot update non-existent user: $username"
        return $EXIT_VALIDATION_ERROR
    fi
    
    case "$field" in
        "expiry")
            value=$(validation::validate_expiry "$value") || {
                utils::log "ERROR" "Expiry validation failed: $(validation::get_errors)"
                return $EXIT_VALIDATION_ERROR
            }
            user_manager::_set_expiry "$username" "$value"
            ;;
        "password")
            value=$(validation::validate_password "$value") || {
                utils::log "ERROR" "Password validation failed: $(validation::get_errors)"
                return $EXIT_VALIDATION_ERROR
            }
            echo "$username:$value" | chpasswd 2>/dev/null
            ;;
        "service")
            value=$(validation::validate_service "$value") || {
                utils::log "ERROR" "Service validation failed: $(validation::get_errors)"
                return $EXIT_VALIDATION_ERROR
            }
            # Complex service migration would go here
            ;;
        *)
            utils::log "ERROR" "Invalid field for update: $field"
            return $EXIT_VALIDATION_ERROR
            ;;
    esac
    
    if ! db::update_user "$username" "$field" "$value"; then
        utils::log "ERROR" "Failed to update database for user: $username"
        return $EXIT_DB_ERROR
    fi
    
    utils::log "INFO" "User updated: $username - $field: $value"
    audit::log "USER_UPDATE_COMPLETE" "User $username updated: $field = $value"
    
    return $EXIT_SUCCESS
}

user_manager::list_users() {
    local format="${1:-text}"
    local filter="${2:-}"
    
    local users=$(db::list_users)
    local output=""
    
    case "$format" in
        "json")
            output='{"users": ['
            local first=true
            while IFS= read -r user; do
                if [[ -n "$filter" ]] && [[ ! "$user" =~ $filter ]]; then
                    continue
                fi
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    output+=','
                fi
                local user_data=$(db::get_user "$user")
                output+="$user_data"
            done <<< "$users"
            output+=']}'
            ;;
        "csv")
            output="username,status,expiry_date,services,created"
            while IFS= read -r user; do
                if [[ -n "$filter" ]] && [[ ! "$user" =~ $filter ]]; then
                    continue
                fi
                local user_data=$(db::get_user "$user")
                local status=$(echo "$user_data" | jq -r '.status')
                local expiry=$(echo "$user_data" | jq -r '.expiry_date')
                local services=$(echo "$user_data" | jq -r '.services | join(";")')
                local created=$(echo "$user_data" | jq -r '.created')
                output+="\n$user,$status,$expiry,$services,$created"
            done <<< "$users"
            ;;
        *)
            output="Registered Users:\n"
            output+="================\n"
            while IFS= read -r user; do
                if [[ -n "$filter" ]] && [[ ! "$user" =~ $filter ]]; then
                    continue
                fi
                local user_data=$(db::get_user "$user")
                local status=$(echo "$user_data" | jq -r '.status')
                local expiry=$(echo "$user_data" | jq -r '.expiry_date')
                output+="• $user ($status, expires: $expiry)\n"
            done <<< "$users"
            ;;
    esac
    
    echo -e "$output"
}

user_manager::get_user_info() {
    local username="$1"
    local format="${2:-json}"
    
    if ! db::user_exists "$username"; then
        utils::log "ERROR" "User not found: $username"
        return $EXIT_VALIDATION_ERROR
    fi
    
    local user_data=$(db::get_user "$username")
    local system_info=""
    
    # Get system information if available
    if id "$username" &>/dev/null; then
        local uid=$(id -u "$username" 2>/dev/null)
        local gid=$(id -g "$username" 2>/dev/null)
        local home=$(getent passwd "$username" | cut -d: -f6)
        local shell=$(getent passwd "$username" | cut -d: -f7)
        
        system_info=$(cat <<EOF
,
  "system_info": {
    "uid": $uid,
    "gid": $gid,
    "home": "$home",
    "shell": "$shell",
    "disk_usage": "$(du -sh "$home" 2>/dev/null | cut -f1 || echo "unknown")"
  }
EOF
        )
    fi
    
    case "$format" in
        "json")
            echo "$user_data" | $JQ_BIN ". += {$system_info}"
            ;;
        "text")
            local status=$(echo "$user_data" | jq -r '.status')
            local expiry=$(echo "$user_data" | jq -r '.expiry_date')
            local services=$(echo "$user_data" | jq -r '.services | join(", ")')
            local created=$(echo "$user_data" | jq -r '.created')
            local modified=$(echo "$user_data" | jq -r '.last_modified')
            local configs=$(echo "$user_data" | jq -r '.configs_generated')
            
            cat <<EOF
User: $username
Status: $status
Expiry: $expiry
Services: $services
Created: $created
Modified: $modified
Configs Generated: $configs
EOF
            ;;
        *)
            utils::log "ERROR" "Invalid format: $format"
            return $EXIT_VALIDATION_ERROR
            ;;
    esac
    
    return $EXIT_SUCCESS
}

user_manager::check_expiries() {
    local users=$(db::list_users)
    local expired_count=0
    local warned_count=0
    
    while IFS= read -r user; do
        if db::check_expiry "$user"; then
            # Check if expiry is within warning period (7 days)
            local user_data=$(db::get_user "$user")
            local expiry=$(echo "$user_data" | jq -r '.expiry_date')
            local status=$(echo "$user_data" | jq -r '.status')
            
            if [[ "$expiry" != "never" && "$status" == "active" ]]; then
                local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null)
                local warning_ts=$(date -d "+7 days" +%s)
                
                if [[ $expiry_ts -le $warning_ts ]]; then
                    utils::log "WARN" "User $username will expire soon: $expiry"
                    ((warned_count++))
                fi
            fi
        else
            ((expired_count++))
        fi
    done <<< "$users"
    
    utils::log "INFO" "Expiry check completed: $expired_count expired, $warned_count nearing expiry"
    echo "Expired: $expired_count, Nearing expiry: $warned_count"
}

user_manager::cleanup() {
    local max_inactive_days="${1:-90}"
    
    utils::log "INFO" "Starting user cleanup (inactive > $max_inactive_days days)"
    
    local users=$(db::list_users)
    local cleaned_count=0
    
    while IFS= read -r user; do
        local user_data=$(db::get_user "$user")
        local last_modified=$(echo "$user_data" | jq -r '.last_modified')
        local status=$(echo "$user_data" | jq -r '.status')
        
        if [[ "$status" == "active" ]]; then
            local modified_ts=$(date -d "$last_modified" +%s 2>/dev/null)
            local cutoff_ts=$(date -d "$max_inactive_days days ago" +%s)
            
            if [[ $modified_ts -lt $cutoff_ts ]]; then
                utils::log "INFO" "Cleaning up inactive user: $user (last active: $last_modified)"
                user_manager::delete_user "$user" "true"
                ((cleaned_count++))
            fi
        fi
    done <<< "$users"
    
    utils::log "INFO" "Cleanup completed: $cleaned_count users removed"
    echo "Cleaned up $cleaned_count inactive users"
}

user_manager::backup() {
    local backup_type="${1:-full}"
    local backup_file=$(utils::create_backup "$backup_type")
    
    if [[ $? -eq 0 ]]; then
        echo "Backup created: $backup_file"
        return $EXIT_SUCCESS
    else
        return $EXIT_FAILURE
    fi
}

user_manager::restore() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        utils::log "ERROR" "Backup file not found: $backup_file"
        return $EXIT_FAILURE
    fi
    
    utils::log "INFO" "Restoring from backup: $backup_file"
    
    # Implementation would depend on backup format
    # This is a placeholder for actual restore logic
    case "$backup_file" in
        *.json)
            cp "$backup_file" "$USER_DB"
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$backup_file" -C "$PANEL_ROOT"
            ;;
        *)
            utils::log "ERROR" "Unsupported backup format: $backup_file"
            return $EXIT_FAILURE
            ;;
    esac
    
    utils::log "INFO" "Restore completed from: $backup_file"
    echo "Restore completed successfully"
    
    return $EXIT_SUCCESS
}

# Main execution
user_manager::init

case "${1:-}" in
    "create")
        shift
        user_manager::create_user "$@"
        ;;
    "delete")
        shift
        user_manager::delete_user "$@"
        ;;
    "update")
        shift
        user_manager::update_user "$@"
        ;;
    "list")
        shift
        user_manager::list_users "$@"
        ;;
    "info")
        shift
        user_manager::get_user_info "$@"
        ;;
    "check-expiries")
        user_manager::check_expiries
        ;;
    "cleanup")
        shift
        user_manager::cleanup "$@"
        ;;
    "backup")
        shift
        user_manager::backup "$@"
        ;;
    "restore")
        shift
        user_manager::restore "$@"
        ;;
    "stats")
        db::get_stats | $JQ_BIN .
        ;;
    *)
        cat <<EOF
VIP-Autoscript User Manager - Enterprise Grade User Management

Usage: $0 COMMAND [ARGS]

Commands:
  create USERNAME SERVICE EXPIRY_DAYS [PASSWORD] - Create new user
  delete USERNAME [force]                        - Delete user
  update USERNAME FIELD VALUE                    - Update user property
  list [format] [filter]                         - List users (text/json/csv)
  info USERNAME [format]                         - Get user information
  check-expiries                                 - Check and handle expired users
  cleanup [DAYS]                                 - Clean up inactive users
  backup [TYPE]                                  - Create backup (full/database/configs)
  restore FILE                                   - Restore from backup
  stats                                          - Show system statistics

Examples:
  $0 create john_doe ssh 30
  $0 delete john_doe
  $0 list json
  $0 info john_doe text
  $0 cleanup 90
EOF
        exit $EXIT_FAILURE
        ;;
esac

exit $?