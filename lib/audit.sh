#!/bin/bash
# VIP-Autoscript Advanced Audit Module
# Comprehensive auditing and logging system

set -euo pipefail
IFS=$'\n\t'

# Configuration variables (should be set by main script or defalts 
LOG_DIR="${LOG_DIR:-/var/log/vip-autoscript}"
SESSION_FILE="${SESSION_FILE:-/tmp/vip-session.id}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/vip-autoscript}"
EXIT_FAILURE="${EXIT_FAILURE:-1}"

# Audit configuration
LOG_DIR="${LOG_DIR:-/var/log/vip-autoscript}"
AUDIT_DB="${LOG_DIR}/audit.db"
AUDIT_RETENTION_DAYS=365
AUDIT_ROTATE_SIZE=10485760
AUDIT_MAX_EVENTS=1000000

# Audit levels
readonly AUDIT_LEVEL_DEBUG=0
readonly AUDIT_LEVEL_INFO=1
readonly AUDIT_LEVEL_WARN=2
readonly AUDIT_LEVEL_ERROR=3
readonly AUDIT_LEVEL_CRITICAL=4

# Audit categories
readonly AUDIT_CATEGORY_USER=1
readonly AUDIT_CATEGORY_SYSTEM=2
readonly AUDIT_CATEGORY_SECURITY=3
readonly AUDIT_CATEGORY_NETWORK=4
readonly AUDIT_CATEGORY_CONFIG=5
readonly AUDIT_CATEGORY_BACKUP=6

declare -A AUDIT_LEVELS=(
    [0]="DEBUG"
    [1]="INFO"
    [2]="WARN"
    [3]="ERROR"
    [4]="CRITICAL"
)

declare -A AUDIT_CATEGORIES=(
    [1]="USER"
    [2]="SYSTEM"
    [3]="SECURITY"
    [4]="NETWORK"
    [5]="CONFIG"
    [6]="BACKUP"
)

# Utility functions (since utils:: functions are not available)
_utils::generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback to simple random generation
        cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1
    fi
}

_utils::log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${AUDIT_LEVELS[$level]:-UNKNOWN}] $message" >&2
}

_utils::sanitize_sql() {
    local input="$1"
    # Remove SQL injection attempts - single quotes, semicolons, comments
    echo "$input" | sed -e "s/'/''/g" -e 's/;//g' -e 's/--.*//g'
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

_utils::format_bytes() {
    local bytes="$1"
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        # Simple formatting without numfmt
        if [[ $bytes -ge 1073741824 ]]; then
            printf "%.1fGiB" $(echo "$bytes / 1073741824" | bc -l)
        elif [[ $bytes -ge 1048576 ]]; then
            printf "%.1fMiB" $(echo "$bytes / 1048576" | bc -l)
        elif [[ $bytes -ge 1024 ]]; then
            printf "%.1fKiB" $(echo "$bytes / 1024" | bc -l)
        else
            printf "%dB" "$bytes"
        fi
    fi
}

_utils::get_cutoff_date() {
    local days="$1"
    # Try GNU date first, then BSD date
    date -d "$days days ago" +%Y-%m-%d 2>/dev/null || \
    date -v-${days}d +%Y-%m-%d 2>/dev/null || \
    date +%Y-%m-%d  # Fallback to today if both fail
}

audit::init() {
    mkdir -p "$(dirname "$AUDIT_DB")"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$SESSION_FILE")"
    audit::_ensure_db
    audit::_cleanup_old
}

audit::_ensure_db() {
    if [[ ! -f "$AUDIT_DB" ]]; then
        sqlite3 "$AUDIT_DB" <<EOF
CREATE TABLE audit_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    level INTEGER NOT NULL,
    category INTEGER NOT NULL,
    event_code TEXT NOT NULL,
    username TEXT,
    source_ip TEXT,
    user_agent TEXT,
    description TEXT,
    details TEXT,
    status INTEGER DEFAULT 0,
    session_id TEXT
);

CREATE INDEX idx_audit_timestamp ON audit_events(timestamp);
CREATE INDEX idx_audit_level ON audit_events(level);
CREATE INDEX idx_audit_category ON audit_events(category);
CREATE INDEX idx_audit_event_code ON audit_events(event_code);
CREATE INDEX idx_audit_username ON audit_events(username);
CREATE INDEX idx_audit_status ON audit_events(status);
CREATE INDEX idx_audit_session_id ON audit_events(session_id);

CREATE TABLE audit_sessions (
    session_id TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    start_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    end_time DATETIME,
    source_ip TEXT,
    user_agent TEXT,
    status INTEGER DEFAULT 0,
    event_count INTEGER DEFAULT 0
);

CREATE TABLE audit_stats (
    date DATE PRIMARY KEY,
    total_events INTEGER DEFAULT 0,
    debug_events INTEGER DEFAULT 0,
    info_events INTEGER DEFAULT 0,
    warn_events INTEGER DEFAULT 0,
    error_events INTEGER DEFAULT 0,
    critical_events INTEGER DEFAULT 0
);
EOF
    fi
}

audit::_cleanup_old() {
    local cutoff_date=$(_utils::get_cutoff_date "$AUDIT_RETENTION_DAYS")
    
    sqlite3 "$AUDIT_DB" "DELETE FROM audit_events WHERE timestamp < '$cutoff_date';"
    sqlite3 "$AUDIT_DB" "VACUUM;"
}

audit::log() {
    local level="$1"
    local category="$2"
    local event_code="$3"
    local description="$4"
    local details="${5:-}"
    local username="${6:-}"
    local status="${7:-0}"
    
    # Sanitize inputs
    event_code=$(_utils::sanitize_sql "$event_code")
    description=$(_utils::sanitize_sql "$description")
    details=$(_utils::sanitize_sql "$details")
    username=$(_utils::sanitize_sql "$username")
    
    local source_ip=$(audit::_get_source_ip)
    local user_agent=$(audit::_get_user_agent)
    local session_id=$(audit::_get_session_id)
    
    if ! sqlite3 "$AUDIT_DB" <<EOF
INSERT INTO audit_events (
    level, category, event_code, username, source_ip, user_agent,
    description, details, status, session_id
) VALUES (
    $level, $category, '$event_code', '$username', '$source_ip', '$user_agent',
    '$description', '$details', $status, '$session_id'
);
EOF
    then
        _utils::log $AUDIT_LEVEL_ERROR "Failed to insert audit event: $event_code"
        return $EXIT_FAILURE
    fi
    
    # Update session event count
    if [[ -n "$session_id" ]]; then
        sqlite3 "$AUDIT_DB" "
            UPDATE audit_sessions 
            SET event_count = event_count + 1 
            WHERE session_id = '$session_id'
        " || true
    fi
    
    # Update daily stats
    local today=$(date +%Y-%m-%d)
    sqlite3 "$AUDIT_DB" "
        INSERT OR IGNORE INTO audit_stats (date) VALUES ('$today');
        UPDATE audit_stats SET total_events = total_events + 1 WHERE date = '$today';
        UPDATE audit_stats SET ${AUDIT_LEVELS[$level],,}_events = ${AUDIT_LEVELS[$level],,}_events + 1 
        WHERE date = '$today'
    " || true
    
    # Rotate if needed
    audit::_rotate_if_needed
    
    return 0
}

audit::_get_source_ip() {
    local ip="${SSH_CLIENT%% *}"
    if [[ -z "$ip" ]]; then
        ip="${HTTP_X_FORWARDED_FOR:-${HTTP_CLIENT_IP:-${REMOTE_ADDR:-unknown}}}"
    fi
    echo "$ip" | tr -d '\n\r' | cut -c1-45
}

audit::_get_user_agent() {
    local agent="${HTTP_USER_AGENT:-CLI}"
    echo "$agent" | cut -c1-250 | tr -d '\n\r' | _utils::sanitize_sql
}

audit::_get_session_id() {
    if [[ -f "$SESSION_FILE" ]]; then
        head -n 1 "$SESSION_FILE" 2>/dev/null | tr -d '\n\r' || echo ""
    else
        echo ""
    fi
}

audit::_rotate_if_needed() {
    local db_size=$(_utils::get_file_size "$AUDIT_DB")
    local event_count=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM audit_events;" 2>/dev/null || echo "0")
    
    if [[ $db_size -gt $AUDIT_ROTATE_SIZE ]] || [[ $event_count -gt $AUDIT_MAX_EVENTS ]]; then
        audit::_rotate_db
    fi
}

audit::_rotate_db() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local rotated_db="${AUDIT_DB}.${timestamp}"
    
    # Backup current database
    cp "$AUDIT_DB" "$rotated_db"
    gzip "$rotated_db" 2>/dev/null || true
    
    # Create new database
    rm -f "$AUDIT_DB"
    audit::_ensure_db
    
    # Keep last 10 rotated files
    find "$(dirname "$AUDIT_DB")" -name "$(basename "$AUDIT_DB").*.gz" -type f 2>/dev/null | \
        sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
}

audit::start_session() {
    local username="$1"
    local source_ip=$(audit::_get_source_ip)
    local user_agent=$(audit::_get_user_agent)
    local session_id=$(_utils::generate_uuid)
    
    # Sanitize username
    username=$(_utils::sanitize_sql "$username")
    
    # Create session directory if needed
    local session_dir=$(dirname "$SESSION_FILE")
    mkdir -p "$session_dir"
    
    echo "$session_id" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE" 2>/dev/null || true
    
    if ! sqlite3 "$AUDIT_DB" <<EOF
INSERT INTO audit_sessions (
    session_id, username, source_ip, user_agent
) VALUES (
    '$session_id', '$username', '$source_ip', '$user_agent'
);
EOF
    then
        _utils::log $AUDIT_LEVEL_ERROR "Failed to start session for user: $username"
        rm -f "$SESSION_FILE"
        return $EXIT_FAILURE
    fi
    
    audit::log $AUDIT_LEVEL_INFO $AUDIT_CATEGORY_SYSTEM "SESSION_START" \
        "User session started" "username=$username" "$username"
    
    echo "$session_id"
    return 0
}

audit::end_session() {
    local status="${1:-0}"
    local session_id=$(audit::_get_session_id)
    local username=""
    
    if [[ -n "$session_id" ]]; then
        # Get username from session for logging
        username=$(sqlite3 "$AUDIT_DB" "SELECT username FROM audit_sessions WHERE session_id = '$session_id'" 2>/dev/null || echo "")
        
        sqlite3 "$AUDIT_DB" "
            UPDATE audit_sessions 
            SET end_time = CURRENT_TIMESTAMP, status = $status 
            WHERE session_id = '$session_id'
        " || true
        
        audit::log $AUDIT_LEVEL_INFO $AUDIT_CATEGORY_SYSTEM "SESSION_END" \
            "User session ended" "status=$status" "$username"
        
        rm -f "$SESSION_FILE" 2>/dev/null || true
    fi
    
    return 0
}

audit::get_events() {
    local limit="${1:-100}"
    local offset="${2:-0}"
    local filters="${3:-}"
    
    local where_clause=""
    if [[ -n "$filters" ]]; then
        where_clause="WHERE $filters"
    fi
    
    sqlite3 -header -csv "$AUDIT_DB" "
        SELECT 
            datetime(timestamp, 'localtime') as timestamp,
            '${AUDIT_LEVELS[level]}' as level,
            '${AUDIT_CATEGORIES[category]}' as category,
            event_code,
            username,
            source_ip,
            description,
            status
        FROM audit_events 
        $where_clause
        ORDER BY timestamp DESC 
        LIMIT $limit OFFSET $offset
    " 2>/dev/null || echo "Error querying audit events"
}

audit::get_stats() {
    local period="${1:-day}"
    local date_filter=""
    
    case "$period" in
        "day")
            date_filter="date = date('now')"
            ;;
        "week")
            date_filter="date >= date('now', '-7 days')"
            ;;
        "month")
            date_filter="date >= date('now', '-1 month')"
            ;;
        "year")
            date_filter="date >= date('now', '-1 year')"
            ;;
        *)
            date_filter="1=1"
            ;;
    esac
    
    sqlite3 -header -csv "$AUDIT_DB" "
        SELECT 
            date,
            total_events,
            debug_events,
            info_events,
            warn_events,
            error_events,
            critical_events
        FROM audit_stats 
        WHERE $date_filter
        ORDER BY date DESC
    " 2>/dev/null || echo "Error querying audit stats"
}

audit::export_events() {
    local format="${1:-csv}"
    local output_file="${2:-}"
    local filters="${3:-}"
    
    if [[ -z "$output_file" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        output_file="${BACKUP_DIR}/audit_export_${timestamp}.${format}"
    fi
    
    mkdir -p "$(dirname "$output_file")"
    
    case "$format" in
        "csv")
            audit::get_events 1000000 0 "$filters" > "$output_file"
            ;;
        "json")
            sqlite3 -json "$AUDIT_DB" "
                SELECT * FROM audit_events 
                WHERE $filters
                ORDER BY timestamp DESC
            " > "$output_file" 2>/dev/null || return $EXIT_FAILURE
            ;;
        "sql")
            sqlite3 "$AUDIT_DB" ".dump audit_events" > "$output_file" 2>/dev/null || return $EXIT_FAILURE
            ;;
        *)
            _utils::log "ERROR" "Unsupported export format: $format"
            return $EXIT_FAILURE
            ;;
    esac
    
    echo "$output_file"
    return 0
}

audit::search_events() {
    local query="$1"
    local limit="${2:-100}"
    
    # Sanitize search query to prevent SQL injection
    query=$(_utils::sanitize_sql "$query")
    
    sqlite3 -header -csv "$AUDIT_DB" "
        SELECT 
            datetime(timestamp, 'localtime') as timestamp,
            '${AUDIT_LEVELS[level]}' as level,
            '${AUDIT_CATEGORIES[category]}' as category,
            event_code,
            username,
            source_ip,
            description
        FROM audit_events 
        WHERE 
            event_code LIKE '%$query%' OR
            username LIKE '%$query%' OR
            description LIKE '%$query%' OR
            details LIKE '%$query%'
        ORDER BY timestamp DESC 
        LIMIT $limit
    " 2>/dev/null || echo "Error searching audit events"
}

audit::get_failed_logins() {
    local limit="${1:-50}"
    local hours="${2:-24}"
    
    sqlite3 -header -csv "$AUDIT_DB" "
        SELECT 
            datetime(timestamp, 'localtime') as timestamp,
            username,
            source_ip,
            user_agent,
            description
        FROM audit_events 
        WHERE 
            event_code = 'LOGIN_FAILED' AND
            timestamp >= datetime('now', '-$hours hours')
        ORDER BY timestamp DESC 
        LIMIT $limit
    " 2>/dev/null || echo "Error querying failed logins"
}

audit::get_user_activity() {
    local username="$1"
    local limit="${2:-100}"
    
    # Sanitize username
    username=$(_utils::sanitize_sql "$username")
    
    audit::get_events "$limit" 0 "username = '$username'"
}

audit::get_security_alerts() {
    local limit="${1:-50}"
    local hours="${2:-24}"
    
    sqlite3 -header -csv "$AUDIT_DB" "
        SELECT 
            datetime(timestamp, 'localtime') as timestamp,
            event_code,
            username,
            source_ip,
            description,
            details
        FROM audit_events 
        WHERE 
            level >= $AUDIT_LEVEL_ERROR AND
            timestamp >= datetime('now', '-$hours hours')
        ORDER BY timestamp DESC 
        LIMIT $limit
    " 2>/dev/null || echo "Error querying security alerts"
}

audit::purge_events() {
    local days="${1:-}"
    local confirm="${2:-false}"
    
    if [[ -z "$days" ]]; then
        days=$AUDIT_RETENTION_DAYS
    fi
    
    if [[ "$confirm" != "true" ]]; then
        _utils::log $AUDIT_LEVEL_ERROR "Purge operation requires confirmation"
        return $EXIT_FAILURE
    fi
    
    local cutoff_date=$(_utils::get_cutoff_date "$days")
    
    local count=$(sqlite3 "$AUDIT_DB" "
        SELECT COUNT(*) FROM audit_events 
        WHERE timestamp < '$cutoff_date'
    " 2>/dev/null || echo "0")
    
    sqlite3 "$AUDIT_DB" "
        DELETE FROM audit_events 
        WHERE timestamp < '$cutoff_date';
        VACUUM;
    " 2>/dev/null || true
    
    echo "Purged $count audit events older than $cutoff_date"
    return 0
}

audit::get_db_size() {
    local size=$(_utils::get_file_size "$AUDIT_DB")
    echo "Audit database size: $(_utils::format_bytes $size)"
}

audit::get_event_count() {
    local total=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM audit_events;" 2>/dev/null || echo "0")
    local today=$(sqlite3 "$AUDIT_DB" "
        SELECT COUNT(*) FROM audit_events 
        WHERE date(timestamp) = date('now')
    " 2>/dev/null || echo "0")
    
    echo "Total events: $total, Today: $today"
}

# Initialize audit system if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    audit::init
    echo "Audit system initialized"
fi