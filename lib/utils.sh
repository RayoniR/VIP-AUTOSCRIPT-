#!/bin/bash
# VIP-Autoscript Utilities Module

set -euo pipefail
IFS=$'\n\t'

# Configuration variables with defaults
readonly USER_DIR="${USER_DIR:-/etc/vip-autoscript/users}"
readonly CONFIG_OUTPUT_DIR="${CONFIG_OUTPUT_DIR:-/etc/vip-autoscript/configs}"
readonly LOG_DIR="${LOG_DIR:-/var/log/vip-autoscript}"
readonly BACKUP_DIR="${BACKUP_DIR:-/var/backups/vip-autoscript}"
readonly TEMP_DIR="${TEMP_DIR:-/tmp/vip-autoscript}"
readonly PANEL_ROOT="${PANEL_ROOT:-/usr/local/vip-autoscript}"

# Log files
readonly PANEL_LOG="${PANEL_LOG:-$LOG_DIR/panel.log}"
readonly ERROR_LOG="${ERROR_LOG:-$LOG_DIR/error.log}"
readonly AUDIT_LOG="${AUDIT_LOG:-$LOG_DIR/audit.log}"

# Network configuration
readonly SERVER_IP_API="${SERVER_IP_API:-https://api.ipify.org}"
readonly SERVER_IP_FALLBACK="${SERVER_IP_FALLBACK:-127.0.0.1}"
readonly CONNECTIVITY_CHECK_URL="${CONNECTIVITY_CHECK_URL:-https://www.google.com}"
readonly CONNECTIVITY_TIMEOUT="${CONNECTIVITY_TIMEOUT:-10}"

# Database configuration
readonly USER_DB="${USER_DB:-$PANEL_ROOT/data/users.db}"

# Retention settings
readonly DB_BACKUP_RETENTION="${DB_BACKUP_RETENTION:-30}"
readonly LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-90}"
readonly LOG_ROTATE_SIZE="${LOG_ROTATE_SIZE:-10485760}"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1

# Colors (only if output is to terminal)
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly NC=''
fi

utils::init() {
    mkdir -p "$USER_DIR" "$CONFIG_OUTPUT_DIR" "$LOG_DIR" "$BACKUP_DIR" "$TEMP_DIR"
    chmod 755 "$USER_DIR" "$CONFIG_OUTPUT_DIR" 2>/dev/null || true
    chmod 700 "$LOG_DIR" "$BACKUP_DIR" "$TEMP_DIR" 2>/dev/null || true
    
    # Create log files if they don't exist
    touch "$PANEL_LOG" "$ERROR_LOG" "$AUDIT_LOG" 2>/dev/null || true
    chmod 600 "$PANEL_LOG" "$ERROR_LOG" "$AUDIT_LOG" 2>/dev/null || true
}

utils::generate_password() {
    local length="${1:-16}"
    local use_special="${2:-true}"
    
    local char_set='A-Za-z0-9'
    if [[ "$use_special" == "true" ]]; then
        char_set='A-Za-z0-9!@#$%^&*()_+-='
    fi
    
    # Try multiple methods for password generation
    if command -v pwgen >/dev/null 2>&1; then
        pwgen -s -1 "$length" 2>/dev/null || return $EXIT_FAILURE
    elif command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 "$length" 2>/dev/null | tr -dc "$char_set" | head -c "$length" || return $EXIT_FAILURE
    else
        # Fallback to urandom
        tr -dc "$char_set" < /dev/urandom 2>/dev/null | head -c "$length" || return $EXIT_FAILURE
    fi
}

utils::generate_uuid() {
    # Try multiple UUID generation methods
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid 2>/dev/null || return $EXIT_FAILURE
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen 2>/dev/null || return $EXIT_FAILURE
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || return $EXIT_FAILURE
    elif command -v python >/dev/null 2>&1; then
        python -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || return $EXIT_FAILURE
    else
        # Final fallback - not cryptographically secure but functional
        echo "$(date +%s%N)$(utils::generate_password 8 false)" | md5sum | cut -d' ' -f1 2>/dev/null || return $EXIT_FAILURE
    fi
}

utils::get_server_ip() {
    local ip=""
    
    # Try multiple IP detection methods
    if command -v curl >/dev/null 2>&1; then
        ip=$(curl -s --connect-timeout 5 "$SERVER_IP_API" 2>/dev/null || echo "")
    elif command -v wget >/dev/null 2>&1; then
        ip=$(wget -q -T 5 -O - "$SERVER_IP_API" 2>/dev/null || echo "")
    fi
    
    # Validate IP or use fallback
    if [[ -z "$ip" ]] || ! utils::validate_ip "$ip"; then
        ip="$SERVER_IP_FALLBACK"
        utils::log "WARN" "Using fallback IP: $ip"
    fi
    
    echo "$ip"
}

utils::validate_ip() {
    local ip="$1"
    local stat=1
    
    # Basic IP format validation
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        if [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && \
              ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]; then
            stat=0
        fi
    fi
    
    return $stat
}

utils::check_connectivity() {
    local timeout="${1:-$CONNECTIVITY_TIMEOUT}"
    local url="${2:-$CONNECTIVITY_CHECK_URL}"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s --connect-timeout "$timeout" "$url" >/dev/null 2>&1
        return $?
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout="$timeout" -O /dev/null "$url" >/dev/null 2>&1
        return $?
    else
        # If no network tools available, assume no connectivity
        return $EXIT_FAILURE
    fi
}

utils::create_backup() {
    local backup_type="$1"
    local backup_file="${BACKUP_DIR}/${backup_type}_$(date +%Y%m%d_%H%M%S).bak"
    local result=$EXIT_SUCCESS
    
    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR" 2>/dev/null || return $EXIT_FAILURE
    
    case "$backup_type" in
        "database")
            if [[ -f "$USER_DB" ]]; then
                cp "$USER_DB" "$backup_file" 2>/dev/null || result=$EXIT_FAILURE
            else
                utils::log "ERROR" "Database file not found: $USER_DB"
                return $EXIT_FAILURE
            fi
            ;;
        "configs")
            if [[ -d "$CONFIG_OUTPUT_DIR" ]]; then
                tar -czf "$backup_file" -C "$CONFIG_OUTPUT_DIR" . 2>/dev/null || result=$EXIT_FAILURE
            else
                utils::log "ERROR" "Config directory not found: $CONFIG_OUTPUT_DIR"
                return $EXIT_FAILURE
            fi
            ;;
        "full")
            if [[ -d "$PANEL_ROOT" ]]; then
                tar -czf "$backup_file" -C "$PANEL_ROOT" \
                    config/ lib/ users/ 2>/dev/null || result=$EXIT_FAILURE
            else
                utils::log "ERROR" "Panel root directory not found: $PANEL_ROOT"
                return $EXIT_FAILURE
            fi
            ;;
        *)
            utils::log "ERROR" "Unknown backup type: $backup_type"
            return $EXIT_FAILURE
            ;;
    esac
    
    if [[ $result -eq $EXIT_SUCCESS && -f "$backup_file" ]]; then
        utils::log "INFO" "Backup created: $backup_file"
        echo "$backup_file"
        return $EXIT_SUCCESS
    else
        utils::log "ERROR" "Failed to create backup: $backup_type"
        rm -f "$backup_file" 2>/dev/null || true
        return $EXIT_FAILURE
    fi
}

utils::cleanup_backups() {
    local backup_patterns=("*.bak" "*.tar.gz" "*.tgz" "*.zip")
    local log_patterns=("*.log" "*.log.*")
    
    # Cleanup old backups
    for pattern in "${backup_patterns[@]}"; do
        find "$BACKUP_DIR" -name "$pattern" -mtime "+$DB_BACKUP_RETENTION" -delete 2>/dev/null || true
    done
    
    # Cleanup old logs
    for pattern in "${log_patterns[@]}"; do
        find "$LOG_DIR" -name "$pattern" -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    done
    
    # Cleanup temp directory
    find "$TEMP_DIR" -type f -mtime +1 -delete 2>/dev/null || true
    find "$TEMP_DIR" -type d -empty -delete 2>/dev/null || true
}

utils::rotate_logs() {
    local log_file="$1"
    local max_size="${2:-$LOG_ROTATE_SIZE}"
    
    if [[ ! -f "$log_file" ]]; then
        return $EXIT_SUCCESS
    fi
    
    local current_size=$(_utils::get_file_size "$log_file")
    
    if [[ $current_size -gt $max_size ]]; then
        local rotated_file="${log_file}.$(date +%Y%m%d_%H%M%S)"
        
        if mv "$log_file" "$rotated_file" 2>/dev/null; then
            touch "$log_file" 2>/dev/null || true
            chmod 600 "$log_file" 2>/dev/null || true
            
            # Compress old log file
            gzip "$rotated_file" 2>/dev/null || true
            
            utils::log "INFO" "Rotated log file: $log_file -> $rotated_file.gz"
            return $EXIT_SUCCESS
        else
            utils::log "ERROR" "Failed to rotate log file: $log_file"
            return $EXIT_FAILURE
        fi
    fi
    
    return $EXIT_SUCCESS
}

_utils::get_file_size() {
    local file="$1"
    if command -v stat >/dev/null 2>&1; then
        if stat -c%s "$file" 2>/dev/null; then
            return
        elif stat -f%z "$file" 2>/dev/null; then
            return
        fi
    fi
    # Fallback to wc if stat fails
    wc -c < "$file" 2>/dev/null || echo "0"
}

utils::log() {
    local level="${1:-INFO}"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR" 2>/dev/null || return $EXIT_SUCCESS
    
    # Write to main log
    echo "[$timestamp] [$level] $message" >> "$PANEL_LOG" 2>/dev/null || true
    
    # Write to error log if level is ERROR
    if [[ "$level" == "ERROR" ]]; then
        echo "[$timestamp] [$level] $message" >> "$ERROR_LOG" 2>/dev/null || true
    fi
    
    # Write to audit log if level is AUDIT
    if [[ "$level" == "AUDIT" ]]; then
        echo "[$timestamp] $message" >> "$AUDIT_LOG" 2>/dev/null || true
    fi
    
    # Also output to stderr for ERROR level if interactive
    if [[ "$level" == "ERROR" && -t 2 ]]; then
        echo -e "${RED}[$timestamp] [$level] $message${NC}" >&2
    fi
}

utils::cleanup() {
    # Cleanup temp files
    find "$TEMP_DIR" -type f -name "*.tmp" -delete 2>/dev/null || true
    find "$TEMP_DIR" -type f -mtime +1 -delete 2>/dev/null || true
    
    # Cleanup backups and logs
    utils::cleanup_backups
    
    # Rotate logs
    utils::rotate_logs "$PANEL_LOG"
    utils::rotate_logs "$ERROR_LOG"
    utils::rotate_logs "$AUDIT_LOG"
    
    return $EXIT_SUCCESS
}

utils::exit_handler() {
    local exit_code=$?
    utils::cleanup
    
    # Release locks if lock module is available
    if declare -f lock::release_all >/dev/null 2>&1; then
        lock::release_all 2>/dev/null || true
    fi
    
    exit $exit_code
}

utils::error_handler() {
    local line="$1"
    local command="$2"
    local code="${3:-1}"
    local script_name="${BASH_SOURCE[1]:-unknown}"
    local script_line="${BASH_LINENO[0]:-0}"
    
    utils::log "ERROR" "Error in $script_name:$line (called from line $script_line) - Command: '$command' - Exit code: $code"
    
    # Only show user-friendly message if interactive
    if [[ -t 2 ]]; then
        echo -e "${RED}Critical error occurred. Check logs for details.${NC}" >&2
    fi
    
    return $code
}

# Helper function to check if running interactively
utils::is_interactive() {
    [[ -t 1 ]]
}

# Helper function to validate directory exists and is writable
utils::validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null || return $EXIT_FAILURE
    fi
    [[ -w "$dir" ]] && return $EXIT_SUCCESS || return $EXIT_FAILURE
}

# Initialize if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    utils::init
    echo "Utilities module initialized"
    exit $EXIT_SUCCESS
fi

# Set traps only if we're in the main shell context
if [[ $- == *i* ]]; then
    trap utils::exit_handler EXIT
    trap 'utils::error_handler $LINENO "$BASH_COMMAND" $?' ERR
fi