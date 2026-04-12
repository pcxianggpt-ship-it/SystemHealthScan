#!/bin/bash
#
# Linux Server Health Check - Core Collection Script
# Output format: KEY=VALUE, one per line
#

set -euo pipefail

# Script version
VERSION="1.0.0"

# ANSI colors for output (optional, for debugging)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Helper function to print key-value pairs
print_kv() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}"
}

# Module 1: System Information
collect_system_info() {
    # Hostname
    local hostname=""
    if command -v hostname >/dev/null 2>&1; then
        hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    fi
    print_kv "HOSTNAME" "${hostname}"

    # Short hostname
    local uname_n=""
    if command -v uname >/dev/null 2>&1; then
        uname_n=$(uname -n 2>/dev/null || echo "unknown")
    fi
    print_kv "UNAME_N" "${uname_n}"

    # Primary IP address
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1 || echo "")
    elif command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [ -z "${ip}" ] && ip="unknown"
    print_kv "IP" "${ip}"

    # Check time
    print_kv "CHECK_TIME" "$(date '+%Y-%m-%d_%H:%M:%S')"

    # OS information
    local os=""
    if [ -f /etc/os-release ]; then
        os=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
    elif [ -f /etc/redhat-release ]; then
        os=$(cat /etc/redhat-release)
    elif [ -f /etc/lsb-release ]; then
        os=$(grep "^DISTRIB_DESCRIPTION=" /etc/lsb-release | cut -d'"' -f2)
    fi
    [ -z "${os}" ] && os="Unknown Linux"
    print_kv "OS" "${os}"

    # Kernel version
    local kernel=""
    if command -v uname >/dev/null 2>&1; then
        kernel=$(uname -r 2>/dev/null || echo "unknown")
    fi
    print_kv "KERNEL" "${kernel}"

    # Architecture
    local arch=""
    if command -v uname >/dev/null 2>&1; then
        arch=$(uname -m 2>/dev/null || echo "unknown")
    fi
    print_kv "ARCH" "${arch}"

    # Uptime
    local uptime=""
    if [ -f /proc/uptime ]; then
        local uptime_sec=$(awk '{print int($1)}' /proc/uptime)
        uptime=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "unknown")
    fi
    print_kv "UPTIME" "${uptime}"

    # Last boot time
    local last_boot=""
    if command -v uptime >/dev/null 2>&1; then
        last_boot=$(uptime -s 2>/dev/null || echo "unknown")
    fi
    print_kv "LAST_BOOT_TIME" "${last_boot}"

    # CPU model
    local cpu_model=""
    if [ -f /proc/cpuinfo ]; then
        cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[[:space:]]*//')
    fi
    [ -z "${cpu_model}" ] && cpu_model="unknown"
main "$@"
