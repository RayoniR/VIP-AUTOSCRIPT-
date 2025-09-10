#!/bin/bash

get_wifi_interface() {
    iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}'
}

scan_wifi() {
    local iface=$(get_wifi_interface)
    if [ -z "$iface" ]; then
        echo "No Wi-Fi interface found."
        return
    fi

    echo "Scanning Wi-Fi networks on interface $iface..."
    sudo iwlist "$iface" scan | awk '
        BEGIN {FS=":"; RS="Cell "}
        /ESSID/ {essid=$2}
        /Quality/ {quality=$1}
        /Encryption key/ {enc=$2}
        /Signal level/ {signal=$1}
        /Encryption key/ {print "SSID:" essid ", " quality ", Encryption:" enc ", Signal:" signal}
    '
}

test_wifi_connection() {
    local iface=$(get_wifi_interface)
    if [ -z "$iface" ]; then
        echo "No Wi-Fi interface found."
        return
    fi

    echo "Enter SSID of open Wi-Fi network to connect:"
    read ssid

    echo "Connecting to $ssid (open network)..."
    nmcli device disconnect "$iface" >/dev/null 2>&1
    nmcli device wifi connect "$ssid" ifname "$iface" >/dev/null 2>&1
    sleep 5

    echo "Testing internet connectivity..."
    if curl -s --max-time 10 http://clients3.google.com/generate_204 | grep -q "204"; then
        echo "Internet access is available on $ssid (likely unlimited browsing)."
    else
        echo "No internet access or captive portal detected on $ssid."
    fi

    nmcli device disconnect "$iface" >/dev/null 2>&1
}