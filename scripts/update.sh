#!/bin/bash

# VIP-Autoscript Advanced Update System
# Complete system update with rollback, verification, and monitoring

set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly CONFIG_DIR="/etc/vip-autoscript-/config"
readonly BACKUP_DIR="/etc/vip-autoscript-/backups"
readonly LOG_DIR="/etc/vip-autoscript-/logs"
readonly LOCK_DIR="/tmp/vip-update"
readonly UPDATE_LOG="$LOG_DIR/update.log"
readonly VERSION_FILE="/etc/vip-autoscript/version"
readonly REPO_URL="https://github.com/RayoniR/VIP-AUTOSCRIPT-.git"
readonly REPO_DIR="/tmp/vip-autoscript-repo"
readonly GPG_KEY_ID="YOUR-GPG-KEY-ID"
readonly GPG_PUBKEY="/etc/vip-autoscript-/keys/pubkey.asc"

# Service management
readonly SERVICES=("xray" "badvpn" "sshws" "slowdns")
readonly SYSTEM_SERVICES=("nginx" "fail2ban" "ufw")

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Exit codes
readonly SUCCESS=0
readonly ERROR_GENERAL=1
readonly ERROR_DEPENDENCY=2
readonly ERROR_VERIFICATION=3
readonly ERROR_ROLLBACK=4
readonly ERROR_LOCK=5

# Initialize system
init_system() {
    mkdir -p "$BACKUP_DIR" "$LOG_DIR" "$LOCK_DIR" "$CONFIG_DIR"
    exec > >(tee -a "$UPDATE_LOG")
    exec 2> >(tee -a "$UPDATE_LOG" >&2)
    setup_traps
    load_config
}

# Setup error handling
setup_traps() {
    trap 'cleanup_lock; exit' INT TERM EXIT
    trap 'error_handler $LINENO' ERR
    trap 'cleanup_temp_files' EXIT
}

error_handler() {
    local line="$1"
    log_error "Error occurred at line $line"
    emergency_rollback
    exit $ERROR_GENERAL
}

# Locking mechanism
acquire_lock() {
    local lock_file="$LOCK_DIR/update.lock"
    if ! mkdir "$lock_file" 2>/dev/null; then
        local pid=$(cat "$lock_file/pid" 2>/dev/null || echo "unknown")
        log_error "Update already in progress (PID: $pid)"
        exit $ERROR_LOCK
    fi
    echo $$ > "$lock_file/pid"
    log_info "Acquired update lock"
}

cleanup_lock() {
    rm -rf "$LOCK_DIR/update.lock"
    log_info "Released update lock"
}

# Logging functions
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1" | tee -a "$UPDATE_LOG"
}

log_warning() {
    echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1${NC}" | tee -a "$UPDATE_LOG"
}

log_error() {
    echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1${NC}" | tee -a "$UPDATE_LOG"
}

log_success() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1${NC}" | tee -a "$UPDATE_LOG"
}

# Configuration management
load_config() {
    if [[ -f "$CONFIG_DIR/update.conf" ]]; then
        source "$CONFIG_DIR/update.conf"
    else
        # Default configuration
        readonly AUTO_UPDATE=${AUTO_UPDATE:-false}
        readonly UPDATE_CHANNEL=${UPDATE_CHANNEL:-"stable"}
        readonly BACKUP_ENABLED=${BACKUP_ENABLED:-true}
        readonly VERIFY_SIGNATURES=${VERIFY_SIGNATURES:-true}
        readonly RESTART_SERVICES=${RESTART_SERVICES:-true}
        readonly NOTIFY_UPDATES=${NOTIFY_UPDATES:-true}
    fi
}

# Dependency checking
check_dependencies() {
    local deps=("git" "gpg" "jq" "curl" "wget" "tar" "gzip")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        exit $ERROR_DEPENDENCY
    fi

    log_info "All dependencies available"
}

# Version management
get_current_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "0.0.0"
    fi
}

set_version() {
    local version="$1"
    echo "$version" > "$VERSION_FILE"
    log_info "Set version to: $version"
}

# Backup system
create_backup() {
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        log_info "Backup disabled by configuration"
        return 0
    fi

    local backup_name="backup-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name.tar.gz"

    log_info "Creating system backup: $backup_path"

    tar -czf "$backup_path" \
        -C /etc/vip-autoscript \
        config/ \
        users/ \
        domains/ \
        scripts/ \
        version 2>/dev/null || true

    # Backup service configurations
    tar -czf "$backup_path-services.tar.gz" \
        /etc/systemd/system/vip-*.service \
        /etc/nginx/sites-available/vip-* \
        /etc/xray/config.json 2>/dev/null || true

    if [[ -f "$backup_path" ]]; then
        log_info "Backup created: $backup_path ($(du -h "$backup_path" | cut -f1))"
        echo "$backup_path"
    else
        log_warning "Backup creation failed"
        echo ""
    fi
}

restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_info "Restoring from backup: $backup_file"
    
    # Stop services before restore
    stop_services
    
    # Restore files
    tar -xzf "$backup_file" -C /etc/vip-autoscript
    
    # Restore service configurations
    if [[ -f "$backup_file-services.tar.gz" ]]; then
        tar -xzf "$backup_file-services.tar.gz" -C /
    fi

    log_info "Backup restored successfully"
}

# Service management
stop_services() {
    log_info "Stopping VIP services..."
    
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            systemctl stop "$service"
            log_info "Stopped service: $service"
        fi
    done
}

start_services() {
    log_info "Starting VIP services..."
    
    for service in "${SERVICES[@]}"; do
        if systemctl is-enabled --quiet "$service"; then
            systemctl start "$service"
            log_info "Started service: $service"
        fi
    done
}

restart_services() {
    if [[ "$RESTART_SERVICES" != "true" ]]; then
        log_info "Service restart disabled by configuration"
        return 0
    fi

    log_info "Restarting services..."
    
    for service in "${SERVICES[@]}"; do
        if systemctl is-enabled --quiet "$service"; then
            systemctl restart "$service"
            log_info "Restarted service: $service"
        fi
    done

    # Reload systemd
    systemctl daemon-reload
}

# Repository operations
setup_repository() {
    local repo_url="${1:-$REPO_URL}"
    local branch="${2:-$UPDATE_CHANNEL}"
    
    log_info "Setting up repository: $repo_url (branch: $branch)"
    
    if [[ -d "$REPO_DIR" ]]; then
        rm -rf "$REPO_DIR"
    fi

    git clone -b "$branch" --depth 1 "$repo_url" "$REPO_DIR"
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to clone repository"
        return 1
    fi

    log_info "Repository cloned successfully"
}

verify_signatures() {
    if [[ "$VERIFY_SIGNATURES" != "true" ]]; then
        log_info "Signature verification disabled by configuration"
        return 0
    fi

    log_info "Verifying package signatures..."
    
    # Import GPG key if not already imported
    if ! gpg --list-keys "$GPG_KEY_ID" &>/dev/null; then
        if [[ -f "$GPG_PUBKEY" ]]; then
            gpg --import "$GPG_PUBKEY"
        else
            log_warning "GPG public key not found, skipping verification"
            return 0
        fi
    fi

    # Verify signatures in repository
    local sig_file="$REPO_DIR/ signatures.tar.gz.asc"
    local package_file="$REPO_DIR/package.tar.gz"
    
    if [[ -f "$sig_file" && -f "$package_file" ]]; then
        if gpg --verify "$sig_file" "$package_file"; then
            log_info "Package signature verified successfully"
            return 0
        else
            log_error "Package signature verification failed"
            return 1
        fi
    else
        log_warning "Signature files not found, skipping verification"
        return 0
    fi
}

# Update operations
download_updates() {
    local update_url="$1"
    local target_dir="$2"
    
    log_info "Downloading updates from: $update_url"
    
    if [[ "$update_url" == *.git ]]; then
        setup_repository "$update_url"
        cp -r "$REPO_DIR"/* "$target_dir/"
    else
        wget -q -O "$target_dir/update-package.tar.gz" "$update_url"
        tar -xzf "$target_dir/update-package.tar.gz" -C "$target_dir"
    fi

    log_info "Updates downloaded successfully"
}

apply_updates() {
    local update_dir="$1"
    
    log_info "Applying updates from: $update_dir"
    
    # Backup current installation
    local backup_file=$(create_backup)
    
    # Stop services before update
    stop_services
    
    # Update main scripts
    if [[ -d "$update_dir/scripts" ]]; then
        cp -r "$update_dir/scripts"/* "/etc/vip-autoscript-/scripts/"
        chmod +x /etc/vip-autoscript-/scripts/*.sh
    fi

    # Update configurations
    if [[ -d "$update_dir/config" ]]; then
        cp -r "$update_dir/config"/* "/etc/vip-autoscript/config/"
    fi

    # Update systemd services
    if [[ -d "$update_dir/services" ]]; then
        cp -r "$update_dir/services"/* "/etc/systemd/system/"
        systemctl daemon-reload
    fi

    # Update documentation
    if [[ -d "$update_dir/docs" ]]; then
        cp -r "$update_dir/docs"/* "/etc/vip-autoscript/docs/"
    fi

    log_info "Updates applied successfully"
}

verify_update() {
    local update_dir="$1"
    
    log_info "Verifying update integrity..."
    
    # Check required files
    local required_files=(
        "scripts/main.sh"
        "config/default.conf"
        "services/xray.service"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$update_dir/$file" ]]; then
            log_error "Missing required file: $file"
            return 1
        fi
    done

    # Verify file permissions
    local script_files=($(find "$update_dir/scripts" -name "*.sh"))
    for script in "${script_files[@]}"; do
        if [[ ! -x "$script" ]]; then
            chmod +x "$script"
        fi
    done

    # Validate configurations
    validate_configurations "$update_dir"

    log_info "Update verification completed"
}

validate_configurations() {
    local update_dir="$1"
    
    # Validate JSON configurations
    local json_files=($(find "$update_dir" -name "*.json"))
    for json_file in "${json_files[@]}"; do
        if ! jq -e . >/dev/null 2>&1 < "$json_file"; then
            log_error "Invalid JSON configuration: $json_file"
            return 1
        fi
    done

    # Validate shell scripts
    local script_files=($(find "$update_dir/scripts" -name "*.sh"))
    for script in "${script_files[@]}"; do
        if ! bash -n "$script"; then
            log_error "Syntax error in script: $script"
            return 1
        fi
    done
}

# Rollback system
emergency_rollback() {
    log_error "Emergency rollback initiated"
    
    # Find latest backup
    local latest_backup=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1)
    
    if [[ -n "$latest_backup" ]]; then
        log_info "Restoring from latest backup: $latest_backup"
        restore_backup "$latest_backup"
        start_services
        log_info "Emergency rollback completed"
    else
        log_error "No backup found for rollback"
    fi
}

perform_rollback() {
    local backup_file="$1"
    
    log_info "Performing rollback to: $backup_file"
    
    if restore_backup "$backup_file"; then
        restart_services
        log_info "Rollback completed successfully"
        return 0
    else
        log_error "Rollback failed"
        return 1
    fi
}

# Update checks
check_for_updates() {
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version)
    
    if [[ "$current_version" != "$latest_version" ]]; then
        log_info "Update available: $current_version -> $latest_version"
        echo "$latest_version"
    else
        log_info "System is up to date"
        echo ""
    fi
}

get_latest_version() {
    local version_url="https://api.github.com/repos/RayoniR/VIP-AUTOSCRIPT-/releases/latest"
    
    if curl -s "$version_url" | jq -r '.tag_name'; then
        return 0
    else
        # Fallback to repository check
        setup_repository
        if [[ -f "$REPO_DIR/version" ]]; then
            cat "$REPO_DIR/version"
        else
            echo "unknown"
        fi
    fi
}

# Notification system
send_notification() {
    local message="$1"
    local level="${2:-info}"
    
    if [[ "$NOTIFY_UPDATES" != "true" ]]; then
        return 0
    fi

    # System notification
    echo "$message" | wall 2>/dev/null || true

    # Email notification (if configured)
    if [[ -f "$CONFIG_DIR/email.conf" ]]; then
        source "$CONFIG_DIR/email.conf"
        if [[ -n "$EMAIL_ADDRESS" ]]; then
            echo "$message" | mail -s "VIP Update $level" "$EMAIL_ADDRESS"
        fi
    fi

    # Telegram notification (if configured)
    if [[ -f "$CONFIG_DIR/telegram.conf" ]]; then
        source "$CONFIG_DIR/telegram.conf"
        if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
            curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                -d chat_id="$TELEGRAM_CHAT_ID" \
                -d text="$message" >/dev/null
        fi
    fi
}

# Cleanup operations
cleanup_temp_files() {
    rm -rf "$REPO_DIR" "/tmp/vip-update-*" 2>/dev/null || true
    log_info "Temporary files cleaned up"
}

cleanup_old_backups() {
    local keep_days=7
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$keep_days -delete 2>/dev/null || true
    log_info "Old backups cleaned up"
}

# Main update functions
perform_update() {
    local update_source="${1:-}"
    local version_target="${2:-}"
    
    acquire_lock
    log_info "Starting update process"
    
    # Check dependencies
    check_dependencies
    
    # Check for updates if no source specified
    if [[ -z "$update_source" ]]; then
        local latest_version=$(check_for_updates)
        if [[ -z "$latest_version" ]]; then
            log_info "No updates available"
            cleanup_lock
            return 0
        fi
        update_source="$REPO_URL"
        version_target="$latest_version"
    fi

    # Create backup
    local backup_file=$(create_backup)
    
    # Download updates
    local update_dir="/tmp/vip-update-$(date +%s)"
    mkdir -p "$update_dir"
    
    download_updates "$update_source" "$update_dir"
    
    # Verify update
    if ! verify_signatures || ! verify_update "$update_dir"; then
        log_error "Update verification failed"
        perform_rollback "$backup_file"
        exit $ERROR_VERIFICATION
    fi

    # Apply updates
    if ! apply_updates "$update_dir"; then
        log_error "Update application failed"
        perform_rollback "$backup_file"
        exit $ERROR_GENERAL
    fi

    # Set new version
    if [[ -n "$version_target" ]]; then
        set_version "$version_target"
    fi

    # Restart services
    restart_services
    
    # Cleanup
    cleanup_temp_files
    cleanup_old_backups
    
    log_success "Update completed successfully"
    send_notification "VIP System updated to version $version_target" "success"
    
    cleanup_lock
    return $SUCCESS
}

perform_rollback_to() {
    local backup_file="$1"
    
    acquire_lock
    
    if perform_rollback "$backup_file"; then
        log_success "Rollback completed successfully"
        send_notification "VIP System rolled back using $backup_file" "info"
    else
        log_error "Rollback failed"
        send_notification "VIP System rollback failed for $backup_file" "error"
        exit $ERROR_ROLLBACK
    fi
    
    cleanup_lock
}

# Interactive functions
list_backups() {
    echo -e "\n${CYAN}===== Available Backups =====${NC}"
    ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print $9 " (" $5 ")"}' || echo "No backups found"
    echo -e "${CYAN}=============================${NC}"
}

show_update_history() {
    echo -e "\n${CYAN}===== Update History =====${NC}"
    tail -20 "$UPDATE_LOG" 2>/dev/null | grep -E "(SUCCESS|ERROR|WARNING)" || echo "No update history found"
    echo -e "${CYAN}=========================${NC}"
}

show_system_info() {
    echo -e "\n${CYAN}===== System Information =====${NC}"
    echo -e "Current Version: ${BOLD}$(get_current_version)${NC}"
    echo -e "Update Channel: ${BOLD}$UPDATE_CHANNEL${NC}"
    echo -e "Auto Update: ${BOLD}$AUTO_UPDATE${NC}"
    echo -e "Backup Enabled: ${BOLD}$BACKUP_ENABLED${NC}"
    echo -e "Signature Verification: ${BOLD}$VERIFY_SIGNATURES${NC}"
    echo -e "${CYAN}===============================${NC}"
}

# Main menu
show_menu() {
    echo -e "\n${MAGENTA}${BOLD}"
    echo -e "╔══════════════════════════════════════════════════╗"
    echo -e "║           VIP-AUTOSCRIPT UPDATE SYSTEM           ║"
    echo -e "║           Advanced Update Management             ║"
    echo -e "╚══════════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e "${BOLD}🔄 Update Operations:${NC}"
    echo -e "  1)  Check for Updates"
    echo -e "  2)  Install Updates"
    echo -e "  3)  Force Update from URL"
    echo -e ""
    echo -e "${BOLD}⏪ Rollback Operations:${NC}"
    echo -e "  4)  List Backups"
    echo -e "  5)  Rollback to Backup"
    echo -e "  6)  Emergency Rollback"
    echo -e ""
    echo -e "${BOLD}📊 System Information:${NC}"
    echo -e "  7)  Show System Info"
    echo -e "  8)  Show Update History"
    echo -e "  9)  Verify System Integrity"
    echo -e ""
    echo -e "${BOLD}⚙️ Configuration:${NC}"
    echo -e "  10) Update Settings"
    echo -e "  11) Test Notifications"
    echo -e "  12) Cleanup System"
    echo -e ""
    echo -e "${BOLD}↩️ Exit:${NC}"
    echo -e "  0)  Exit"
    echo -e ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════╗${NC}"
}

# Main execution
main() {
    init_system
    
    local action="${1:-}"
    local param1="${2:-}"
    local param2="${3:-}"
    
    case "$action" in
        "check")
            check_for_updates
            ;;
        "update")
            perform_update "$param1" "$param2"
            ;;
        "rollback")
            perform_rollback_to "$param1"
            ;;
        "emergency-rollback")
            emergency_rollback
            ;;
        "list-backups")
            list_backups
            ;;
        "history")
            show_update_history
            ;;
        "info")
            show_system_info
            ;;
        "cleanup")
            cleanup_old_backups
            cleanup_temp_files
            ;;
        "notify-test")
            send_notification "Test notification from VIP Update System" "info"
            ;;
        "")
            interactive_mode
            ;;
        *)
            echo "Usage: $0 [check|update|rollback|emergency-rollback|list-backups|history|info|cleanup|notify-test]"
            exit 1
            ;;
    esac
}

interactive_mode() {
    while true; do
        show_menu
        read -p "$(echo -e "${BOLD}Choose an option: ${NC}")" choice
        
        case $choice in
            1) check_for_updates
               read -p "Press Enter to continue..." ;;
            2) perform_update
               read -p "Press Enter to continue..." ;;
            3) read -p "Enter update URL: " url
               perform_update "$url"
               read -p "Press Enter to continue..." ;;
            4) list_backups
               read -p "Press Enter to continue..." ;;
            5) list_backups
               read -p "Enter backup file: " backup_file
               perform_rollback_to "$backup_file"
               read -p "Press Enter to continue..." ;;
            6) emergency_rollback
               read -p "Press Enter to continue..." ;;
            7) show_system_info
               read -p "Press Enter to continue..." ;;
            8) show_update_history
               read -p "Press Enter to continue..." ;;
            9) verify_system_integrity
               read -p "Press Enter to continue..." ;;
            10) update_settings
                read -p "Press Enter to continue..." ;;
            11) send_notification "Test notification from VIP Update System" "info"
                read -p "Press Enter to continue..." ;;
            12) cleanup_old_backups
                cleanup_temp_files
                read -p "Press Enter to continue..." ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}"
               sleep 1 ;;
        esac
    done
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi