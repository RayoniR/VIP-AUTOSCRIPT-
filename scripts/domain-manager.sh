#!/bin/bash

# VIP-Autoscript Modern Domain Management Panel
# Beautiful terminal interface for domain management

set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly CONFIG_DIR="/etc/vip-autoscript/config"
readonly DOMAIN_DIR="/etc/vip-autoscript/domains"  
readonly LOG_DIR="/etc/vip-autoscript/logs"
readonly BACKUP_DIR="/etc/vip-autoscript/backups"
readonly LOCK_DIR="/tmp/vip-domains"
readonly DOMAIN_DB="$DOMAIN_DIR/domains.json"
readonly PANEL_LOG="$LOG_DIR/domain-panel.log"

# UI Configuration
readonly PANEL_WIDTH=80
readonly PANEL_HEIGHT=25

# Colors for modern UI
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly BG_BLUE='\033[44m'
readonly BG_GREEN='\033[42m'
readonly BG_RED='\033[41m'
readonly BG_CYAN='\033[46m'
readonly NC='\033[0m'

# Initialize system
init_system() {
    mkdir -p "$CONFIG_DIR" "$DOMAIN_DIR" "$LOG_DIR" "$BACKUP_DIR" "$LOCK_DIR"
    if [[ ! -f "$DOMAIN_DB" ]]; then
        echo '{"domains":{},"metadata":{"total_count":0,"active_count":0}}' > "$DOMAIN_DB"
    fi
}

# Modern UI Functions
draw_header() {
    clear
    echo -e "${BG_BLUE}${WHITE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                   VIP-AUTOSCRIPT DOMAIN MANAGEMENT PANEL                    ║"
    echo "║                     Enterprise Domain Administration System                 ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

draw_footer() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║ [A]dd Domain  [E]dit  [D]elete  [S]tats  [R]eload  [Q]uit                   ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

draw_box() {
    local width="$1"
    local title="$2"
    local color="${3:-$BLUE}"
    
    echo -e "${color}"
    echo "╔$(printf '═%.0s' $(seq 1 $((width-2))))╗"
    echo "║$(printf ' %-.0s' $(seq 1 $((width-4))))║" | sed "s/^║ /║ ${title} /"
    echo "╚$(printf '═%.0s' $(seq 1 $((width-2))))╝"
    echo -e "${NC}"
}

print_center() {
    local text="$1"
    local color="${2:-$WHITE}"
    local width="${3:-$PANEL_WIDTH}"
    
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s" ""
    echo -e "${color}${text}${NC}"
}

show_stats() {
    local total_domains=$(jq '.metadata.total_count' "$DOMAIN_DB")
    local active_domains=$(jq '.metadata.active_count' "$DOMAIN_DB")
    local inactive_domains=$((total_domains - active_domains))
    
    draw_box 60 "📊 DOMAIN STATISTICS" "$MAGENTA"
    echo -e " ${GREEN}• Total Domains:${NC}    $total_domains"
    echo -e " ${GREEN}• Active Domains:${NC}   $active_domains"
    echo -e " ${RED}• Inactive Domains:${NC} $inactive_domains"
    echo -e " ${CYAN}• Server Time:${NC}      $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

show_domains_table() {
    local domains=()
    local statuses=()
    local services=()
    local ssl_statuses=()
    
    # Get domain data
    while IFS= read -r domain; do
        domains+=("$domain")
        statuses+=("$(jq -r ".domains[\"$domain\"].enabled" "$DOMAIN_DB")")
        
        # Get services
        local service_list=""
        if jq -e ".domains[\"$domain\"].services.xray" "$DOMAIN_DB" >/dev/null; then
            service_list+="xray,"
        fi
        if jq -e ".domains[\"$domain\"].services.nginx" "$DOMAIN_DB" >/dev/null; then
            service_list+="nginx,"
        fi
        services+=("${service_list%,}")
        
        # SSL status
        if jq -e ".domains[\"$domain\"].ssl.enabled" "$DOMAIN_DB" >/dev/null; then
            ssl_statuses+=("SSL")
        else
            ssl_statuses+=("No SSL")
        fi
    done < <(jq -r '.domains | keys[]' "$DOMAIN_DB")
    
    draw_box 80 "🌐 MANAGED DOMAINS" "$BLUE"
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        print_center "No domains configured" "$YELLOW"
        return
    fi
    
    # Table header
    echo -e " ${GREEN}Domain               Status     Services          SSL${NC}"
    echo -e " ${GREEN}------------------- ---------- ---------------- ---------${NC}"
    
    # Table rows
    for i in "${!domains[@]}"; do
        local domain="${domains[$i]}"
        local status="${statuses[$i]}"
        local service="${services[$i]}"
        local ssl="${ssl_statuses[$i]}"
        
        # Color coding
        local status_color=$GREEN
        [[ "$status" == "false" ]] && status_color=$RED
        
        local ssl_color=$CYAN
        [[ "$ssl" == "No SSL" ]] && ssl_color=$YELLOW
        
        printf " %-19s ${status_color}%-10s${NC} %-16s ${ssl_color}%9s${NC}\n" \
               "$domain" "$status" "$service" "$ssl"
    done
    echo ""
}

# Interactive Dialogs
add_domain_dialog() {
    local domain
    local enable_ssl
    local services=()
    
    draw_header
    draw_box 60 "➕ ADD NEW DOMAIN" "$GREEN"
    
    read -p " Enter domain name: " domain
    if [[ -z "$domain" ]]; then
        show_error "Domain name cannot be empty!"
        return 1
    fi
    
    # Validate domain
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
        show_error "Invalid domain format!"
        return 1
    fi
    
    # Service selection
    echo " Select services to enable:"
    echo "  1) Xray"
    echo "  2) Nginx"
    echo "  3) Both Xray and Nginx"
    read -p " Enter choice [1-3]: " service_choice
    
    case $service_choice in
        1) services=("xray") ;;
        2) services=("nginx") ;;
        3) services=("xray" "nginx") ;;
        *) services=("xray") ;;
    esac
    
    # SSL selection
    echo " Enable SSL certificate?"
    echo "  1) Yes (Let's Encrypt)"
    echo "  2) No"
    read -p " Enter choice [1-2]: " ssl_choice
    
    case $ssl_choice in
        1) enable_ssl=true ;;
        2) enable_ssl=false ;;
        *) enable_ssl=true ;;
    esac
    
    # Build config
    local config=$(build_domain_config "$domain" "$services" "$enable_ssl")
    
    # Add domain
    if /etc/vip-autoscript/scripts/domain-manager.sh add "$domain" "$config"; then
        show_success "Domain $domain added successfully!"
    else
        show_error "Failed to add domain $domain"
    fi
}

build_domain_config() {
    local domain="$1"
    local services=("$2")
    local enable_ssl="$3"
    
    local services_json=""
    for service in "${services[@]}"; do
        services_json+="\"$service\": true,"
    done
    services_json="${services_json%,}"
    
    cat << EOF
{
    "enabled": true,
    "services": {$services_json},
    "ssl": {
        "enabled": $enable_ssl,
        "cert_type": "letsencrypt",
        "auto_renew": true
    },
    "routing": {
        "backend": "http://localhost:3000",
        "load_balancing": "round-robin",
        "health_check": true
    },
    "security": {
        "waf": false,
        "rate_limiting": true,
        "ip_whitelist": [],
        "ip_blacklist": []
    },
    "monitoring": {
        "enabled": true,
        "uptime_check": true,
        "response_time": false,
        "alert_threshold": 80
    }
}
EOF
}

edit_domain_dialog() {
    local domain
    
    draw_header
    draw_box 60 "✏️ EDIT DOMAIN" "$YELLOW"
    
    read -p " Enter domain to edit: " domain
    
    if ! domain_exists "$domain"; then
        show_error "Domain $domain not found!"
        return 1
    fi
    
    show_domain_details "$domain"
    echo ""
    
    echo " Editing options:"
    echo "  1) Toggle SSL"
    echo "  2) Toggle services"
    echo "  3) Change backend"
    echo "  4) Cancel"
    read -p " Enter choice [1-4]: " edit_choice
    
    case $edit_choice in
        1) toggle_ssl "$domain" ;;
        2) toggle_services "$domain" ;;
        3) change_backend "$domain" ;;
        *) show_info "Edit cancelled" ;;
    esac
}

delete_domain_dialog() {
    local domain
    
    draw_header
    draw_box 60 "🗑️ DELETE DOMAIN" "$RED"
    
    read -p " Enter domain to delete: " domain
    
    if ! domain_exists "$domain"; then
        show_error "Domain $domain not found!"
        return 1
    fi
    
    show_domain_details "$domain"
    echo ""
    
    read -p " Are you sure you want to delete $domain? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        show_info "Deletion cancelled"
        return 0
    fi
    
    if /etc/vip-autoscript/scripts/domain-manager.sh remove "$domain"; then
        show_success "Domain $domain deleted successfully!"
    else
        show_error "Failed to delete domain $domain"
    fi
}

# Utility Functions
domain_exists() {
    local domain="$1"
    jq -e ".domains[\"$domain\"]" "$DOMAIN_DB" >/dev/null 2>&1
}

show_domain_details() {
    local domain="$1"
    
    if ! domain_exists "$domain"; then
        show_error "Domain not found: $domain"
        return 1
    fi
    
    local enabled=$(jq -r ".domains[\"$domain\"].enabled" "$DOMAIN_DB")
    local ssl_enabled=$(jq -r ".domains[\"$domain\"].ssl.enabled" "$DOMAIN_DB")
    local services=$(jq -r ".domains[\"$domain\"].services | to_entries[] | select(.value) | .key" "$DOMAIN_DB" | tr '\n' ',')
    
    echo -e " ${CYAN}Domain:${NC}     $domain"
    echo -e " ${CYAN}Status:${NC}     $([ "$enabled" = "true" ] && echo -e "${GREEN}Enabled${NC}" || echo -e "${RED}Disabled${NC}")"
    echo -e " ${CYAN}SSL:${NC}       $([ "$ssl_enabled" = "true" ] && echo -e "${GREEN}Enabled${NC}" || echo -e "${YELLOW}Disabled${NC}")"
    echo -e " ${CYAN}Services:${NC}   ${services%,}"
}

show_error() {
    echo -e "${RED}❌ Error: $1${NC}"
    sleep 2
}

show_success() {
    echo -e "${GREEN}✅ Success: $1${NC}"
    sleep 2
}

show_info() {
    echo -e "${BLUE}ℹ️ Info: $1${NC}"
    sleep 1
}

show_warning() {
    echo -e "${YELLOW}⚠️ Warning: $1${NC}"
    sleep 1
}

# Main Panel Loop
main_panel() {
    init_system
    
    while true; do
        draw_header
        show_stats
        show_domains_table
        draw_footer
        
        read -n 1 -p " Select option: " choice
        echo ""
        
        case $choice in
            a|A) add_domain_dialog ;;
            e|E) edit_domain_dialog ;;
            d|D) delete_domain_dialog ;;
            s|S) show_stats
                 read -n 1 -p " Press any key to continue..." ;;
            r|R) /etc/vip-autoscript/scripts/domain-manager.sh reload
                 show_info "Services reloaded"
                 ;;
            q|Q) echo "Goodbye!"; exit 0 ;;
            *) show_error "Invalid option: $choice" ;;
        esac
    done
}

# Quick actions (preserve original functionality)
quick_action() {
    local action="$1"
    local domain="$2"
    local config="$3"
    
    case $action in
        "add")
            /etc/vip-autoscript/scripts/domain-manager.sh add "$domain" "$config"
            ;;
        "remove")
            /etc/vip-autoscript/scripts/domain-manager.sh remove "$domain"
            ;;
        "list")
            /etc/vip-autoscript/scripts/domain-manager.sh list
            ;;
        "panel")
            main_panel
            ;;
        *)
            echo "Usage: $0 [add|remove|list|panel] [domain] [config]"
            exit 1
            ;;
    esac
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        main_panel
    else
        quick_action "$@"
    fi
fi