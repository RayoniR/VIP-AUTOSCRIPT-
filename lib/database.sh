#!/bin/bash
# VIP-Autoscript Database Module

db::acquire_lock() {
    local lock_file="${USER_DB}.lock"
    local timeout=$DB_LOCK_TIMEOUT
    local start_time=$(date +%s)
    
    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        if (set -o noclobber; echo $$ > "$lock_file") 2>/dev/null; then
            return $EXIT_SUCCESS
        fi
        sleep 0.1
    done
    
    utils::log "ERROR" "Failed to acquire database lock after $timeout seconds"
    return $EXIT_LOCK_ERROR
}

db::release_lock() {
    local lock_file="${USER_DB}.lock"
    [[ -f "$lock_file" ]] && rm -f "$lock_file"
}

db::ensure_db() {
    if [[ ! -f "$USER_DB" ]]; then
        echo '{"users":{},"metadata":{"total_users":0,"active_users":0,"created":"'"$(date +%Y-%m-%dT%H:%M:%S)"'","version":"1.0"}}' > "$USER_DB"
    fi
}

db::user_exists() {
    local username="$1"
    db::acquire_lock || return $EXIT_LOCK_ERROR
    local exists=$(jq -e ".users[\"$username\"]" "$USER_DB" >/dev/null 2>&1; echo $?)
    db::release_lock
    return $exists
}

db::create_user() {
    local username="$1"
    local service="$2"
    local expiry_days="$3"
    
    db::acquire_lock || return $EXIT_LOCK_ERROR
    
    local created=$(date +%Y-%m-%dT%H:%M:%S)
    local expiry_date="never"
    
    if [[ "$expiry_days" != "never" ]]; then
        expiry_date=$(date -d "+$expiry_days days" +%Y-%m-%dT%H:%M:%S 2>/dev/null || \
                     date -v+${expiry_days}d +%Y-%m-%dT%H:%M:%S 2>/dev/null || \
                     echo "never")
    fi
    
    local user_data=$(jq -n \
        --arg created "$created" \
        --arg expiry "$expiry_date" \
        --arg service "$service" \
        '{
            created: $created,
            expiry_date: $expiry,
            services: ($service | split(",")),
            status: "active",
            last_modified: $created,
            configs_generated: 0
        }')
    
    jq --arg user "$username" --argjson data "$user_data" \
        '.users[$user] = $data |
         .metadata.total_users = (.users | length) |
         .metadata.active_users = (.users | to_entries | map(select(.value.status == "active")) | length)' \
        "$USER_DB" > "${USER_DB}.tmp" && \
    mv "${USER_DB}.tmp" "$USER_DB"
    
    local result=$?
    db::release_lock
    
    if [[ $result -eq 0 ]]; then
        utils::log "INFO" "User created: $username"
        audit::log "USER_CREATE" "User $username created with service: $service, expiry: $expiry_days days"
        return $EXIT_SUCCESS
    else
        utils::log "ERROR" "Failed to create user: $username"
        return $EXIT_DB_ERROR
    fi
}

db::update_user() {
    local username="$1"
    local field="$2"
    local value="$3"
    
    if ! db::user_exists "$username"; then
        return $EXIT_FAILURE
    fi
    
    db::acquire_lock || return $EXIT_LOCK_ERROR
    
    jq --arg user "$username" --arg field "$field" --arg value "$value" \
        '.users[$user][$field] = $value |
         .users[$user].last_modified = now | strftime("%Y-%m-%dT%H:%M:%S")' \
        "$USER_DB" > "${USER_DB}.tmp" && \
    mv "${USER_DB}.tmp" "$USER_DB"
    
    local result=$?
    db::release_lock
    
    if [[ $result -eq 0 ]]; then
        utils::log "INFO" "User updated: $username - $field: $value"
        audit::log "USER_UPDATE" "User $username updated: $field = $value"
        return $EXIT_SUCCESS
    else
        utils::log "ERROR" "Failed to update user: $username"
        return $EXIT_DB_ERROR
    fi
}

db::delete_user() {
    local username="$1"
    
    if ! db::user_exists "$username"; then
        return $EXIT_FAILURE
    fi
    
    db::acquire_lock || return $EXIT_LOCK_ERROR
    
    jq --arg user "$username" \
        'del(.users[$user]) |
         .metadata.total_users = (.users | length) |
         .metadata.active_users = (.users | to_entries | map(select(.value.status == "active")) | length)' \
        "$USER_DB" > "${USER_DB}.tmp" && \
    mv "${USER_DB}.tmp" "$USER_DB"
    
    local result=$?
    db::release_lock
    
    if [[ $result -eq 0 ]]; then
        utils::log "INFO" "User deleted: $username"
        audit::log "USER_DELETE" "User $username deleted"
        return $EXIT_SUCCESS
    else
        utils::log "ERROR" "Failed to delete user: $username"
        return $EXIT_DB_ERROR
    fi
}

db::get_user() {
    local username="$1"
    
    if ! db::user_exists "$username"; then
        return $EXIT_FAILURE
    fi
    
    db::acquire_lock || return $EXIT_LOCK_ERROR
    local user_data=$(jq -r ".users[\"$username\"]" "$USER_DB" 2>/dev/null)
    db::release_lock
    
    echo "$user_data"
    return $EXIT_SUCCESS
}

db::list_users() {
    db::acquire_lock || return $EXIT_LOCK_ERROR
    local users=$(jq -r '.users | keys[]' "$USER_DB" 2>/dev/null)
    db::release_lock
    
    echo "$users"
}

db::get_stats() {
    db::acquire_lock || return $EXIT_LOCK_ERROR
    local stats=$(jq -r '.metadata' "$USER_DB" 2>/dev/null)
    db::release_lock
    
    echo "$stats"
}

db::increment_config_count() {
    local username="$1"
    
    if ! db::user_exists "$username"; then
        return $EXIT_FAILURE
    fi
    
    db::acquire_lock || return $EXIT_LOCK_ERROR
    
    jq --arg user "$username" \
        '.users[$user].configs_generated = (.users[$user].configs_generated + 1) |
         .users[$user].last_modified = now | strftime("%Y-%m-%dT%H:%M:%S")' \
        "$USER_DB" > "${USER_DB}.tmp" && \
    mv "${USER_DB}.tmp" "$USER_DB"
    
    local result=$?
    db::release_lock
    
    return $result
}

db::check_expiry() {
    local username="$1"
    local user_data=$(db::get_user "$username")
    
    if [[ $? -ne 0 ]]; then
        return $EXIT_FAILURE
    fi
    
    local expiry=$(echo "$user_data" | jq -r '.expiry_date')
    local status=$(echo "$user_data" | jq -r '.status')
    
    if [[ "$expiry" == "never" ]] || [[ "$status" != "active" ]]; then
        return $EXIT_SUCCESS
    fi
    
    local current_ts=$(date +%s)
    local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    
    if [[ $current_ts -gt $expiry_ts ]]; then
        db::update_user "$username" "status" "expired"
        utils::log "INFO" "User expired: $username"
        return 1
    fi
    
    return $EXIT_SUCCESS
}