#!/bin/bash
# VIP-Autoscript Advanced Audit Module
# Comprehensive auditing and logging system

set -euo pipefail
IFS=$'\n\t'

# Audit configuration
AUDIT_DB="${LOG_DIR}/audit.db"
AUDIT_RETENTION_DAYS=365
AUDIT_ROTATE_SIZE=10485760
AUDIT_MAX_EVENTS=1000000

# Audit levels
AUDIT_LEVEL_DEBUG=0
AUDIT_LEVEL_INFO=1
AUDIT_LEVEL_WARN=2
AUDIT_LEVEL_ERROR=3
AUDIT_LEVEL_CRITICAL=4

# Audit categories
AUDIT_CATEGORY_USER=1
AUDIT_CATEGORY_SYSTEM=2
AUDIT_CATEGORY_SECURITY=3
AUDIT_CATEGORY_NETWORK=4
AUDIT_CATEGORY_CONFIG=5
AUDIT_CATEGORY_BACKUP=6

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

audit::init() {
    mkdir -p "$(dirname "$AUDIT_DB")"
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
    local cutoff_date=$(date -d "$AUDIT_RETENTION_DAYS days ago" +%Y-%m-%d 2>/dev/null || \
                       date -v-${AUDIT_RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null)
    
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
    
    local source_ip=$(audit::_get_source_ip)
    local user_agent=$(audit::_get_user_agent)
    local session_id=$(audit::_get_session_id)
    
    sqlite3 "$AUDIT_DB" <<EOF
INSERT INTO audit_events (
    level, category, event_code, username, source_ip, user_agent,
    description, details, status, session_id
) VALUES (
    $level, $category, '$event_code', '$username', '$source_ip', '$user_agent',
    '$description', '$details', $status, '$session_id'
);
EOF
    
    # Update session event count
    if [[ -n "$session_id" ]]; then
        sqlite3 "$AUDIT_DB" "
            UPDATE audit_sessions 
            SET event_count = event_count + 1 
            WHERE session_id = '$session_id'
        "
    fi
    
    # Update daily stats
    local today=$(date +%Y-%m-%d)
    sqlite3 "$AUDIT_DB" "
        INSERT OR IGNORE INTO audit_stats (date) VALUES ('$today');
        UPDATE audit_stats SET total_events = total_events + 1 WHERE date = '$today';
        UPDATE audit_stats SET ${AUDIT_LEVELS[$level],,}_events = ${AUDIT_LEVELS[$level],,}_events + 1 
        WHERE date = '$today'
    "
    
    # Rotate if needed
    audit::_rotate_if_needed
}

audit::_get_source_ip() {
    local ip="${SSH_CLIENT%% *}"
    if [[ -z "$ip" ]]; then
        ip="${HTTP_X_FORWARDED_FOR:-${HTTP_CLIENT_IP:-${REMOTE_ADDR:-unknown}}}"
    fi
    echo "$ip" | tr -d '\n\r'
}

audit::_get_user_agent() {
    local agent="${HTTP_USER_AGENT:-CLI}"
    echo "$agent" | cut -c1-250 | tr -d '\n\r'
}

audit::_get_session_id() {
    if [[ -f "$SESSION_FILE" ]]; then
        cat "$SESSION_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

audit::_rotate_if_needed() {
    local db_size=$(stat -c%s "$AUDIT_DB" 2>/dev/null || stat -f%z "$AUDIT_DB" 2>/dev/null)
    local event_count=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM audit_events;")
    
    if [[ $db_size -gt $AUDIT_ROTATE_SIZE ]] || [[ $event_count -gt $AUDIT_MAX_EVENTS ]]; then
        audit::_rotate_db
    fi
}

audit::_rotate_db() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local rotated_db="${AUDIT_DB}.${timestamp}"
    
    # Backup current database
    cp "$AUDIT_DB" "$rotated_db"
    gzip "$rotated_db"
    
    # Create new database
    rm -f "$AUDIT_DB"
    audit::_ensure_db
    
    # Keep last 10 rotated files
    find "$(dirname "$AUDIT_DB")" -name "$(basename "$AUDIT_DB").*.gz" -type f | \
        sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
}

audit::start_session() {
    local username="$1"
    local source_ip=$(audit::_get_source_ip)
    local user_agent=$(audit::_get_user_agent)
    local session_id=$(utils::generate_uuid)
    
    echo "$session_id" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE"
    
    sqlite3 "$AUDIT_DB" <<EOF
INSERT INTO audit_sessions (
    session_id, username, source_ip, user_agent
) VALUES (
    '$session_id', '$username', '$source_ip', '$user_agent'
);
EOF
    
    audit::log $AUDIT_LEVEL_INFO $AUDIT_CATEGORY_SYSTEM "SESSION_START" \
        "User session started" "username=$username" "$username"
    
    echo "$session_id"
}

audit::end_session() {
    local session_id=$(audit::_get_session_id)
    local status="${1:-0}"
    
    if [[ -n "$session_id" ]]; then
        sqlite3 "$AUDIT_DB" "
            UPDATE audit_sessions 
            SET end_time = CURRENT_TIMESTAMP, status = $status 
            WHERE session_id = '$session_id'
        "
        
        audit::log $AUDIT_LEVEL_INFO $AUDIT_CATEGORY_SYSTEM "SESSION_END" \
            "User session ended" "status=$status" "$username"
        
        rm -f "$SESSION_FILE"
    fi
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
            ${AUDIT_LEVELS[level]} as level,
            ${AUDIT_CATEGORIES[category]} as category,
            event_code,
            username,
            source_ip,
            description,
            status
        FROM audit_events 
        $where_clause
        ORDER BY timestamp DESC 
        LIMIT $limit OFFSET $offset
    "
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
    "
}

audit::export_events() {
    local format="${1:-csv}"
    local output_file="${2:-}"
    local filters="${3:-}"
    
    if [[ -z "$output_file" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        output_file="${BACKUP_DIR}/audit_export_${timestamp}.${format}"
    fi
    
    case "$format" in
        "csv")
            audit::get_events 1000000 0 "$filters" > "$output_file"
            ;;
        "json")
            sqlite3 -json "$AUDIT_DB" "
                SELECT * FROM audit_events 
                WHERE $filters
                ORDER BY timestamp DESC
            " > "$output_file"
            ;;
        "sql")
            sqlite3 "$AUDIT_DB" ".dump audit_events" > "$output_file"
            ;;
        *)
            utils::log "ERROR" "Unsupported export format: $format"
            return $EXIT_FAILURE
            ;;
    esac
    
    echo "$output_file"
}

audit::search_events() {
    local query="$1"
    local limit="${2:-100}"
    
    sqlite3 -header -csv "$AUDIT_DB" "
        SELECT 
            datetime(timestamp, 'localtime') as timestamp,
            ${AUDIT_LEVELS[level]} as level,
            ${AUDIT_CATEGORIES[category]} as category,
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
    "
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
    "
}

audit::get_user_activity() {
    local username="$1"
    local limit="${2:-100}"
    
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
    "
}

audit::purge_events() {
    local days="${1:-}"
    local confirm="${2:-false}"
    
    if [[ -z "$days" ]]; then
        days=$AUDIT_RETENTION_DAYS
    fi
    
    if [[ "$confirm" != "true" ]]; then
        utils::log "ERROR" "Purge operation requires confirmation"
        return $EXIT_FAILURE
    fi
    
    local cutoff_date=$(date -d "$days days ago" +%Y-%m-%d 2>/dev/null || \
                       date -v-${days}d +%Y-%m-%d 2>/dev/null)
    
    local count=$(sqlite3 "$AUDIT_DB" "
        SELECT COUNT(*) FROM audit_events 
        WHERE timestamp < '$cutoff_date'
    ")
    
    sqlite3 "$AUDIT_DB" "
        DELETE FROM audit_events 
        WHERE timestamp < '$cutoff_date';
        VACUUM;
    "
    
    echo "Purged $count audit events older than $cutoff_date"
}

audit::get_db_size() {
    local size=$(stat -c%s "$AUDIT_DB" 2>/dev/null || stat -f%z "$AUDIT_DB" 2>/dev/null)
    echo "Audit database size: $(numfmt --to=iec-i --suffix=B $size)"
}

audit::get_event_count() {
    local total=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM audit_events;")
    local today=$(sqlite3 "$AUDIT_DB" "
        SELECT COUNT(*) FROM audit_events 
        WHERE date(timestamp) = date('now')
    ")
    
    echo "Total events: $total, Today: $today"
}

# Initialize audit system
audit::init