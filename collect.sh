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
        ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1)
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
    print_kv "CPU_MODEL" "${cpu_model}"

    # CPU cores
    local cpu_cores=0
    if [ -f /proc/cpuinfo ]; then
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo || echo "0")
    fi
    print_kv "CPU_CORES" "${cpu_cores}"

    # CPU sockets
    local cpu_sockets=0
    if [ -f /proc/cpuinfo ]; then
        cpu_sockets=$(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l || echo "1")
    fi
    [ "${cpu_sockets}" -eq 0 ] && cpu_sockets=1
    print_kv "CPU_SOCKETS" "${cpu_sockets}"

    # CPU frequency (MHz)
    local cpu_freq=0
    if [ -f /proc/cpuinfo ]; then
        cpu_freq=$(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | awk '{print $4}' || echo "0")
    fi
    print_kv "CPU_FREQ" "${cpu_freq}.000"

    # Virtualization type
    local virt_type=""
    if [ -f /proc/cpuinfo ]; then
        if grep -qi "hypervisor" /proc/cpuinfo; then
            virt_type="VMware"
        elif grep -qi "QEMU" /proc/cpuinfo; then
            virt_type="KVM/QEMU"
        elif grep -qi "Xen" /proc/cpuinfo; then
            virt_type="Xen"
        else
            virt_type="Physical"
        fi
    fi
    print_kv "VIRTUAL_TYPE" "${virt_type}"
}

# Main collection function
main() {
    # Module 1: System Information
    collect_system_info
    echo "---"

    # Module 2: Basic Resources
    collect_basic_resources
    echo "---"

    # Module 3: Network Status
    collect_network_status
    echo "---"

    # Module 4: Process and Services
    collect_process_services
    echo "---"

    # Module 5: Environment Information
    collect_environment_info
}

# Execute main function
main "$@"
