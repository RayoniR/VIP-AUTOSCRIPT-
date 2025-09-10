#!/bin/bash

# Source the other scripts
source ./scripts/wifi_host.sh
source ./scripts/ip_host.sh
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

while true; do
    echo "Select an option:"
    echo "1) Scan Wi-Fi hosts"
    echo "2) Test Wi-Fi connection and internet access"
    echo "3) Scan IP hosts and test browsing access"
    echo "4) Exit"
    read -p "Enter choice [1-4]: " choice

    case $choice in
        1) scan_wifi ;;
        2) test_wifi_connection ;;
        3) scan_ip ;;
        4) echo "Exiting."; exit 0 ;;
        *) echo "Invalid option. Please enter 1-4." ;;
    esac
    echo ""
done