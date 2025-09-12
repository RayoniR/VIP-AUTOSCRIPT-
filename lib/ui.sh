#!/bin/bash
# VIP-Autoscript Advanced UI Module

ui::init() {
    declare -gA UI_STATE
    declare -gA UI_CACHE
    UI_STATE["CURRENT_SCREEN"]="MAIN_MENU"
    UI_STATE["LAST_SCREEN"]=""
    UI_STATE["SELECTED_USER"]=""
    UI_STATE["PAGINATION"]=1
    UI_STATE["FILTER"]=""
    UI_STATE["SORT_FIELD"]="username"
    UI_STATE["SORT_ORDER"]="asc"
    
    # Terminal detection
    UI_STATE["TERMINAL_WIDTH"]=$(tput cols 2>/dev/null || echo $PANEL_WIDTH)
    UI_STATE["TERMINAL_HEIGHT"]=$(tput lines 2>/dev/null || echo $PANEL_HEIGHT)
    UI_STATE["HAS_COLOR"]=$(tput colors 2>/dev/null || echo 0)
    
    # Load animations if supported
    ui::_load_animations
}

ui::_load_animations() {
    declare -gA UI_ANIMATIONS
    UI_ANIMATIONS["SPINNER"]=("⣷" "⣯" "⣟" "⡿" "⢿" "⣻" "⣽" "⣾")
    UI_ANIMATIONS["PROGRESS"]=("▏" "▎" "▍" "▌" "▋" "▊" "▉" "█")
    UI_ANIMATIONS["BOUNCE"]=("⠁" "⠂" "⠄" "⠂")
}

ui::clear_screen() {
    clear
    printf "\033[3J\033[H\033[2J"  # Clear screen and scrollback
}

ui::draw_box() {
    local width="${1:-$PANEL_WIDTH}"
    local title="$2"
    local color="${3:-$BLUE}"
    local style="${4:-single}"
    
    local border_chars=""
    case "$style" in
        "double")
            border_chars=("╔" "╗" "╚" "╝" "═" "║" "╦" "╩")
            ;;
        "rounded")
            border_chars=("╭" "╮" "╰" "╯" "─" "│" "┬" "┴")
            ;;
        "bold")
            border_chars=("┏" "┓" "┗" "┛" "━" "┃" "┳" "┻")
            ;;
        *)
            border_chars=("┌" "┐" "└" "┘" "─" "│" "┬" "┴")
            ;;
    esac
    
    echo -e "${color}"
    echo -n "${border_chars[0]}"
    for ((i=0; i<width-2; i++)); do echo -n "${border_chars[4]}"; done
    echo "${border_chars[1]}"
    
    if [[ -n "$title" ]]; then
        local title_len=${#title}
        local padding=$(( (width - title_len - 4) / 2 ))
        printf "${border_chars[5]}%${padding}s %s %$((padding + (width - title_len - 4) % 2))s${border_chars[5]}\n" "" "$title" ""
    fi
    
    echo -n "${border_chars[2]}"
    for ((i=0; i<width-2; i++)); do echo -n "${border_chars[4]}"; done
    echo "${border_chars[3]}"
    echo -e "${NC}"
}

ui::show_loading() {
    local message="$1"
    local pid=$2
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        local frame=$((i % ${#UI_ANIMATIONS["SPINNER"][@]}))
        echo -ne "\r${CYAN}${UI_ANIMATIONS["SPINNER"][$frame]}${NC} $message..."
        sleep 0.1
        ((i++))
    done
    echo -ne "\r\033[K"
}

ui::progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))
    
    printf "\r${GREEN}["
    for ((i=0; i<completed; i++)); do printf "█"; done
    for ((i=0; i<remaining; i++)); do printf " "; done
    printf "]${NC} %3d%%" "$percentage"
}

ui::show_header() {
    local title="VIP-AUTOSCRIPT USER & CONFIG MANAGEMENT PANEL"
    local subtitle="Advanced User Accounts + VPN Config Generation"
    local width=${UI_STATE["TERMINAL_WIDTH"]}
    
    echo -e "${BG_BLUE}${WHITE}"
    printf "╔%*s╗\n" $((width - 2)) "" | tr ' ' '═'
    printf "║%*s║\n" $((width - 2)) ""
    printf "║   %-${width-6}s║\n" "$title"
    printf "║   %-${width-6}s║\n" "$subtitle"
    printf "║%*s║\n" $((width - 2)) ""
    printf "╚%*s╝\n" $((width - 2)) "" | tr ' ' '═'
    echo -e "${NC}"
}

ui::show_footer() {
    local width=${UI_STATE["TERMINAL_WIDTH"]}
    local options="[N]ew User  [E]dit  [D]elete  [G]enerate Config  [S]tats  [F]ilter  [O]rder  [Q]uit"
    
    echo -e "${CYAN}"
    printf "╔%*s╗\n" $((width - 2)) "" | tr ' ' '═'
    printf "║   %-${width-6}s║\n" "$options"
    printf "╚%*s╝\n" $((width - 2)) "" | tr ' ' '═'
    echo -e "${NC}"
}

ui::show_stats() {
    local stats=$(db::get_stats)
    local total_users=$(echo "$stats" | jq -r '.total_users')
    local active_users=$(echo "$stats" | jq -r '.active_users')
    local expired_users=$((total_users - active_users))
    local config_count=$(find "$CONFIG_OUTPUT_DIR" -name "*.*" 2>/dev/null | wc -l)
    local phone_available=$(phone_storage::is_available && echo "Connected" || echo "Disconnected")
    
    ui::draw_box 60 "📊 SYSTEM STATISTICS" "$MAGENTA" "rounded"
    
    echo -e " ${GREEN}• Total Users:${NC}      $(printf "%4d" $total_users)"
    echo -e " ${GREEN}• Active Users:${NC}     $(printf "%4d" $active_users)"
    echo -e " ${RED}• Expired Users:${NC}    $(printf "%4d" $expired_users)"
    echo -e " ${CYAN}• Config Files:${NC}     $(printf "%4d" $config_count)"
    echo -e " ${YELLOW}• Phone Storage:${NC}   $phone_available"
    echo -e " ${BLUE}• Server Time:${NC}      $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e " ${MAGENTA}• Uptime:${NC}          $(uptime -p | cut -d' ' -f2-)"
    echo ""
}

ui::show_users_table() {
    local users=()
    local statuses=()
    local expiries=()
    local services=()
    local configs=()
    local created_dates=()
    
    # Get sorted and filtered user list
    local user_list=$(ui::_get_filtered_users)
    
    if [[ -z "$user_list" ]]; then
        ui::draw_box 80 "👥 USER ACCOUNTS & CONFIGS" "$BLUE" "rounded"
        ui::print_center "No users found matching filter: ${UI_STATE["FILTER"]}" "$YELLOW"
        return
    fi
    
    # Get user data with caching
    while IFS= read -r user; do
        local cache_key="user_${user}_${UI_STATE["SORT_FIELD"]}_${UI_STATE["SORT_ORDER"]}"
        
        if [[ -z "${UI_CACHE[$cache_key]}" ]]; then
            local user_data=$(db::get_user "$user")
            UI_CACHE["$cache_key"]="$user_data"
        fi
        
        local user_data="${UI_CACHE[$cache_key]}"
        
        users+=("$user")
        statuses+=("$(echo "$user_data" | jq -r '.status')")
        expiries+=("$(echo "$user_data" | jq -r '.expiry_date')")
        services+=("$(echo "$user_data" | jq -r '.services | join(",")')")
        configs+=("$(echo "$user_data" | jq -r '.configs_generated')")
        created_dates+=("$(echo "$user_data" | jq -r '.created')")
    done <<< "$user_list"
    
    # Pagination
    local total_users=${#users[@]}
    local page=${UI_STATE["PAGINATION"]}
    local page_size=$((UI_STATE["TERMINAL_HEIGHT"] - 12))
    local total_pages=$(( (total_users + page_size - 1) / page_size ))
    local start=$(( (page - 1) * page_size ))
    local end=$(( start + page_size ))
    
    ui::draw_box 80 "👥 USER ACCOUNTS & CONFIGS (Page $page/$total_pages)" "$BLUE" "rounded"
    
    # Table header with sort indicators
    local sort_indicator=""
    echo -e " ${GREEN}Username       Status     Expiry Date     Services     Configs Created${NC}"
    echo -e " ${GREEN}-------------- ---------- --------------- ------------ --------------${NC}"
    
    # Table rows
    for ((i=start; i<end && i<total_users; i++)); do
        local user="${users[$i]}"
        local status="${statuses[$i]}"
        local expiry="${expiries[$i]}"
        local service="${services[$i]}"
        local config_count="${configs[$i]}"
        local created="${created_dates[$i]}"
        
        # Color coding
        local status_color=$GREEN
        [[ "$status" == "expired" ]] && status_color=$RED
        [[ "$status" == "disabled" ]] && status_color=$YELLOW
        
        local config_color=$CYAN
        [[ "$config_count" -eq 0 ]] && config_color=$YELLOW
        
        printf " %-14s ${status_color}%-10s${NC} %-15s %-12s ${config_color}%7s${NC}\n" \
               "$user" "$status" "$expiry" "$service" "$config_count"
    done
    
    # Pagination footer
    if [[ $total_pages -gt 1 ]]; then
        echo -e " ${BLUE}Page $page of $total_pages | ← Previous | Next → | [G]oto Page${NC}"
    fi
}

ui::_get_filtered_users() {
    local users=$(db::list_users)
    local filter="${UI_STATE["FILTER"]}"
    local sort_field="${UI_STATE["SORT_FIELD"]}"
    local sort_order="${UI_STATE["SORT_ORDER"]}"
    
    # Apply filter
    if [[ -n "$filter" ]]; then
        users=$(echo "$users" | grep -i "$filter" || true)
    fi
    
    # Apply sorting
    if [[ "$sort_field" == "username" ]]; then
        if [[ "$sort_order" == "asc" ]]; then
            echo "$users" | sort
        else
            echo "$users" | sort -r
        fi
    else
        # Complex sorting by other fields would require jq processing
        echo "$users"  # Simplified for now
    fi
}

ui::print_center() {
    local text="$1"
    local color="${2:-$WHITE}"
    local width="${3:-${UI_STATE["TERMINAL_WIDTH"]}}"
    
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s" ""
    echo -e "${color}${text}${NC}"
}

ui::show_error() {
    local message="$1"
    echo -e "${RED}❌ Error: $message${NC}" >&2
    sleep 2
}

ui::show_success() {
    local message="$1"
    echo -e "${GREEN}✅ Success: $message${NC}"
    sleep 1
}

ui::show_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️ Warning: $message${NC}"
    sleep 1
}

ui::show_info() {
    local message="$1"
    echo -e "${BLUE}ℹ️ Info: $message${NC}"
    sleep 1
}

ui::interactive_menu() {
    local title="$1"
    local options=("${!2}")
    local selected=0
    
    while true; do
        ui::clear_screen
        ui::draw_box 50 "$title" "$CYAN" "rounded"
        
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e " ${GREEN}▶ ${options[$i]}${NC}"
            else
                echo -e "   ${options[$i]}"
            fi
        done
        
        read -sn1 key
        case "$key" in
            A) selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} )) ;;
            B) selected=$(( (selected + 1) % ${#options[@]} )) ;;
            "") break ;;
            q) return 255 ;;
        esac
    done
    
    return $selected
}

ui::confirm_dialog() {
    local message="$1"
    local default="${2:-no}"
    
    echo -e "${YELLOW}❓ $message${NC}"
    if [[ "$default" == "yes" ]]; then
        read -p " [Y/n]: " confirm
        confirm=${confirm:-y}
    else
        read -p " [y/N]: " confirm
        confirm=${confirm:-n}
    fi
    
    [[ "$confirm" =~ ^[Yy]$ ]]
    return $?
}