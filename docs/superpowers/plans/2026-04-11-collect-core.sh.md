# 核心采集脚本 (collect.sh) 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 collect.sh 核心采集脚本，支持系统信息、基础资源、网络状态、进程服务、环境信息 5 个基础模块，输出标准键值对格式。

**Architecture:** 纯 Bash 脚本，每个检查模块封装为独立函数，统一通过 stdout 输出键值对，按模块分段标记。兼容 CentOS/Ubuntu/Debian，自动检测命令可用性并降级处理。

**Tech Stack:** Bash (POSIX 兼容), 标准Linux命令 (awk, sed, grep, free, df, top, ss, ps 等)

---

## 文件结构

```
SystemHealthScan/
├── collect.sh              # 核心采集脚本（本模块产出）
├── tests/
│   └── collect_test.sh     # 采集脚本测试
└── output/                 # 采集结果目录（运行时创建）
```

---

### Task 1: 创建 collect.sh 脚本框架

**Files:**
- Create: `collect.sh`

- [ ] **Step 1: 创建脚本基础框架**

```bash
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
```

- [ ] **Step 2: 使脚本可执行**

```bash
chmod +x collect.sh
```

- [ ] **Step 3: 验证脚本可以执行（预期会报错函数未定义）**

```bash
./collect.sh 2>&1 | head -5
```

预期输出: `collect.sh: line XX: collect_system_info: command not found`

- [ ] **Step 4: 提交初始框架**

```bash
git add collect.sh
git commit -m "feat: create collect.sh framework with module structure"
```

---

### Task 2: 实现系统信息模块 (collect_system_info)

**Files:**
- Modify: `collect.sh`

- [ ] **Step 1: 在 main() 函数前添加 collect_system_info 函数**

```bash
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
```

- [ ] **Step 2: 验证系统信息模块输出**

```bash
./collect.sh 2>&1 | grep -A 30 "^HOSTNAME="
```

预期输出: 应该看到 HOSTNAME、UNAME_N、IP、CHECK_TIME、OS、KERNEL、ARCH、UPTIME、LAST_BOOT_TIME、CPU_MODEL、CPU_CORES、CPU_SOCKETS、CPU_FREQ、VIRTUAL_TYPE 的键值对

- [ ] **Step 3: 提交系统信息模块**

```bash
git add collect.sh
git commit -m "feat: implement system info collection module"
```

---

### Task 3: 实现基础资源模块 (collect_basic_resources)

**Files:**
- Modify: `collect.sh`

- [ ] **Step 1: 在 collect_system_info 函数后添加 collect_basic_resources 函数**

```bash
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
            mem_buffers=$(echo "${mem_output}" | awk '{print $6}')
            mem_cached=$(echo "${mem_output}" | awk '{print $6}')

            # Calculate percentage
            if [ "${mem_total}" -gt 0 ]; then
                mem_percent=$(awk "BEGIN {printf \"%.2f\", (${mem_used} / ${mem_total}) * 100}")
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
```

- [ ] **Step 2: 验证基础资源模块输出**

```bash
./collect.sh 2>&1 | sed -n '/^---$/,/^---$/p' | head -30
```

预期输出: 应该看到 CPU_USAGE、CPU_LOAD_*、CPU_TOP5、MEM_*、SWAP_*、DISK_、INODE_、IO_* 的键值对

- [ ] **Step 3: 提交基础资源模块**

```bash
git add collect.sh
git commit -m "feat: implement basic resources collection module"
```

---

### Task 4: 实现网络状态模块 (collect_network_status)

**Files:**
- Modify: `collect.sh`

- [ ] **Step 1: 在 collect_basic_resources 函数后添加 collect_network_status 函数**

```bash
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
        dns_resolve=$(nslookup -timeout=2 8.8.8.8 2>/dev/null | grep -q "8.8.8.8" && echo "OK:8.8.8.8:1ms" || echo "FAIL")
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
```

- [ ] **Step 2: 验证网络状态模块输出**

```bash
./collect.sh 2>&1 | sed -n '/^---$/,/^---$/p' | tail -30
```

预期输出: 应该看到 NET_NIC_、NET_LISTEN_PORTS、NET_TCP_STATUS、NET_DNS_RESOLVE、NET_FIREWALL、NET_ROUTE、NET_CONNECTIONS_TOP5 的键值对

- [ ] **Step 3: 提交网络状态模块**

```bash
git add collect.sh
git commit -m "feat: implement network status collection module"
```

---

### Task 5: 实现进程与服务模块 (collect_process_services)

**Files:**
- Modify: `collect.sh`

- [ ] **Step 1: 在 collect_network_status 函数后添加 collect_process_services 函数**

```bash
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

    if [ -f /proc/stat ]; then
        process_total=$(grep "^processes" /proc/stat 2>/dev/null | awk '{print $2}' || echo "0")
    fi

    if command -v ps >/dev/null 2>&1; then
        local ps_output
        ps_output=$(ps aux 2>/dev/null)

        process_zombie=$(echo "${ps_output}" | grep -c "[Zz]" || echo "0")
        process_running=$(echo "${ps_output}" | grep -c "[Rr]" || echo "0")
        process_sleeping=$(echo "${ps_output}" | grep -c "[Ss]" || echo "0")
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
```

- [ ] **Step 2: 验证进程与服务模块输出**

```bash
./collect.sh 2>&1 | sed -n '/^---$/,/^---$/p' | head -20
```

预期输出: 应该看到 SERVICE_STATUS、PROCESS_* 的键值对

- [ ] **Step 3: 提交进程与服务模块**

```bash
git add collect.sh
git commit -m "feat: implement process and services collection module"
```

---

### Task 6: 实现环境信息模块 (collect_environment_info)

**Files:**
- Modify: `collect.sh`

- [ ] **Step 1: 在 collect_process_services 函数后添加 collect_environment_info 函数**

```bash
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
```

- [ ] **Step 2: 验证环境信息模块输出**

```bash
./collect.sh 2>&1 | tail -20
```

预期输出: 应该看到 DOCKER_STATUS、DOCKER_CONTAINER_、ENV_JAVA_VERSION、ENV_PYTHON_VERSION、ENV_NODE_VERSION 的键值对

- [ ] **Step 3: 提交环境信息模块**

```bash
git add collect.sh
git commit -m "feat: implement environment info collection module"
```

---

### Task 7: 创建输出目录支持

**Files:**
- Modify: `collect.sh`

- [ ] **Step 1: 在脚本开头添加输出目录处理函数**

```bash
# Helper function to ensure output directory exists
ensure_output_dir() {
    local output_dir="${1:-./output}"
    if [ ! -d "${output_dir}" ]; then
        mkdir -p "${output_dir}" 2>/dev/null || {
            echo "ERROR: Failed to create output directory: ${output_dir}" >&2
            return 1
        }
    fi
}

# Main collection function
main() {
    local output_file="${1:-/dev/stdout}"

    # If not stdout, ensure parent directory exists
    if [ "${output_file}" != "/dev/stdout" ]; then
        ensure_output_dir "$(dirname "${output_file}")"
    fi

    # ... rest of main function
```

- [ ] **Step 2: 修改 main 函数使用输出文件参数**

```bash
# Main collection function
main() {
    local output_file="${1:-/dev/stdout}"

    # If not stdout, ensure parent directory exists
    if [ "${output_file}" != "/dev/stdout" ]; then
        ensure_output_dir "$(dirname "${output_file}")"
    fi

    # Redirect all output to the specified file
    exec 3>&1
    exec >"${output_file}"

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
```

- [ ] **Step 3: 测试输出到文件**

```bash
./collect.sh output/test_server_$(date +%Y%m%d).dat
ls -lh output/
```

预期输出: output/ 目录下应该有 test_server_YYYYMMDD.dat 文件，内容包含所有模块的键值对

- [ ] **Step 4: 提交输出目录支持**

```bash
git add collect.sh
git add output/
git commit -m "feat: add output directory support"
```

---

### Task 8: 创建测试脚本验证输出格式

**Files:**
- Create: `tests/collect_test.sh`

- [ ] **Step 1: 创建测试脚本框架**

```bash
#!/bin/bash
#
# Test script for collect.sh
# Validates output format and required keys
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((TESTS_PASSED++)) || true
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((TESTS_FAILED++)) || true
}

info() {
    echo -e "${YELLOW}INFO${NC}: $1"
}

run_test() {
    ((TESTS_TOTAL++)) || true
}

# Main test function
main() {
    local output_file
    output_file=$(mktemp)

    info "Running collect.sh and capturing output..."
    ./collect.sh "${output_file}" >/dev/null 2>&1 || {
        fail "collect.sh execution failed"
        exit 1
    }

    info "Validating output file: ${output_file}"

    # Test 1: Check file exists
    run_test
    if [ -f "${output_file}" ]; then
        pass "Output file created"
    else
        fail "Output file not created"
    fi

    # Test 2: Check file is not empty
    run_test
    if [ -s "${output_file}" ]; then
        pass "Output file is not empty"
    else
        fail "Output file is empty"
    fi

    # Test 3: Check required keys from System Information module
    run_test
    local system_keys=("HOSTNAME" "IP" "CHECK_TIME" "OS" "KERNEL" "ARCH" "CPU_CORES")
    local missing_keys=()
    for key in "${system_keys[@]}"; do
        if ! grep -q "^${key}=" "${output_file}"; then
            missing_keys+=("${key}")
        fi
    done
    if [ ${#missing_keys[@]} -eq 0 ]; then
        pass "All system info keys present"
    else
        fail "Missing system info keys: ${missing_keys[*]}"
    fi

    # Test 4: Check required keys from Basic Resources module
    run_test
    local resource_keys=("CPU_USAGE" "CPU_LOAD_1" "MEM_TOTAL" "MEM_USED" "MEM_PERCENT")
    missing_keys=()
    for key in "${resource_keys[@]}"; do
        if ! grep -q "^${key}=" "${output_file}"; then
            missing_keys+=("${key}")
        fi
    done
    if [ ${#missing_keys[@]} -eq 0 ]; then
        pass "All basic resources keys present"
    else
        fail "Missing basic resources keys: ${missing_keys[*]}"
    fi

    # Test 5: Check required keys from Network module
    run_test
    local network_keys=("NET_LISTEN_PORTS" "NET_TCP_STATUS")
    missing_keys=()
    for key in "${network_keys[@]}"; do
        if ! grep -q "^${key}=" "${output_file}"; then
            missing_keys+=("${key}")
        fi
    done
    if [ ${#missing_keys[@]} -eq 0 ]; then
        pass "All network keys present"
    else
        fail "Missing network keys: ${missing_keys[*]}"
    fi

    # Test 6: Check module separators
    run_test
    local separator_count
    separator_count=$(grep -c "^---$" "${output_file}" || echo "0")
    if [ "${separator_count}" -eq 4 ]; then
        pass "Correct number of module separators (4)"
    else
        fail "Expected 4 module separators, found ${separator_count}"
    fi

    # Test 7: Verify KEY=VALUE format
    run_test
    local invalid_lines
    invalid_lines=$(grep -vE "^[A-Z_]+=|^---$" "${output_file}" | wc -l)
    if [ "${invalid_lines}" -eq 0 ]; then
        pass "All lines follow KEY=VALUE format or separator"
    else
        fail "Found ${invalid_lines} lines not following KEY=VALUE format"
    fi

    # Cleanup
    rm -f "${output_file}"

    # Summary
    echo ""
    echo "===================="
    echo "Test Summary"
    echo "===================="
    echo "Total:  ${TESTS_TOTAL}"
    echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
    echo "===================="

    if [ "${TESTS_FAILED}" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
```

- [ ] **Step 2: 使测试脚本可执行**

```bash
chmod +x tests/collect_test.sh
```

- [ ] **Step 3: 运行测试脚本**

```bash
./tests/collect_test.sh
```

预期输出: 所有测试应该通过，显示绿色的 PASS 信息

- [ ] **Step 4: 提交测试脚本**

```bash
git add tests/collect_test.sh
git commit -m "test: add collect.sh validation tests"
```

---

### Task 9: 添加脚本版本和帮助信息

**Files:**
- Modify: `collect.sh`

- [ ] **Step 1: 添加版本显示和帮助功能**

```bash
# Print version
show_version() {
    echo "SystemHealthScan Core Collection Script v${VERSION}"
    exit 0
}

# Print usage
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
```

- [ ] **Step 2: 修改 main 函数集成参数解析**

```bash
# Main collection function
main() {
    local output_file="${OUTPUT_FILE:-/dev/stdout}"

    # If not stdout, ensure parent directory exists
    if [ "${output_file}" != "/dev/stdout" ]; then
        ensure_output_dir "$(dirname "${output_file}")"
    fi

    # Redirect all output to the specified file
    exec 3>&1
    exec >"${output_file}"

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

# Parse command line arguments
parse_args "$@"

# Execute main function
main "$@"
```

- [ ] **Step 3: 测试版本和帮助选项**

```bash
./collect.sh -v
./collect.sh --help
```

预期输出:
- `-v` 显示版本信息并退出
- `--help` 显示使用帮助信息并退出

- [ ] **Step 4: 提交版本和帮助功能**

```bash
git add collect.sh
git commit -m "feat: add version and help options"
```

---

### Task 10: 最终集成测试和文档

**Files:**
- Create: `README_COLLECT.md`

- [ ] **Step 1: 创建 collect.sh 使用文档**

```markdown
# collect.sh 使用说明

## 概述

`collect.sh` 是 Linux 服务器健康巡检工具的核心采集脚本，负责收集服务器基础状态信息并以键值对格式输出。

## 功能模块

1. **系统信息** - 主机名、IP、操作系统、内核、CPU信息等
2. **基础资源** - CPU使用率、负载、内存、磁盘、IO等
3. **网络状态** - 网卡状态、端口监听、TCP连接、DNS等
4. **进程与服务** - 服务状态、进程统计、Top进程等
5. **环境信息** - Docker、Java、Python、Node.js版本等

## 使用方法

### 基本用法

```bash
# 输出到标准输出
./collect.sh

# 输出到文件
./collect.sh output/server_$(date +%Y%m%d).dat

# 查看帮助
./collect.sh -h

# 查看版本
./collect.sh -v
```

### 输出格式

输出格式为 `KEY=VALUE`，每行一个键值对，模块之间用 `---` 分隔。

```
HOSTNAME=web-server-01
IP=192.168.1.10
CHECK_TIME=2026-04-11_14:30:00
OS=CentOS 7.9
KERNEL=3.10.0-1160.el7.x86_64
---
CPU_USAGE=35.2
CPU_LOAD_1=0.82
MEM_TOTAL=32768
MEM_USED=18432
...
```

## 系统兼容性

- CentOS 6/7/8/9
- Ubuntu 18.04+
- Debian 10+
- KylinOS v10

## 测试

运行测试脚本验证输出格式：

```bash
./tests/collect_test.sh
```

## 注意事项

1. 脚本需要 Bash 环境
2. 某些统计指标需要额外命令支持（如 iostat、mpstat），缺失时会显示 N/A
3. 容器环境中部分硬件信息可能不可用
4. 输出文件路径如果不存在会自动创建
