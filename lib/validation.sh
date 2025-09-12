#!/bin/bash
# VIP-Autoscript Validation Module

validation::init() {
    declare -gA VALIDATION_ERRORS
}

validation::sanitize_input() {
    local input="$1"
    local type="${2:-text}"
    
    case "$type" in
        "username")
            echo "$input" | tr -cd 'a-zA-Z0-9_-' | head -c 20
            ;;
        "password")
            echo "$input" | tr -d '\n\r' | head -c $PASSWORD_MAX_LENGTH
            ;;
        "number")
            echo "$input" | tr -cd '0-9'
            ;;
        "text")
            echo "$input" | tr -cd 'a-zA-Z0-9 .,!?@#$%^&*()_-' | head -c 100
            ;;
        "filename")
            echo "$input" | tr -cd 'a-zA-Z0-9._-' | head -c 50
            ;;
        *)
            echo "$input" | head -c 100
            ;;
    esac
}

validation::validate_username() {
    local username="$1"
    username=$(validation::sanitize_input "$username" "username")
    
    if [[ ! "$username" =~ $USERNAME_PATTERN ]]; then
        VALIDATION_ERRORS["username"]="Invalid username format. Must be 3-20 chars, start with letter, and contain only a-zA-Z0-9_-"
        return $EXIT_VALIDATION_ERROR
    fi
    
    if db::user_exists "$username"; then
        VALIDATION_ERRORS["username"]="Username already exists"
        return $EXIT_VALIDATION_ERROR
    fi
    
    echo "$username"
    return $EXIT_SUCCESS
}

validation::validate_password() {
    local password="$1"
    password=$(validation::sanitize_input "$password" "password")
    
    if [[ ${#password} -lt $PASSWORD_MIN_LENGTH ]]; then
        VALIDATION_ERRORS["password"]="Password must be at least $PASSWORD_MIN_LENGTH characters"
        return $EXIT_VALIDATION_ERROR
    fi
    
    echo "$password"
    return $EXIT_SUCCESS
}

validation::validate_service() {
    local service="$1"
    service=$(validation::sanitize_input "$service" "text")
    
    if [[ ! " ${SERVICES[@]} " =~ " ${service} " ]]; then
        VALIDATION_ERRORS["service"]="Invalid service type. Must be one of: ${SERVICES[*]}"
        return $EXIT_VALIDATION_ERROR
    fi
    
    echo "$service"
    return $EXIT_SUCCESS
}

validation::validate_expiry() {
    local expiry="$1"
    expiry=$(validation::sanitize_input "$expiry" "number")
    
    if [[ "$expiry" == "never" ]]; then
        echo "never"
        return $EXIT_SUCCESS
    fi
    
    if [[ -z "$expiry" ]] || [[ "$expiry" -lt 1 ]] || [[ "$expiry" -gt 3650 ]]; then
        VALIDATION_ERRORS["expiry"]="Invalid expiry days. Must be between 1-3650 or 'never'"
        return $EXIT_VALIDATION_ERROR
    fi
    
    echo "$expiry"
    return $EXIT_SUCCESS
}

validation::validate_vpn_client() {
    local client="$1"
    client=$(validation::sanitize_input "$client" "text")
    
    if [[ -z "${VPN_EXTENSIONS[$client]}" ]]; then
        VALIDATION_ERRORS["vpn_client"]="Invalid VPN client. Available: ${!VPN_EXTENSIONS[*]}"
        return $EXIT_VALIDATION_ERROR
    fi
    
    echo "$client"
    return $EXIT_SUCCESS
}

validation::validate_ip() {
    local ip="$1"
    
    if ! utils::validate_ip "$ip"; then
        VALIDATION_ERRORS["ip"]="Invalid IP address format"
        return $EXIT_VALIDATION_ERROR
    fi
    
    echo "$ip"
    return $EXIT_SUCCESS
}

validation::get_errors() {
    local error_string=""
    for key in "${!VALIDATION_ERRORS[@]}"; do
        error_string+="${key}: ${VALIDATION_ERRORS[$key]}\n"
    done
    echo -e "$error_string"
}

validation::clear_errors() {
    unset VALIDATION_ERRORS
    declare -gA VALIDATION_ERRORS
}