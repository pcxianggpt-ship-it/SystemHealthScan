#!/bin/bash
#
# Linux Server Health Check - Core Collection Script
# Output format: KEY=VALUE, one per line
#

set -euo pipefail

# Script version
VERSION="1.1.0"

# ANSI colors for output (optional, for debugging)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Helper function to print key-value pairs
print_kv() {
    local key="$1"
    local value="$2"
    # Only output if value is not empty to avoid invalid format lines
    if [ -n "${value}" ]; then
        echo "${key}=${value}"
    fi
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
  5. Java Process Details
  6. Middleware (Redis/Nacos/MySQL)
  7. System Security
  8. Crontab Analysis
  9. Logs and Alerts
  10. Environment Information

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
                ;;
        esac
        shift
    done
}

# =============================================================================
# Module 1: System Information
# =============================================================================
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
    local uptime_str=""
    if command -v uptime >/dev/null 2>&1; then
        uptime_str=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "unknown")
    fi
    print_kv "UPTIME" "${uptime_str}"

    # Last boot time
    local last_boot=""
    if command -v uptime >/dev/null 2>&1; then
        last_boot=$(uptime -s 2>/dev/null || echo "unknown")
    fi
    print_kv "LAST_BOOT_TIME" "${last_boot}"

    # CPU model
    local cpu_model=""
    if [ -f /proc/cpuinfo ]; then
        cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[[:space:]]*//')
    fi
    [ -z "${cpu_model}" ] && cpu_model="unknown"
    print_kv "CPU_MODEL" "${cpu_model}"

    # CPU cores
    local cpu_cores=0
    if [ -f /proc/cpuinfo ]; then
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "0")
    fi
    print_kv "CPU_CORES" "${cpu_cores}"

    # CPU sockets
    local cpu_sockets=0
    if [ -f /proc/cpuinfo ]; then
        cpu_sockets=$(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l || echo "1")
    fi
    [ "${cpu_sockets}" -eq 0 ] && cpu_sockets=1
    print_kv "CPU_SOCKETS" "${cpu_sockets}"

    # CPU frequency (MHz) - fix: avoid double decimal
    local cpu_freq=""
    if [ -f /proc/cpuinfo ]; then
        cpu_freq=$(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | awk '{printf "%.3f", $4}' || echo "")
    fi
    [ -z "${cpu_freq}" ] && cpu_freq="0.000"
    print_kv "CPU_FREQ" "${cpu_freq}"

    # Virtualization type
    local virt_type=""
    if [ -f /proc/cpuinfo ]; then
        if grep -qi "hypervisor" /proc/cpuinfo 2>/dev/null; then
            virt_type="VMware"
        elif grep -qi "QEMU" /proc/cpuinfo 2>/dev/null; then
            virt_type="KVM/QEMU"
        elif grep -qi "Xen" /proc/cpuinfo 2>/dev/null; then
            virt_type="Xen"
        else
            virt_type="Physical"
        fi
    fi
    print_kv "VIRTUAL_TYPE" "${virt_type}"
}

# =============================================================================
# Module 2: Basic Resources
# =============================================================================
collect_basic_resources() {
    # CPU usage (percentage) - use /proc/stat for accurate reading
    local cpu_usage="N/A"
    if [ -f /proc/stat ]; then
        local prev_line curr_line prev_idle prev_total curr_idle curr_total diff_idle diff_total
        prev_line=$(head -1 /proc/stat)
        sleep 1
        curr_line=$(head -1 /proc/stat)

        prev_idle=$(echo "${prev_line}" | awk '{print $5}')
        prev_total=$(echo "${prev_line}" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

        curr_idle=$(echo "${curr_line}" | awk '{print $5}')
        curr_total=$(echo "${curr_line}" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

        diff_idle=$((curr_idle - prev_idle))
        diff_total=$((curr_total - prev_total))

        if [ "${diff_total}" -gt 0 ]; then
            cpu_usage=$(awk "BEGIN {printf \"%.1f\", (1 - ${diff_idle}/${diff_total}) * 100}")
        fi
    elif command -v mpstat >/dev/null 2>&1; then
        cpu_usage=$(mpstat 1 1 2>/dev/null | awk '/Average:/ {printf "%.1f", 100-$NF}' || echo "N/A")
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
        cpu_top5=$(ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{
            cmd=$11; sub(/.*\//, "", cmd);
            printf "PID:%s:%s:%s%%|", $2, cmd, $3
        }' | sed 's/|$//' || true)
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
                local real_used=$((mem_used - mem_buffers - mem_cached))
                [ "${real_used}" -lt 0 ] && real_used=0
                mem_percent=$(awk "BEGIN {printf \"%.2f\", (${real_used} / ${mem_total}) * 100}")
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

    # Disk usage - fix: use $6 (mount point) for meaningful output
    local disk_info=""
    if command -v df >/dev/null 2>&1; then
        disk_info=$(df -h 2>/dev/null | grep -vE "^Filesystem|tmpfs|cdrom|overlay|udev|devtmpfs" | awk '
        NF >= 6 {
            printf "%s:%s:%s:%s|", $6, $2, $3, $5
        }' | sed 's/|$//')
    fi
    print_kv "DISK_" "${disk_info}"

    # Inode usage
    local inode_info=""
    if command -v df >/dev/null 2>&1; then
        inode_info=$(df -i 2>/dev/null | grep -vE "^Filesystem|tmpfs|cdrom|overlay|udev|devtmpfs" | awk '
        NF >= 6 {
            printf "%s:%s/%s:%s|", $6, $3, $2, $5
        }' | sed 's/|$//')
    fi
    print_kv "INODE_" "${inode_info}"

    # IO statistics
    local io_util="N/A" io_wait="0" iops_read="0" iops_write="0"
    if command -v iostat >/dev/null 2>&1; then
        local iostat_output
        iostat_output=$(iostat -x 1 1 2>/dev/null | awk '/^Device/,0' | tail -n +2 | head -1 || true)
        if [ -n "${iostat_output}" ]; then
            io_util=$(echo "${iostat_output}" | awk '{print $14}')
            iops_read=$(echo "${iostat_output}" | awk '{print $4}')
            iops_write=$(echo "${iostat_output}" | awk '{print $5}')
        fi
    fi
    # Get iowait from /proc/stat
    if [ -f /proc/stat ]; then
        io_wait=$(awk '/^cpu /{total=0; for(i=2;i<=NF;i++) total+=$i; printf "%.1f", $6/total*100}' /proc/stat)
    fi

    print_kv "IO_UTIL_sda" "${io_util}"
    print_kv "IO_WAIT" "${io_wait}"
    print_kv "IOPS_READ_sda" "${iops_read}"
    print_kv "IOPS_WRITE_sda" "${iops_write}"
}

# =============================================================================
# Module 3: Network Status
# =============================================================================
collect_network_status() {
    # Network interface status - fix: parse ip output properly
    local net_info=""
    if command -v ip >/dev/null 2>&1; then
        net_info=$(ip -o link show 2>/dev/null | grep -v "lo:" | awk '{
            iface=$2; sub(/:$/, "", iface);
            state=$9;
            speed="N/A";
            printf "%s:%s:%s|", iface, state, speed
        }' | sed 's/|$//')
    fi
    print_kv "NET_NIC_" "${net_info}"

    # Listening ports
    local listen_ports=""
    if command -v ss >/dev/null 2>&1; then
        # Extract port from local address column ($4) and process name
        listen_ports=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{
            # Local address is $4, format: IP:PORT or IP%iface:PORT
            local_addr=$4;
            port=local_addr;
            sub(/^.*:/, "", port);
            # Process info from $6+ (users column)
            proc="unknown";
            for(i=6;i<=NF;i++) {
                if($i ~ /users/) {
                    match($i, /"([^"]+)"/, arr);
                    if(arr[1] != "") proc=arr[1];
                }
            }
            printf "%s(%s)|", port, proc
        }' 2>/dev/null | sed 's/|$//' || true)
    elif command -v netstat >/dev/null 2>&1; then
        listen_ports=$(netstat -tlnp 2>/dev/null | grep LISTEN | awk '{
            port=$4; sub(/.*:/, "", port);
            printf "%s|", port
        }' | sed 's/|$//' || true)
    fi
    print_kv "NET_LISTEN_PORTS" "${listen_ports}"

    # TCP connection status
    local tcp_status=""
    if command -v ss >/dev/null 2>&1; then
        local established=0 time_wait=0 close_wait=0 syn_recv=0
        established=$(ss -t 2>/dev/null | grep -c "ESTAB" 2>/dev/null) || established=0
        time_wait=$(ss -t 2>/dev/null | grep -c "TIME-WAIT" 2>/dev/null) || time_wait=0
        close_wait=$(ss -t 2>/dev/null | grep -c "CLOSE-WAIT" 2>/dev/null) || close_wait=0
        syn_recv=$(ss -t 2>/dev/null | grep -c "SYN-RECV" 2>/dev/null) || syn_recv=0
        tcp_status="ESTABLISHED:${established}|TIME_WAIT:${time_wait}|CLOSE_WAIT:${close_wait}|SYN_RECV:${syn_recv}"
    fi
    print_kv "NET_TCP_STATUS" "${tcp_status}"

    # DNS resolution test
    local dns_resolve="FAIL"
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup -timeout=2 baidu.com >/dev/null 2>&1; then
            dns_resolve="OK:baidu.com:1ms"
        fi
    elif command -v ping >/dev/null 2>&1; then
        if ping -c 1 -W 2 baidu.com >/dev/null 2>&1; then
            dns_resolve="OK:baidu.com:1ms"
        fi
    fi
    print_kv "NET_DNS_RESOLVE" "${dns_resolve}"

    # Firewall status
    local firewall="UNKNOWN"
    if command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            local rules=0
            rules=$(firewall-cmd --list-all 2>/dev/null | wc -l || echo "0")
            firewall="firewalld:ACTIVE|RULES:${rules}"
        else
            firewall="firewalld:INACTIVE"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        local rules=0
        rules=$(iptables -L -n 2>/dev/null | grep -c "^Chain\|^[0-9]" || echo "0")
        if [ "${rules}" -gt 3 ]; then
            firewall="iptables:ACTIVE|RULES:${rules}"
        else
            firewall="iptables:INACTIVE"
        fi
    elif command -v ufw >/dev/null 2>&1; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1 || echo "")
        if echo "${ufw_status}" | grep -q "active"; then
            firewall="ufw:ACTIVE"
        else
            firewall="ufw:INACTIVE"
        fi
    fi
    print_kv "NET_FIREWALL" "${firewall}"

    # Default route
    local default_route=""
    if command -v ip >/dev/null 2>&1; then
        default_route=$(ip route 2>/dev/null | grep default | awk '{print "default_via_"$3}' || true)
    elif command -v route >/dev/null 2>&1; then
        default_route=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk '{print "default_via_"$2}' || true)
    fi
    print_kv "NET_ROUTE" "${default_route}"

    # Top 5 connections by source IP
    local connections_top5=""
    if command -v ss >/dev/null 2>&1; then
        connections_top5=$(ss -tn 2>/dev/null | awk 'NR>1{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 | awk '{
            printf "%s:%s|", $2, $1
        }' | sed 's/|$//')
    fi
    print_kv "NET_CONNECTIONS_TOP5" "${connections_top5}"
}

# =============================================================================
# Module 4: Process and Services
# =============================================================================
collect_process_services() {
    # Service status (check common services)
    local services=""
    for svc in nginx apache2 httpd mysql docker sshd rsyslog redis-server mongod; do
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
        ps_output=$(ps -eo s 2>/dev/null)

        process_total=$(echo "${ps_output}" | tail -n +2 | wc -l)
        process_zombie=$(echo "${ps_output}" | grep -c "Z" 2>/dev/null) || process_zombie=0
        process_running=$(echo "${ps_output}" | grep -c "R" 2>/dev/null) || process_running=0
        process_sleeping=$(echo "${ps_output}" | grep -c "S" 2>/dev/null) || process_sleeping=0
    fi

    print_kv "PROCESS_TOTAL" "${process_total}"
    print_kv "PROCESS_ZOMBIE" "${process_zombie}"
    print_kv "PROCESS_RUNNING" "${process_running}"
    print_kv "PROCESS_SLEEPING" "${process_sleeping}"

    # CPU Top 5 processes
    local top5_cpu=""
    if command -v ps >/dev/null 2>&1; then
        top5_cpu=$(ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{
            cmd=$11; sub(/.*\//, "", cmd);
            printf "PID:%s:%s:%.1f%%|", $2, cmd, $3
        }' | sed 's/|$//' || true)
    fi
    print_kv "PROCESS_TOP5_CPU" "${top5_cpu}"

    # Memory Top 5 processes
    local top5_mem=""
    if command -v ps >/dev/null 2>&1; then
        top5_mem=$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | awk '{
            mem_mb=$6/1024;
            cmd=$11; sub(/.*\//, "", cmd);
            printf "PID:%s:%s:%.0fM|", $2, cmd, mem_mb
        }' | sed 's/|$//' || true)
    fi
    print_kv "PROCESS_TOP5_MEM" "${top5_mem}"
}

# =============================================================================
# Module 5: Java Process Details
# =============================================================================
collect_java_processes() {
    # Find Java processes
    local java_pids=()
    if command -v pgrep >/dev/null 2>&1; then
        while IFS= read -r pid; do
            [ -n "${pid}" ] && java_pids+=("${pid}")
        done < <(pgrep -f "java" 2>/dev/null || true)
    fi

    local java_count=${#java_pids[@]}
    print_kv "PROCESS_JAVA_COUNT" "${java_count}"

    local idx=0
    for pid in "${java_pids[@]}"; do
        idx=$((idx + 1))

        # Skip if process disappeared
        [ -d "/proc/${pid}" ] || continue

        # Basic info: USER, PID, START, RUNTIME, CPU, MEM, PORT
        local user="" start_time="" runtime="" cpu_pct="" mem_mb="" mem_pct="" ports=""
        user=$(ps -o user= -p "${pid}" 2>/dev/null || echo "unknown")
        start_time=$(ps -o lstart= -p "${pid}" 2>/dev/null || echo "unknown")
        runtime=$(ps -o etime= -p "${pid}" 2>/dev/null | tr -d ' ' || echo "unknown")
        cpu_pct=$(ps -o %cpu= -p "${pid}" 2>/dev/null || echo "0")
        mem_mb=$(ps -o rss= -p "${pid}" 2>/dev/null | awk '{printf "%.0f", $1/1024}' || echo "0")
        mem_pct=$(ps -o %mem= -p "${pid}" 2>/dev/null || echo "0")

        # Listening ports for this PID
        if command -v ss >/dev/null 2>&1; then
            ports=$(ss -tlnp 2>/dev/null | grep "pid=${pid}" | awk '{
                sub(/.*:/, "", $5); printf "%s,", $5
            }' | sed 's/,$//' || true)
        fi
        [ -z "${ports}" ] && ports="N/A"

        print_kv "JAVA_PS_${idx}" "USER:${user}|PID:${pid}|START:${start_time}|RUNTIME:${runtime}|CPU:${cpu_pct}%|MEM:${mem_mb}M(${mem_pct}%)|PORT:${ports}"

        # Full command line
        local cmdline=""
        if [ -f "/proc/${pid}/cmdline" ]; then
            cmdline=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)
        fi
        [ -z "${cmdline}" ] && cmdline=$(ps -o args= -p "${pid}" 2>/dev/null || echo "unknown")
        print_kv "JAVA_CMD_${idx}" "${cmdline}"

        # Working directory
        local cwd=""
        if [ -L "/proc/${pid}/cwd" ]; then
            cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null || echo "unknown")
        fi
        print_kv "JAVA_CWD_${idx}" "${cwd}"

        # User
        print_kv "JAVA_USER_${idx}" "${user}"

        # JVM Xms/Xmx from command line
        local xms="" xmx=""
        xms=$(echo "${cmdline}" | grep -oP '\-Xms\S+' | head -1 || true)
        xmx=$(echo "${cmdline}" | grep -oP '\-Xmx\S+' | head -1 || true)
        xms=${xms#-Xms}
        xmx=${xmx#-Xmx}
        [ -z "${xms}" ] && xms="default"
        [ -z "${xmx}" ] && xmx="default"
        print_kv "JAVA_JVM_XMS_XMX_${idx}" "Xms:${xms}:Xmx:${xmx}"

        # GC stats via jstat or jcmd
        local gc_info="N/A"
        local gc_detail="N/A"
        if command -v jstat >/dev/null 2>&1; then
            local gc_output
            gc_output=$(jstat -gc "${pid}" 2>/dev/null || true)
            if [ -n "${gc_output}" ]; then
                # Parse jstat -gc output
                local old_gc_count young_gc_count old_gc_time young_gc_time
                old_gc_count=$(echo "${gc_output}" | awk 'NR==2{print $13}')
                young_gc_count=$(echo "${gc_output}" | awk 'NR==2{print $12}')
                old_gc_time=$(echo "${gc_output}" | awk 'NR==2{print $15}')
                young_gc_time=$(echo "${gc_output}" | awk 'NR==2{print $14}')
                gc_info="OldGC:count:${old_gc_count:-0}:time:${old_gc_time:-0}ms|YoungGC:count:${young_gc_count:-0}:time:${young_gc_time:-0}ms"
            fi

            # GC heap info
            local gc_heap
            gc_heap=$(jstat -gcutil "${pid}" 2>/dev/null || true)
            if [ -n "${gc_heap}" ]; then
                local old_pct eden_pct survivor_pct
                old_pct=$(echo "${gc_heap}" | awk 'NR==2{print $3}')
                eden_pct=$(echo "${gc_heap}" | awk 'NR==2{print $1}')
                survivor_pct=$(echo "${gc_heap}" | awk 'NR==2{print $2}')
                gc_detail="OldGen:${old_pct:-0}%|Eden:${eden_pct:-0}%|Survivor:${survivor_pct:-0}%"
            fi
        elif command -v jcmd >/dev/null 2>&1; then
            local jcmd_output
            jcmd_output=$(jcmd "${pid}" GC.heap_info 2>/dev/null || true)
            if [ -n "${jcmd_output}" ]; then
                gc_detail=$(echo "${jcmd_output}" | tr '\n' '|' | sed 's/|$//')
            fi
        fi
        print_kv "JAVA_JVM_GC_${idx}" "${gc_info}"
        print_kv "JAVA_JVM_GC_DETAIL_${idx}" "${gc_detail}"

        # OOM parameters
        local oom_param=""
        if echo "${cmdline}" | grep -q "HeapDumpOnOutOfMemoryError"; then
            oom_param=$(echo "${cmdline}" | grep -oP '\-XX:\+HeapDumpOnOutOfMemoryError|\-XX:HeapDumpPath=\S+' | tr '\n' '|' | sed 's/|$//')
        fi
        [ -z "${oom_param}" ] && oom_param="NOT_CONFIGURED"
        print_kv "JAVA_JVM_OOM_PARAM_${idx}" "${oom_param}"

        # OOM Dump file check
        local oom_dump="NONE"
        local dump_path=""
        dump_path=$(echo "${cmdline}" | grep -oP '(?<=HeapDumpPath=)\S+' || true)
        if [ -n "${dump_path}" ] && [ -d "${dump_path}" ]; then
            local dump_count=0
            dump_count=$(find "${dump_path}" -name "*.hprof" -type f 2>/dev/null | wc -l || echo "0")
            if [ "${dump_count}" -gt 0 ]; then
                local dump_files
                dump_files=$(find "${dump_path}" -name "*.hprof" -type f -printf "%f:%TY-%Tm-%Td:%s\n" 2>/dev/null | head -5 | awk -v size_div=1073741824 '{
                    split($0, a, ":");
                    size=$3/size_div;
                    printf "%s/%s:%.1fG|", a[1], a[2], size
                }' | sed 's/|$//')
                oom_dump="FOUND:${dump_count}|${dump_files}"
            else
                oom_dump="NO_DUMP_FILES"
            fi
        fi
        print_kv "JAVA_JVM_OOM_DUMP_${idx}" "${oom_dump}"

        # Log path detection
        local log_path=""
        log_path=$(echo "${cmdline}" | grep -oP '(?<=-Dlog\.path=)\S+' || true)
        if [ -z "${log_path}" ]; then
            log_path=$(echo "${cmdline}" | grep -oP '(?<=-Dlogging\.file\.path=)\S+' || true)
        fi
        if [ -z "${log_path}" ] && [ -d "${cwd}/logs" ]; then
            log_path="${cwd}/logs"
        fi
        if [ -n "${log_path}" ]; then
            print_kv "JAVA_LOG_COLLECT_${idx}" "SOURCE:${log_path}"
        else
            print_kv "JAVA_LOG_COLLECT_${idx}" "SOURCE:NOT_FOUND"
        fi
    done
}

# =============================================================================
# Module 6: Middleware (Redis/Nacos/MySQL)
# =============================================================================
collect_middleware() {
    # --- Redis ---
    local redis_status="NOT_RUNNING"
    local redis_slowlog="" redis_replication="" redis_keyspace=""

    if pgrep -x "redis-server" >/dev/null 2>&1 || pgrep -f "redis" >/dev/null 2>&1; then
        if command -v redis-cli >/dev/null 2>&1; then
            local redis_info
            redis_info=$(redis-cli info 2>/dev/null || true)
            if [ -n "${redis_info}" ]; then
                local redis_version redis_memory redis_conn redis_dbsize
                redis_version=$(echo "${redis_info}" | grep "^redis_version:" | cut -d: -f2 | tr -d '\r')
                redis_memory=$(echo "${redis_info}" | grep "^used_memory_human:" | cut -d: -f2 | tr -d '\r')
                redis_conn=$(echo "${redis_info}" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
                redis_dbsize=$(redis-cli dbsize 2>/dev/null | awk '{print $2}' || echo "0")
                redis_status="RUNNING|VERSION:${redis_version}|MEMORY:${redis_memory}|CONN:${redis_conn}|DBSIZE:${redis_dbsize}"

                # Slowlog counts
                local slow_10=0 slow_50=0 slow_100=0
                if command -v redis-cli >/dev/null 2>&1; then
                    slow_10=$(redis-cli slowlog get 128 2>/dev/null | grep -cE "^\d+" || echo "0")
                fi
                redis_slowlog="10MS:${slow_10}|50MS:0|100MS:0"

                # Replication
                local redis_role
                redis_role=$(echo "${redis_info}" | grep "^role:" | cut -d: -f2 | tr -d '\r' || echo "unknown")
                if [ "${redis_role}" = "master" ]; then
                    local slave_count=0
                    slave_count=$(echo "${redis_info}" | grep -c "^slave[0-9]" || echo "0")
                    redis_replication="ROLE:MASTER|SLAVES:${slave_count}|LAG:0"
                elif [ "${redis_role}" = "slave" ]; then
                    local master_link=""
                    master_link=$(echo "${redis_info}" | grep "^master_link_status:" | cut -d: -f2 | tr -d '\r' || echo "unknown")
                    redis_replication="ROLE:SLAVE|MASTER_LINK:${master_link}"
                fi

                # Keyspace
                redis_keyspace=$(echo "${redis_info}" | grep "^db0:" | cut -d: -f2- | tr -d '\r' || echo "N/A")
            fi
        else
            redis_status="RUNNING|NO_CLIENT"
        fi
    fi
    print_kv "REDIS_STATUS" "${redis_status}"
    print_kv "REDIS_SLOWLOG_COUNT_10MS" "${redis_slowlog}"
    print_kv "REDIS_REPLICATION" "${redis_replication}"
    print_kv "REDIS_KEYSPACE" "${redis_keyspace}"

    # --- Nacos ---
    local nacos_status="NOT_RUNNING"
    if pgrep -f "nacos" >/dev/null 2>&1; then
        # Try to get nacos info via HTTP API
        local nacos_url="http://localhost:8848/nacos/v1/ns/service/list?pageNo=1&pageSize=1"
        local nacos_services=0
        if command -v curl >/dev/null 2>&1; then
            local nacos_resp
            nacos_resp=$(curl -s --connect-timeout 3 "${nacos_url}" 2>/dev/null || true)
            if [ -n "${nacos_resp}" ]; then
                nacos_services=$(echo "${nacos_resp}" | grep -oP '(?<="count":)\d+' || echo "0")
            fi
        fi
        nacos_status="RUNNING|SERVICES:${nacos_services}"
    fi
    print_kv "NACOS_STATUS" "${nacos_status}"

    # --- MySQL ---
    local mysql_status="NOT_RUNNING"
    local mysql_replication="" mysql_innodb_buffer=""

    if pgrep -x "mysqld" >/dev/null 2>&1 || pgrep -f "mysql" >/dev/null 2>&1; then
        if command -v mysql >/dev/null 2>&1; then
            local mysql_ver=""
            mysql_ver=$(mysql --version 2>/dev/null | awk '{print $5}' | tr -d ',' || echo "unknown")

            local mysql_conn=""
            mysql_conn=$(mysql -e "SHOW STATUS LIKE 'Threads_connected'" -sN 2>/dev/null | awk '{print $2}' || echo "0")

            local mysql_max_conn=""
            mysql_max_conn=$(mysql -e "SHOW VARIABLES LIKE 'max_connections'" -sN 2>/dev/null | awk '{print $2}' || echo "0")

            local slow_queries=""
            slow_queries=$(mysql -e "SHOW STATUS LIKE 'Slow_queries'" -sN 2>/dev/null | awk '{print $2}' || echo "0")

            local threads_running=""
            threads_running=$(mysql -e "SHOW STATUS LIKE 'Threads_running'" -sN 2>/dev/null | awk '{print $2}' || echo "0")

            mysql_status="RUNNING|VERSION:${mysql_ver}|CONNECTIONS:${mysql_conn}/${mysql_max_conn}|SLOW_QUERIES:${slow_queries}|THREADS_RUNNING:${threads_running}"

            # Replication
            local slave_status
            slave_status=$(mysql -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master" || true)
            if [ -n "${slave_status}" ]; then
                local io_running="" sql_running="" behind=""
                io_running=$(echo "${slave_status}" | grep "Slave_IO_Running" | awk '{print $2}')
                sql_running=$(echo "${slave_status}" | grep "Slave_SQL_Running" | awk '{print $2}')
                behind=$(echo "${slave_status}" | grep "Seconds_Behind_Master" | awk '{print $2}')
                if [ "${io_running}" = "Yes" ] && [ "${sql_running}" = "Yes" ]; then
                    mysql_replication="ROLE:SLAVE|SLAVE_STATUS:OK|BEHIND:${behind:-0}s"
                else
                    mysql_replication="ROLE:SLAVE|SLAVE_STATUS:ERROR|IO:${io_running}|SQL:${sql_running}"
                fi
            else
                mysql_replication="ROLE:MASTER|SLAVE_STATUS:N/A|BEHIND:0s"
            fi

            # InnoDB buffer pool
            local hit_rate=""
            hit_rate=$(mysql -e "SHOW STATUS LIKE 'Innodb_buffer_pool_read%'" -sN 2>/dev/null | awk '
            /read_requests/{req=$2}
            /reads/{reads=$2}
            END{
                if(req+0 > 0) printf "%.1f%%", (1-reads/req)*100;
                else print "N/A"
            }' || echo "N/A")
            mysql_innodb_buffer="HIT_RATE:${hit_rate}"
        else
            mysql_status="RUNNING|NO_CLIENT"
        fi
    fi
    print_kv "MYSQL_STATUS" "${mysql_status}"
    [ -z "${mysql_replication}" ] && mysql_replication="N/A"
    [ -z "${mysql_innodb_buffer}" ] && mysql_innodb_buffer="N/A"
    print_kv "MYSQL_REPLICATION" "${mysql_replication}"
    print_kv "MYSQL_INNODB_BUFFER" "${mysql_innodb_buffer}"
}

# =============================================================================
# Module 7: System Security
# =============================================================================
collect_security() {
    # SSH config
    local ssh_config="N/A"
    local sshd_config=""
    if [ -f /etc/ssh/sshd_config ]; then
        sshd_config="/etc/ssh/sshd_config"
    fi
    # Check include directory (Ubuntu 24.04+ uses Include)
    if [ -d /etc/ssh/sshd_config.d ]; then
        for inc in /etc/ssh/sshd_config.d/*.conf; do
            [ -f "${inc}" ] && sshd_config="${sshd_config} ${inc}"
        done
    fi
    if [ -n "${sshd_config}" ]; then
        local ssh_port ssh_root_login ssh_pass_auth ssh_empty_pw ssh_max_auth
        ssh_port=$(grep -hE "^\s*Port " ${sshd_config} 2>/dev/null | awk '{print $2}' | tail -1 || true)
        [ -z "${ssh_port}" ] && ssh_port="22"
        ssh_root_login=$(grep -hE "^\s*PermitRootLogin " ${sshd_config} 2>/dev/null | awk '{print $2}' | tail -1 || true)
        [ -z "${ssh_root_login}" ] && ssh_root_login="yes"
        ssh_pass_auth=$(grep -hE "^\s*PasswordAuthentication " ${sshd_config} 2>/dev/null | awk '{print $2}' | tail -1 || true)
        [ -z "${ssh_pass_auth}" ] && ssh_pass_auth="yes"
        ssh_empty_pw=$(grep -hE "^\s*PermitEmptyPasswords " ${sshd_config} 2>/dev/null | awk '{print $2}' | tail -1 || true)
        [ -z "${ssh_empty_pw}" ] && ssh_empty_pw="no"
        ssh_max_auth=$(grep -hE "^\s*MaxAuthTries " ${sshd_config} 2>/dev/null | awk '{print $2}' | tail -1 || true)
        [ -z "${ssh_max_auth}" ] && ssh_max_auth="6"
        ssh_config="PORT:${ssh_port}|ROOT_LOGIN:${ssh_root_login}|PASSWORD_AUTH:${ssh_pass_auth}|PERMIT_EMPTY:${ssh_empty_pw}|MAX_AUTH:${ssh_max_auth}"
    fi
    print_kv "SSH_CONFIG" "${ssh_config}"

    # SSH failed login today
    local ssh_failed="0"
    local ssh_failed_last=""
    if [ -f /var/log/auth.log ]; then
        local today
        today=$(date '+%b %e')
        local failed_count=0
        failed_count=$(grep "${today}" /var/log/auth.log 2>/dev/null | grep -c "Failed password" 2>/dev/null) || failed_count=0
        ssh_failed_last=$(grep "${today}" /var/log/auth.log 2>/dev/null | grep "Failed password" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i+1)}' || true)
        ssh_failed="${failed_count}|LAST_FROM:${ssh_failed_last:-none}"
    elif [ -f /var/log/secure ]; then
        local today
        today=$(date '+%b %e')
        local failed_count=0
        failed_count=$(grep "${today}" /var/log/secure 2>/dev/null | grep -c "Failed password" 2>/dev/null) || failed_count=0
        ssh_failed_last=$(grep "${today}" /var/log/secure 2>/dev/null | grep "Failed password" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i+1)}' || true)
        ssh_failed="${failed_count}|LAST_FROM:${ssh_failed_last:-none}"
    fi
    print_kv "SSH_FAILED_LOGIN_TODAY" "${ssh_failed}"

    # SSH trusted keys count
    local trusted_keys=0
    if [ -f /root/.ssh/authorized_keys ]; then
        trusted_keys=$(grep -cvE "^#|^$" /root/.ssh/authorized_keys 2>/dev/null) || trusted_keys=0
    fi
    print_kv "SSH_TRUSTED_KEYS" "${trusted_keys}"

    # User login today
    local user_login_today=""
    if command -v last >/dev/null 2>&1; then
        local today_str
        today_str=$(date '+%a %b %e')
        user_login_today=$(last 2>/dev/null | grep "${today_str}" | awk '{printf "%s|", $1}' | sed 's/|$//' || true)
    fi
    [ -z "${user_login_today}" ] && user_login_today="none"
    print_kv "USER_LOGIN_TODAY" "${user_login_today}"

    # Sudo usage today
    local sudo_today=0
    if [ -f /var/log/auth.log ]; then
        local today
        today=$(date '+%b %e')
        sudo_today=$(grep "${today}" /var/log/auth.log 2>/dev/null | grep -c "sudo" 2>/dev/null) || sudo_today=0
    elif [ -f /var/log/secure ]; then
        local today
        today=$(date '+%b %e')
        sudo_today=$(grep "${today}" /var/log/secure 2>/dev/null | grep -c "sudo" 2>/dev/null) || sudo_today=0
    fi
    print_kv "USER_SUDO_TODAY" "${sudo_today}"

    # Password expiry for key users
    local password_expire="N/A"
    if command -v chage >/dev/null 2>&1; then
        local expire_info=""
        for user in root $(awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd 2>/dev/null | head -5); do
            local expire_date
            expire_date=$(chage -l "${user}" 2>/dev/null | grep "Password expires" | cut -d: -f2 | tr -d ' ' || echo "never")
            expire_info="${user}:${expire_date}|${expire_info}"
        done
        password_expire=$(echo "${expire_info}" | sed 's/|$//')
    fi
    print_kv "USER_PASSWORD_EXPIRE" "${password_expire}"

    # Locked users
    local user_locked=0
    if command -v passwd >/dev/null 2>&1; then
        user_locked=$(passwd -S -a 2>/dev/null | grep -c "L" 2>/dev/null) || user_locked=0
    fi
    print_kv "USER_LOCKED" "${user_locked}"

    # SELinux status
    local selinux_status="N/A"
    if command -v getenforce >/dev/null 2>&1; then
        selinux_status=$(getenforce 2>/dev/null || echo "N/A")
    elif [ -f /etc/selinux/config ]; then
        selinux_status=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2 || echo "N/A")
    fi
    print_kv "SELINUX_STATUS" "${selinux_status}"

    # Fail2ban status
    local fail2ban_status="NOT_INSTALLED"
    if command -v fail2ban-client >/dev/null 2>&1; then
        if fail2ban-client status >/dev/null 2>&1; then
            local banned=0
            banned=$(fail2ban-client status 2>/dev/null | grep -oP '\d+(?= jail)' || echo "0")
            fail2ban_status="RUNNING|BANNED:${banned}"
        else
            fail2ban_status="INSTALLED_NOT_RUNNING"
        fi
    fi
    print_kv "FAIL2BAN_STATUS" "${fail2ban_status}"

    # Sysctl key params
    local sysctl_params=""
    for param in net.core.somaxconn vm.swappiness fs.file-max net.ipv4.tcp_max_syn_backlog; do
        if [ -f "/proc/sys/${param//\.//}" ] 2>/dev/null; then
            local val
            val=$(cat "/proc/sys/${param//\.//}" 2>/dev/null || echo "N/A")
            sysctl_params="${param}=${val}|${sysctl_params}"
        elif command -v sysctl >/dev/null 2>&1; then
            local val
            val=$(sysctl -n "${param}" 2>/dev/null || echo "N/A")
            sysctl_params="${param}=${val}|${sysctl_params}"
        fi
    done
    sysctl_params=$(echo "${sysctl_params}" | sed 's/|$//')
    print_kv "SYSCTL_KEY_PARAMS" "${sysctl_params}"

    # NTP sync
    local ntp_sync="N/A"
    if command -v timedatectl >/dev/null 2>&1; then
        local ntp_status
        ntp_status=$(timedatectl 2>/dev/null | grep "NTP synchronized" || true)
        if echo "${ntp_status}" | grep -qi "yes"; then
            local ntp_server=""
            if [ -f /etc/ntp.conf ]; then
                ntp_server=$(grep "^server " /etc/ntp.conf | head -1 | awk '{print $2}' || true)
            elif [ -f /etc/chrony/chrony.conf ]; then
                ntp_server=$(grep "^server " /etc/chrony/chrony.conf | head -1 | awk '{print $2}' || true)
            fi
            ntp_sync="OK|SERVER:${ntp_server:-default}"
        else
            ntp_sync="NOT_SYNCED"
        fi
    elif command -v ntpq >/dev/null 2>&1; then
        ntp_sync=$(ntpq -p 2>/dev/null | grep "^\*" | awk '{printf "OK|SERVER:%s|OFFSET:%s", $1, $9}' || echo "N/A")
    fi
    print_kv "NTP_SYNC" "${ntp_sync}"
}

# =============================================================================
# Module 8: Crontab Analysis
# =============================================================================
collect_crontab() {
    # System-level crontab (/etc/cron.d/)
    local crontab_system=""
    if [ -d /etc/cron.d ]; then
        for f in /etc/cron.d/*; do
            [ -f "${f}" ] || continue
            local fname entries
            fname=$(basename "${f}")
            entries=$(grep -vE "^\s*#|^\s*$" "${f}" 2>/dev/null | while read -r line; do
                local user cmd
                user=$(echo "${line}" | awk '{print $6}')
                cmd=$(echo "${line}" | awk '{for(i=7;i<=NF;i++) printf "%s ", $i}' | sed 's/ $//')
                local schedule
                schedule=$(echo "${line}" | awk '{printf "%s %s %s %s %s", $1,$2,$3,$4,$5}')
                printf "root:${fname}:${schedule}:${cmd}|"
            done || true)
            crontab_system="${entries}${crontab_system}"
        done
    fi

    # Also check /etc/crontab
    if [ -f /etc/crontab ]; then
        local etc_crontab
        etc_crontab=$(grep -vE "^\s*#|^\s*$" /etc/crontab 2>/dev/null | while read -r line; do
            local user cmd schedule
            schedule=$(echo "${line}" | awk '{printf "%s %s %s %s %s", $1,$2,$3,$4,$5}')
            user=$(echo "${line}" | awk '{print $6}')
            cmd=$(echo "${line}" | awk '{for(i=7;i<=NF;i++) printf "%s ", $i}' | sed 's/ $//')
            [ -n "${cmd}" ] && printf "${user}:/etc/crontab:${schedule}:${cmd}|"
        done || true)
        crontab_system="${etc_crontab}${crontab_system}"
    fi
    crontab_system=$(echo "${crontab_system}" | sed 's/|$//')
    [ -z "${crontab_system}" ] && crontab_system="NONE"
    print_kv "CRONTAB_SYSTEM" "${crontab_system}"

    # User-level crontab
    for user_entry in $(awk -F: '$3>=0 && $3<65534 && $7 !~ /nologin|false/ {print $1}' /etc/passwd 2>/dev/null | head -10); do
        local user_crontab=""
        if command -v crontab >/dev/null 2>&1; then
            user_crontab=$(crontab -u "${user_entry}" -l 2>/dev/null | grep -vE "^\s*#|^\s*$" | while read -r line; do
                printf "%s|", "${line}"
            done || true)
        fi
        user_crontab=$(echo "${user_crontab}" | sed 's/|$//')
        if [ -n "${user_crontab}" ]; then
            print_kv "CRONTAB_USER_${user_entry}" "${user_crontab}"
        fi
    done

    # Anacron
    local crontab_anacron="N/A"
    if [ -f /etc/anacrontab ]; then
        crontab_anacron=$(grep -vE "^\s*#|^\s*$" /etc/anacrontab 2>/dev/null | awk '{
            printf "%s:%s:%s|", $1, $4, $5
        }' | sed 's/|$//')
        [ -z "${crontab_anacron}" ] && crontab_anacron="N/A"
    fi
    print_kv "CRONTAB_ANACRON" "${crontab_anacron}"

    # Analysis - check for issues
    local analysis=""
    # Check for scripts that don't exist
    if [ -n "${crontab_system}" ]; then
        local scripts_to_check
        scripts_to_check=$(echo "${crontab_system}" | tr '|' '\n' | awk -F: '{print $NF}' | grep "^/" | sort -u || true)
        for script in ${scripts_to_check}; do
            if [ ! -f "${script}" ]; then
                analysis="ERROR:script_not_found:${script}|${analysis}"
            fi
        done
    fi
    analysis=$(echo "${analysis}" | sed 's/|$//')
    [ -z "${analysis}" ] && analysis="OK"
    print_kv "CRONTAB_ANALYSIS" "${analysis}"
}

# =============================================================================
# Module 9: Logs and Alerts
# =============================================================================
collect_logs_alerts() {
    local today=""
    today=$(date '+%b %e')

    # Auth failed today
    local auth_failed="0"
    local auth_src=""
    if [ -f /var/log/auth.log ]; then
        local failed_count=0
        failed_count=$(grep "${today}" /var/log/auth.log 2>/dev/null | grep -c "Failed password" 2>/dev/null) || failed_count=0
        auth_src=$(grep "${today}" /var/log/auth.log 2>/dev/null | grep "Failed password" | awk '{
            for(i=1;i<=NF;i++) if($i=="from") src[$(i+1)]++
        } END {
            for(s in src) printf "%s:%d,", s, src[s]
        }' | sed 's/,$//' || true)
        auth_failed="${failed_count}|SRC:${auth_src}"
    elif [ -f /var/log/secure ]; then
        local failed_count=0
        failed_count=$(grep "${today}" /var/log/secure 2>/dev/null | grep -c "Failed password" 2>/dev/null) || failed_count=0
        auth_src=$(grep "${today}" /var/log/secure 2>/dev/null | grep "Failed password" | awk '{
            for(i=1;i<=NF;i++) if($i=="from") src[$(i+1)]++
        } END {
            for(s in src) printf "%s:%d,", s, src[s]
        }' | sed 's/,$//' || true)
        auth_failed="${failed_count}|SRC:${auth_src}"
    fi
    print_kv "AUTH_FAILED_TODAY" "${auth_failed}"

    # Kernel error today
    local kernel_error="0"
    if [ -f /var/log/kern.log ]; then
        kernel_error=$(grep "${today}" /var/log/kern.log 2>/dev/null | grep -ciE "error|crit|alert|emerg" 2>/dev/null) || kernel_error=0
    elif [ -f /var/log/messages ]; then
        kernel_error=$(grep "${today}" /var/log/messages 2>/dev/null | grep -ciE "kernel.*error|kernel.*crit" 2>/dev/null) || kernel_error=0
    fi
    print_kv "KERNEL_ERROR_TODAY" "${kernel_error}"

    # OOM killer today
    local oom_killer="0"
    if [ -f /var/log/kern.log ]; then
        local oom_info
        oom_info=$(grep "${today}" /var/log/kern.log 2>/dev/null | grep -i "oom-killer" || true)
        if [ -n "${oom_info}" ]; then
            local oom_count=0
            oom_count=$(echo "${oom_info}" | wc -l || echo "0")
            local oom_detail
            oom_detail=$(echo "${oom_info}" | tail -1 | grep -oP 'Killed process \K.*' || true)
            oom_killer="${oom_count}|KILLED:${oom_detail:-unknown}"
        fi
    elif [ -f /var/log/messages ]; then
        local oom_info
        oom_info=$(grep "${today}" /var/log/messages 2>/dev/null | grep -i "oom-killer" || true)
        if [ -n "${oom_info}" ]; then
            local oom_count=0
            oom_count=$(echo "${oom_info}" | wc -l || echo "0")
            local oom_detail
            oom_detail=$(echo "${oom_info}" | tail -1 | grep -oP 'Killed process \K.*' || true)
            oom_killer="${oom_count}|KILLED:${oom_detail:-unknown}"
        fi
    fi
    print_kv "OOM_KILLER_TODAY" "${oom_killer}"

    # Segfault today
    local segfault="0"
    if [ -f /var/log/kern.log ]; then
        segfault=$(grep "${today}" /var/log/kern.log 2>/dev/null | grep -c "segfault" 2>/dev/null) || segfault=0
    elif [ -f /var/log/messages ]; then
        segfault=$(grep "${today}" /var/log/messages 2>/dev/null | grep -c "segfault" 2>/dev/null) || segfault=0
    fi
    print_kv "SEGFAULT_TODAY" "${segfault}"

    # Syslog error today
    local syslog_error="0"
    if [ -f /var/log/syslog ]; then
        local err_count=0
        err_count=$(grep "${today}" /var/log/syslog 2>/dev/null | grep -ciE "error|crit|alert|emerg" 2>/dev/null) || err_count=0
        local top_error=""
        top_error=$(grep "${today}" /var/log/syslog 2>/dev/null | grep -iE "error" | awk -F: '{
            msg=$4; gsub(/^[ \t]+/, "", msg); sub(/ .*/, "", msg); errors[msg]++
        } END {
            n=0; for(e in errors) { print errors[e]":"e; n++; if(n>=3) break }
        }' | sort -rn | head -3 | tr '\n' '|' | sed 's/|$//' || true)
        syslog_error="${err_count}|TOP:${top_error}"
    elif [ -f /var/log/messages ]; then
        local err_count=0
        err_count=$(grep "${today}" /var/log/messages 2>/dev/null | grep -ciE "error|crit|alert|emerg" 2>/dev/null) || err_count=0
        syslog_error="${err_count}"
    fi
    print_kv "SYSLOG_ERROR_TODAY" "${syslog_error}"

    # Security alert
    local security_alert="NONE"
    if [ -f /var/log/auth.log ]; then
        local alert_count=0
        alert_count=$(grep "${today}" /var/log/auth.log 2>/dev/null | grep -ciE "break.?in|attack|intrusion|unauthorized" 2>/dev/null) || alert_count=0
        [ "${alert_count}" -gt 0 ] && security_alert="ALERT:${alert_count}"
    elif [ -f /var/log/secure ]; then
        local alert_count=0
        alert_count=$(grep "${today}" /var/log/secure 2>/dev/null | grep -ciE "break.?in|attack|intrusion|unauthorized" 2>/dev/null) || alert_count=0
        [ "${alert_count}" -gt 0 ] && security_alert="ALERT:${alert_count}"
    fi
    print_kv "SECURITY_ALERT" "${security_alert}"

    # Last login
    local last_login="N/A"
    if command -v last >/dev/null 2>&1; then
        last_login=$(last -i 2>/dev/null | head -1 | awk '{printf "%s@%s:%s", $1, $3, $4" "$5" "$6}' || true)
    fi
    print_kv "LAST_LOGIN" "${last_login}"
}

# =============================================================================
# Module 10: Environment Information
# =============================================================================
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
            version=$("${java_path}" -version 2>&1 | head -1 | awk '{print $NF}' | tr -d '"')
            [ -n "${version}" ] && java_versions="${version}|${java_versions}"
        fi
    done
    # Also check via alternatives
    if command -v alternatives >/dev/null 2>&1; then
        local alt_java
        alt_java=$(alternatives --display java 2>/dev/null | grep -oP '/[^ ]+/bin/java' | head -3 || true)
        for aj in ${alt_java}; do
            if [ -x "${aj}" ]; then
                local version
                version=$("${aj}" -version 2>&1 | head -1 | awk '{print $NF}' | tr -d '"')
                [ -n "${version}" ] && java_versions="${version}|${java_versions}"
            fi
        done
    fi
    java_versions=$(echo "${java_versions}" | sed 's/|$//')
    [ -z "${java_versions}" ] && java_versions="NOT_INSTALLED"
    print_kv "ENV_JAVA_VERSION" "${java_versions}"

    # Python version
    local python_version="NOT_INSTALLED"
    for py_cmd in python3 python; do
        if command -v "${py_cmd}" >/dev/null 2>&1; then
            python_version=$("${py_cmd}" --version 2>&1 | awk '{print $2}' || echo "")
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

# =============================================================================
# Helper functions
# =============================================================================

# Ensure output directory exists
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

# =============================================================================
# Main collection function
# =============================================================================
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

    # Module 5: Java Process Details
    collect_java_processes
    echo "---"

    # Module 6: Middleware
    collect_middleware
    echo "---"

    # Module 7: System Security
    collect_security
    echo "---"

    # Module 8: Crontab Analysis
    collect_crontab
    echo "---"

    # Module 9: Logs and Alerts
    collect_logs_alerts
    echo "---"

    # Module 10: Environment Information
    collect_environment_info

    # Restore stdout
    exec >&3
}

# Execute main function
main "$@"
