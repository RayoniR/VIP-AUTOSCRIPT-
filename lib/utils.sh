#!/bin/bash
# VIP-Autoscript Utilities Module

utils::init() {
    mkdir -p "$USER_DIR" "$CONFIG_OUTPUT_DIR" "$LOG_DIR" "$BACKUP_DIR" "$TEMP_DIR"
    chmod 755 "$USER_DIR" "$CONFIG_OUTPUT_DIR"
    chmod 700 "$LOG_DIR" "$BACKUP_DIR" "$TEMP_DIR"
}

utils::generate_password() {
    local length="${1:-16}"
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom 2>/dev/null | head -c "$length"
}

utils::generate_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || \
    python -c 'import uuid; print(str(uuid.uuid4()))' 2>/dev/null || \
    echo "$(date +%s)$(utils::generate_password 8)" | md5sum | cut -d' ' -f1
}

utils::get_server_ip() {
    local ip=$(curl -s --connect-timeout 5 "$SERVER_IP_API" 2>/dev/null)
    if [[ -z "$ip" ]] || ! utils::validate_ip "$ip"; then
        ip="$SERVER_IP_FALLBACK"
    fi
    echo "$ip"
}

utils::validate_ip() {
    local ip="$1"
    local stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && \
           ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

utils::check_connectivity() {
    curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" "$CONNECTIVITY_CHECK_URL" >/dev/null 2>&1
    return $?
}

utils::create_backup() {
    local backup_type="$1"
    local backup_file="${BACKUP_DIR}/${backup_type}_$(date +%Y%m%d_%H%M%S).bak"
    
    case "$backup_type" in
        "database")
            cp "$USER_DB" "$backup_file"
            ;;
        "configs")
            tar -czf "$backup_file" -C "$CONFIG_OUTPUT_DIR" . 2>/dev/null
            ;;
        "full")
            tar -czf "$backup_file" -C "$PANEL_ROOT" \
                config/ lib/ users/ 2>/dev/null
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        utils::log "INFO" "Backup created: $backup_file"
        echo "$backup_file"
    else
        utils::log "ERROR" "Failed to create backup: $backup_type"
        return $EXIT_FAILURE
    fi
}

utils::cleanup_backups() {
    find "$BACKUP_DIR" -name "*.bak" -mtime +$DB_BACKUP_RETENTION -delete 2>/dev/null
    find "$LOG_DIR" -name "*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
}

utils::rotate_logs() {
    local log_file="$1"
    if [[ -f "$log_file" && $(stat -c%s "$log_file") -gt $LOG_ROTATE_SIZE ]]; then
        local rotated_file="${log_file}.$(date +%Y%m%d_%H%M%S)"
        mv "$log_file" "$rotated_file"
        touch "$log_file"
        chmod 600 "$log_file"
        gzip "$rotated_file" 2>/dev/null
    fi
}

utils::log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$PANEL_LOG"
    
    if [[ "$level" == "ERROR" ]]; then
        echo "[$timestamp] [$level] $message" >> "$ERROR_LOG"
    fi
    
    if [[ "$level" == "AUDIT" ]]; then
        echo "[$timestamp] $message" >> "$AUDIT_LOG"
    fi
}

utils::cleanup() {
    rm -rf "${TEMP_DIR}/*" 2>/dev/null
    utils::cleanup_backups
    utils::rotate_logs "$PANEL_LOG"
    utils::rotate_logs "$ERROR_LOG"
    utils::rotate_logs "$AUDIT_LOG"
}

utils::exit_handler() {
    local exit_code=$?
    utils::cleanup
    lock::release_all
    exit $exit_code
}

utils::error_handler() {
    local line="$1"
    local command="$2"
    local code="${3:-1}"
    
    utils::log "ERROR" "Error in ${BASH_SOURCE[1]}:$line - Command: '$command' - Exit code: $code"
    echo -e "${RED}Critical error occurred. Check logs for details.${NC}" >&2
    
    return $code
}

# Set traps
trap utils::exit_handler EXIT
trap 'utils::error_handler $LINENO "$BASH_COMMAND" $?' ERR