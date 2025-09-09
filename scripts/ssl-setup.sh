#!/bin/bash

# VIP-Autoscript SSL Certificate Setup
# Manages SSL certificates for Xray services

# Configuration
SSL_DIR="/etc/ssl/vip-autoscript"
CONFIG_DIR="/etc/vip-autoscript/config"

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

# Function to create SSL directory
create_ssl_dir() {
    mkdir -p "$SSL_DIR"
    chmod 700 "$SSL_DIR"
    print_status "SUCCESS" "SSL directory created: $SSL_DIR"
}

# Function to generate self-signed certificate
generate_self_signed() {
    local domain=${1:-"vip-autoscript.example.com"}
    
    print_status "INFO" "Generating self-signed certificate for $domain..."
    
    # Generate private key
    openssl genrsa -out "$SSL_DIR/private.key" 2048 2>/dev/null
    if [ $? -ne 0 ]; then
        print_status "ERROR" "Failed to generate private key"
        return 1
    fi
    
    # Generate certificate signing request
    openssl req -new -key "$SSL_DIR/private.key" \
        -out "$SSL_DIR/request.csr" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" 2>/dev/null
    
    # Generate self-signed certificate
    openssl x509 -req -days 365 \
        -in "$SSL_DIR/request.csr" \
        -signkey "$SSL_DIR/private.key" \
        -out "$SSL_DIR/certificate.crt" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "Self-signed certificate generated for $domain"
        update_xray_config
    else
        print_status "ERROR" "Failed to generate self-signed certificate"
        return 1
    fi
}

# Function to update Xray configuration with new certificates
update_xray_config() {
    if [ ! -f "$SSL_DIR/certificate.crt" ] || [ ! -f "$SSL_DIR/private.key" ]; then
        print_status "ERROR" "Certificate files not found"
        return 1
    fi
    
    # Backup current config
    cp "$CONFIG_DIR/xray.json" "$CONFIG_DIR/xray.json.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update Xray config with new certificate paths
    jq '.inbounds[0].streamSettings.xtlsSettings.certificates[0] = {
        "certificateFile": "/etc/ssl/vip-autoscript/certificate.crt",
        "keyFile": "/etc/ssl/vip-autoscript/private.key"
    }' "$CONFIG_DIR/xray.json" > "$CONFIG_DIR/xray.json.tmp" \
    && mv "$CONFIG_DIR/xray.json.tmp" "$CONFIG_DIR/xray.json"
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "Xray configuration updated with new certificates"
        restart_xray
    else
        print_status "ERROR" "Failed to update Xray configuration"
        return 1
    fi
}

# Function to restart Xray service
restart_xray() {
    print_status "INFO" "Restarting Xray service..."
    systemctl restart xray
    sleep 2
    
    if systemctl is-active --quiet xray; then
        print_status "SUCCESS" "Xray service restarted successfully"
    else
        print_status "ERROR" "Failed to restart Xray service"
        return 1
    fi
}

# Function to check certificate validity
check_certificate() {
    if [ ! -f "$SSL_DIR/certificate.crt" ]; then
        print_status "ERROR" "Certificate file not found"
        return 1
    fi
    
    local expiry_date=$(openssl x509 -in "$SSL_DIR/certificate.crt" -noout -enddate | cut -d= -f2)
    local days_until_expiry=$(( ($(date -d "$expiry_date" +%s) - $(date +%s)) / 86400 ))
    
    echo -e "\n${BLUE}===== Certificate Information =====${NC}"
    echo -e "Subject: $(openssl x509 -in "$SSL_DIR/certificate.crt" -noout -subject)"
    echo -e "Issuer: $(openssl x509 -in "$SSL_DIR/certificate.crt" -noout -issuer)"
    echo -e "Expiry Date: $expiry_date"
    echo -e "Days until expiry: $days_until_expiry"
    
    if [ $days_until_expiry -lt 30 ]; then
        print_status "WARNING" "Certificate will expire in $days_until_expiry days"
    else
        print_status "SUCCESS" "Certificate is valid for $days_until_expiry days"
    fi
    
    echo -e "${BLUE}====================================${NC}"
}

# Function to setup Let's Encrypt certificate
setup_letsencrypt() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        print_status "ERROR" "Domain name is required for Let's Encrypt"
        return 1
    fi
    
    if ! command_exists certbot; then
        print_status "INFO" "Installing certbot..."
        apt-get update
        apt-get install -y certbot
    fi
    
    print_status "INFO" "Requesting Let's Encrypt certificate for $domain..."
    
    # Stop Xray temporarily during certificate issuance
    systemctl stop xray
    
    # Get certificate
    certbot certonly --standalone --non-interactive --agree-tos \
        --email admin@$domain -d $domain
    
    if [ $? -eq 0 ]; then
        # Create symlinks to Let's Encrypt certificates
        ln -sf /etc/letsencrypt/live/$domain/fullchain.pem "$SSL_DIR/certificate.crt"
        ln -sf /etc/letsencrypt/live/$domain/privkey.pem "$SSL_DIR/private.key"
        
        print_status "SUCCESS" "Let's Encrypt certificate obtained for $domain"
        update_xray_config
        
        # Setup automatic renewal
        setup_renewal
    else
        print_status "ERROR" "Failed to obtain Let's Encrypt certificate"
        systemctl start xray
        return 1
    fi
}

# Function to setup automatic certificate renewal
setup_renewal() {
    print_status "INFO" "Setting up automatic certificate renewal..."
    
    # Create renewal hook script
    cat > /etc/letsencrypt/renewal-hooks/deploy/vip-autoscript.sh << EOF
#!/bin/bash
# VIP-Autoscript Certificate Renewal Hook

# Restart Xray after certificate renewal
systemctl restart xray

# Update certificate symlinks
if [ -f "\$RENEWED_LINEAGE/fullchain.pem" ] && [ -f "\$RENEWED_LINEAGE/privkey.pem" ]; then
    ln -sf "\$RENEWED_LINEAGE/fullchain.pem" /etc/ssl/vip-autoscript/certificate.crt
    ln -sf "\$RENEWED_LINEAGE/privkey.pem" /etc/ssl/vip-autoscript/private.key
    echo "\$(date): Certificates renewed and symlinks updated" >> /var/log/vip-cert-renewal.log
fi
EOF
    
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/vip-autoscript.sh
    
    # Test renewal
    certbot renew --dry-run
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "Automatic certificate renewal configured"
    else
        print_status "WARNING" "Automatic renewal test failed"
    fi
}

# Function to show SSL menu
show_ssl_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         VIP-Autoscript SSL Setup       ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "1)  Generate self-signed certificate"
    echo -e "2)  Setup Let's Encrypt certificate"
    echo -e "3)  Check certificate status"
    echo -e "4)  Setup automatic renewal"
    echo -e "5)  Back to main menu"
    echo -e "${BLUE}========================================${NC}"
}

# Main SSL function
main_ssl() {
    check_root
    create_ssl_dir
    
    local option=$1
    local domain=$2
    
    case $option in
        "self-signed")
            generate_self_signed "$domain"
            ;;
        "letsencrypt")
            setup_letsencrypt "$domain"
            ;;
        "check")
            check_certificate
            ;;
        "renewal")
            setup_renewal
            ;;
        *)
            while true; do
                show_ssl_menu
                read -p "Choose an option: " choice
                
                case $choice in
                    1) read -p "Enter domain name [vip-autoscript.example.com]: " domain
                       generate_self_signed "${domain:-vip-autoscript.example.com}"
                       read -p "Press Enter to continue..." ;;
                    2) read -p "Enter domain name: " domain
                       if [ -n "$domain" ]; then
                           setup_letsencrypt "$domain"
                       else
                           print_status "ERROR" "Domain name is required"
                       fi
                       read -p "Press Enter to continue..." ;;
                    3) check_certificate
                       read -p "Press Enter to continue..." ;;
                    4) setup_renewal
                       read -p "Press Enter to continue..." ;;
                    5) break ;;
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
        -s|--self-signed)
            main_ssl "self-signed" "$2"
            exit 0
            ;;
        -l|--letsencrypt)
            main_ssl "letsencrypt" "$2"
            exit 0
            ;;
        -c|--check)
            main_ssl "check"
            exit 0
            ;;
        -r|--renewal)
            main_ssl "renewal"
            exit 0
            ;;
        *)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -s, --self-signed [domain]  Generate self-signed certificate"
            echo "  -l, --letsencrypt [domain]  Setup Let's Encrypt certificate"
            echo "  -c, --check                 Check certificate status"
            echo "  -r, --renewal               Setup automatic renewal"
            exit 1
            ;;
    esac
else
    # Start interactive mode if no arguments provided
    main_ssl
fi
