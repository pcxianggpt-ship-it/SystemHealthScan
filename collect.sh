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

# Module 2: Basic Resources
collect_basic_resources() {
    # CPU usage (percentage)
    local cpu_usage=0
    if command -v mpstat >/dev/null 2>&1; then
        cpu_usage=$(mpstat 1 1 2>/dev/null | awk '/Average:/ {print 100-$NF}' || echo "0")
    elif [ -f /proc/stat ]; then
        local prev_idle=$(awk '/^cpu /{print $5}' /proc/stat)
        sleep 1
        local curr_idle=$(awk '/^cpu /{print $5}' /proc/stat)
        # Simplified calculation - would need more for accurate CPU usage
        cpu_usage="N/A"
    else
        cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
    fi
    print_kv "CPU_USAGE" "${cpu_usage}"

    # Load average
    local load_1=0 load_5=0 load_15=0
    if [ -f /proc/loadavg ]; then
        read -r load_1 load_5 load_15 _ < <(cat /proc/loadavg)
    fi
    print_kv "CPU_LOAD_1" "${load_1}"
    print_kv "CPU_LOAD_5" "${load_5}"
    print_kv "CPU_LOAD_15" "${load_15}"

    # CPU Top 5 processes (by CPU usage)
    local cpu_top5=""
    if command -v ps >/dev/null 2>&1; then
        cpu_top5=$(ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{print "PID:"$2":"$11":"$3"%"}' | tr '\n' '|' | sed 's/|$//')
    fi
    print_kv "CPU_TOP5" "${cpu_top5}"

    # Memory information
    local mem_total=0 mem_used=0 mem_available=0 mem_buffers=0 mem_cached=0 mem_percent=0

    if command -v free >/dev/null 2>&1; then
        local mem_output
        mem_output=$(free -m 2>/dev/null | grep "^Mem:")

        if [ -n "${mem_output}" ]; then
            mem_total=$(echo "${mem_output}" | awk '{print $2}')
            mem_used=$(echo "${mem_output}" | awk '{print $3}')
            mem_available=$(echo "${mem_output}" | awk '{print $7}')

            # Get buffers and cached from /proc/meminfo
            if [ -f /proc/meminfo ]; then
                mem_buffers=$(awk '/^Buffers:/ {print $2}' /proc/meminfo)
                mem_cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
            fi

            # Calculate percentage using actual used memory (excluding cache/buffers)
            if [ "${mem_total}" -gt 0 ]; then
                mem_percent=$(awk "BEGIN {printf \"%.2f\", ((${mem_used} - ${mem_buffers} - ${mem_cached}) / ${mem_total}) * 100}")
            fi
        fi
    fi

    print_kv "MEM_TOTAL" "${mem_total}"
    print_kv "MEM_USED" "${mem_used}"
    print_kv "MEM_AVAILABLE" "${mem_available}"
    print_kv "MEM_BUFFERS" "${mem_buffers}"
    print_kv "MEM_CACHED" "${mem_cached}"
    print_kv "MEM_PERCENT" "${mem_percent}"

    # Swap information
    local swap_total=0 swap_used=0
    if command -v free >/dev/null 2>&1; then
        local swap_output
        swap_output=$(free -m 2>/dev/null | grep "^Swap:")

        if [ -n "${swap_output}" ]; then
            swap_total=$(echo "${swap_output}" | awk '{print $2}')
            swap_used=$(echo "${swap_output}" | awk '{print $3}')
        fi
    fi

    print_kv "SWAP_TOTAL" "${swap_total}"
    print_kv "SWAP_USED" "${swap_used}"

    # Disk usage
    local disk_info=""
    if command -v df >/dev/null 2>&1; then
        disk_info=$(df -h 2>/dev/null | grep -vE "^Filesystem|tmpfs|cdrom|overlay" | awk '{
            split($5, pct, "%");
            printf "%s:%s:%s:%s|", $1, $2, $3, $5
        }' | sed 's/|$//')
    fi
    print_kv "DISK_" "${disk_info}"

    # Inode usage
    local inode_info=""
    if command -v df >/dev/null 2>&1; then
        inode_info=$(df -i 2>/dev/null | grep -vE "^Filesystem|tmpfs|cdrom|overlay" | awk '{
            printf "%s:%s/%s:%s%%|", $1, $3, $2, $5
        }' | sed 's/|$//')
    fi
    print_kv "INODE_" "${inode_info}"

    # IO statistics
    local io_util=0 io_wait=0 iops_read=0 iops_write=0
    if [ -f /proc/diskstats ]; then
        local sda_read sda_write
        sda_read=$(awk '/sda /{print $4}' /proc/diskstats 2>/dev/null || echo "0")
        sda_write=$(awk '/sda /{print $8}' /proc/diskstats 2>/dev/null || echo "0")
        # IO stats need iostat for accurate readings
        io_util="N/A"
        io_wait=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $10}' | cut -d'%' -f1 || echo "0")
    elif command -v iostat >/dev/null 2>&1; then
        local iostat_output
        iostat_output=$(iostat -x 1 1 2>/dev/null | tail -n +4 | head -1)
        io_util=$(echo "${iostat_output}" | awk '{print $14}')
        io_wait=$(echo "${iostat_output}" | awk '{print $5}')
        iops_read=$(echo "${iostat_output}" | awk '{print $4}')
        iops_write=$(echo "${iostat_output}" | awk '{print $5}')
    fi

    print_kv "IO_UTIL_sda" "${io_util}"
    print_kv "IO_WAIT" "${io_wait}"
    print_kv "IOPS_READ_sda" "${iops_read}"
    print_kv "IOPS_WRITE_sda" "${iops_write}"
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
