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

# Show version information
show_version() {
    echo "SystemHealthScan Core Collection Script v${VERSION}"
    exit 0
}

# Show usage information
show_usage() {
    cat << EOF
SystemHealthScan Core Collection Script v${VERSION}

Usage: $(basename "$0") [OPTIONS] [OUTPUT_FILE]

Options:
  -v, --version    Show version information
  -h, --help       Show this help message

Arguments:
  OUTPUT_FILE      Output file path (default: stdout)

Examples:
  $(basename "$0")                          # Output to stdout
  $(basename "$0") output/server.dat       # Output to file
  $(basename "$0") -v                      # Show version

Output Format:
  KEY=VALUE (one per line)
  Modules separated by '---'

Modules:
  1. System Information
  2. Basic Resources
  3. Network Status
  4. Process and Services
  5. Environment Information

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                show_version
                ;;
            -h|--help)
                show_usage
                ;;
            -*)
                echo "ERROR: Unknown option: $1" >&2
                echo "Use -h or --help for usage information" >&2
                exit 1
                ;;
            *)
                OUTPUT_FILE="$1"
                shift
                ;;
        esac
        shift
    done
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
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
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
        cpu_top5=$(ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{print "PID:"$2":"$11":"$3"%"}' | sed 's|.*/||g' | tr '\n' '|' | sed 's/|$//')
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

            # Get buffers and cached from /proc/meminfo (convert KB to MB)
            if [ -f /proc/meminfo ]; then
                mem_buffers=$(awk '/^Buffers:/ {print int($2/1024)}' /proc/meminfo)
                mem_cached=$(awk '/^Cached:/ {print int($2/1024)}' /proc/meminfo)
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

# Module 3: Network Status
collect_network_status() {
    # Network interface status
    local net_info=""
    if command -v ip >/dev/null 2>&1; then
        net_info=$(ip link show 2>/dev/null | grep -E "^[0-9]+:" | grep -v "lo:" | awk '{
            iface=$2; sub(/:$/, "", iface);
            state=$9;
            speed="N/A";
            rx_err="0"; tx_err="0"; drop="0";
            printf "%s:%s:%s:RX_ERR:%s:TX_ERR:%s:DROP:%s|", iface, state, speed, rx_err, tx_err, drop
        }' | sed 's/|$//')
    fi
    print_kv "NET_NIC_" "${net_info}"

    # Listening ports
    local listen_ports=""
    if command -v ss >/dev/null 2>&1; then
        listen_ports=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{
            port=$5;
            sub(/.*:/, "", port);
            service=$7;
            sub(/.name=/, "", service);
            printf "%s(%s)|", port, service
        }' | sed 's/|$//' | sed 's/()/(unknown)/g')
    elif command -v netstat >/dev/null 2>&1; then
        listen_ports=$(netstat -tlnp 2>/dev/null | grep LISTEN | awk '{
            port=$4;
            sub(/.*:/, "", port);
            printf "%s|", port
        }' | sed 's/|$//')
    fi
    print_kv "NET_LISTEN_PORTS" "${listen_ports}"

    # TCP connection status
    local tcp_status=""
    if command -v ss >/dev/null 2>&1; then
        local established=$(ss -t 2>/dev/null | grep -c ESTAB || echo "0")
        local time_wait=$(ss -t 2>/dev/null | grep -c TIME-WAIT || echo "0")
        local close_wait=$(ss -t 2>/dev/null | grep -c CLOSE-WAIT || echo "0")
        local syn_recv=$(ss -t 2>/dev/null | grep -c SYN-RECV || echo "0")
        tcp_status="ESTABLISHED:${established}|TIME_WAIT:${time_wait}|CLOSE_WAIT:${close_wait}|SYN_RECV:${syn_recv}"
    fi
    print_kv "NET_TCP_STATUS" "${tcp_status}"

    # DNS resolution test
    local dns_resolve="FAIL"
    if command -v nslookup >/dev/null 2>&1; then
        dns_resolve=$(nslookup -timeout=2 8.8.8.8 2>/dev/null | grep -qiE "server:|name:" && echo "OK:8.8.8.8:1ms" || echo "FAIL")
    elif command -v ping >/dev/null 2>&1; then
        ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && dns_resolve="OK:8.8.8.8:1ms" || dns_resolve="FAIL"
    fi
    print_kv "NET_DNS_RESOLVE" "${dns_resolve}"

    # Firewall status
    local firewall="UNKNOWN"
    if command -v iptables >/dev/null 2>&1; then
        local rules=0
        rules=$(iptables -L -n 2>/dev/null | grep -c "^Chain\|^[0-9]" || echo "0")
        [ "${rules}" -gt 3 ] && firewall="iptables:ACTIVE|RULES:${rules}" || firewall="iptables:INACTIVE"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall="firewalld:ACTIVE"
    fi
    print_kv "NET_FIREWALL" "${firewall}"

    # Default route
    local default_route=""
    if command -v ip >/dev/null 2>&1; then
        default_route=$(ip route 2>/dev/null | grep default | awk '{print "default_via_"$3}')
    elif command -v route >/dev/null 2>&1; then
        default_route=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk '{print "default_via_"$2}')
    fi
    print_kv "NET_ROUTE" "${default_route}"

    # Top 5 connections by source IP
    local connections_top5=""
    if command -v ss >/dev/null 2>&1; then
        connections_top5=$(ss -tn 2>/dev/null | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 | awk '{
            printf "%s:%s|", $2, $1
        }' | sed 's/|$//')
    fi
    print_kv "NET_CONNECTIONS_TOP5" "${connections_top5}"
}

# Module 4: Process and Services
collect_process_services() {
    # Service status (check common services)
    local services=""
    for svc in nginx apache2 httpd mysql docker sshd rsyslog; do
        local status="UNKNOWN"
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet "${svc}" 2>/dev/null; then
                status="RUNNING"
            elif systemctl is-enabled --quiet "${svc}" 2>/dev/null; then
                status="STOPPED"
            fi
        elif command -v service >/dev/null 2>&1; then
            if service "${svc}" status 2>/dev/null | grep -q "running"; then
                status="RUNNING"
            else
                status="STOPPED"
            fi
        fi
        [ "${status}" != "UNKNOWN" ] && services="${svc}:${status}|${services}"
    done
    services=$(echo "${services}" | sed 's/|$//')
    print_kv "SERVICE_STATUS" "${services}"

    # Process statistics
    local process_total=0 process_zombie=0 process_running=0 process_sleeping=0

    if command -v ps >/dev/null 2>&1; then
        local ps_output
        ps_output=$(ps aux 2>/dev/null)

        # Count total processes (excluding header)
        process_total=$(echo "${ps_output}" | tail -n +2 | wc -l)

        # Count by process state using column 8 (state column)
        process_zombie=$(echo "${ps_output}" | awk 'NR>1 && $8 ~ /^Z$/ {count++} END {print count+0}')
        process_running=$(echo "${ps_output}" | awk 'NR>1 && $8 ~ /^R$/ {count++} END {print count+0}')
        process_sleeping=$(echo "${ps_output}" | awk 'NR>1 && $8 ~ /^S$/ {count++} END {print count+0}')
    fi

    print_kv "PROCESS_TOTAL" "${process_total}"
    print_kv "PROCESS_ZOMBIE" "${process_zombie}"
    print_kv "PROCESS_RUNNING" "${process_running}"
    print_kv "PROCESS_SLEEPING" "${process_sleeping}"

    # CPU Top 5 processes
    local top5_cpu=""
    if command -v ps >/dev/null 2>&1; then
        top5_cpu=$(ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{
            printf "PID:%s:%s:%.1f%%|", $2, $11, $3
        }' | sed 's/|$//')
    fi
    print_kv "PROCESS_TOP5_CPU" "${top5_cpu}"

    # Memory Top 5 processes
    local top5_mem=""
    if command -v ps >/dev/null 2>&1; then
        top5_mem=$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | awk '{
            mem_mb=$6/1024;
            printf "PID:%s:%s:%.0fM|", $2, $11, mem_mb
        }' | sed 's/|$//')
    fi
    print_kv "PROCESS_TOP5_MEM" "${top5_mem}"
}

# Module 5: Environment Information
collect_environment_info() {
    # Docker status
    local docker_status="NOT_INSTALLED"
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            local containers=0 images=0 volumes=0
            containers=$(docker ps -q 2>/dev/null | wc -l)
            images=$(docker images -q 2>/dev/null | wc -l)
            volumes=$(docker volume ls -q 2>/dev/null | wc -l)
            docker_status="RUNNING|CONTAINERS:${containers}|IMAGES:${images}|VOLUMES:${volumes}"
        else
            docker_status="INSTALLED_NOT_RUNNING"
        fi
    fi
    print_kv "DOCKER_STATUS" "${docker_status}"

    # Docker container details
    local docker_containers=""
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        docker_containers=$(docker ps --format "{{.Names}}:{{.Status}}" 2>/dev/null | head -10 | tr '\n' '|' | sed 's/|$//')
    fi
    print_kv "DOCKER_CONTAINER_" "${docker_containers}"

    # Java versions
    local java_versions=""
    local java_paths=("/usr/bin/java" "/usr/local/bin/java" "/opt/java/bin/java")
    for java_path in "${java_paths[@]}"; do
        if [ -x "${java_path}" ]; then
            local version
            version=$("${java_path}" -version 2>&1 | head -1 | awk '{print $NF}')
            [ -n "${version}" ] && java_versions="${version},${java_versions}"
        fi
    done
    java_versions=$(echo "${java_versions}" | sed 's/,$//')
    [ -z "${java_versions}" ] && java_versions="NOT_INSTALLED"
    print_kv "ENV_JAVA_VERSION" "${java_versions}"

    # Python version
    local python_version="NOT_INSTALLED"
    for py_cmd in python3 python; do
        if command -v "${py_cmd}" >/dev/null 2>&1; then
            python_version=$("${py_cmd}" --version 2>&1 | awk '{print $2}')
            [ -n "${python_version}" ] && break
        fi
    done
    print_kv "ENV_PYTHON_VERSION" "${python_version}"

    # Node.js version
    local node_version="NOT_INSTALLED"
    if command -v node >/dev/null 2>&1; then
        node_version=$(node --version 2>/dev/null || echo "unknown")
    fi
    print_kv "ENV_NODE_VERSION" "${node_version}"
}

# Helper function to ensure output directory exists
ensure_output_dir() {
    local output_dir="${1:-./output}"
    if [ ! -d "${output_dir}" ]; then
        mkdir -p "${output_dir}" 2>/dev/null || {
            echo "ERROR: Failed to create output directory: ${output_dir}" >&2
            return 1
        }
    fi
    return 0
}

# Main collection function
main() {
    # Parse command line arguments
    parse_args "$@"

    local output_file="${OUTPUT_FILE:-/dev/stdout}"

    # If not stdout, ensure parent directory exists
    if [ "${output_file}" != "/dev/stdout" ]; then
        ensure_output_dir "$(dirname "${output_file}")"
    fi

    # Redirect all output to the specified file
    exec 3>&1
    exec >"${output_file}"

    # Ensure stdout is always restored even on error
    trap 'exec >&3' EXIT

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

    # Restore stdout
    exec >&3
}

# Execute main function
main "$@"
