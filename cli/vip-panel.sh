#!/bin/bash
# VIP-Autoscript Advanced Management Panel
# Enterprise-grade VPN user management system

set -euo pipefail
IFS=$'\n\t'

# Load configuration and libraries
PANEL_ROOT="/etc/vip-autoscript-"
CONFIG_DIR="${PANEL_ROOT}/config"
LIB_DIR="${PANEL_ROOT}/lib"
SCRIPTS_DIR="${PANEL_ROOT}/scripts"

source "${CONFIG_DIR}/panel.conf"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/validation.sh"
source "${LIB_DIR}/database.sh"
source "${LIB_DIR}/ui.sh"
source "${LIB_DIR}/config-generator.sh"
source "${LIB_DIR}/phone-storage.sh"
source "${LIB_DIR}/audit.sh"
source "${LIB_DIR}/lock.sh"

# Panel state management
declare -A PANEL_STATE
declare -A USER_CACHE
declare -A CONFIG_CACHE
declare -A STATS_CACHE

# Session management
readonly SESSION_FILE="/tmp/vip-panel-session.$$"
readonly SESSION_TIMEOUT=900

panel::init() {
    utils::log "INFO" "VIP Panel initialization started"
    
    # Initialize all modules
    utils::init
    validation::init
    db::ensure_db
    ui::init
    phone_storage::init
    audit::init
    
    # Load panel state
    panel::_load_state
    
    # Set up signal handlers
    trap panel::cleanup EXIT
    trap 'utils::error_handler $LINENO "$BASH_COMMAND" $?' ERR
    trap panel::handle_sigint INT
    trap panel::handle_sigterm TERM
    
    utils::log "INFO" "VIP Panel initialized successfully"
}

panel::_load_state() {
    PANEL_STATE["CURRENT_SCREEN"]="MAIN_MENU"
    PANEL_STATE["LAST_SCREEN"]=""
    PANEL_STATE["SELECTED_USER"]=""
    PANEL_STATE["PAGINATION"]=1
    PANEL_STATE["FILTER"]=""
    PANEL_STATE["SORT_FIELD"]="username"
    PANEL_STATE["SORT_ORDER"]="asc"
    PANEL_STATE["VIEW_MODE"]="table"
    PANEL_STATE["THEME"]="dark"
    PANEL_STATE["LANGUAGE"]="en"
    PANEL_STATE["AUTO_REFRESH"]=true
    PANEL_STATE["NOTIFICATIONS"]=true
}

panel::cleanup() {
    utils::log "INFO" "Panel cleanup initiated"
    
    # Release all locks
    lock::release_all
    
    # Clear caches
    USER_CACHE=()
    CONFIG_CACHE=()
    STATS_CACHE=()
    
    # Remove session file
    rm -f "$SESSION_FILE" 2>/dev/null || true
    
    # Cleanup temporary files
    utils::cleanup
    
    utils::log "INFO" "Panel cleanup completed"
}

panel::handle_sigint() {
    echo -e "\n${YELLOW}Received interrupt signal. Cleaning up...${NC}"
    panel::cleanup
    exit $EXIT_SUCCESS
}

panel::handle_sigterm() {
    echo -e "\n${YELLOW}Received termination signal. Cleaning up...${NC}"
    panel::cleanup
    exit $EXIT_SUCCESS
}

panel::check_session() {
    local current_time=$(date +%s)
    local last_activity=${PANEL_STATE["LAST_ACTIVITY"]:-0}
    
    if [[ $((current_time - last_activity)) -gt $SESSION_TIMEOUT ]]; then
        utils::log "WARN" "Session timeout detected"
        echo -e "${RED}Session timeout. Please log in again.${NC}"
        panel::cleanup
        exit $EXIT_SUCCESS
    fi
    
    PANEL_STATE["LAST_ACTIVITY"]=$current_time
}

panel::main_menu() {
    while true; do
        panel::check_session
        
        ui::clear_screen
        ui::show_header
        panel::show_dashboard
        ui::show_footer
        
        local choice
        read -t $UI_REFRESH_RATE -n 1 -p " Select option: " choice || true
        echo ""
        
        case $choice in
            n|N) panel::create_user_dialog ;;
            e|E) panel::edit_user_dialog ;;
            d|D) panel::delete_user_dialog ;;
            g|G) panel::generate_config_dialog ;;
            s|S) panel::show_stats_dialog ;;
            f|F) panel::filter_dialog ;;
            o|O) panel::sort_dialog ;;
            v|V) panel::toggle_view_mode ;;
            t|T) panel::toggle_theme ;;
            r|R) panel::refresh_data ;;
            b|B) panel::backup_dialog ;;
            m|M) panel::maintenance_dialog ;;
            a|A) panel::advanced_menu ;;
            q|Q) panel::quit_dialog ;;
            *) panel::handle_unknown_input "$choice" ;;
        esac
    done
}

panel::show_dashboard() {
    local stats=$(db::get_stats)
    local total_users=$(echo "$stats" | jq -r '.total_users')
    local active_users=$(echo "$stats" | jq -r '.active_users')
    
    # Show quick stats
    ui::draw_box 60 "📊 QUICK STATS" "$MAGENTA" "rounded"
    echo -e " ${GREEN}• Total Users:${NC}    $(printf "%4d" $total_users)"
    echo -e " ${GREEN}• Active Users:${NC}   $(printf "%4d" $active_users)"
    echo -e " ${CYAN}• Config Files:${NC}    $(find "$CONFIG_OUTPUT_DIR" -name "*.*" 2>/dev/null | wc -l)"
    echo -e " ${YELLOW}• Phone Storage:${NC}  $(phone_storage::is_available && echo "Connected" || echo "Disconnected")"
    echo ""
    
    # Show users table or cards based on view mode
    if [[ "${PANEL_STATE["VIEW_MODE"]}" == "table" ]]; then
        ui::show_users_table
    else
        panel::show_users_cards
    fi
}

panel::show_users_cards() {
    local users=$(db::list_users)
    local user_count=$(echo "$users" | wc -l)
    local width=$(( (UI_STATE["TERMINAL_WIDTH"] - 20) / 3 ))
    
    ui::draw_box $UI_STATE["TERMINAL_WIDTH"] "👥 USER ACCOUNTS (Card View)" "$BLUE" "rounded"
    
    if [[ $user_count -eq 0 ]]; then
        ui::print_center "No users found" "$YELLOW"
        return
    fi
    
    local i=0
    while IFS= read -r user; do
        if [[ $((i % 3)) -eq 0 ]]; then
            echo ""
        fi
        
        panel::show_user_card "$user" "$width"
        ((i++))
    done <<< "$users"
    
    echo ""
}

panel::show_user_card() {
    local user="$1"
    local width="$2"
    local user_data=$(db::get_user "$user")
    local status=$(echo "$user_data" | jq -r '.status')
    local expiry=$(echo "$user_data" | jq -r '.expiry_date')
    local services=$(echo "$user_data" | jq -r '.services | join(", ")')
    local configs=$(echo "$user_data" | jq -r '.configs_generated')
    
    local status_color=$GREEN
    [[ "$status" == "expired" ]] && status_color=$RED
    [[ "$status" == "disabled" ]] && status_color=$YELLOW
    
    local box_color=$BLUE
    [[ "$status" == "expired" ]] && box_color=$RED
    [[ "$status" == "disabled" ]] && box_color=$YELLOW
    
    echo -e "${box_color}╭$(printf '─%.0s' $(seq 1 $((width-2))))╮${NC}"
    printf "${box_color}│${NC} %-${width-4}s ${box_color}│${NC}\n" "User: $user"
    printf "${box_color}│${NC} %-${width-4}s ${box_color}│${NC}\n" "Status: ${status_color}$status${NC}"
    printf "${box_color}│${NC} %-${width-4}s ${box_color}│${NC}\n" "Expiry: $expiry"
    printf "${box_color}│${NC} %-${width-4}s ${box_color}│${NC}\n" "Services: $services"
    printf "${box_color}│${NC} %-${width-4}s ${box_color}│${NC}\n" "Configs: $configs"
    echo -e "${box_color}╰$(printf '─%.0s' $(seq 1 $((width-2))))╯${NC}"
}

panel::create_user_dialog() {
    local username service expiry_days vpn_client generate_config password
    
    ui::clear_screen
    ui::draw_box 60 "➕ CREATE NEW USER" "$GREEN" "rounded"
    
    # Username validation loop
    while true; do
        read -p " Enter username: " username
        username=$(validation::sanitize_input "$username" "username")
        
        if validation::validate_username "$username" 2>/dev/null; then
            break
        else
            ui::show_error "$(validation::get_errors)"
            validation::clear_errors
        fi
    done
    
    # Service selection
    ui::draw_box 40 " Select Service Type" "$CYAN" "rounded"
    local service_choice=$(ui::interactive_menu "Service Type" \
        ["1] SSH Only" "2] Xray Only" "3] Both SSH & Xray"])
    
    case $service_choice in
        0) service="ssh" ;;
        1) service="xray" ;;
        2) service="both" ;;
        *) service="ssh" ;;
    esac
    
    # Expiry selection
    ui::draw_box 40 " Select Expiry" "$YELLOW" "rounded"
    local expiry_choice=$(ui::interactive_menu "Expiry Options" \
        ["1] 7 days" "2] 30 days" "3] 90 days" "4] Never expire"])
    
    case $expiry_choice in
        0) expiry_days=7 ;;
        1) expiry_days=30 ;;
        2) expiry_days=90 ;;
        3) expiry_days="never" ;;
        *) expiry_days=30 ;;
    esac
    
    # Config generation
    ui::draw_box 40 " Config Generation" "$MAGENTA" "rounded"
    local config_choice=$(ui::interactive_menu "Generate Config?" \
        ["1] Yes, generate config" "2] No, just create user"])
    
    if [[ $config_choice -eq 0 ]]; then
        generate_config=true
        vpn_client=$(panel::select_vpn_client)
    else
        generate_config=false
    fi
    
    # Password option
    ui::draw_box 40 " Password Setup" "$BLUE" "rounded"
    local pass_choice=$(ui::interactive_menu "Password Option" \
        ["1] Auto-generate password" "2] Set custom password"])
    
    if [[ $pass_choice -eq 1 ]]; then
        read -sp " Enter password: " password
        echo ""
        password=$(validation::validate_password "$password") || {
            ui::show_error "$(validation::get_errors)"
            return 1
        }
    else
        password=""
    fi
    
    # Confirmation
    ui::draw_box 50 " Confirm Creation" "$GREEN" "rounded"
    echo -e " ${CYAN}Username:${NC}    $username"
    echo -e " ${CYAN}Service:${NC}     $service"
    echo -e " ${CYAN}Expiry:${NC}      $expiry_days days"
    echo -e " ${CYAN}Generate Config:${NC} $generate_config"
    [[ -n "$password" ]] && echo -e " ${CYAN}Password:${NC}    ******"
    echo ""
    
    if ! ui::confirm_dialog "Create user with these settings?"; then
        ui::show_info "User creation cancelled"
        return 0
    fi
    
    # Create user
    if "${SCRIPTS_DIR}/user-managers.sh" create "$username" "$service" "$expiry_days" "$password"; then
        ui::show_success "User $username created successfully!"
        audit::log "USER_CREATE" "Created user $username with service: $service"
        
        # Generate config if requested
        if [[ "$generate_config" == "true" ]]; then
            panel::generate_config_file "$username" "$vpn_client"
        fi
    else
        ui::show_error "Failed to create user $username"
        return 1
    fi
    
    sleep 2
}

panel::edit_user_dialog() {
    local username new_expiry new_service new_status
    
    ui::clear_screen
    ui::draw_box 60 "✏️ EDIT USER" "$YELLOW" "rounded"
    
    read -p " Enter username to edit: " username
    
    if ! db::user_exists "$username"; then
        ui::show_error "User $username not found!"
        return 1
    fi
    
    local user_data=$(db::get_user "$username")
    panel::show_user_details "$username"
    
    ui::draw_box 50 " Edit Options" "$CYAN" "rounded"
    local edit_choice=$(ui::interactive_menu "Edit Field" \
        ["1] Change expiry" "2] Change service" "3] Change status" "4] Reset password"])
    
    case $edit_choice in
        0)
            panel::change_expiry_dialog "$username"
            ;;
        1)
            panel::change_service_dialog "$username"
            ;;
        2)
            panel::change_status_dialog "$username"
            ;;
        3)
            panel::reset_password_dialog "$username"
            ;;
        *)
            ui::show_info "Edit cancelled"
            ;;
    esac
}

panel::change_expiry_dialog() {
    local username="$1"
    local new_expiry
    
    ui::draw_box 40 " Change Expiry" "$YELLOW" "rounded"
    local expiry_choice=$(ui::interactive_menu "New Expiry" \
        ["1] 7 days" "2] 30 days" "3] 90 days" "4] Never expire" "5] Custom days"])
    
    case $expiry_choice in
        0) new_expiry=7 ;;
        1) new_expiry=30 ;;
        2) new_expiry=90 ;;
        3) new_expiry="never" ;;
        4)
            read -p " Enter custom days: " custom_days
            new_expiry=$(validation::validate_expiry "$custom_days") || {
                ui::show_error "$(validation::get_errors)"
                return 1
            }
            ;;
        *) return 1 ;;
    esac
    
    if "${SCRIPTS_DIR}/user-managers.sh" update "$username" "expiry" "$new_expiry"; then
        ui::show_success "Expiry updated for $username"
        audit::log "USER_UPDATE" "Updated expiry for $username to $new_expiry"
    else
        ui::show_error "Failed to update expiry for $username"
    fi
}

panel::delete_user_dialog() {
    local username force=false
    
    ui::clear_screen
    ui::draw_box 60 "🗑️ DELETE USER" "$RED" "rounded"
    
    read -p " Enter username to delete: " username
    
    if ! db::user_exists "$username"; then
        ui::show_error "User $username not found!"
        return 1
    fi
    
    panel::show_user_details "$username"
    echo ""
    
    ui::draw_box 40 " Delete Options" "$RED" "rounded"
    local delete_choice=$(ui::interactive_menu "Delete Method" \
        ["1] Soft delete (keep configs)" "2] Hard delete (remove everything)" "3] Cancel"])
    
    case $delete_choice in
        0)
            force=false
            ;;
        1)
            force=true
            ;;
        *)
            ui::show_info "Deletion cancelled"
            return 0
            ;;
    esac
    
    if ! ui::confirm_dialog "Are you sure you want to delete $username?"; then
        ui::show_info "Deletion cancelled"
        return 0
    fi
    
    if "${SCRIPTS_DIR}/user-managers.sh" delete "$username" "$force"; then
        ui::show_success "User $username deleted successfully!"
        audit::log "USER_DELETE" "Deleted user $username (force: $force)"
        
        # Remove config files if hard delete
        if [[ "$force" == "true" ]]; then
            find "$CONFIG_OUTPUT_DIR" -name "${username}_*" -delete
            find "$PHONE_STORAGE_DIR" -name "${username}_*" -delete 2>/dev/null || true
        fi
    else
        ui::show_error "Failed to delete user $username"
    fi
    
    sleep 2
}

panel::generate_config_dialog() {
    local username vpn_client
    
    ui::clear_screen
    ui::draw_box 60 "⚙️ GENERATE CONFIG" "$MAGENTA" "rounded"
    
    read -p " Enter username: " username
    
    if ! db::user_exists "$username"; then
        ui::show_error "User $username not found!"
        return 1
    fi
    
    panel::show_user_details "$username"
    echo ""
    
    vpn_client=$(panel::select_vpn_client)
    
    ui::draw_box 40 " Generation Options" "$CYAN" "rounded"
    local gen_choice=$(ui::interactive_menu "Generate Options" \
        ["1] Single config" "2] All clients" "3] Custom selection"])
    
    case $gen_choice in
        0)
            panel::generate_config_file "$username" "$vpn_client"
            ;;
        1)
            panel::generate_all_configs "$username"
            ;;
        2)
            panel::generate_custom_configs "$username"
            ;;
        *)
            ui::show_info "Config generation cancelled"
            ;;
    esac
}

panel::generate_config_file() {
    local username="$1"
    local vpn_client="$2"
    
    ui::show_loading "Generating $vpn_client config" $$ &
    local load_pid=$!
    
    if config::generate "$username" "$vpn_client"; then
        kill $load_pid 2>/dev/null || true
        ui::show_success "Config generated successfully for $username!"
        
        # Sync to phone if available
        if phone_storage::is_available; then
            phone_storage::sync
        fi
    else
        kill $load_pid 2>/dev/null || true
        ui::show_error "Failed to generate config for $username"
    fi
    
    sleep 1
}

panel::generate_all_configs() {
    local username="$1"
    
    ui::show_loading "Generating all configs" $$ &
    local load_pid=$!
    
    local clients=("${!VPN_EXTENSIONS[@]}")
    local total=${#clients[@]}
    local success=0
    local errors=0
    
    for client in "${clients[@]}"; do
        if config::generate "$username" "$client" "quiet"; then
            ((success++))
        else
            ((errors++))
            utils::log "ERROR" "Failed to generate $client config for $username"
        fi
    done
    
    kill $load_pid 2>/dev/null || true
    
    if [[ $success -gt 0 ]]; then
        ui::show_success "Generated $success configs for $username ($errors failed)"
    else
        ui::show_error "All config generation attempts failed"
    fi
    
    sleep 2
}

panel::show_stats_dialog() {
    ui::clear_screen
    ui::show_stats
    
    local stats=$(db::get_stats)
    local total_users=$(echo "$stats" | jq -r '.total_users')
    local active_users=$(echo "$stats" | jq -r '.active_users')
    
    ui::draw_box 60 "📈 DETAILED STATISTICS" "$GREEN" "rounded"
    echo -e " ${CYAN}• User Distribution:${NC}"
    echo -e "   - Active:    $(printf "%4d" $active_users)"
    echo -e "   - Expired:   $(printf "%4d" $((total_users - active_users)))"
    echo -e "   - Total:     $(printf "%4d" $total_users)"
    echo ""
    
    # Show config statistics
    local config_stats=$(find "$CONFIG_OUTPUT_DIR" -name "*.*" -exec basename {} \; | awk -F_ '{print $2}' | \
        awk -F. '{print $1}' | sort | uniq -c | sort -nr)
    echo -e " ${CYAN}• Config Types:${NC}"
    if [[ -n "$config_stats" ]]; then
        echo "$config_stats" | while read count client; do
            echo -e "   - $client: $(printf "%3d" $count)"
        done
    else
        echo -e "   ${YELLOW}No config files found${NC}"
    fi
    
    echo ""
    read -n 1 -p " Press any key to continue... "
}

panel::filter_dialog() {
    ui::clear_screen
    ui::draw_box 50 "🔍 FILTER USERS" "$CYAN" "rounded"
    
    echo " Current filter: ${PANEL_STATE["FILTER"]:-None}"
    echo ""
    echo " 1) Filter by username"
    echo " 2) Filter by status"
    echo " 3) Filter by service"
    echo " 4) Clear filter"
    echo " 5) Cancel"
    echo ""
    
    read -n 1 -p " Select option: " choice
    echo ""
    
    case $choice in
        1)
            read -p " Enter username filter: " filter
            PANEL_STATE["FILTER"]="$filter"
            ;;
        2)
            ui::draw_box 40 " Filter by Status" "$YELLOW" "rounded"
            local status_choice=$(ui::interactive_menu "Status Filter" \
                ["1] Active" "2] Expired" "3] Disabled"])
            case $status_choice in
                0) PANEL_STATE["FILTER"]="active" ;;
                1) PANEL_STATE["FILTER"]="expired" ;;
                2) PANEL_STATE["FILTER"]="disabled" ;;
            esac
            ;;
        3)
            read -p " Enter service filter (ssh/xray/both): " filter
            PANEL_STATE["FILTER"]="$filter"
            ;;
        4)
            PANEL_STATE["FILTER"]=""
            ui::show_info "Filter cleared"
            ;;
        5)
            ui::show_info "Filter operation cancelled"
            ;;
        *)
            ui::show_error "Invalid option"
            ;;
    esac
    
    sleep 1
}

panel::sort_dialog() {
    ui::clear_screen
    ui::draw_box 50 "🔢 SORT USERS" "$MAGENTA" "rounded"
    
    echo " Current sort: ${PANEL_STATE["SORT_FIELD"]} (${PANEL_STATE["SORT_ORDER"]})"
    echo ""
    echo " 1) Sort by username"
    echo " 2) Sort by expiry"
    echo " 3) Sort by status"
    echo " 4) Toggle order (ASC/DESC)"
    echo " 5) Cancel"
    echo ""
    
    read -n 1 -p " Select option: " choice
    echo ""
    
    case $choice in
        1) PANEL_STATE["SORT_FIELD"]="username" ;;
        2) PANEL_STATE["SORT_FIELD"]="expiry_date" ;;
        3) PANEL_STATE["SORT_FIELD"]="status" ;;
        4)
            if [[ "${PANEL_STATE["SORT_ORDER"]}" == "asc" ]]; then
                PANEL_STATE["SORT_ORDER"]="desc"
            else
                PANEL_STATE["SORT_ORDER"]="asc"
            fi
            ;;
        5)
            ui::show_info "Sort operation cancelled"
            return
            ;;
        *)
            ui::show_error "Invalid option"
            return
            ;;
    esac
    
    ui::show_info "Sort order updated: ${PANEL_STATE["SORT_FIELD"]} (${PANEL_STATE["SORT_ORDER"]})"
    sleep 1
}

panel::toggle_view_mode() {
    if [[ "${PANEL_STATE["VIEW_MODE"]}" == "table" ]]; then
        PANEL_STATE["VIEW_MODE"]="cards"
        ui::show_info "Switched to card view"
    else
        PANEL_STATE["VIEW_MODE"]="table"
        ui::show_info "Switched to table view"
    fi
    sleep 1
}

panel::toggle_theme() {
    if [[ "${PANEL_STATE["THEME"]}" == "dark" ]]; then
        PANEL_STATE["THEME"]="light"
        ui::show_info "Switched to light theme"
    else
        PANEL_STATE["THEME"]="dark"
        ui::show_info "Switched to dark theme"
    fi
    sleep 1
}

panel::refresh_data() {
    USER_CACHE=()
    CONFIG_CACHE=()
    STATS_CACHE=()
    ui::show_info "Data cache refreshed"
    sleep 1
}

panel::backup_dialog() {
    ui::clear_screen
    ui::draw_box 60 "💾 BACKUP & RESTORE" "$BLUE" "rounded"
    
    echo " 1) Create backup"
    echo " 2) Restore backup"
    echo " 3) List backups"
    echo " 4) Cancel"
    echo ""
    
    read -n 1 -p " Select option: " choice
    echo ""
    
    case $choice in
        1)
            panel::create_backup
            ;;
        2)
            panel::restore_backup
            ;;
        3)
            panel::list_backups
            ;;
        *)
            ui::show_info "Backup operation cancelled"
            ;;
    esac
}

panel::create_backup() {
    ui::draw_box 40 " Backup Type" "$GREEN" "rounded"
    local backup_choice=$(ui::interactive_menu "Backup Type" \
        ["1] Full backup" "2] Database only" "3] Configs only"])
    
    local backup_type
    case $backup_choice in
        0) backup_type="full" ;;
        1) backup_type="database" ;;
        2) backup_type="configs" ;;
        *) return 1 ;;
    esac
    
    ui::show_loading "Creating $backup_type backup" $$ &
    local load_pid=$!
    
    if "${SCRIPTS_DIR}/user-manager.sh" backup "$backup_type"; then
        kill $load_pid 2>/dev/null || true
        ui::show_success "Backup created successfully!"
    else
        kill $load_pid 2>/dev/null || true
        ui::show_error "Backup creation failed"
    fi
    
    sleep 2
}

panel::maintenance_dialog() {
    ui::clear_screen
    ui::draw_box 60 "🔧 MAINTENANCE" "$YELLOW" "rounded"
    
    echo " 1) Check expiries"
    echo " 2) Cleanup old users"
    echo " 3) Sync phone storage"
    echo " 4) Repair database"
    echo " 5) Cancel"
    echo ""
    
    read -n 1 -p " Select option: " choice
    echo ""
    
    case $choice in
        1)
            panel::check_expiries
            ;;
        2)
            panel::cleanup_users
            ;;
        3)
            panel::sync_phone_storage
            ;;
        4)
            panel::repair_database
            ;;
        *)
            ui::show_info "Maintenance operation cancelled"
            ;;
    esac
}

panel::advanced_menu() {
    ui::clear_screen
    ui::draw_box 60 "⚡ ADVANCED MENU" "$MAGENTA" "rounded"
    
    echo " 1) Bulk operations"
    echo " 2) API management"
    echo " 3) System info"
    echo " 4) Log viewer"
    echo " 5) Settings"
    echo " 6) Back to main"
    echo ""
    
    read -n 1 -p " Select option: " choice
    echo ""
    
    case $choice in
        1)
            panel::bulk_operations
            ;;
        2)
            panel::api_management
            ;;
        3)
            panel::system_info
            ;;
        4)
            panel::log_viewer
            ;;
        5)
            panel::settings_menu
            ;;
        *)
            ui::show_info "Returning to main menu"
            ;;
    esac
}

panel::quit_dialog() {
    ui::draw_box 40 " Exit Confirmation" "$RED" "rounded"
    
    if ui::confirm_dialog "Are you sure you want to quit?" "no"; then
        ui::show_info "Goodbye!"
        panel::cleanup
        exit $EXIT_SUCCESS
    else
        ui::show_info "Continue working..."
    fi
}

panel::handle_unknown_input() {
    local choice="$1"
    ui::show_error "Unknown option: $choice"
    sleep 1
}

panel::show_user_details() {
    local username="$1"
    local user_data=$(db::get_user "$username")
    
    echo -e " ${CYAN}Username:${NC}    $username"
    echo -e " ${CYAN}Status:${NC}      $(echo "$user_data" | jq -r '.status')"
    echo -e " ${CYAN}Expiry:${NC}      $(echo "$user_data" | jq -r '.expiry_date')"
    echo -e " ${CYAN}Services:${NC}    $(echo "$user_data" | jq -r '.services | join(", ")')"
    echo -e " ${CYAN}Created:${NC}     $(echo "$user_data" | jq -r '.created')"
    echo -e " ${CYAN}Modified:${NC}    $(echo "$user_data" | jq -r '.last_modified')"
    echo -e " ${CYAN}Configs:${NC}     $(echo "$user_data" | jq -r '.configs_generated')"
}

panel::select_vpn_client() {
    ui::clear_screen
    ui::draw_box 60 "📱 SELECT VPN CLIENT" "$CYAN" "rounded"
    
    local clients=()
    local i=1
    for client in "${!VPN_EXTENSIONS[@]}"; do
        clients+=("$i) $client (${VPN_EXTENSIONS[$client]})")
        ((i++))
    done
    
    local choice
    read -p " Select client [1-${#VPN_EXTENSIONS[@]}]: " choice
    
    if [[ "$choice" -ge 1 && "$choice" -le ${#VPN_EXTENSIONS[@]} ]]; then
        local client_names=("${!VPN_EXTENSIONS[@]}")
        echo "${client_names[$((choice-1))]}"
    else
        echo "HTTPCustom"  # Default
    fi
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        panel::init
        panel::main_menu
    else
        # Command-line mode
        case "$1" in
            "create")
                shift
                "${SCRIPTS_DIR}/user-managers.sh" create "$@"
                ;;
            "delete")
                shift
                "${SCRIPTS_DIR}/user-managers.sh" delete "$@"
                ;;
            "list")
                shift
                "${SCRIPTS_DIR}/user-managers.sh" list "$@"
                ;;
            "stats")
                "${SCRIPTS_DIR}/user-managers.sh" stats
                ;;
            "backup")
                shift
                "${SCRIPTS_DIR}/user-managers.sh" backup "$@"
                ;;
            "restore")
                shift
                "${SCRIPTS_DIR}/user-managers.sh" restore "$@"
                ;;
            "version")
                echo "VIP-Autoscript Panel v3.2.0"
                ;;
            "help")
                cat <<EOF
VIP-Autoscript Panel - Advanced VPN Management

Usage: vip-panel [COMMAND] [ARGS]

Commands:
  create USERNAME SERVICE EXPIRY [PASSWORD] - Create new user
  delete USERNAME [force]                   - Delete user
  list [format] [filter]                    - List users
  stats                                     - Show statistics
  backup [type]                             - Create backup
  restore FILE                              - Restore backup
  version                                   - Show version
  help                                      - Show this help

Without arguments: Start interactive mode
EOF
                ;;
            *)
                echo "Unknown command: $1"
                echo "Use 'vip-panel help' for usage information"
                exit $EXIT_FAILURE
                ;;
        esac
    fi
}

# Run main function
main "$@"
