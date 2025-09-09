#!/bin/bash

# VIP-Autoscript Comprehensive Maintenance Script
# Complete system maintenance with automated tasks, cleanup, and reporting

# Configuration
CONFIG_DIR="/etc/vip-autoscript/config"
LOG_DIR="/etc/vip-autoscript/logs"
BACKUP_DIR="/etc/vip-autoscript/backups"
REPORT_DIR="/etc/vip-autoscript/reports"
TEMP_DIR="/tmp/vip-maintenance"
MAINTENANCE_LOG="$LOG_DIR/maintenance.log"
CRON_JOB_FILE="/etc/cron.d/vip-maintenance"

# Services to maintain
declare -A SERVICES=(
    ["xray"]="Xray Proxy Service"
    ["badvpn"]="BadVPN UDP Gateway"
    ["sshws"]="SSH WebSocket Service"
    ["slowdns"]="SlowDNS Service"
)

# Maintenance schedules
declare -A SCHEDULES=(
    ["daily"]="0 2 * * *"      # 2:00 AM daily
    ["weekly"]="0 3 * * 0"     # 3:00 AM every Sunday
    ["monthly"]="0 4 1 * *"    # 4:00 AM on 1st of month
)

# Thresholds for cleanup
DISK_CLEANUP_THRESHOLD=80
LOG_RETENTION_DAYS=30
BACKUP_RETENTION_DAYS=7
TEMP_FILE_AGE_DAYS=7

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Create necessary directories
mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$REPORT_DIR" "$TEMP_DIR"

# Function to print status with colors
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "SUCCESS") echo -e "${GREEN}[✓]${NC} $message" ;;
        "ERROR") echo -e "${RED}[✗]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[!]${NC} $message" ;;
        "INFO") echo -e "${BLUE}[i]${NC} $message" ;;
        "DEBUG") echo -e "${CYAN}[d]${NC} $message" ;;
        "MAINT") echo -e "${MAGENTA}[⚙]${NC} $message" ;;
        *) echo -e "[$status] $message" ;;
    esac
}

# Function to log messages with timestamp
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] $message" >> "$MAINTENANCE_LOG"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_status "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Function to check disk usage
check_disk_usage() {
    local usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    echo "$usage"
}

# Function to check service status
check_service_status() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo "running"
        return 0
    else
        echo "stopped"
        return 1
    fi
}

# Function to restart service with validation
restart_service() {
    local service=$1
    print_status "INFO" "Restarting $service..."
    
    systemctl restart "$service"
    sleep 3
    
    if systemctl is-active --quiet "$service"; then
        print_status "SUCCESS" "$service restarted successfully"
        log_message "RESTART" "Service $service restarted successfully"
        return 0
    else
        print_status "ERROR" "Failed to restart $service"
        log_message "ERROR" "Failed to restart service $service"
        return 1
    fi
}

# Function to perform log rotation and cleanup
cleanup_logs() {
    local force=${1:-false}
    local disk_usage=$(check_disk_usage)
    
    print_status "MAINT" "Starting log cleanup operation..."
    log_message "CLEANUP" "Starting log cleanup. Disk usage: $disk_usage%"
    
    # Cleanup system logs
    print_status "INFO" "Cleaning system logs older than $LOG_RETENTION_DAYS days..."
    find /var/log -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    find /var/log -name "*.gz" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    
    # Cleanup application logs
    print_status "INFO" "Cleaning application logs..."
    find "$LOG_DIR" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    
    # Cleanup temporary files
    print_status "INFO" "Cleaning temporary files..."
    find /tmp -name "vip-*" -type f -mtime +$TEMP_FILE_AGE_DAYS -delete 2>/dev/null
    find "$TEMP_DIR" -type f -mtime +1 -delete 2>/dev/null
    
    # Cleanup package cache
    if [ "$force" = true ] || [ $disk_usage -gt $DISK_CLEANUP_THRESHOLD ]; then
        print_status "INFO" "Cleaning package cache..."
        apt-get clean 2>/dev/null
        apt-get autoclean 2>/dev/null
    fi
    
    # Cleanup old kernels (keep only 2 latest)
    if [ "$force" = true ]; then
        print_status "INFO" "Removing old kernels..."
        dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | 
        head -n -2 | xargs sudo apt-get -y purge 2>/dev/null
    fi
    
    print_status "SUCCESS" "Log cleanup completed"
    log_message "CLEANUP" "Log cleanup completed. Freed space: $(check_disk_usage)%"
}

# Function to cleanup old backups
cleanup_backups() {
    print_status "MAINT" "Cleaning up old backups..."
    log_message "CLEANUP" "Starting backup cleanup"
    
    local backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f | wc -l)
    
    if [ $backup_count -gt $BACKUP_RETENTION_DAYS ]; then
        print_status "INFO" "Removing backups older than $BACKUP_RETENTION_DAYS days..."
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null
        local removed=$((backup_count - $(find "$BACKUP_DIR" -name "*.tar.gz" -type f | wc -l)))
        print_status "SUCCESS" "Removed $removed old backups"
        log_message "CLEANUP" "Removed $removed old backup files"
    else
        print_status "INFO" "No backups older than $BACKUP_RETENTION_DAYS days found"
    fi
}

# Function to perform system update
system_update() {
    print_status "MAINT" "Starting system update..."
    log_message "UPDATE" "Starting system update process"
    
    # Update package lists
    print_status "INFO" "Updating package lists..."
    apt-get update >> "$TEMP_DIR/update.log" 2>&1
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "Package lists updated"
        
        # Check for upgrades
        local upgrades=$(apt-get -s dist-upgrade | grep -c "^Inst")
        
        if [ $upgrades -gt 0 ]; then
            print_status "INFO" "Found $upgrades packages to upgrade"
            
            # Perform upgrades
            print_status "INFO" "Performing upgrades..."
            DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade >> "$TEMP_DIR/update.log" 2>&1
            
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "System upgrades completed successfully"
                log_message "UPDATE" "System upgraded successfully. $upgrades packages updated"
                
                # Cleanup after update
                apt-get autoremove -y >> "$TEMP_DIR/update.log" 2>&1
                apt-get clean >> "$TEMP_DIR/update.log" 2>&1
                
            else
                print_status "ERROR" "System upgrades failed"
                log_message "ERROR" "System upgrade failed. Check $TEMP_DIR/update.log for details"
                return 1
            fi
        else
            print_status "INFO" "System is already up to date"
        fi
    else
        print_status "ERROR" "Failed to update package lists"
        log_message "ERROR" "Failed to update package lists"
        return 1
    fi
    
    return 0
}

# Function to check and repair disk errors
check_disk_health() {
    print_status "MAINT" "Checking disk health..."
    log_message "DISKCHECK" "Starting disk health check"
    
    local disk_errors=0
    
    # Check filesystem errors
    print_status "INFO" "Checking filesystem errors..."
    if touch /root/disk-check-test 2>/dev/null; then
        rm -f /root/disk-check-test
        print_status "SUCCESS" "Filesystem is writable"
    else
        print_status "ERROR" "Filesystem is read-only or has errors"
        log_message "ERROR" "Filesystem is read-only or has errors"
        disk_errors=$((disk_errors + 1))
    fi
    
    # Check inode usage
    local inode_usage=$(df -i / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $inode_usage -gt 90 ]; then
        print_status "WARNING" "High inode usage: $inode_usage%"
        log_message "WARNING" "High inode usage: $inode_usage%"
        disk_errors=$((disk_errors + 1))
    fi
    
    # Check disk SMART status if available
    if command -v smartctl >/dev/null 2>&1; then
        print_status "INFO" "Checking SMART status..."
        local smart_status=$(smartctl -H /dev/sda 2>/dev/null | grep "result:" | awk '{print $6}')
        if [ "$smart_status" = "PASSED" ]; then
            print_status "SUCCESS" "SMART status: PASSED"
        else
            print_status "WARNING" "SMART status: $smart_status"
            log_message "WARNING" "SMART status check: $smart_status"
        fi
    fi
    
    if [ $disk_errors -eq 0 ]; then
        print_status "SUCCESS" "Disk health check completed successfully"
        log_message "DISKCHECK" "Disk health check completed successfully"
        return 0
    else
        print_status "WARNING" "Disk health check completed with $disk_errors warnings"
        log_message "WARNING" "Disk health check completed with $disk_errors warnings"
        return 1
    fi
}

# Function to optimize database files (if any)
optimize_databases() {
    print_status "MAINT" "Optimizing databases..."
    log_message "OPTIMIZE" "Starting database optimization"
    
    # Check for SQLite databases
    local optimized=0
    find /var/lib -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" 2>/dev/null | while read db_file; do
        if command -v sqlite3 >/dev/null 2>&1; then
            print_status "INFO" "Optimizing $db_file..."
            sqlite3 "$db_file" "VACUUM;" 2>/dev/null && optimized=$((optimized + 1))
        fi
    done
    
    if [ $optimized -gt 0 ]; then
        print_status "SUCCESS" "Optimized $optimized database files"
        log_message "OPTIMIZE" "Optimized $optimized database files"
    else
        print_status "INFO" "No databases found to optimize"
    fi
}

# Function to check and optimize system performance
optimize_system() {
    print_status "MAINT" "Optimizing system performance..."
    log_message "OPTIMIZE" "Starting system optimization"
    
    # Clear disk caches
    print_status "INFO" "Clearing disk caches..."
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    # Optimize swap
    if [ -f /proc/sys/vm/swappiness ]; then
        local current_swappiness=$(cat /proc/sys/vm/swappiness)
        if [ $current_swappiness -gt 10 ]; then
            echo 10 > /proc/sys/vm/swappiness
            print_status "INFO" "Reduced swappiness from $current_swappiness to 10"
        fi
    fi
    
    # Optimize network settings
    if [ -f /proc/sys/net/core/rmem_max ]; then
        echo 16777216 > /proc/sys/net/core/rmem_max 2>/dev/null
        echo 16777216 > /proc/sys/net/core/wmem_max 2>/dev/null
    fi
    
    print_status "SUCCESS" "System optimization completed"
    log_message "OPTIMIZE" "System optimization completed"
}

# Function to verify configuration files
verify_configurations() {
    print_status "MAINT" "Verifying configuration files..."
    log_message "VERIFY" "Starting configuration verification"
    
    local errors=0
    local config_files=(
        "$CONFIG_DIR/xray.json"
        "$CONFIG_DIR/sshws.json"
        "$CONFIG_DIR/slowdns.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            # Check if file is valid JSON if it has .json extension
            if [[ "$config_file" == *.json ]]; then
                if ! jq empty "$config_file" 2>/dev/null; then
                    print_status "ERROR" "Invalid JSON in $config_file"
                    log_message "ERROR" "Invalid JSON configuration: $config_file"
                    errors=$((errors + 1))
                else
                    print_status "SUCCESS" "$config_file - Valid JSON"
                fi
            else
                # Basic check for non-JSON config files
                if [ -s "$config_file" ]; then
                    print_status "SUCCESS" "$config_file - Valid configuration"
                else
                    print_status "ERROR" "$config_file - Empty or invalid"
                    log_message "ERROR" "Empty configuration file: $config_file"
                    errors=$((errors + 1))
                fi
            fi
        else
            print_status "WARNING" "$config_file - Missing"
            log_message "WARNING" "Missing configuration file: $config_file"
        fi
    done
    
    if [ $errors -eq 0 ]; then
        print_status "SUCCESS" "All configuration files verified"
        log_message "VERIFY" "Configuration verification completed successfully"
        return 0
    else
        print_status "ERROR" "Configuration verification completed with $errors errors"
        log_message "ERROR" "Configuration verification completed with $errors errors"
        return 1
    fi
}

# Function to check resource usage
check_resource_usage() {
    print_status "MAINT" "Checking resource usage..."
    log_message "RESOURCE" "Starting resource usage check"
    
    echo -e "\n${CYAN}===== Resource Usage Report =====${NC}"
    echo -e "CPU Load: $(cat /proc/loadavg | awk '{print $1", "$2", "$3}')"
    echo -e "Memory Usage: $(free -h | awk '/^Mem:/ {print $3 "/" $2 " (" $3/$2*100 "%)"}')"
    echo -e "Disk Usage: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    echo -e "Swap Usage: $(free -h | awk '/^Swap:/ {if ($2 == "0B") print "Disabled"; else print $3 "/" $2 " (" $3/$2*100 "%)"}')"
    
    # Check individual service memory usage
    echo -e "\n${CYAN}----- Service Memory Usage -----${NC}"
    for service in "${!SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            local pid=$(systemctl show --property=MainPID "$service" | cut -d= -f2)
            if [ $pid -ne 0 ]; then
                local mem_usage=$(ps -p $pid -o %mem --no-headers | awk '{print $1 "%"}')
                echo -e "$service: $mem_usage"
            fi
        fi
    done
    
    log_message "RESOURCE" "Resource usage check completed"
}

# Function to create maintenance report
create_maintenance_report() {
    local report_type=${1:-"manual"}
    local report_file="$REPORT_DIR/maintenance_$(date +%Y%m%d_%H%M%S).log"
    
    print_status "MAINT" "Generating maintenance report..."
    log_message "REPORT" "Generating maintenance report: $report_file"
    
    {
        echo "===== VIP-Autoscript Maintenance Report ====="
        echo "Generated: $(date)"
        echo "Report Type: $report_type"
        echo "============================================="
        echo ""
        echo "----- System Information -----"
        echo "Hostname: $(hostname)"
        echo "Uptime: $(uptime -p)"
        echo "OS: $(lsb_release -d | cut -f2-)"
        echo "Kernel: $(uname -r)"
        echo ""
        echo "----- Resource Usage -----"
        echo "CPU Load: $(cat /proc/loadavg | awk '{print $1", "$2", "$3}')"
        echo "Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
        echo "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
        echo ""
        echo "----- Service Status -----"
        for service in "${!SERVICES[@]}"; do
            echo "$service: $(check_service_status $service)"
        done
        echo ""
        echo "----- Recent Maintenance Activities -----"
        tail -20 "$MAINTENANCE_LOG" 2>/dev/null || echo "No maintenance log found"
        echo ""
        echo "----- Recommendations -----"
        generate_recommendations
        echo ""
        echo "============================================="
    } > "$report_file"
    
    print_status "SUCCESS" "Maintenance report generated: $report_file"
    log_message "REPORT" "Maintenance report saved: $report_file"
    
    echo "$report_file"
}

# Function to generate system recommendations
generate_recommendations() {
    local disk_usage=$(check_disk_usage)
    local memory_usage=$(free | awk '/^Mem:/ {printf("%.0f"), $3/$2 * 100}')
    
    if [ $disk_usage -gt 80 ]; then
        echo "- [URGENT] Disk usage is high ($disk_usage%). Consider cleaning up files or expanding storage."
    elif [ $disk_usage -gt 65 ]; then
        echo "- [WARNING] Disk usage is moderate ($disk_usage%). Monitor and consider cleanup."
    fi
    
    if [ $memory_usage -gt 90 ]; then
        echo "- [URGENT] Memory usage is critical ($memory_usage%). Consider optimizing applications or adding more RAM."
    elif [ $memory_usage -gt 75 ]; then
        echo "- [WARNING] Memory usage is high ($memory_usage%). Monitor application memory usage."
    fi
    
    # Check if automatic updates are enabled
    if ! systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
        echo "- [RECOMMENDED] Enable automatic security updates for system maintenance."
    fi
    
    # Check if monitoring is enabled
    if ! crontab -l | grep -q "monitor.sh"; then
        echo "- [RECOMMENDED] Set up regular monitoring with scripts/monitor.sh"
    fi
    
    # Check backup status
    local backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime -7 | wc -l)
    if [ $backup_count -eq 0 ]; then
        echo "- [IMPORTANT] No recent backups found. Schedule regular backups."
    fi
}

# Function to setup automated maintenance
setup_automated_maintenance() {
    print_status "MAINT" "Setting up automated maintenance..."
    log_message "AUTOMATION" "Setting up automated maintenance schedules"
    
    # Create cron job file
    cat > "$CRON_JOB_FILE" << EOF
# VIP-Autoscript Maintenance Schedule
# Auto-generated on $(date)

# Daily maintenance (2:00 AM)
${SCHEDULES[daily]} root /etc/vip-autoscript/scripts/maintenance.sh --daily

# Weekly maintenance (3:00 AM Sunday)
${SCHEDULES[weekly]} root /etc/vip-autoscript/scripts/maintenance.sh --weekly

# Monthly maintenance (4:00 AM 1st of month)
${SCHEDULES[monthly]} root /etc/vip-autoscript/scripts/maintenance.sh --monthly

# Log rotation (daily)
0 1 * * * root /usr/sbin/logrotate /etc/logrotate.d/vip-autoscript
EOF
    
    chmod 644 "$CRON_JOB_FILE"
    
    print_status "SUCCESS" "Automated maintenance scheduled"
    log_message "AUTOMATION" "Automated maintenance schedules configured"
    
    # Show scheduled jobs
    echo -e "\n${CYAN}===== Scheduled Maintenance Jobs =====${NC}"
    echo "Daily:   ${SCHEDULES[daily]} - Cleanup, verification, quick checks"
    echo "Weekly:  ${SCHEDULES[weekly]} - Updates, optimization, full checks"
    echo "Monthly: ${SCHEDULES[monthly]} - Comprehensive maintenance, reports"
    echo -e "${CYAN}========================================${NC}"
}

# Function to perform daily maintenance
perform_daily_maintenance() {
    print_status "MAINT" "Starting daily maintenance..."
    log_message "DAILY" "Starting daily maintenance routine"
    
    # Quick cleanup
    cleanup_logs false
    
    # Verify configurations
    verify_configurations
    
    # Quick service check
    for service in "${!SERVICES[@]}"; do
        if [ "$(check_service_status $service)" = "stopped" ]; then
            restart_service "$service"
        fi
    done
    
    # Quick resource check
    check_resource_usage
    
    log_message "DAILY" "Daily maintenance completed"
}

# Function to perform weekly maintenance
perform_weekly_maintenance() {
    print_status "MAINT" "Starting weekly maintenance..."
    log_message "WEEKLY" "Starting weekly maintenance routine"
    
    # Full cleanup
    cleanup_logs true
    
    # System updates
    system_update
    
    # Backup cleanup
    cleanup_backups
    
    # Disk health check
    check_disk_health
    
    # System optimization
    optimize_system
    
    # Full service restart
    for service in "${!SERVICES[@]}"; do
        restart_service "$service"
    done
    
    log_message "WEEKLY" "Weekly maintenance completed"
}

# Function to perform monthly maintenance
perform_monthly_maintenance() {
    print_status "MAINT" "Starting monthly maintenance..."
    log_message "MONTHLY" "Starting monthly maintenance routine"
    
    # Comprehensive cleanup
    cleanup_logs true
    cleanup_backups
    
    # Full system update
    system_update
    
    # Comprehensive checks
    check_disk_health
    verify_configurations
    check_resource_usage
    
    # Database optimization
    optimize_databases
    
    # System optimization
    optimize_system
    
    # Create comprehensive report
    local report_file=$(create_maintenance_report "monthly")
    
    # Archive old reports (keep only last 3 months)
    find "$REPORT_DIR" -name "maintenance_*.log" -mtime +90 -delete 2>/dev/null
    
    log_message "MONTHLY" "Monthly maintenance completed. Report: $report_file"
}

# Function to show maintenance menu
show_maintenance_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}      VIP-Autoscript Maintenance        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "1)  Run daily maintenance"
    echo -e "2)  Run weekly maintenance"
    echo -e "3)  Run monthly maintenance"
    echo -e "4)  Cleanup logs and temp files"
    echo -e "5)  Update system packages"
    echo -e "6)  Check disk health"
    echo -e "7)  Verify configurations"
    echo -e "8)  Optimize system"
    echo -e "9)  Check resource usage"
    echo -e "10) Generate maintenance report"
    echo -e "11) Setup automated maintenance"
    echo -e "12) View maintenance log"
    echo -e "13) Back to main menu"
    echo -e "${BLUE}========================================${NC}"
}

# Main maintenance function
main_maintenance() {
    check_root
    
    local option=$1
    
    case $option in
        "--daily")
            perform_daily_maintenance
            ;;
        "--weekly")
            perform_weekly_maintenance
            ;;
        "--monthly")
            perform_monthly_maintenance
            ;;
        "--cleanup")
            cleanup_logs true
            ;;
        "--update")
            system_update
            ;;
        "--diskcheck")
            check_disk_health
            ;;
        "--verify")
            verify_configurations
            ;;
        "--optimize")
            optimize_system
            ;;
        "--report")
            create_maintenance_report "manual"
            ;;
        "--auto")
            setup_automated_maintenance
            ;;
        *)
            while true; do
                show_maintenance_menu
                read -p "Choose an option: " choice
                
                case $choice in
                    1) perform_daily_maintenance
                       read -p "Press Enter to continue..." ;;
                    2) perform_weekly_maintenance
                       read -p "Press Enter to continue..." ;;
                    3) perform_monthly_maintenance
                       read -p "Press Enter to continue..." ;;
                    4) cleanup_logs true
                       read -p "Press Enter to continue..." ;;
                    5) system_update
                       read -p "Press Enter to continue..." ;;
                    6) check_disk_health
                       read -p "Press Enter to continue..." ;;
                    7) verify_configurations
                       read -p "Press Enter to continue..." ;;
                    8) optimize_system
                       read -p "Press Enter to continue..." ;;
                    9) check_resource_usage
                       read -p "Press Enter to continue..." ;;
                    10) create_maintenance_report "manual"
                        read -p "Press Enter to continue..." ;;
                    11) setup_automated_maintenance
                        read -p "Press Enter to continue..." ;;
                    12) echo -e "\n${CYAN}===== Maintenance Log =====${NC}"
                        tail -20 "$MAINTENANCE_LOG" 2>/dev/null || echo "No maintenance log found"
                        echo -e "${CYAN}===========================${NC}"
                        read -p "Press Enter to continue..." ;;
                    13) break ;;
                    *) print_status "ERROR" "Invalid option!"
                       sleep 1 ;;
                esac
            done
            ;;
    esac
}

# Parse command line arguments
if [ $# -gt 0 ]; then
    case $1 in
        -d|--daily)
            main_maintenance "--daily"
            exit 0
            ;;
        -w|--weekly)
            main_maintenance "--weekly"
            exit 0
            ;;
        -m|--monthly)
            main_maintenance "--monthly"
            exit 0
            ;;
        -c|--cleanup)
            main_maintenance "--cleanup"
            exit 0
            ;;
        -u|--update)
            main_maintenance "--update"
            exit 0
            ;;
        -D|--diskcheck)
            main_maintenance "--diskcheck"
            exit 0
            ;;
        -v|--verify)
            main_maintenance "--verify"
            exit 0
            ;;
        -o|--optimize)
            main_maintenance "--optimize"
            exit 0
            ;;
        -r|--report)
            main_maintenance "--report"
            exit 0
            ;;
        -a|--auto)
            main_maintenance "--auto"
            exit 0
            ;;
        -l|--log)
            tail -f "$MAINTENANCE_LOG"
            exit 0
            ;;
        *)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -d, --daily       Run daily maintenance tasks"
            echo "  -w, --weekly      Run weekly maintenance tasks"
            echo "  -m, --monthly     Run monthly maintenance tasks"
            echo "  -c, --cleanup     Cleanup logs and temporary files"
            echo "  -u, --update      Update system packages"
            echo "  -D, --diskcheck   Check disk health"
            echo "  -v, --verify      Verify configuration files"
            echo "  -o, --optimize    Optimize system performance"
            echo "  -r, --report      Generate maintenance report"
            echo "  -a, --auto        Setup automated maintenance"
            echo "  -l, --log         View maintenance log"
            exit 1
            ;;
    esac
else
    # Start interactive mode if no arguments provided
    main_maintenance
fi
