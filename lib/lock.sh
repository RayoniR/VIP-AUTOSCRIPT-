#!/bin/bash
# VIP-Autoscript Advanced Locking Module
# Distributed locking system for concurrent access control

set -euo pipefail
IFS=$'\n\t'

# Lock configuration
readonly LOCK_DIR="/tmp/vip-locks"
readonly LOCK_TIMEOUT=30
readonly LOCK_RETRY_INTERVAL=0.1
readonly LOCK_MAX_RETRIES=300

# Lock types
readonly LOCK_READ=1
readonly LOCK_WRITE=2

declare -A LOCKS
declare -A LOCK_TIMESTAMPS

lock::init() {
    mkdir -p "$LOCK_DIR"
    chmod 700 "$LOCK_DIR"
    
    # Cleanup stale locks on init
    lock::_cleanup_stale_locks
}

lock::acquire() {
    local lock_name="$1"
    local lock_type="${2:-$LOCK_WRITE}"
    local timeout="${3:-$LOCK_TIMEOUT}"
    
    local lock_file="${LOCK_DIR}/${lock_name}.lock"
    local start_time=$(date +%s)
    local attempts=0
    
    # Check if we already hold this lock
    if [[ -n "${LOCKS[$lock_name]}" ]]; then
        if [[ "${LOCKS[$lock_name]}" -ge $lock_type ]]; then
            # We already have sufficient lock level
            LOCK_TIMESTAMPS[$lock_name]=$(date +%s)
            return $EXIT_SUCCESS
        fi
    fi
    
    while [[ $attempts -lt $LOCK_MAX_RETRIES ]]; do
        # Try to acquire lock based on type
        case $lock_type in
            $LOCK_READ)
                if lock::_acquire_read_lock "$lock_file"; then
                    LOCKS[$lock_name]=$lock_type
                    LOCK_TIMESTAMPS[$lock_name]=$(date +%s)
                    return $EXIT_SUCCESS
                fi
                ;;
            $LOCK_WRITE)
                if lock::_acquire_write_lock "$lock_file"; then
                    LOCKS[$lock_name]=$lock_type
                    LOCK_TIMESTAMPS[$lock_name]=$(date +%s)
                    return $EXIT_SUCCESS
                fi
                ;;
        esac
        
        # Check timeout
        local current_time=$(date +%s)
        if [[ $((current_time - start_time)) -ge $timeout ]]; then
            utils::log "ERROR" "Lock timeout for $lock_name after $timeout seconds"
            return $EXIT_LOCK_ERROR
        fi
        
        # Wait before retry
        sleep $LOCK_RETRY_INTERVAL
        ((attempts++))
    done
    
    utils::log "ERROR" "Failed to acquire lock for $lock_name after $attempts attempts"
    return $EXIT_LOCK_ERROR
}

lock::_acquire_read_lock() {
    local lock_file="$1"
    
    # For read locks, we can have multiple readers
    if [[ -f "${lock_file}.write" ]]; then
        # Write lock exists, cannot acquire read lock
        return $EXIT_FAILURE
    fi
    
    # Increment read lock count
    local count=1
    if [[ -f "${lock_file}.read" ]]; then
        count=$(cat "${lock_file}.read")
        ((count++))
    fi
    
    echo $count > "${lock_file}.read"
    return $EXIT_SUCCESS
}

lock::_acquire_write_lock() {
    local lock_file="$1"
    
    # For write locks, we need exclusive access
    if [[ -f "${lock_file}.read" ]] || [[ -f "${lock_file}.write" ]]; then
        # Other locks exist, cannot acquire write lock
        return $EXIT_FAILURE
    fi
    
    # Create write lock
    echo $$ > "${lock_file}.write"
    return $EXIT_SUCCESS
}

lock::release() {
    local lock_name="$1"
    local lock_file="${LOCK_DIR}/${lock_name}.lock"
    
    if [[ -z "${LOCKS[$lock_name]}" ]]; then
        return $EXIT_SUCCESS
    fi
    
    case ${LOCKS[$lock_name]} in
        $LOCK_READ)
            lock::_release_read_lock "$lock_file"
            ;;
        $LOCK_WRITE)
            lock::_release_write_lock "$lock_file"
            ;;
    esac
    
    unset LOCKS[$lock_name]
    unset LOCK_TIMESTAMPS[$lock_name]
}

lock::_release_read_lock() {
    local lock_file="$1"
    
    if [[ ! -f "${lock_file}.read" ]]; then
        return $EXIT_SUCCESS
    fi
    
    local count=$(cat "${lock_file}.read")
    ((count--))
    
    if [[ $count -le 0 ]]; then
        rm -f "${lock_file}.read"
    else
        echo $count > "${lock_file}.read"
    fi
}

lock::_release_write_lock() {
    local lock_file="$1"
    rm -f "${lock_file}.write"
}

lock::release_all() {
    for lock_name in "${!LOCKS[@]}"; do
        lock::release "$lock_name"
    done
}

lock::upgrade() {
    local lock_name="$1"
    
    if [[ -z "${LOCKS[$lock_name]}" ]]; then
        utils::log "ERROR" "Cannot upgrade non-existent lock: $lock_name"
        return $EXIT_LOCK_ERROR
    fi
    
    if [[ ${LOCKS[$lock_name]} -eq $LOCK_WRITE ]]; then
        # Already write lock
        return $EXIT_SUCCESS
    fi
    
    # Release read lock and acquire write lock
    lock::release "$lock_name"
    lock::acquire "$lock_name" $LOCK_WRITE
}

lock::downgrade() {
    local lock_name="$1"
    
    if [[ -z "${LOCKS[$lock_name]}" ]]; then
        utils::log "ERROR" "Cannot downgrade non-existent lock: $lock_name"
        return $EXIT_LOCK_ERROR
    fi
    
    if [[ ${LOCKS[$lock_name]} -eq $LOCK_READ ]]; then
        # Already read lock
        return $EXIT_SUCCESS
    fi
    
    # Release write lock and acquire read lock
    lock::release "$lock_name"
    lock::acquire "$lock_name" $LOCK_READ
}

lock::check() {
    local lock_name="$1"
    local lock_file="${LOCK_DIR}/${lock_name}.lock"
    
    if [[ -f "${lock_file}.write" ]]; then
        local pid=$(cat "${lock_file}.write")
        if kill -0 $pid 2>/dev/null; then
            echo "Write lock held by process $pid"
            return $EXIT_SUCCESS
        else
            # Stale lock
            rm -f "${lock_file}.write"
            return $EXIT_FAILURE
        fi
    fi
    
    if [[ -f "${lock_file}.read" ]]; then
        local count=$(cat "${lock_file}.read")
        echo "Read lock with $count holders"
        return $EXIT_SUCCESS
    fi
    
    return $EXIT_FAILURE
}

lock::_cleanup_stale_locks() {
    # Cleanup stale write locks
    for lock_file in "$LOCK_DIR"/*.write; do
        [[ -f "$lock_file" ]] || continue
        
        local pid=$(cat "$lock_file" 2>/dev/null)
        if [[ -n "$pid" ]] && ! kill -0 $pid 2>/dev/null; then
            rm -f "$lock_file"
            utils::log "WARN" "Cleaned up stale write lock: $(basename "$lock_file")"
        fi
    done
    
    # Cleanup orphaned read locks (no corresponding write lock but read count exists)
    for lock_file in "$LOCK_DIR"/*.read; do
        [[ -f "$lock_file" ]] || continue
        
        local lock_name=$(basename "$lock_file" .read)
        if [[ ! -f "${LOCK_DIR}/${lock_name}.write" ]]; then
            rm -f "$lock_file"
            utils::log "WARN" "Cleaned up orphaned read lock: $lock_name"
        fi
    done
}

lock::get_stats() {
    local total_locks=0
    local read_locks=0
    local write_locks=0
    
    for lock_file in "$LOCK_DIR"/*.read; do
        [[ -f "$lock_file" ]] && ((read_locks++))
    done
    
    for lock_file in "$LOCK_DIR"/*.write; do
        [[ -f "$lock_file" ]] && ((write_locks++))
    done
    
    total_locks=$((read_locks + write_locks))
    
    echo "Total locks: $total_locks"
    echo "Read locks: $read_locks"
    echo "Write locks: $write_locks"
    echo "Held by current process: ${#LOCKS[@]}"
}

lock::with_lock() {
    local lock_name="$1"
    local lock_type="${2:-$LOCK_WRITE}"
    local timeout="${3:-$LOCK_TIMEOUT}"
    local command="$4"
    shift 4
    
    if lock::acquire "$lock_name" "$lock_type" "$timeout"; then
        # Execute command with lock held
        (
            trap 'lock::release "$lock_name"' EXIT
            eval "$command" "$@"
        )
        local result=$?
        return $result
    else
        utils::log "ERROR" "Failed to acquire lock $lock_name for command: $command"
        return $EXIT_LOCK_ERROR
    fi
}

lock::wait_for() {
    local lock_name="$1"
    local timeout="${2:-$LOCK_TIMEOUT}"
    local check_interval="${3:-0.5}"
    
    local start_time=$(date +%s)
    
    while true; do
        if ! lock::check "$lock_name" >/dev/null 2>&1; then
            return $EXIT_SUCCESS
        fi
        
        local current_time=$(date +%s)
        if [[ $((current_time - start_time)) -ge $timeout ]]; then
            utils::log "ERROR" "Timeout waiting for lock $lock_name"
            return $EXIT_LOCK_ERROR
        fi
        
        sleep $check_interval
    done
}

lock::validate() {
    local lock_name="$1"
    local expected_type="${2:-}"
    
    if [[ -z "${LOCKS[$lock_name]}" ]]; then
        utils::log "ERROR" "Lock $lock_name not held by current process"
        return $EXIT_LOCK_ERROR
    fi
    
    if [[ -n "$expected_type" ]] && [[ ${LOCKS[$lock_name]} -ne $expected_type ]]; then
        utils::log "ERROR" "Lock $lock_name type mismatch. Expected: $expected_type, Actual: ${LOCKS[$lock_name]}"
        return $EXIT_LOCK_ERROR
    fi
    
    return $EXIT_SUCCESS
}

lock::cleanup() {
    # Release all locks held by this process
    lock::release_all
    
    # Cleanup stale locks
    lock::_cleanup_stale_locks
}

# Initialize locking system
lock::init

# Register cleanup handler
trap lock::cleanup EXIT