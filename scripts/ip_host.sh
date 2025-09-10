#!/bin/bash

# ip_host.sh - Powerful IP host scanner and service tester

# --- Configuration ---
LOG_DIR="$HOME/ip_host_logs"
TEMP_DIR="/tmp/ip_host_tmp"
SUDO_PROMPTED=0
DEFAULT_PORTS="22,80,443,8080,8443"  # Common ports to scan
PING_TARGETS=("8.8.8.8" "1.1.1.1" "google.com")
NMAP_BIN=$(command -v nmap)
CURL_BIN=$(command -v curl)
PING_BIN=$(command -v ping)
AWK_BIN=$(command -v awk)
GREP_BIN=$(command -v grep)
NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'

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

function check_dependencies() {
  local missing=()
  for cmd in nmap curl ping awk grep; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo -e "${RED}Missing dependencies: ${missing[*]}${NC}"
    echo "Please install them and rerun the script."
    exit 1
  fi
}

function timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

function log() {
  echo "[$(timestamp)] $1" >> "$LOG_DIR/ip_host.log"
}

function pause() {
  read -rp "Press Enter to continue..."
}

function cleanup() {
  rm -rf "$TEMP_DIR"/*
}

# --- Network Range Input and Validation ---

function get_ip_range() {
  local ip_range
  while true; do
    read -rp "Enter IP range to scan (e.g., 192.168.1.0/24): " ip_range
    if [[ $ip_range =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
      echo "$ip_range"
      return
    else
      echo -e "${RED}Invalid IP range format. Try again.${NC}"
    fi
  done
}

# --- Host Discovery ---

function discover_hosts() {
  local ip_range=$1
  echo -e "${CYAN}Discovering live hosts in $ip_range...${NC}"
  require_sudo
  # Use nmap ping scan (-sn) to find live hosts
  nmap -sn "$ip_range" -oG - | grep Up | awk '{print $2}' > "$TEMP_DIR/live_hosts.txt"
  local count
  count=$(wc -l < "$TEMP_DIR/live_hosts.txt")
  echo -e "${GREEN}Found $count live hosts.${NC}"
  log "Discovered $count live hosts in $ip_range"
}

# --- Port Scan ---

function scan_ports() {
  local hosts_file=$1
  local ports=$2
  echo -e "${CYAN}Scanning ports $ports on discovered hosts...${NC}"
  require_sudo
  nmap -p "$ports" -iL "$hosts_file" -oG "$TEMP_DIR/port_scan.txt" >/dev/null
  echo -e "${GREEN}Port scan completed.${NC}"
  log "Port scan on hosts in $hosts_file for ports $ports completed"
}

# --- Service Detection and Banner Grabbing ---

function service_detection() {
  local hosts_file=$1
  echo -e "${CYAN}Performing service detection and banner grabbing...${NC}"
  require_sudo
  nmap -sV -iL "$hosts_file" -oN "$TEMP_DIR/service_scan.txt" >/dev/null
  echo -e "${GREEN}Service detection completed.${NC}"
  log "Service detection on hosts in $hosts_file completed"
}

# --- HTTP/HTTPS Browsing Access Test ---

function test_browsing_access() {
  local hosts_file=$1
  echo -e "${CYAN}Testing HTTP/HTTPS browsing access on hosts...${NC}"
  while IFS= read -r host; do
    for port in 80 443 8080 8443; do
      local proto="http"
      [[ "$port" == "443" || "$port" == "8443" ]] && proto="https"
      local url="${proto}://${host}:${port}"
      echo -n "Testing $url ... "
      if $CURL_BIN -s --max-time 5 "$url" -o /dev/null; then
        echo -e "${GREEN}Accessible${NC}"
        log "Browsing access: $url accessible"
      else
        echo -e "${YELLOW}No response${NC}"
      fi
    done
  done < "$hosts_file"
}

# --- Ping Test ---

function ping_test() {
  local hosts_file=$1
  echo -e "${CYAN}Performing ping test on hosts...${NC}"
  while IFS= read -r host; do
    if $PING_BIN -c 2 -W 2 "$host" &>/dev/null; then
      echo -e "${GREEN}$host is reachable${NC}"
      log "Ping test: $host reachable"
    else
      echo -e "${RED}$host is unreachable${NC}"
      log "Ping test: $host unreachable"
    fi
  done < "$hosts_file"
}

# --- Export Logs ---

function export_logs() {
  local export_file="$LOG_DIR/ip_host_export_$(date +%F_%T).log"
  cp "$LOG_DIR/ip_host.log" "$export_file"
  echo -e "${GREEN}Logs exported to $export_file${NC}"
}

# --- Main Menu ---

function main_menu() {
  clear
  echo -e "${CYAN}=== IP Host Scanner & Service Tester Panel ===${NC}"
  echo "1) Enter IP range and discover live hosts"
  echo "2) Scan common ports on discovered hosts"
  echo "3) Perform service detection and banner grabbing"
  echo "4) Test HTTP/HTTPS browsing access"
  echo "5) Ping test on discovered hosts"
  echo "6) Export logs"
  echo "7) Cleanup temporary files"
  echo "0) Exit"
  echo
  read -rp "Select an option: " choice
  case $choice in
    1)
      IP_RANGE=$(get_ip_range)
      discover_hosts "$IP_RANGE"
      pause
      ;;
    2)
      if [[ ! -f "$TEMP_DIR/live_hosts.txt" || ! -s "$TEMP_DIR/live_hosts.txt" ]]; then
        echo -e "${RED}No live hosts found. Please run discovery first.${NC}"
        pause
        return
      fi
      read -rp "Enter ports to scan (default: $DEFAULT_PORTS): " ports
      ports=${ports:-$DEFAULT_PORTS}
      scan_ports "$TEMP_DIR/live_hosts.txt" "$ports"
      pause
      ;;
    3)
      if [[ ! -f "$TEMP_DIR/live_hosts.txt" || ! -s "$TEMP_DIR/live_hosts.txt" ]]; then
        echo -e "${RED}No live hosts found. Please run discovery first.${NC}"
        pause
        return
      fi
      service_detection "$TEMP_DIR/live_hosts.txt"
      pause
      ;;
    4)
      if [[ ! -f "$TEMP_DIR/live_hosts.txt" || ! -s "$TEMP_DIR/live_hosts.txt" ]]; then
        echo -e "${RED}No live hosts found. Please run discovery first.${NC}"
        pause
        return
      fi
      test_browsing_access "$TEMP_DIR/live_hosts.txt"
      pause
      ;;
    5)
      if [[ ! -f "$TEMP_DIR/live_hosts.txt" || ! -s "$TEMP_DIR/live_hosts.txt" ]]; then
        echo -e "${RED}No live hosts found. Please run discovery first.${NC}"
        pause
        return
      fi
      ping_test "$TEMP_DIR/live_hosts.txt"
      pause
      ;;
    6)
      export_logs
      pause
      ;;
    7)
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

require_sudo
check_dependencies

while true; do
  main_menu
done