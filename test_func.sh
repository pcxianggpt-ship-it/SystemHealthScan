#!/bin/bash
set -euo pipefail

# Copy the collect_system_info function from collect.sh
collect_system_info() {
    # Hostname
    local hostname=""
    if command -v hostname >/dev/null 2>&1; then
        hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    fi
    echo "HOSTNAME=${hostname}"

    # Short hostname
    local uname_n=""
    if command -v uname >/dev/null 2>&1; then
        uname_n=$(uname -n 2>/dev/null || echo "unknown")
    fi
    echo "UNAME_N=${uname_n}"

    # Primary IP address
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1)
    elif command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [ -z "${ip}" ] && ip="unknown"
    echo "IP=${ip}"

    # Check time
    echo "CHECK_TIME=$(date '+%Y-%m-%d_%H:%M:%S')"

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
    echo "OS=${os}"

    # Kernel version
    local kernel=""
    if command -v uname >/dev/null 2>&1; then
        kernel=$(uname -r 2>/dev/null || echo "unknown")
    fi
    echo "KERNEL=${kernel}"

    # Architecture
    local arch=""
    if command -v uname >/dev/null 2>&1; then
        arch=$(uname -m 2>/dev/null || echo "unknown")
    fi
    echo "ARCH=${arch}"

    # Uptime
    local uptime=""
    if [ -f /proc/uptime ]; then
        local uptime_sec=$(awk '{print int($1)}' /proc/uptime)
        uptime=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "unknown")
    fi
    echo "UPTIME=${uptime}"

    # Last boot time
    local last_boot=""
    if command -v uptime >/dev/null 2>&1; then
        last_boot=$(uptime -s 2>/dev/null || echo "unknown")
    fi
    echo "LAST_BOOT_TIME=${last_boot}"

    # CPU model
    local cpu_model=""
    if [ -f /proc/cpuinfo ]; then
        cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[[:space:]]*//')
    fi
    [ -z "${cpu_model}" ] && cpu_model="unknown"
    echo "CPU_MODEL=${cpu_model}"

    # CPU cores
    local cpu_cores=0
    if [ -f /proc/cpuinfo ]; then
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo || echo "0")
    fi
    echo "CPU_CORES=${cpu_cores}"

    # CPU sockets
    local cpu_sockets=0
    if [ -f /proc/cpuinfo ]; then
        cpu_sockets=$(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l || echo "1")
    fi
    [ "${cpu_sockets}" -eq 0 ] && cpu_sockets=1
    echo "CPU_SOCKETS=${cpu_sockets}"

    # CPU frequency (MHz)
    local cpu_freq=0
    if [ -f /proc/cpuinfo ]; then
        cpu_freq=$(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | awk '{print $4}' || echo "0")
    fi
    echo "CPU_FREQ=${cpu_freq}.000"

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
    echo "VIRTUAL_TYPE=${virt_type}"
}

collect_system_info
