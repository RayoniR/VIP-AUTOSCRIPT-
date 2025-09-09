#!/bin/bash

# VIP-Autoscript Git Sync Manager
# Syncs local cloned repo with updated GitHub repository

set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly CONFIG_DIR="/etc/vip-autoscript-/config"
readonly LOG_DIR="/etc/vip-autoscript-/logs"
readonly BACKUP_DIR="/etc/vip-autoscript-/backups"
readonly LOCK_DIR="/tmp/vip-git-sync"
readonly SYNC_LOG="$LOG_DIR/git-sync.log"
readonly GIT_REPO_DIR="/etc/vip-autoscript/repo"
readonly GIT_REPO_URL="https://github.com/RayoniR/VIP-AUTOSCRIPT-.git"
readonly GIT_BRANCH="main"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Initialize system
init_system() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR" "$LOCK_DIR" "$GIT_REPO_DIR"
    exec > >(tee -a "$SYNC_LOG")
    exec 2> >(tee -a "$SYNC_LOG" >&2)
    setup_traps
    load_config
}

# Setup error handling
setup_traps() {
    trap 'cleanup_lock; exit' INT TERM EXIT
    trap 'error_handler $LINENO' ERR
}

error_handler() {
    local line="$1"
    log_error "Error occurred at line $line"
    exit 1
}

# Locking mechanism
acquire_lock() {
    local lock_file="$LOCK_DIR/git-sync.lock"
    if ! mkdir "$lock_file" 2>/dev/null; then
        local pid=$(cat "$lock_file/pid" 2>/dev/null || echo "unknown")
        log_error "Git sync already in progress (PID: $pid)"
        exit 1
    fi
    echo $$ > "$lock_file/pid"
    log_info "Acquired git sync lock"
}

cleanup_lock() {
    rm -rf "$LOCK_DIR/git-sync.lock"
    log_info "Released git sync lock"
}

# Logging functions
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1" | tee -a "$SYNC_LOG"
}

log_warning() {
    echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1${NC}" | tee -a "$SYNC_LOG"
}

log_error() {
    echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1${NC}" | tee -a "$SYNC_LOG"
}

log_success() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1${NC}" | tee -a "$SYNC_LOG"
}

# Configuration management
load_config() {
    if [[ -f "$CONFIG_DIR/git-sync.conf" ]]; then
        source "$CONFIG_DIR/git-sync.conf"
    else
        # Default configuration
        readonly AUTO_SYNC=${AUTO_SYNC:-false}
        readonly SYNC_INTERVAL=${SYNC_INTERVAL:-3600}
        readonly BACKUP_BEFORE_SYNC=${BACKUP_BEFORE_SYNC:-true}
        readonly VERIFY_COMMITS=${VERIFY_COMMITS:-true}
        readonly CONFLICT_RESOLUTION=${CONFLICT_RESOLUTION:-"theirs"}
    fi
}

# Git operations
setup_git_repo() {
    log_info "Setting up git repository..."
    
    if [[ ! -d "$GIT_REPO_DIR/.git" ]]; then
        log_info "Cloning repository for the first time..."
        git clone -b "$GIT_BRANCH" "$GIT_REPO_URL" "$GIT_REPO_DIR"
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to clone repository"
            return 1
        fi
    else
        log_info "Repository already exists, checking remote..."
        cd "$GIT_REPO_DIR"
        
        # Check if remote URL is correct
        local current_url=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ "$current_url" != "$GIT_REPO_URL" ]]; then
            log_warning "Remote URL mismatch, updating..."
            git remote set-url origin "$GIT_REPO_URL"
        fi
    fi
    
    log_success "Git repository setup completed"
}

fetch_updates() {
    log_info "Fetching updates from remote repository..."
    
    cd "$GIT_REPO_DIR"
    
    # Fetch all updates
    if ! git fetch --all --prune; then
        log_error "Failed to fetch updates from remote"
        return 1
    fi
    
    # Check for updates
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/$GIT_BRANCH")
    
    if [[ "$local_commit" == "$remote_commit" ]]; then
        log_info "No updates available - already up to date"
        return 0
    else
        log_info "Updates available: $local_commit -> $remote_commit"
        return 1
    fi
}

pull_updates() {
    log_info "Pulling updates from remote repository..."
    
    cd "$GIT_REPO_DIR"
    
    # Stash local changes if any
    if ! git diff --quiet || ! git diff --staged --quiet; then
        log_warning "Local changes detected, stashing..."
        git stash push -m "Auto-stash before sync $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    
    # Pull updates
    if git pull origin "$GIT_BRANCH"; then
        log_success "Successfully pulled updates"
        return 0
    else
        log_error "Failed to pull updates"
        handle_merge_conflicts
        return 1
    fi
}

handle_merge_conflicts() {
    log_warning "Merge conflicts detected, attempting resolution..."
    
    cd "$GIT_REPO_DIR"
    
    case "$CONFLICT_RESOLUTION" in
        "theirs")
            log_info "Using 'theirs' resolution strategy"
            git checkout --theirs -- .
            git add -A
            ;;
        "ours")
            log_info "Using 'ours' resolution strategy"
            git checkout --ours -- .
            git add -A
            ;;
        "abort")
            log_info "Aborting merge"
            git merge --abort
            return 1
            ;;
        *)
            log_error "Unknown conflict resolution strategy: $CONFLICT_RESOLUTION"
            return 1
            ;;
    esac
    
    # Complete the merge
    if git commit -m "Auto-merge: Resolved conflicts using $CONFLICT_RESOLUTION strategy"; then
        log_success "Merge conflicts resolved successfully"
        return 0
    else
        log_error "Failed to resolve merge conflicts"
        git merge --abort
        return 1
    fi
}

# File synchronization
sync_files() {
    log_info "Synchronizing files with production..."
    
    # Create backup before sync if enabled
    if [[ "$BACKUP_BEFORE_SYNC" == "true" ]]; then
        create_backup
    fi
    
    # Sync scripts
    if [[ -d "$GIT_REPO_DIR/scripts" ]]; then
        rsync -av --delete --backup --suffix=".bak-$(date +%Y%m%d)" \
            "$GIT_REPO_DIR/scripts/" "/etc/vip-autoscript/scripts/"
        log_info "Scripts synchronized"
    fi
    
    # Sync configs (carefully - don't overwrite production configs)
    if [[ -d "$GIT_REPO_DIR/config" ]]; then
        rsync -av --ignore-existing \
            "$GIT_REPO_DIR/config/" "/etc/vip-autoscript/config/"
        log_info "Configs synchronized (existing files preserved)"
    fi
    
    # Sync other directories
    local directories=("docs" "services" "tools")
    for dir in "${directories[@]}"; do
        if [[ -d "$GIT_REPO_DIR/$dir" ]]; then
            rsync -av --delete \
                "$GIT_REPO_DIR/$dir/" "/etc/vip-autoscript/$dir/"
            log_info "$dir synchronized"
        fi
    done
    
    # Set executable permissions on scripts
    chmod +x /etc/vip-autoscript/scripts/*.sh 2>/dev/null || true
    
    log_success "File synchronization completed"
}

# Backup system
create_backup() {
    log_info "Creating backup before synchronization..."
    
    local backup_name="pre-sync-backup-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name.tar.gz"
    
    tar -czf "$backup_path" \
        -C /etc/vip-autoscript \
        scripts/ \
        config/ \
        docs/ \
        services/ \
        2>/dev/null || true
    
    if [[ -f "$backup_path" ]]; then
        log_info "Backup created: $backup_path ($(du -h "$backup_path" | cut -f1))"
    else
        log_warning "Backup creation failed"
    fi
}

# Verification
verify_sync() {
    log_info "Verifying synchronization..."
    
    # Check if essential files exist
    local essential_files=(
        "scripts/main.sh"
        "scripts/update.sh"
        "config/main.conf"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "/etc/vip-autoscript/$file" ]]; then
            log_error "Essential file missing after sync: $file"
            return 1
        fi
    done
    
    # Verify script permissions
    local script_files=($(find /etc/vip-autoscript/scripts -name "*.sh"))
    for script in "${script_files[@]}"; do
        if [[ ! -x "$script" ]]; then
            log_warning "Script not executable: $script"
            chmod +x "$script"
        fi
    done
    
    log_success "Synchronization verified successfully"
}

# Main sync function
perform_sync() {
    local force="${1:-false}"
    
    acquire_lock
    log_info "Starting git synchronization process"
    
    # Setup repository if not exists
    if ! setup_git_repo; then
        log_error "Failed to setup git repository"
        cleanup_lock
        return 1
    fi
    
    # Check for updates
    if fetch_updates && [[ "$force" == "false" ]]; then
        log_info "No updates available, synchronization not needed"
        cleanup_lock
        return 0
    fi
    
    # Pull updates
    if ! pull_updates; then
        log_error "Failed to pull updates from remote"
        cleanup_lock
        return 1
    fi
    
    # Sync files to production
    if ! sync_files; then
        log_error "Failed to synchronize files"
        cleanup_lock
        return 1
    fi
    
    # Verify synchronization
    if ! verify_sync; then
        log_error "Synchronization verification failed"
        cleanup_lock
        return 1
    fi
    
    log_success "Git synchronization completed successfully"
    cleanup_lock
    return 0
}

# Status functions
get_repo_status() {
    cd "$GIT_REPO_DIR" 2>/dev/null || return 1
    
    echo -e "\n${CYAN}===== Git Repository Status =====${NC}"
    echo -e "Repository: ${BLUE}$GIT_REPO_URL${NC}"
    echo -e "Branch: ${BLUE}$GIT_BRANCH${NC}"
    echo -e "Location: ${BLUE}$GIT_REPO_DIR${NC}"
    
    if [[ -d "$GIT_REPO_DIR/.git" ]]; then
        local current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local remote_commit=$(git rev-parse --short "origin/$GIT_BRANCH" 2>/dev/null || echo "unknown")
        
        echo -e "Local Commit: ${BLUE}$current_commit${NC}"
        echo -e "Remote Commit: ${BLUE}$remote_commit${NC}"
        
        if [[ "$current_commit" != "unknown" && "$remote_commit" != "unknown" ]]; then
            if [[ "$current_commit" == "$remote_commit" ]]; then
                echo -e "Status: ${GREEN}Up to date${NC}"
            else
                echo -e "Status: ${YELLOW}Updates available${NC}"
            fi
        fi
        
        # Show local changes
        if ! git diff --quiet; then
            echo -e "Local Changes: ${YELLOW}Yes${NC}"
        else
            echo -e "Local Changes: ${GREEN}No${NC}"
        fi
    else
        echo -e "Status: ${RED}Not initialized${NC}"
    fi
    echo -e "${CYAN}=================================${NC}"
}

# Main execution
main() {
    init_system
    
    local action="${1:-}"
    local param="${2:-}"
    
    case "$action" in
        "sync")
            perform_sync "$param"
            ;;
        "status")
            get_repo_status
            ;;
        "force-sync")
            perform_sync "true"
            ;;
        "setup")
            setup_git_repo
            ;;
        "fetch")
            fetch_updates
            ;;
        "log")
            show_sync_log
            ;;
        "")
            interactive_mode
            ;;
        *)
            echo "Usage: $0 [sync|force-sync|status|setup|fetch|log]"
            exit 1
            ;;
    esac
}

show_sync_log() {
    echo -e "\n${CYAN}===== Sync Log (last 20 lines) =====${NC}"
    tail -20 "$SYNC_LOG" 2>/dev/null || echo "No sync log found"
    echo -e "${CYAN}=====================================${NC}"
}

interactive_mode() {
    while true; do
        echo -e "\n${CYAN}===== Git Sync Manager =====${NC}"
        echo "1) Check repository status"
        echo "2) Synchronize with remote"
        echo "3) Force synchronization"
        echo "4) Setup repository"
        echo "5) Check for updates"
        echo "6) View sync log"
        echo "0) Exit"
        echo -e "${CYAN}=============================${NC}"
        
        read -p "Choose an option: " choice
        
        case $choice in
            1) get_repo_status
               read -p "Press Enter to continue..." ;;
            2) perform_sync "false"
               read -p "Press Enter to continue..." ;;
            3) perform_sync "true"
               read -p "Press Enter to continue..." ;;
            4) setup_git_repo
               read -p "Press Enter to continue..." ;;
            5) fetch_updates
               read -p "Press Enter to continue..." ;;
            6) show_sync_log
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