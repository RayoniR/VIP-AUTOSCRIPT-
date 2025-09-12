#!/bin/bash
# VIP-Autoscript Advanced Phone Storage Module

phone_storage::init() {
    declare -gA PHONE_STATE
    PHONE_STATE["AVAILABLE"]=false
    PHONE_STATE["LAST_CHECK"]=0
    PHONE_STATE["MOUNT_POINT"]=""
    PHONE_STATE["CAPACITY"]=0
    PHONE_STATE["USED"]=0
    
    phone_storage::detect
}

phone_storage::detect() {
    local current_time=$(date +%s)
    local last_check=${PHONE_STATE["LAST_CHECK"]}
    
    # Only check every 30 seconds to avoid performance issues
    if [[ $((current_time - last_check)) -lt 30 ]]; then
        return ${PHONE_STATE["AVAILABLE"]}
    fi
    
    PHONE_STATE["LAST_CHECK"]=$current_time
    PHONE_STATE["AVAILABLE"]=false
    
    # Check all possible mount points
    for mount_pattern in "${PHONE_MOUNT_POINTS[@]}"; do
        for mount_point in $mount_pattern; do
            if [[ -d "$mount_point" && -w "$mount_point" ]]; then
                PHONE_STATE["MOUNT_POINT"]="$mount_point"
                PHONE_STATE["AVAILABLE"]=true
                
                # Get storage information
                local storage_info=$(df "$mount_point" 2>/dev/null | tail -1)
                PHONE_STATE["CAPACITY"]=$(echo "$storage_info" | awk '{print $2}')
                PHONE_STATE["USED"]=$(echo "$storage_info" | awk '{print $3}')
                
                # Create config directory
                mkdir -p "${mount_point}/Configs"
                PHONE_STORAGE_DIR="${mount_point}/Configs"
                
                utils::log "INFO" "Phone storage detected: $mount_point"
                return $EXIT_SUCCESS
            fi
        done
    done
    
    # Fallback to local storage
    PHONE_STORAGE_DIR="$HOME/Phone_Configs"
    mkdir -p "$PHONE_STORAGE_DIR"
    utils::log "WARN" "Phone storage not available, using local directory: $PHONE_STORAGE_DIR"
    
    return $EXIT_FAILURE
}

phone_storage::is_available() {
    phone_storage::detect
    [[ ${PHONE_STATE["AVAILABLE"]} == true ]]
    return $?
}

phone_storage::get_info() {
    phone_storage::detect
    
    if [[ ${PHONE_STATE["AVAILABLE"]} == true ]]; then
        local capacity_mb=$((PHONE_STATE["CAPACITY"] / 1024))
        local used_mb=$((PHONE_STATE["USED"] / 1024))
        local free_mb=$((capacity_mb - used_mb))
        local percent_used=$((used_mb * 100 / capacity_mb))
        
        echo "Mount: ${PHONE_STATE["MOUNT_POINT"]}"
        echo "Capacity: ${capacity_mb}MB"
        echo "Used: ${used_mb}MB (${percent_used}%)"
        echo "Free: ${free_mb}MB"
    else
        echo "Status: Not connected"
        echo "Fallback: $PHONE_STORAGE_DIR"
    fi
}

phone_storage::sync() {
    local mode="${1:-incremental}"
    
    if ! phone_storage::is_available; then
        utils::log "ERROR" "Phone sync failed: storage not available"
        return $EXIT_FAILURE
    fi
    
    utils::log "INFO" "Starting phone storage sync: $mode mode"
    
    case "$mode" in
        "incremental")
            rsync -au --delete "$CONFIG_OUTPUT_DIR/" "$PHONE_STORAGE_DIR/" 2>/dev/null
            ;;
        "full")
            rsync -a --delete "$CONFIG_OUTPUT_DIR/" "$PHONE_STORAGE_DIR/" 2>/dev/null
            ;;
        "verify")
            rsync -acu "$CONFIG_OUTPUT_DIR/" "$PHONE_STORAGE_DIR/" 2>/dev/null
            ;;
    esac
    
    local sync_result=$?
    
    if [[ $sync_result -eq 0 ]]; then
        utils::log "INFO" "Phone storage sync completed successfully"
        audit::log "PHONE_SYNC" "Configs synchronized to phone storage"
    else
        utils::log "ERROR" "Phone storage sync failed with code: $sync_result"
    fi
    
    return $sync_result
}

phone_storage::cleanup() {
    local max_age_days="${1:-30}"
    
    if ! phone_storage::is_available; then
        return $EXIT_FAILURE
    fi
    
    utils::log "INFO" "Cleaning up phone storage (files older than $max_age_days days)"
    
    find "$PHONE_STORAGE_DIR" -name "*.*" -mtime "+$max_age_days" -delete 2>/dev/null
    local deleted_count=$?
    
    utils::log "INFO" "Phone storage cleanup completed"
    return $deleted_count
}

phone_storage::get_file_count() {
    if phone_storage::is_available; then
        find "$PHONE_STORAGE_DIR" -name "*.*" 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

phone_storage::monitor() {
    local monitor_pid=0
    local last_state=${PHONE_STATE["AVAILABLE"]}
    
    while true; do
        phone_storage::detect
        local current_state=${PHONE_STATE["AVAILABLE"]}
        
        if [[ "$current_state" != "$last_state" ]]; then
            if [[ "$current_state" == true ]]; then
                utils::log "INFO" "Phone storage connected: ${PHONE_STATE["MOUNT_POINT"]}"
                phone_storage::sync
            else
                utils::log "INFO" "Phone storage disconnected"
            fi
            last_state="$current_state"
        fi
        
        sleep 10
    done
}