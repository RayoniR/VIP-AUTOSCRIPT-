#!/bin/bash
# VIP-Autoscript Advanced Config Generator Module

config::init() {
    declare -gA CONFIG_TEMPLATES
    declare -gA CONFIG_CACHE
    readonly TEMPLATE_DIR="${CONFIG_DIR}/vpn-templates"
    
    config::_load_templates
}

config::_load_templates() {
    mkdir -p "$TEMPLATE_DIR"
    
    # Default templates if none exist
    if [[ ! -f "${TEMPLATE_DIR}/httpcustom.tpl" ]]; then
        cat > "${TEMPLATE_DIR}/httpcustom.tpl" << 'EOF'
[CONFIG]
server={{SERVER_IP}}
username={{USERNAME}}
password={{PASSWORD}}
expiry={{EXPIRY_DATE}}
services={{SERVICES}}
protocol=SSL
port=443
mode=websocket
sni={{SERVER_IP}}
path=/v2ray
EOF
    fi
    
    # Load all templates into memory
    for template_file in "$TEMPLATE_DIR"/*.tpl; do
        local client_name=$(basename "$template_file" .tpl)
        CONFIG_TEMPLATES["$client_name"]=$(cat "$template_file")
    done
}

config::generate() {
    local username="$1"
    local vpn_client="$2"
    local options="${3:-}"
    
    if ! db::user_exists "$username"; then
        utils::log "ERROR" "Config generation failed: User $username not found"
        return $EXIT_FAILURE
    fi
    
    local user_data=$(db::get_user "$username")
    local expiry_date=$(echo "$user_data" | jq -r '.expiry_date')
    local services=$(echo "$user_data" | jq -r '.services | join(",")')
    local server_ip=$(utils::get_server_ip)
    
    # Generate unique values
    local password=$(utils::generate_password 16)
    local uuid=$(utils::generate_uuid)
    
    # Select template
    local template="${CONFIG_TEMPLATES[$vpn_client]}"
    if [[ -z "$template" ]]; then
        template="${CONFIG_TEMPLATES["default"]}"
    fi
    
    # Render template
    local config_content=$(config::_render_template "$template" \
        "USERNAME" "$username" \
        "PASSWORD" "$password" \
        "UUID" "$uuid" \
        "SERVER_IP" "$server_ip" \
        "EXPIRY_DATE" "$expiry_date" \
        "SERVICES" "$services" \
        "GENERATED_DATE" "$(date)" \
        "CLIENT" "$vpn_client")
    
    # Determine file extension
    local extension="${VPN_EXTENSIONS[$vpn_client]}"
    local config_file="${CONFIG_OUTPUT_DIR}/${username}_${vpn_client}${extension}"
    local phone_file="${PHONE_STORAGE_DIR}/${username}_${vpn_client}${extension}"
    
    # Save config
    echo "$config_content" > "$config_file"
    chmod 600 "$config_file"
    
    # Deploy to phone if available
    if phone_storage::is_available; then
        cp "$config_file" "$phone_file"
        chmod 644 "$phone_file"
    fi
    
    # Update user stats
    db::increment_config_count "$username"
    
    utils::log "INFO" "Config generated for $username: $vpn_client"
    audit::log "CONFIG_GENERATE" "Generated $vpn_client config for user $username"
    
    echo "$config_file"
    return $EXIT_SUCCESS
}

config::_render_template() {
    local template="$1"
    shift
    local variables=("$@")
    
    local output="$template"
    
    for ((i=0; i<${#variables[@]}; i+=2)); do
        local key="${variables[$i]}"
        local value="${variables[$i+1]}"
        output="${output//\{\{$key\}\}/$value}"
    done
    
    echo "$output"
}

config::generate_bulk() {
    local users=("$@")
    local total=${#users[@]}
    local completed=0
    local errors=0
    
    utils::log "INFO" "Starting bulk config generation for $total users"
    
    for user in "${users[@]}"; do
        if config::generate "$user" "HTTPCustom" "quiet"; then
            ((completed++))
        else
            ((errors++))
            utils::log "ERROR" "Failed to generate config for user: $user"
        fi
        
        ui::progress_bar $completed $total
    done
    
    echo
    utils::log "INFO" "Bulk config generation completed: $completed success, $errors errors"
    return $errors
}

config::regenerate_all() {
    local users=$(db::list_users)
    local user_array=()
    
    while IFS= read -r user; do
        user_array+=("$user")
    done <<< "$users"
    
    config::generate_bulk "${user_array[@]}"
}

config::export_configs() {
    local export_dir="$1"
    local format="${2:-zip}"
    
    mkdir -p "$export_dir"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local export_file="${export_dir}/configs_export_${timestamp}"
    
    case "$format" in
        "zip")
            zip -r "${export_file}.zip" "$CONFIG_OUTPUT_DIR" >/dev/null 2>&1
            ;;
        "tar")
            tar -czf "${export_file}.tar.gz" -C "$CONFIG_OUTPUT_DIR" . 2>/dev/null
            ;;
        "copy")
            cp -r "$CONFIG_OUTPUT_DIR"/* "$export_dir/"
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        utils::log "INFO" "Configs exported to ${export_file}.${format}"
        echo "${export_file}.${format}"
    else
        utils::log "ERROR" "Config export failed"
        return $EXIT_FAILURE
    fi
}

config::validate_config() {
    local config_file="$1"
    local client_type="$2"
    
    case "$client_type" in
        "OpenVPN")
            grep -q "BEGIN CERTIFICATE" "$config_file" && \
            grep -q "END CERTIFICATE" "$config_file"
            ;;
        "WireGuard")
            grep -q "\[Interface\]" "$config_file" && \
            grep -q "\[Peer\]" "$config_file"
            ;;
        "V2Ray"|"Trojan")
            jq empty "$config_file" 2>/dev/null
            ;;
        *)
            [[ -s "$config_file" ]] && grep -q -v "^\s*$" "$config_file"
            ;;
    esac
    
    return $?
}

config::get_config_info() {
    local username="$1"
    local configs=()
    
    for config_file in "$CONFIG_OUTPUT_DIR/${username}"_*; do
        [[ -f "$config_file" ]] || continue
        local client=$(basename "$config_file" | cut -d_ -f2 | cut -d. -f1)
        local size=$(du -h "$config_file" | cut -f1)
        local modified=$(date -r "$config_file" "+%Y-%m-%d %H:%M")
        configs+=("$client|$size|$modified")
    done
    
    printf "%s\n" "${configs[@]}"
}