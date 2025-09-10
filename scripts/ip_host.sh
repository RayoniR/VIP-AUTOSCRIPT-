#!/bin/bash

scan_ip() {
    echo "Enter the IP range to scan (e.g., 192.168.1.0/24):"
    read ip_range

    echo "Scanning for hosts with open HTTP (80) or HTTPS (443) ports..."
    nmap -p 80,443 --open $ip_range -oG - | grep Up | awk '{print $2}' > hosts.txt

    if [ ! -s hosts.txt ]; then
        echo "No hosts with open HTTP/HTTPS ports found."
        return
    fi

    echo "Testing internet access on found hosts..."

    while read -r host; do
        echo -n "Testing $host ... "
        if curl -s --max-time 10 "http://$host/generate_204" | grep -q "204"; then
            echo "Likely unlimited browsing (no captive portal)."
        else
            echo "Captive portal or restricted access detected."
        fi
    done < hosts.txt

    rm -f hosts.txt
}