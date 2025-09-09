#!/bin/bash

# VIP-Autoscript Firewall Configuration
# Comprehensive firewall setup with security hardening

# Configuration
FIREWALL_LOG="/var/log/vip-firewall.log"
WHITELIST_FILE="/etc/vip-autoscript/config/whitelist.txt"
BLACKLIST_FILE="/etc/vip-autoscript/config/blacklist.txt"

# Services and ports
declare -A SERVICE_PORTS=(
    ["SSH"]="22"
    ["XRAY_MAIN"]="443"
    ["XRAY_FALLBACK"]="80"
    ["BADVPN"]="7300,7301,7302"
    ["SSHWS"]="8080,8081"
    ["SLOWDNS"]="53,5300"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        *) echo -e "[$status] $message" ;;
    esac
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_status "ERROR" "Please run as root or use sudo"
        exit 1
    fi
}

# Function to detect active firewall
detect_firewall() {
    if command_exists ufw && ufw status | grep -q "active"; then
        echo "ufw"
    elif command_exists firewall-cmd && systemctl is-active firewalld >/dev/null 2>&1; then
        echo "firewalld"
    elif command_exists iptables && iptables -L >/dev/null 2>&1; then
        echo "iptables"
    else
        echo "none"
    fi
}

# Function to setup UFW firewall
setup_ufw() {
    print_status "INFO" "Configuring UFW firewall..."
    
    # Reset UFW to default
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow essential services
    ufw allow 22/tcp comment 'SSH'
    
    # Allow VIP services
    ufw allow 443/tcp comment 'Xray Main'
    ufw allow 80/tcp comment 'Xray Fallback'
    ufw allow 7300:7302/udp comment 'BadVPN'
    ufw allow 8080:8081/tcp comment 'SSH WebSocket'
    ufw allow 53/udp comment 'DNS'
    ufw allow 5300/udp comment 'SlowDNS'
    
    # Enable logging
    ufw logging on
    
    # Enable UFW
    echo "y" | ufw enable
    
    # Reload to apply settings
    ufw reload
    
    print_status "SUCCESS" "UFW firewall configured successfully"
}

# Function to setup Firewalld
setup_firewalld() {
    print_status "INFO" "Configuring Firewalld..."
    
    # Start and enable firewalld
    systemctl enable firewalld
    systemctl start firewalld
    
    # Add services to default zone
    firewall-cmd --permanent --add-service=ssh
    
    # Add VIP services ports
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=7300-7302/udp
    firewall-cmd --permanent --add-port=8080-8081/tcp
    firewall-cmd --permanent --add-port=53/udp
    firewall-cmd --permanent --add-port=5300/udp
    
    # Reload firewalld
    firewall-cmd --reload
    
    print_status "SUCCESS" "Firewalld configured successfully"
}

# Function to setup iptables
setup_iptables() {
    print_status "INFO" "Configuring iptables..."
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # Set default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Allow ICMP (ping)
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
    
    # Allow SSH
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Allow VIP services
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p udp --dport 7300:7302 -j ACCEPT
    iptables -A INPUT -p tcp --dport 8080:8081 -j ACCEPT
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 5300 -j ACCEPT
    
    # Save rules based on distribution
    if command_exists iptables-save; then
        iptables-save > /etc/iptables/rules.v4
    fi
    
    print_status "SUCCESS" "iptables configured successfully"
}

# Function to configure system hardening
configure_hardening() {
    print_status "INFO" "Configuring system security hardening..."
    
    # Configure sysctl for security
    cat > /etc/sysctl.d/99-vip-security.conf << EOF
# Network security
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_rfc1337=1

# IP spoofing protection
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1
net.ipv4.icmp_ignore_bogus_error_responses=1

# Disable IP forwarding
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0

# Prevent source routing
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0

# Ignore send redirects
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
EOF
    
    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-vip-security.conf
    
    # Configure fail2ban if installed
    if command_exists fail2ban-client; then
        configure_fail2ban
    fi
    
    print_status "SUCCESS" "System security hardening configured"
}

# Function to configure fail2ban
configure_fail2ban() {
    print_status "INFO" "Configuring fail2ban..."
    
    # Create VIP fail2ban jail
    cat > /etc/fail2ban/jail.d/vip-autoscript.conf << EOF
[vip-ssh]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

[vip-xray]
enabled = true
port = 443,80
filter = xray
logpath = /var/log/xray/access.log
maxretry = 5
bantime = 86400
findtime = 3600
EOF
    
    # Create Xray filter
    cat > /etc/fail2ban/filter.d/xray.conf << EOF
[Definition]
failregex = ^.*email:.+?level:warning.*msg:connection from.*<HOST>:.+?rejected.*$
ignoreregex =
EOF
    
    # Restart fail2ban
    systemctl restart fail2ban
    
    print_status "SUCCESS" "fail2ban configured for VIP services"
}

# Function to show firewall status
show_firewall_status() {
    local firewall_type=$(detect_firewall)
    
    echo -e "\n${BLUE}===== Firewall Status =====${NC}"
    echo -e "Active firewall: $firewall_type"
    
    case $firewall_type in
        "ufw")
            ufw status verbose
            ;;
        "firewalld")
            firewall-cmd --list-all
            ;;
        "iptables")
            iptables -L -n -v
            ;;
        *)
            print_status "WARNING" "No active firewall detected"
            ;;
    esac
    
    echo -e "${BLUE}===========================${NC}"
}

# Function to block an IP address
block_ip() {
    local ip=$1
    local firewall_type=$(detect_firewall)
    
    if [ -z "$ip" ]; then
        print_status "ERROR" "IP address is required"
        return 1
    fi
    
    # Validate IP address
    if ! [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_status "ERROR" "Invalid IP address format"
        return 1
    fi
    
    case $firewall_type in
        "ufw")
            ufw deny from $ip
            ;;
        "firewalld")
            firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ip' reject"
            firewall-cmd --reload
            ;;
        "iptables")
            iptables -A INPUT -s $ip -j DROP
            ;;
        *)
            print_status "ERROR" "No supported firewall found"
            return 1
            ;;
    esac
    
    # Add to blacklist file
    echo "$ip # Blocked on $(date)" >> "$BLACKLIST_FILE"
    
    print_status "SUCCESS" "IP address $ip blocked successfully"
}

# Function to unblock an IP address
unblock_ip() {
    local ip=$1
    local firewall_type=$(detect_firewall)
    
    if [ -z "$ip" ]; then
        print_status "ERROR" "IP address is required"
        return 1
    fi
    
    case $firewall_type in
        "ufw")
            ufw delete deny from $ip
            ;;
        "firewalld")
            firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='$ip' reject"
            firewall-cmd --reload
            ;;
        "iptables")
            iptables -D INPUT -s $ip -j DROP
            ;;
        *)
            print_status "ERROR" "No supported firewall found"
            return 1
            ;;
    esac
    
    # Remove from blacklist file
    sed -i "/^$ip/d" "$BLACKLIST_FILE"
    
    print_status "SUCCESS" "IP address $ip unblocked successfully"
}

# Function to show blocked IPs
show_blocked_ips() {
    local firewall_type=$(detect_firewall)
    
    echo -e "\n${BLUE}===== Blocked IP Addresses =====${NC}"
    
    case $firewall_type in
        "ufw")
            ufw status | grep DENY
            ;;
        "firewalld")
            firewall-cmd --list-rich-rules | grep reject
            ;;
        "iptables")
            iptables -L INPUT -n -v | grep DROP
            ;;
        *)
            print_status "INFO" "No blocked IPs found or firewall not active"
            ;;
    esac
    
    if [ -f "$BLACKLIST_FILE" ]; then
        echo -e "\n${YELLOW}Blacklist file contents:${NC}"
        cat "$BLACKLIST_FILE"
    fi
    
    echo -e "${BLUE}================================${NC}"
}

# Function to setup complete firewall
setup_firewall() {
    check_root
    
    local firewall_type=$(detect_firewall)
    
    # If no firewall detected, try to install UFW
    if [ "$firewall_type" = "none" ]; then
        print_status "INFO" "No firewall detected. Installing UFW..."
        apt-get update
        apt-get install -y ufw
        firewall_type="ufw"
    fi
    
    # Setup the detected firewall
    case $firewall_type in
        "ufw")
            setup_ufw
            ;;
        "firewalld")
            setup_firewalld
            ;;
        "iptables")
            setup_iptables
            ;;
        *)
            print_status "ERROR" "Unsupported firewall type: $firewall_type"
            return 1
            ;;
    esac
    
    # Configure system hardening
    configure_hardening
    
    show_firewall_status
}

# Function to show firewall menu
show_firewall_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         VIP-Autoscript Firewall        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "1)  Setup firewall"
    echo -e "2)  Show firewall status"
    echo -e "3)  Block IP address"
    echo -e "4)  Unblock IP address"
    echo -e "5)  Show blocked IPs"
    echo -e "6)  Configure security hardening"
    echo -e "7)  Back to main menu"
    echo -e "${BLUE}========================================${NC}"
}

# Main firewall function
main_firewall() {
    local option=$1
    
    case $option in
        "setup")
            setup_firewall
            ;;
        "status")
            show_firewall_status
            ;;
        "block")
            block_ip "$2"
            ;;
        "unblock")
            unblock_ip "$2"
            ;;
        "list-blocked")
            show_blocked_ips
            ;;
        "harden")
            configure_hardening
            ;;
        *)
            while true; do
                show_firewall_menu
                read -p "Choose an option: " choice
                
                case $choice in
                    1) setup_firewall
                       read -p "Press Enter to continue..." ;;
                    2) show_firewall_status
                       read -p "Press Enter to continue..." ;;
                    3) read -p "Enter IP address to block: " ip
                       block_ip "$ip"
                       read -p "Press Enter to continue..." ;;
                    4) read -p "Enter IP address to unblock: " ip
                       unblock_ip "$ip"
                       read -p "Press Enter to continue..." ;;
                    5) show_blocked_ips
                       read -p "Press Enter to continue..." ;;
                    6) configure_hardening
                       read -p "Press Enter to continue..." ;;
                    7) break ;;
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
        -s|--setup)
            setup_firewall
            exit 0
            ;;
        -S|--status)
            show_firewall_status
            exit 0
            ;;
        -b|--block)
            block_ip "$2"
            exit 0
            ;;
        -u|--unblock)
            unblock_ip "$2"
            exit 0
            ;;
        -l|--list-blocked)
            show_blocked_ips
            exit 0
            ;;
        -H|--harden)
            configure_hardening
            exit 0
            ;;
        *)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -s, --setup              Setup firewall"
            echo "  -S, --status             Show firewall status"
            echo "  -b, --block [IP]         Block IP address"
            echo "  -u, --unblock [IP]       Unblock IP address"
            echo "  -l, --list-blocked       Show blocked IPs"
            echo "  -H, --harden             Configure security hardening"
            exit 1
            ;;
    esac
else
    # Start interactive mode if no arguments provided
    main_firewall
fi
