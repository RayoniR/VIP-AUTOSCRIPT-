#!/bin/bash

# VIP-Autoscript Manager - Production Ready
# Complete service management with monitoring, logging, and backup

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
BACKUP_DIR="$SCRIPT_DIR/backups"
LOG_DIR="$SCRIPT_DIR/logs"
SERVICE_DIR="$SCRIPT_DIR/services"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# Service definitions
declare -A SERVICES=(
    ["xray"]="Xray Proxy"
    ["badvpn"]="BadVPN UDP Gateway"
    ["sshws"]="SSH WebSocket"
    ["slowdns"]="SlowDNS"
)

# Service ports
declare -A PORTS=(
    ["xray"]="443 80"
    ["badvpn"]="7300 7301 7302"
    ["sshws"]="8080 8081"
    ["slowdns"]="53 5300"
)

# Service dependencies
declare -A DEPENDENCIES=(
    ["xray"]=""
    ["badvpn"]="xray"
    ["sshws"]=""
    ["slowdns"]=""
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Create necessary directories
mkdir -p "$CONFIG_DIR" "$BACKUP_DIR" "$LOG_DIR" "$SERVICE_DIR" "$SCRIPTS_DIR"

# Function to print status with colors
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "DEBUG") echo -e "${CYAN}[DEBUG]${NC} $message" ;;
        *) echo -e "[$status] $message" ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check service status
check_service_status() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}RUNNING${NC}"
        return 0
    else
        echo -e "${RED}STOPPED${NC}"
        return 1
    fi
}

# Function to start a service
start_service() {
    local service=$1
    print_status "INFO" "Starting $service..."
    
    # Check dependencies
    local dependency=${DEPENDENCIES[$service]}
    if [ -n "$dependency" ]; then
        if ! check_service_status "$dependency" >/dev/null 2>&1; then
            print_status "INFO" "Starting dependency $dependency first..."
            start_service "$dependency"
        fi
    fi
    
    sudo systemctl start "$service"
    sleep 2
    
    if check_service_status "$service" >/dev/null 2>&1; then
        print_status "SUCCESS" "$service started successfully"
        return 0
    else
        print_status "ERROR" "Failed to start $service"
        sudo journalctl -u "$service" -n 10 --no-pager
        return 1
    fi
}

# Function to stop a service
stop_service() {
    local service=$1
    print_status "INFO" "Stopping $service..."
    
    sudo systemctl stop "$service"
    sleep 2
    
    if ! systemctl is-active --quiet "$service"; then
        print_status "SUCCESS" "$service stopped successfully"
        return 0
    else
        print_status "ERROR" "Failed to stop $service"
        return 1
    fi
}

# Function to restart a service
restart_service() {
    local service=$1
    print_status "INFO" "Restarting $service..."
    
    sudo systemctl restart "$service"
    sleep 2
    
    if check_service_status "$service" >/dev/null 2>&1; then
        print_status "SUCCESS" "$service restarted successfully"
        return 0
    else
        print_status "ERROR" "Failed to restart $service"
        return 1
    fi
}

# Function to enable a service on boot
enable_service() {
    local service=$1
    sudo systemctl enable "$service" 2>/dev/null
}

# Function to disable a service on boot
disable_service() {
    local service=$1
    sudo systemctl disable "$service" 2>/dev/null
}

# Function to show service status
status_services() {
    echo -e "\n${BLUE}===== Service Status =====${NC}"
    for service in "${!SERVICES[@]}"; do
        status=$(check_service_status "$service")
        echo -e "$service: $status"
    done
    echo -e "${BLUE}==========================${NC}"
}

# Function to show service logs
show_logs() {
    local service=$1
    local lines=${2:-20}
    
    if [ -z "$service" ]; then
        echo -e "\n${BLUE}===== Service Logs =====${NC}"
        for service in "${!SERVICES[@]}"; do
            echo -e "\n${YELLOW}--- $service logs (last $lines lines) ---${NC}"
            sudo journalctl -u "$service" -n "$lines" --no-pager
        done
    else
        if [[ "${SERVICES[$service]}" ]]; then
            echo -e "\n${YELLOW}===== $service Logs (last $lines lines) =====${NC}"
            sudo journalctl -u "$service" -n "$lines" --no-pager
        else
            print_status "ERROR" "Service $service not found"
        fi
    fi
}

# Function to monitor services in real-time
monitor_services() {
    echo -e "${BLUE}Starting service monitor (Ctrl+C to stop)...${NC}"
    trap "echo -e '\n${BLUE}Monitoring stopped${NC}'; exit 0" INT
    
    while true; do
        clear
        echo -e "${BLUE}===== Service Monitor =====${NC}"
        echo -e "Press Ctrl+C to stop monitoring\n"
        
        for service in "${!SERVICES[@]}"; do
            status=$(check_service_status "$service")
            echo -e "$service: $status"
        done
        
        echo -e "\n${BLUE}Uptime: $(uptime -p)${NC}"
        echo -e "${BLUE}Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')${NC}"
        echo -e "${BLUE}===========================${NC}"
        sleep 5
    done
}

# Function to backup configurations
backup_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/config_backup_$timestamp.tar.gz"
    
    print_status "INFO" "Creating backup..."
    
    # Backup configurations and scripts
    tar -czf "$backup_file" "$CONFIG_DIR" "$SCRIPTS_DIR" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "Backup created: $backup_file"
        print_status "INFO" "Size: $(du -h "$backup_file" | cut -f1)"
    else
        print_status "ERROR" "Backup failed!"
        return 1
    fi
}

# Function to restore configurations
restore_config() {
    echo "Available backups:"
    local backups=($(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_status "ERROR" "No backups found!"
        return 1
    fi
    
    for i in "${!backups[@]}"; do
        echo "[$i] ${backups[$i]}"
    done
    
    read -p "Select backup to restore [0-$((${#backups[@]}-1))]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -ge ${#backups[@]} ]; then
        print_status "ERROR" "Invalid selection!"
        return 1
    fi
    
    local backup_file="${backups[$choice]}"
    print_status "INFO" "Restoring from $backup_file..."
    
    # Stop services before restore
    stop_services
    
    # Restore configurations
    tar -xzf "$backup_file" -C "/" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "Configuration restored successfully!"
        
        # Reload systemd and restart services
        sudo systemctl daemon-reload
        start_services
    else
        print_status "ERROR" "Restore failed!"
        return 1
    fi
}

# Function to start all services
start_services() {
    print_status "INFO" "Starting all services..."
    for service in "${!SERVICES[@]}"; do
        start_service "$service"
    done
    print_status "SUCCESS" "All services started."
}

# Function to stop all services
stop_services() {
    print_status "INFO" "Stopping all services..."
    for service in "${!SERVICES[@]}"; do
        stop_service "$service"
    done
    print_status "SUCCESS" "All services stopped."
}

# Function to restart all services
restart_services() {
    print_status "INFO" "Restarting all services..."
    for service in "${!SERVICES[@]}"; do
        restart_service "$service"
    done
    print_status "SUCCESS" "All services restarted."
}

# Function to enable all services on boot
enable_services() {
    print_status "INFO" "Enabling all services to start on boot..."
    for service in "${!SERVICES[@]}"; do
        enable_service "$service"
    done
    print_status "SUCCESS" "All services enabled on boot."
}

# Function to disable all services on boot
disable_services() {
    print_status "INFO" "Disabling all services from starting on boot..."
    for service in "${!SERVICES[@]}"; do
        disable_service "$service"
    done
    print_status "SUCCESS" "All services disabled from starting on boot."
}

# Function to show system information
show_system_info() {
    echo -e "\n${BLUE}===== System Information =====${NC}"
    echo -e "Hostname: $(hostname)"
    echo -e "Uptime: $(uptime -p)"
    echo -e "OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    echo -e "Kernel: $(uname -r)"
    echo -e "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
    echo -e "Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2 " used"}')"
    echo -e "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " used (" $5 ")"}')"
    echo -e "${BLUE}===============================${NC}"
}

# Function to check firewall status
check_firewall() {
    echo -e "\n${BLUE}===== Firewall Status =====${NC}"
    if command_exists ufw; then
        sudo ufw status
    elif command_exists firewall-cmd; then
        sudo firewall-cmd --list-all
    else
        echo "No known firewall detected"
    fi
    echo -e "${BLUE}===========================${NC}"
}

# Function to update scripts
update_scripts() {
    print_status "INFO" "Updating scripts..."
    
    # Backup current configuration
    backup_config
    
    # Placeholder for update logic - in real scenario, this would pull from git repo
    print_status "INFO" "Checking for updates..."
    
    # Simulate update process
    if [ -f "$SCRIPTS_DIR/update.sh" ]; then
        "$SCRIPTS_DIR/update.sh"
    else
        print_status "WARNING" "Update script not found"
    fi
    
    print_status "SUCCESS" "Update process completed"
}

# Main menu
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         VIP-Autoscript Manager         ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "1)  Start all services"
    echo -e "2)  Stop all services"
    echo -e "3)  Restart all services"
    echo -e "4)  Show service status"
    echo -e "5)  Monitor services (real-time)"
    echo -e "6)  Show service logs"
    echo -e "7)  Start individual service"
    echo -e "8)  Stop individual service"
    echo -e "9)  Restart individual service"
    echo -e "10) Backup configurations"
    echo -e "11) Restore configurations"
    echo -e "12) Update scripts"
    echo -e "13) Enable services on boot"
    echo -e "14) Disable services on boot"
    echo -e "15) System information"
    echo -e "16) Firewall status"
    echo -e "17) Install services"
    echo -e "18) Exit"
    echo -e "19) Advanced monitoring"
    echo -e "20) Firewall configuration"
    echo -e "21) SSL certificate setup"
    echo -e "22) User management"
    echo -e "23) System maintenance"
    echo -e "24)  Advanced AI Maintenance"
    echo -e "${BLUE}========================================${NC}"
}

# Individual service menu
show_service_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         Service Selection              ${NC}"
    echo -e "${BLUE}========================================${NC}"
    local i=1
    for service in "${!SERVICES[@]}"; do
        echo -e "$i) $service - ${SERVICES[$service]}"
        ((i++))
    done
    echo -e "$i) Back to main menu"
    echo -e "${BLUE}========================================${NC}"
}

# Function to install services
install_services() {
    print_status "INFO" "Installing services..."
    
    # Check if we're running as root
    if [ "$EUID" -ne 0 ]; then
        print_status "ERROR" "Please run as root or use sudo"
        exit 1
    fi
    
    # Run installation script if available
    if [ -f "$SCRIPT_DIR/install.sh" ]; then
        "$SCRIPT_DIR/install.sh"
    else
        print_status "ERROR" "Installation script not found"
        return 1
    fi
}

# Main program loop
while true; do
    show_menu
    read -p "Choose an option: " choice
    
    case $choice in
        1) start_services
           read -p "Press Enter to continue..." ;;
        2) stop_services
           read -p "Press Enter to continue..." ;;
        3) restart_services
           read -p "Press Enter to continue..." ;;
        4) status_services
           read -p "Press Enter to continue..." ;;
        5) monitor_services ;;
        6) show_logs
           read -p "Press Enter to continue..." ;;
        7) show_service_menu
           read -p "Select service to start: " service_choice
           services_list=("${!SERVICES[@]}")
           if [[ $service_choice -le ${#services_list[@]} ]]; then
               start_service "${services_list[$((service_choice-1))]}"
           fi
           read -p "Press Enter to continue..." ;;
        8) show_service_menu
           read -p "Select service to stop: " service_choice
           services_list=("${!SERVICES[@]}")
           if [[ $service_choice -le ${#services_list[@]} ]]; then
               stop_service "${services_list[$((service_choice-1))]}"
           fi
           read -p "Press Enter to continue..." ;;
        9) show_service_menu
           read -p "Select service to restart: " service_choice
           services_list=("${!SERVICES[@]}")
           if [[ $service_choice -le ${#services_list[@]} ]]; then
               restart_service "${services_list[$((service_choice-1))]}"
           fi
           read -p "Press Enter to continue..." ;;
        10) backup_config
            read -p "Press Enter to continue..." ;;
        11) restore_config
            read -p "Press Enter to continue..." ;;
        12) update_scripts
            read -p "Press Enter to continue..." ;;
        13) enable_services
            read -p "Press Enter to continue..." ;;
        14) disable_services
            read -p "Press Enter to continue..." ;;
        15) show_system_info
            read -p "Press Enter to continue..." ;;
        16) check_firewall
            read -p "Press Enter to continue..." ;;
        17) install_services
            read -p "Press Enter to continue..." ;;
        18) echo "Exiting..."; break ;;
        19) sudo "$SCRIPTS_DIR/monitor.sh"
‎    read -p "Press Enter to continue..." ;;
        20) sudo "$SCRIPTS_DIR/firewall.sh"
‎    read -p "Press Enter to continue..." ;;
        21) sudo "$SCRIPTS_DIR/ssl-setup.sh"
‎    read -p "Press Enter to continue..." ;;
        22) sudo "$SCRIPTS_DIR/user-manager.sh"
‎    read -p "Press Enter to continue..." ;;
        23) sudo "$SCRIPTS_DIR/maintenance.sh"
‎    read -p "Press Enter to continue..." ;;
        24) sudo "$SCRIPTS_DIR/advance-maintenance.sh"
‎    read -p "Press Enter to continue..." ;;
        *) print_status "ERROR" "Invalid option!"
           sleep 1 ;;
    esac
done
