#!/bin/bash

# VIP-Autoscript Advanced Domain Management
# Enterprise-grade domain/host management system

set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly CONFIG_DIR="/etc/vip-autoscript/config"
readonly DOMAIN_DIR="/etc/vip-autoscript/domains"  
readonly LOG_DIR="/etc/vip-autoscript/logs"
readonly BACKUP_DIR="/etc/vip-autoscript/backups"
readonly LOCK_DIR="/tmp/vip-domains"
readonly DOMAIN_DB="$DOMAIN_DIR/domains.json"
readonly DOMAIN_SCHEMA="$DOMAIN_DIR/schema.json"
readonly AUDIT_LOG="$LOG_DIR/domain-audit.log"

# Service configurations
readonly SERVICES=("xray" "nginx" "haproxy" "caddy")
readonly SERVICE_PORTS=("443:ssl" "80:http" "2053:alternative" "8443:admin")

# Validation patterns
readonly DOMAIN_REGEX='^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$'
readonly IPV4_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
readonly IPV6_REGEX='^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$'

# Exit codes
readonly SUCCESS=0
readonly ERROR_INVALID_DOMAIN=1
readonly ERROR_DUPLICATE=2
readonly ERROR_CONFIG=3
readonly ERROR_VALIDATION=4
readonly ERROR_DEPENDENCY=5

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Initialize system
init_system() {
    mkdir -p "$CONFIG_DIR" "$DOMAIN_DIR" "$LOG_DIR" "$BACKUP_DIR" "$LOCK_DIR"
    setup_logging
    setup_traps
    load_config
    init_database
}

# Setup error handling and logging
setup_logging() {
    exec 3>>"$AUDIT_LOG"
    exec 4>>"$LOG_DIR/domain-errors.log"
}

setup_traps() {
    trap 'cleanup_lock; exit' INT TERM EXIT
    trap 'log_error "Error at line $LINENO"' ERR
}

# Database management
init_database() {
    if [[ ! -f "$DOMAIN_DB" ]]; then
        cat > "$DOMAIN_DB" << EOF
{
    "version": "1.0.0",
    "domains": {},
    "metadata": {
        "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "last_modified": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "total_count": 0,
        "active_count": 0
    },
    "services": {
        "xray": {"enabled": true, "template": "xray-template.json"},
        "nginx": {"enabled": true, "template": "nginx-template.conf"},
        "haproxy": {"enabled": false, "template": "haproxy-template.cfg"},
        "caddy": {"enabled": false, "template": "Caddyfile-template"}
    }
}
EOF
    fi

    create_schema
}

create_schema() {
    cat > "$DOMAIN_SCHEMA" << EOF
{
    "\$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
        "domain": {
            "type": "string",
            "pattern": "$DOMAIN_REGEX",
            "maxLength": 253
        },
        "enabled": {
            "type": "boolean",
            "default": true
        },
        "services": {
            "type": "object",
            "properties": {
                "xray": {"type": "boolean", "default": true},
                "nginx": {"type": "boolean", "default": true},
                "haproxy": {"type": "boolean", "default": false},
                "caddy": {"type": "boolean", "default": false}
            },
            "additionalProperties": false
        },
        "ssl": {
            "type": "object",
            "properties": {
                "enabled": {"type": "boolean", "default": true},
                "cert_type": {"type": "string", "enum": ["letsencrypt", "selfsigned", "custom"], "default": "letsencrypt"},
                "auto_renew": {"type": "boolean", "default": true}
            }
        },
        "routing": {
            "type": "object",
            "properties": {
                "backend": {"type": "string", "format": "uri"},
                "load_balancing": {"type": "string", "enum": ["round-robin", "least-connections", "ip-hash"]},
                "health_check": {"type": "boolean", "default": true}
            }
        },
        "security": {
            "type": "object",
            "properties": {
                "waf": {"type": "boolean", "default": false},
                "rate_limiting": {"type": "boolean", "default": true},
                "ip_whitelist": {"type": "array", "items": {"type": "string", "format": "ip"}},
                "ip_blacklist": {"type": "array", "items": {"type": "string", "format": "ip"}}
            }
        },
        "monitoring": {
            "type": "object",
            "properties": {
                "enabled": {"type": "boolean", "default": true},
                "uptime_check": {"type": "boolean", "default": true},
                "response_time": {"type": "boolean", "default": false},
                "alert_threshold": {"type": "number", "minimum": 0, "maximum": 100}
            }
        }
    },
    "required": ["domain"],
    "additionalProperties": false
}
EOF
}

# Locking mechanism
acquire_lock() {
    local lock_file="$LOCK_DIR/domain.lock"
    if ! mkdir "$lock_file" 2>/dev/null; then
        log_error "Could not acquire lock. Another operation may be in progress."
        exit 1
    fi
    echo $$ > "$lock_file/pid"
}

cleanup_lock() {
    rm -rf "$LOCK_DIR/domain.lock"
}

# Validation functions
validate_domain() {
    local domain="$1"
    
    if [[ ! "$domain" =~ $DOMAIN_REGEX ]]; then
        log_error "Invalid domain format: $domain"
        return $ERROR_INVALID_DOMAIN
    fi

    # Check for valid TLD length
    local tld="${domain##*.}"
    if [[ ${#tld} -lt 2 || ${#tld} > 6 ]]; then
        log_error "Invalid TLD length: $tld"
        return $ERROR_INVALID_DOMAIN
    fi

    # Check total length
    if [[ ${#domain} -gt 253 ]]; then
        log_error "Domain exceeds maximum length: $domain"
        return $ERROR_INVALID_DOMAIN
    fi

    return $SUCCESS
}

validate_ip() {
    local ip="$1"
    
    if [[ "$ip" =~ $IPV4_REGEX ]] || [[ "$ip" =~ $IPV6_REGEX ]]; then
        return $SUCCESS
    else
        log_error "Invalid IP address: $ip"
        return $ERROR_VALIDATION
    fi
}

validate_service_config() {
    local service="$1"
    local config="$2"
    
    case "$service" in
        "xray")
            validate_json "$config"
            ;;
        "nginx"|"haproxy"|"caddy")
            validate_config_file "$config" "$service"
            ;;
        *)
            log_error "Unknown service: $service"
            return $ERROR_VALIDATION
            ;;
    esac
}

validate_json() {
    local json="$1"
    if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
        log_error "Invalid JSON configuration"
        return $ERROR_VALIDATION
    fi
}

validate_config_file() {
    local config="$1"
    local service="$2"
    
    # Basic syntax validation for different config types
    case "$service" in
        "nginx")
            if ! nginx -t -c "$config" 2>/dev/null; then
                log_error "Invalid nginx configuration"
                return $ERROR_CONFIG
            fi
            ;;
        "haproxy")
            if ! haproxy -c -f "$config" 2>/dev/null; then
                log_error "Invalid haproxy configuration"
                return $ERROR_CONFIG
            fi
            ;;
        "caddy")
            if ! caddy validate --config "$config" 2>/dev/null; then
                log_error "Invalid caddy configuration"
                return $ERROR_CONFIG
            fi
            ;;
    esac
}

# Core domain operations
add_domain() {
    local domain="$1"
    local config="${2:-}"
    
    acquire_lock
    
    if ! validate_domain "$domain"; then
        return $ERROR_INVALID_DOMAIN
    fi

    if domain_exists "$domain"; then
        log_error "Domain already exists: $domain"
        return $ERROR_DUPLICATE
    fi

    local domain_config=$(build_domain_config "$domain" "$config")
    
    if ! update_database "$domain" "$domain_config"; then
        log_error "Failed to update database for domain: $domain"
        return $ERROR_CONFIG
    fi

    if ! configure_services "$domain" "$domain_config"; then
        log_error "Failed to configure services for domain: $domain"
        rollback_domain "$domain"
        return $ERROR_CONFIG
    fi

    if ! generate_ssl_certificate "$domain"; then
        log_warning "SSL certificate generation failed for domain: $domain"
    fi

    log_audit "DOMAIN_ADD" "Added domain: $domain" "$domain_config"
    print_success "Domain added successfully: $domain"
    
    cleanup_lock
    return $SUCCESS
}

remove_domain() {
    local domain="$1"
    
    acquire_lock

    if ! domain_exists "$domain"; then
        log_error "Domain does not exist: $domain"
        return $ERROR_VALIDATION
    fi

    local domain_config=$(get_domain_config "$domain")
    
    if ! remove_service_configs "$domain"; then
        log_error "Failed to remove service configurations for domain: $domain"
        return $ERROR_CONFIG
    fi

    if ! remove_from_database "$domain"; then
        log_error "Failed to remove domain from database: $domain"
        return $ERROR_CONFIG
    fi

    cleanup_ssl_certificate "$domain"

    log_audit "DOMAIN_REMOVE" "Removed domain: $domain" "$domain_config"
    print_success "Domain removed successfully: $domain"
    
    cleanup_lock
    return $SUCCESS
}

update_domain() {
    local domain="$1"
    local updates="$2"
    
    acquire_lock

    if ! domain_exists "$domain"; then
        log_error "Domain does not exist: $domain"
        return $ERROR_VALIDATION
    fi

    local current_config=$(get_domain_config "$domain")
    local new_config=$(update_domain_config "$current_config" "$updates")
    
    if ! validate_domain_config "$new_config"; then
        log_error "Invalid domain configuration update"
        return $ERROR_VALIDATION
    fi

    if ! update_database "$domain" "$new_config"; then
        log_error "Failed to update domain in database: $domain"
        return $ERROR_CONFIG
    fi

    if ! reconfigure_services "$domain" "$new_config"; then
        log_error "Failed to reconfigure services for domain: $domain"
        rollback_domain_update "$domain" "$current_config"
        return $ERROR_CONFIG
    fi

    log_audit "DOMAIN_UPDATE" "Updated domain: $domain" "{\"old\": $current_config, \"new\": $new_config}"
    print_success "Domain updated successfully: $domain"
    
    cleanup_lock
    return $SUCCESS
}

# Service configuration management
configure_services() {
    local domain="$1"
    local config="$2"
    
    for service in "${SERVICES[@]}"; do
        if is_service_enabled "$service" "$config"; then
            if ! configure_service "$service" "$domain" "$config"; then
                log_error "Failed to configure $service for domain: $domain"
                return $ERROR_CONFIG
            fi
        fi
    done
    
    reload_services
}

configure_service() {
    local service="$1"
    local domain="$2"
    local config="$3"
    
    local service_config=$(generate_service_config "$service" "$domain" "$config")
    local config_file="$CONFIG_DIR/${service}/$domain.conf"
    
    if ! validate_service_config "$service" "$service_config"; then
        return $ERROR_CONFIG
    fi

    echo "$service_config" > "$config_file"
    
    if ! test_service_config "$service" "$config_file"; then
        rm -f "$config_file"
        return $ERROR_CONFIG
    fi
    
    return $SUCCESS
}

generate_service_config() {
    local service="$1"
    local domain="$2"
    local config="$3"
    
    case "$service" in
        "xray")
            generate_xray_config "$domain" "$config"
            ;;
        "nginx")
            generate_nginx_config "$domain" "$config"
            ;;
        "haproxy")
            generate_haproxy_config "$domain" "$config"
            ;;
        "caddy")
            generate_caddy_config "$domain" "$config"
            ;;
        *)
            echo ""
            ;;
    esac
}

# SSL Certificate management
generate_ssl_certificate() {
    local domain="$1"
    
    if ! command -v certbot >/dev/null 2>&1; then
        log_warning "certbot not installed, skipping SSL certificate generation"
        return 1
    fi

    local email="admin@$domain"
    local cert_dir="/etc/letsencrypt/live/$domain"
    
    if [[ -d "$cert_dir" ]]; then
        print_info "SSL certificate already exists for domain: $domain"
        return $SUCCESS
    fi

    # Temporary web server for ACME challenge
    start_temp_webserver
    
    local certbot_cmd=(
        "certbot" "certonly" "--non-interactive" "--agree-tos"
        "--email" "$email" "--domain" "$domain"
        "--standalone" "--http-01-port" "8080"
    )
    
    if "${certbot_cmd[@]}"; then
        setup_ssl_config "$domain"
        return $SUCCESS
    else
        log_error "SSL certificate generation failed for domain: $domain"
        return 1
    fi
}

setup_ssl_config() {
    local domain="$1"
    local cert_dir="/etc/letsencrypt/live/$domain"
    
    for service in "${SERVICES[@]}"; do
        if [[ -f "$CONFIG_DIR/${service}/$domain.conf" ]]; then
            update_service_ssl_config "$service" "$domain" "$cert_dir"
        fi
    done
}

# Database operations
update_database() {
    local domain="$1"
    local config="$2"
    
    local temp_db="$DOMAIN_DB.tmp"
    
    jq --arg domain "$domain" --argjson config "$config" \
        '.domains[$domain] = $config |
         .metadata.last_modified = "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'" |
         .metadata.total_count = (.domains | length) |
         .metadata.active_count = (.domains | to_entries | map(select(.value.enabled == true)) | length)' \
        "$DOMAIN_DB" > "$temp_db"
    
    if validate_database "$temp_db"; then
        mv "$temp_db" "$DOMAIN_DB"
        return $SUCCESS
    else
        rm -f "$temp_db"
        return 1
    fi
}

validate_database() {
    local db_file="$1"
    jq -e . >/dev/null 2>&1 < "$db_file"
}

# Utility functions
domain_exists() {
    local domain="$1"
    jq -e ".domains[\"$domain\"]" "$DOMAIN_DB" >/dev/null 2>&1
}

get_domain_config() {
    local domain="$1"
    jq -c ".domains[\"$domain\"]" "$DOMAIN_DB" 2>/dev/null
}

is_service_enabled() {
    local service="$1"
    local config="$2"
    jq -e ".services.$service" <<<"$config" >/dev/null 2>&1
}

# Logging functions
log_audit() {
    local action="$1"
    local message="$2"
    local data="${3:-}"
    
    local log_entry=$(jq -n \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg action "$action" \
        --arg message "$message" \
        --argjson data "$data" \
        '{timestamp: $timestamp, action: $action, message: $message, data: $data}')
    
    echo "$log_entry" >&3
}

log_error() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $message" >&4
}

log_warning() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $message" >&4
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Main execution
main() {
    init_system
    
    local action="${1:-}"
    local domain="${2:-}"
    local config="${3:-}"
    
    case "$action" in
        "add")
            add_domain "$domain" "$config"
            ;;
        "remove")
            remove_domain "$domain"
            ;;
        "update")
            update_domain "$domain" "$config"
            ;;
        "list")
            list_domains
            ;;
        "show")
            show_domain "$domain"
            ;;
        "enable")
            toggle_domain "$domain" true
            ;;
        "disable")
            toggle_domain "$domain" false
            ;;
        "validate")
            validate_domain "$domain"
            ;;
        "reload")
            reload_services
            ;;
        "backup")
            backup_database
            ;;
        "restore")
            restore_database "$domain"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

show_usage() {
    cat << EOF
VIP Domain Management System

Usage: $0 <action> [domain] [config]

Actions:
  add <domain> [config]     Add a new domain
  remove <domain>           Remove a domain
  update <domain> <config>  Update domain configuration
  list                      List all domains
  show <domain>             Show domain details
  enable <domain>           Enable domain
  disable <domain>          Disable domain
  validate <domain>         Validate domain format
  reload                    Reload services
  backup                    Backup database
  restore <file>            Restore database from backup

Examples:
  $0 add example.com '{"ssl": {"enabled": true}}'
  $0 remove example.com
  $0 list
EOF
}

# Service-specific configuration generators (simplified examples)
generate_xray_config() {
    local domain="$1"
    local config="$2"
    
    cat << EOF
{
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$domain",
                    "certificates": [
                        {
                            "certificateFile": "/etc/letsencrypt/live/$domain/fullchain.pem",
                            "keyFile": "/etc/letsencrypt/live/$domain/privkey.pem"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
}

generate_nginx_config() {
    local domain="$1"
    local config="$2"
    
    cat << EOF
server {
    listen 80;
    listen 443 ssl http2;
    
    server_name $domain;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
}

# Start temporary web server for ACME challenges
start_temp_webserver() {
    # Simple Python web server for ACME challenges
    python3 -m http.server 8080 -d /tmp/ >/dev/null 2>&1 &
    local webserver_pid=$!
    sleep 2
    kill $webserver_pid 2>/dev/null
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_DIR/domain-config.json" ]]; then
        source <(jq -r '. | to_entries | .[] | "export \(.key)=\(.value)"' "$CONFIG_DIR/domain-config.json")
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
