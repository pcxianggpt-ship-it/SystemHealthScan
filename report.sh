#!/usr/bin/env bash
# =============================================================================
# report.sh — Linux 服务器健康巡检报告生成脚本
# 读取 collect.sh 输出的 .dat 键值对文件，生成 Markdown 并转为 Word 报告
# =============================================================================

set -euo pipefail

# Script version
VERSION="1.0.0"

# Directories (defaults, overridden by parse_args)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_DIR="${SCRIPT_DIR}/output"
OUTPUT_DIR="${SCRIPT_DIR}/report"
CHECKS_CONF="${SCRIPT_DIR}/config/checks.conf"

# Markdown temp file
MD_FILE=""

# =============================================================================
# Global data structures
# =============================================================================
declare -a SERVER_FILES=()
declare -a SERVER_HOSTNAMES=()
declare -a SERVER_IPS=()
declare -a SERVER_OS=()
declare -a SERVER_KERNEL=()
declare -a SERVER_VIRTUAL=()
declare -a SERVER_CHECK_TIME=()
declare -a SERVER_HEALTH=()

# Flat key-value store: "serverIdx__KEY" = VALUE
declare -A DATA=()

# Module boundaries per server: "serverIdx__module_N_start" / "serverIdx__module_N_end"
declare -A MODULE_BOUNDS=()

# Thresholds from checks.conf
declare -A THRESHOLD=()

# Issue collection
declare -a ISSUES_CRIT=()
declare -a ISSUES_WARN=()
declare -a ISSUES_INFO=()

# =============================================================================
# Utility functions
# =============================================================================

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

show_version() {
    echo "report.sh version ${VERSION}"
}

show_usage() {
    cat <<'EOF'
Usage: report.sh [OPTIONS]

Generate health inspection report from .dat collection files.

Options:
  -i DIR      Input directory containing .dat files (default: output/)
  -o FILE     Output .docx file path (default: report/巡检报告_YYYYMMDD.docx)
  -c FILE     Checks configuration file (default: config/checks.conf)
  -h          Show this help message
  -v          Show version

Examples:
  report.sh                                    # Use defaults
  report.sh -i output/ -o report/my_report.docx
  report.sh -c /path/to/custom_checks.conf

EOF
    exit 0
}

# =============================================================================
# Argument parsing
# =============================================================================

parse_args() {
    local output_path=""

    while getopts "i:o:c:hv" opt; do
        case "${opt}" in
            i) INPUT_DIR="$(cd "${OPTARG}" && pwd)" ;;
            o) output_path="${OPTARG}" ;;
            c) CHECKS_CONF="${OPTARG}" ;;
            h) show_usage ;;
            v) show_version; exit 0 ;;
            *) show_usage ;;
        esac
    done

    # Default output path
    if [ -z "${output_path}" ]; then
        local today
        today=$(date +%Y%m%d)
        output_path="${SCRIPT_DIR}/report/巡检报告_${today}.docx"
    fi

    # Ensure output path is absolute
    if [[ "${output_path}" != /* ]]; then
        output_path="$(pwd)/${output_path}"
    fi

    OUTPUT_DIR="$(dirname "${output_path}")"
    OUTPUT_FILE="${output_path}"

    # Validate inputs
    if [ ! -d "${INPUT_DIR}" ]; then
        log_error "Input directory not found: ${INPUT_DIR}"
        exit 1
    fi

    if [ ! -f "${CHECKS_CONF}" ]; then
        log_error "Checks config not found: ${CHECKS_CONF}"
        exit 1
    fi
}

# =============================================================================
# Threshold loading
# =============================================================================

load_thresholds() {
    log_info "Loading thresholds from ${CHECKS_CONF}"
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "${key}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key}" ]] && continue
        # Trim whitespace
        key=$(echo "${key}" | xargs)
        value=$(echo "${value}" | xargs)
        THRESHOLD["${key}"]="${value}"
    done < "${CHECKS_CONF}"
    log_info "Loaded ${#THRESHOLD[@]} threshold rules"
}

# =============================================================================
# .dat file loading and parsing
# =============================================================================

load_all_dat() {
    local dat_count=0

    for dat_file in "${INPUT_DIR}"/*.dat; do
        [ -f "${dat_file}" ] || continue
        log_info "Loading: ${dat_file}"

        local idx="${dat_count}"
        SERVER_FILES+=("$(basename "${dat_file}")")

        # Read file content, split by modules
        local module_idx=0
        local line_num=0
        local module_start=0

        while IFS= read -r line || [ -n "${line}" ]; do
            line_num=$((line_num + 1))

            if [ "${line}" = "---" ]; then
                # Record module boundary
                if [ "${module_start}" -gt 0 ]; then
                    MODULE_BOUNDS["${idx}__${module_idx}_end"]=$((line_num - 1))
                fi
                module_idx=$((module_idx + 1))
                module_start=$((line_num + 1))
                MODULE_BOUNDS["${idx}__${module_idx}_start"]="${module_start}"
                continue
            fi

            # Parse KEY=VALUE
            if [[ "${line}" == *"="* ]]; then
                local key="${line%%=*}"
                local value="${line#*=}"
                DATA["${idx}__${key}"]="${value}"

                # Cache server identity fields
                case "${key}" in
                    HOSTNAME)  SERVER_HOSTNAMES+=("${value}") ;;
                    IP)        SERVER_IPS+=("${value}") ;;
                    OS)        SERVER_OS+=("${value}") ;;
                    KERNEL)    SERVER_KERNEL+=("${value}") ;;
                    VIRTUAL_TYPE) SERVER_VIRTUAL+=("${value}") ;;
                    CHECK_TIME)   SERVER_CHECK_TIME+=("${value}") ;;
                esac
            fi
        done < "${dat_file}"

        # Record last module end
        MODULE_BOUNDS["${idx}__${module_idx}_end"]="${line_num}"

        # Default health
        SERVER_HEALTH+=("OK")

        dat_count=$((dat_count + 1))
    done

    if [ "${dat_count}" -eq 0 ]; then
        log_error "No .dat files found in ${INPUT_DIR}"
        exit 1
    fi

    log_info "Loaded ${dat_count} server data file(s)"
}

# Get value for a server index and key
get_val() {
    local idx="$1"
    local key="$2"
    echo "${DATA["${idx}__${key}"]:-}"
}

# Check threshold: returns OK / WARN / CRIT
check_threshold() {
    local metric="$1"
    local value="$2"

    # Handle N/A or empty
    if [ -z "${value}" ] || [ "${value}" = "N/A" ]; then
        echo "OK"
        return
    fi

    # Extract numeric part (remove % suffix if present)
    local num_value
    num_value=$(echo "${value}" | sed 's/%$//' | awk '{print $1}')

    # Check if numeric
    if ! awk "BEGIN { exit ($num_value + 0 == $num_value) ? 0 : 1 }" 2>/dev/null; then
        echo "OK"
        return
    fi

    # Check CRIT first
    local crit_key="CRIT_${metric}"
    if [ -n "${THRESHOLD[${crit_key}]:-}" ]; then
        local crit_val="${THRESHOLD[${crit_key}]}"
        if awk "BEGIN { exit ($num_value > $crit_val) ? 0 : 1 }" 2>/dev/null; then
            echo "CRIT"
            return
        fi
    fi

    # Check WARN
    local warn_key="WARN_${metric}"
    if [ -n "${THRESHOLD[${warn_key}]:-}" ]; then
        local warn_val="${THRESHOLD[${warn_key}]}"
        if awk "BEGIN { exit ($num_value > $warn_val) ? 0 : 1 }" 2>/dev/null; then
            echo "WARN"
            return
        fi
    fi

    echo "OK"
}

# Record an issue
add_issue() {
    local level="$1"  # CRIT / WARN / INFO
    local message="$2"
    local server="$3"

    local entry="[${server}] ${message}"
    case "${level}" in
        CRIT) ISSUES_CRIT+=("${entry}") ;;
        WARN) ISSUES_WARN+=("${entry}") ;;
        INFO) ISSUES_INFO+=("${entry}") ;;
    esac

    # Update server health if worse
    for i in "${!SERVER_HOSTNAMES[@]}"; do
        if [ "${SERVER_HOSTNAMES[$i]}" = "${server}" ]; then
            if [ "${level}" = "CRIT" ]; then
                SERVER_HEALTH[$i]="CRIT"
            elif [ "${level}" = "WARN" ] && [ "${SERVER_HEALTH[$i]}" != "CRIT" ]; then
                SERVER_HEALTH[$i]="WARN"
            fi
            break
        fi
    done
}

# Parse compound value: split by | then by :
# Usage: parse_compound "value_with_pipes" callback_func
parse_compound() {
    local value="$1"
    local callback="$2"
    local extra_args="${3:-}"

    IFS='|' read -ra parts <<< "${value}"
    for part in "${parts[@]}"; do
        [ -z "${part}" ] && continue
        if [ -n "${extra_args}" ]; then
            "${callback}" "${part}" "${extra_args}"
        else
            "${callback}" "${part}"
        fi
    done
}

# =============================================================================
# Markdown generation — Cover Page
# =============================================================================

generate_cover() {
    local server_count=${#SERVER_HOSTNAMES[@]}
    local today
    today=$(date +%Y-%m-%d)

    cat >> "${MD_FILE}" <<EOF

---

# Linux 服务器健康巡检报告

**巡检日期：** ${today}

**巡检服务器数量：** ${server_count} 台

**报告生成工具：** AutoSystemCheck report.sh v${VERSION}

---

EOF
}

# =============================================================================
# Markdown generation — Overview
# =============================================================================

generate_overview() {
    cat >> "${MD_FILE}" <<EOF

# 1. 巡检概览

## 1.1 服务器清单

| 序号 | 主机名 | IP 地址 | 操作系统 | 虚拟化类型 | 状态 |
|------|--------|---------|----------|------------|------|
EOF

    local i
    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local os="${SERVER_OS[$i]:-N/A}"
        local virt="${SERVER_VIRTUAL[$i]:-N/A}"
        local health="${SERVER_HEALTH[$i]}"
        local status_text

        case "${health}" in
            CRIT) status_text="**异常**" ;;
            WARN) status_text="**警告**" ;;
            *)    status_text="正常" ;;
        esac

        printf "| %d | %s | %s | %s | %s | %s |\n" \
            "$((i + 1))" "${hostname}" "${ip}" "${os}" "${virt}" "${status_text}" \
            >> "${MD_FILE}"
    done

    # Health summary
    local crit_count=0 warn_count=0 ok_count=0
    for h in "${SERVER_HEALTH[@]}"; do
        case "${h}" in
            CRIT) crit_count=$((crit_count + 1)) ;;
            WARN) warn_count=$((warn_count + 1)) ;;
            *)    ok_count=$((ok_count + 1)) ;;
        esac
    done

    cat >> "${MD_FILE}" <<EOF

## 1.2 总体健康评分

| 状态 | 台数 |
|------|------|
| 正常 | ${ok_count} |
| 警告 | ${warn_count} |
| 异常 | ${crit_count} |

EOF
}

# =============================================================================
# Markdown generation — Issues Summary
# =============================================================================

generate_issues_summary() {
    cat >> "${MD_FILE}" <<EOF

# 2. 问题汇总

EOF

    # Critical issues
    if [ ${#ISSUES_CRIT[@]} -gt 0 ]; then
        echo "## 2.1 严重问题（需立即处理）" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
        for issue in "${ISSUES_CRIT[@]}"; do
            echo "- ${issue}" >> "${MD_FILE}"
        done
        echo "" >> "${MD_FILE}"
    else
        echo "## 2.1 严重问题" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
        echo "无严重问题。" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
    fi

    # Warnings
    if [ ${#ISSUES_WARN[@]} -gt 0 ]; then
        echo "## 2.2 警告项（建议处理）" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
        for issue in "${ISSUES_WARN[@]}"; do
            echo "- ${issue}" >> "${MD_FILE}"
        done
        echo "" >> "${MD_FILE}"
    else
        echo "## 2.2 警告项" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
        echo "无警告项。" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
    fi

    # Suggestions
    if [ ${#ISSUES_INFO[@]} -gt 0 ]; then
        echo "## 2.3 建议优化项" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
        for issue in "${ISSUES_INFO[@]}"; do
            echo "- ${issue}" >> "${MD_FILE}"
        done
        echo "" >> "${MD_FILE}"
    else
        echo "## 2.3 建议优化项" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
        echo "无优化建议。" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
    fi
}

# =============================================================================
# Markdown generation — 3.1 Resource Usage
# =============================================================================

generate_resource_section() {
    cat >> "${MD_FILE}" <<EOF

# 3. 应用巡检

## 3.1 资源使用概况

EOF

    # CPU summary table
    echo "### CPU 使用率" >> "${MD_FILE}"
    echo "" >> "${MD_FILE}"
    echo "| 主机名 | CPU% | 负载(1m) | 负载(5m) | 负载(15m) | 状态 |" >> "${MD_FILE}"
    echo "|--------|------|----------|----------|-----------|------|" >> "${MD_FILE}"

    local i
    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local cpu_usage
        cpu_usage=$(get_val "$i" "CPU_USAGE")
        local load1 load5 load15
        load1=$(get_val "$i" "CPU_LOAD_1")
        load5=$(get_val "$i" "CPU_LOAD_5")
        load15=$(get_val "$i" "CPU_LOAD_15")
        local status
        status=$(check_threshold "CPU_USAGE" "${cpu_usage}")

        [ "${status}" != "OK" ] && add_issue "${status}" "CPU 使用率 ${cpu_usage}% (${status})" "${hostname}"

        local status_text
        case "${status}" in
            CRIT) status_text="**异常**" ;;
            WARN) status_text="**警告**" ;;
            *)    status_text="正常" ;;
        esac

        printf "| %s | %s%% | %s | %s | %s | %s |\n" \
            "${hostname}" "${cpu_usage:-N/A}" "${load1:-N/A}" "${load5:-N/A}" "${load15:-N/A}" "${status_text}" \
            >> "${MD_FILE}"
    done

    # Memory summary table
    echo "" >> "${MD_FILE}"
    echo "### 内存使用率" >> "${MD_FILE}"
    echo "" >> "${MD_FILE}"
    echo "| 主机名 | 总计(MB) | 已用(MB) | 可用(MB) | 使用率 | 状态 |" >> "${MD_FILE}"
    echo "|--------|----------|----------|----------|--------|------|" >> "${MD_FILE}"

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local mem_total mem_used mem_avail mem_percent
        mem_total=$(get_val "$i" "MEM_TOTAL")
        mem_used=$(get_val "$i" "MEM_USED")
        mem_avail=$(get_val "$i" "MEM_AVAILABLE")
        mem_percent=$(get_val "$i" "MEM_PERCENT")
        local status
        status=$(check_threshold "MEM_PERCENT" "${mem_percent}")

        [ "${status}" != "OK" ] && add_issue "${status}" "内存使用率 ${mem_percent}% (${status})" "${hostname}"

        local status_text
        case "${status}" in
            CRIT) status_text="**异常**" ;;
            WARN) status_text="**警告**" ;;
            *)    status_text="正常" ;;
        esac

        printf "| %s | %s | %s | %s | %s%% | %s |\n" \
            "${hostname}" "${mem_total:-N/A}" "${mem_used:-N/A}" "${mem_avail:-N/A}" "${mem_percent:-N/A}" "${status_text}" \
            >> "${MD_FILE}"
    done

    # SWAP
    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local swap_total swap_used
        swap_total=$(get_val "$i" "SWAP_TOTAL")
        swap_used=$(get_val "$i" "SWAP_USED")
        if [ -n "${swap_total}" ] && [ "${swap_total}" != "0" ] 2>/dev/null; then
            local swap_percent=0
            swap_percent=$(awk "BEGIN { printf \"%.1f\", ${swap_used:-0} / ${swap_total} * 100 }" 2>/dev/null || echo "0")
            local status
            status=$(check_threshold "SWAP_PERCENT" "${swap_percent}")
            [ "${status}" != "OK" ] && add_issue "${status}" "SWAP 使用率 ${swap_percent}% (${status})" "${hostname}"
        fi
    done

    # Disk summary table
    echo "" >> "${MD_FILE}"
    echo "### 磁盘使用率" >> "${MD_FILE}"
    echo "" >> "${MD_FILE}"
    echo "| 主机名 | 挂载点 | 总大小 | 已用 | 使用率 | 状态 |" >> "${MD_FILE}"
    echo "|--------|--------|--------|------|--------|------|" >> "${MD_FILE}"

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local disk_val
        disk_val=$(get_val "$i" "DISK_")
        [ -z "${disk_val}" ] && continue

        IFS='|' read -ra disk_parts <<< "${disk_val}"
        for part in "${disk_parts[@]}"; do
            [ -z "${part}" ] && continue
            local mount total used percent
            mount=$(echo "${part}" | cut -d: -f1)
            total=$(echo "${part}" | cut -d: -f2)
            used=$(echo "${part}" | cut -d: -f3)
            percent=$(echo "${part}" | cut -d: -f4 | sed 's/%$//')

            [ -z "${percent}" ] || [ "${percent}" = "-" ] && continue

            local status
            status=$(check_threshold "DISK_PERCENT" "${percent}")

            [ "${status}" != "OK" ] && add_issue "${status}" "磁盘 ${mount} 使用率 ${percent}% (${status})" "${hostname}"

            local status_text
            case "${status}" in
                CRIT) status_text="**异常**" ;;
                WARN) status_text="**警告**" ;;
                *)    status_text="正常" ;;
            esac

            printf "| %s | %s | %s | %s | %s%% | %s |\n" \
                "${hostname}" "${mount}" "${total}" "${used}" "${percent}" "${status_text}" \
                >> "${MD_FILE}"
        done
    done

    # IO summary table
    echo "" >> "${MD_FILE}"
    echo "### IO 使用情况" >> "${MD_FILE}"
    echo "" >> "${MD_FILE}"
    echo "| 主机名 | IO Wait% | IO Util | 状态 |" >> "${MD_FILE}"
    echo "|--------|----------|---------|------|" >> "${MD_FILE}"

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local io_wait io_util
        io_wait=$(get_val "$i" "IO_WAIT")

        # Find first IO_UTIL key
        local io_util=""
        for key in "${!DATA[@]}"; do
            if [[ "${key}" == "${i}__IO_UTIL_"* ]]; then
                io_util="${DATA[$key]}"
                break
            fi
        done

        local status
        status=$(check_threshold "IO_WAIT" "${io_wait}")

        local status_text
        case "${status}" in
            CRIT) status_text="**异常**" ;;
            WARN) status_text="**警告**" ;;
            *)    status_text="正常" ;;
        esac

        printf "| %s | %s | %s | %s |\n" \
            "${hostname}" "${io_wait:-N/A}" "${io_util:-N/A}" "${status_text}" \
            >> "${MD_FILE}"
    done
    echo "" >> "${MD_FILE}"
}

# =============================================================================
# Markdown generation — 3.2 Network Status
# =============================================================================

generate_network_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.2 网络状态

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        echo "### ${hostname}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"

        # NIC status
        local nic_val
        nic_val=$(get_val "$i" "NET_NIC_")
        if [ -n "${nic_val}" ]; then
            echo "**网卡状态：**" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
            echo "| 网卡 | 状态 | 速率 |" >> "${MD_FILE}"
            echo "|------|------|------|" >> "${MD_FILE}"
            IFS='|' read -ra parts <<< "${nic_val}"
            for part in "${parts[@]}"; do
                [ -z "${part}" ] && continue
                local nic_name nic_status nic_speed
                nic_name=$(echo "${part}" | cut -d: -f1)
                nic_status=$(echo "${part}" | cut -d: -f2)
                nic_speed=$(echo "${part}" | cut -d: -f3)
                printf "| %s | %s | %s |\n" "${nic_name}" "${nic_status}" "${nic_speed}" >> "${MD_FILE}"
            done
            echo "" >> "${MD_FILE}"
        fi

        # TCP status
        local tcp_val
        tcp_val=$(get_val "$i" "NET_TCP_STATUS")
        if [ -n "${tcp_val}" ]; then
            echo "**TCP 连接状态：**" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
            echo "| 状态 | 连接数 |" >> "${MD_FILE}"
            echo "|------|--------|" >> "${MD_FILE}"
            IFS='|' read -ra parts <<< "${tcp_val}"
            for part in "${parts[@]}"; do
                [ -z "${part}" ] && continue
                local state count
                state=$(echo "${part}" | cut -d: -f1)
                count=$(echo "${part}" | cut -d: -f2)
                printf "| %s | %s |\n" "${state}" "${count}" >> "${MD_FILE}"

                # Check CLOSE_WAIT and TIME_WAIT thresholds
                if [ "${state}" = "CLOSE_WAIT" ]; then
                    local s
                    s=$(check_threshold "CLOSE_WAIT" "${count}")
                    [ "${s}" != "OK" ] && add_issue "${s}" "TCP CLOSE_WAIT 连接数 ${count} (${s})" "${hostname}"
                elif [ "${state}" = "TIME_WAIT" ]; then
                    local s
                    s=$(check_threshold "TIME_WAIT" "${count}")
                    [ "${s}" != "OK" ] && add_issue "${s}" "TCP TIME_WAIT 连接数 ${count} (${s})" "${hostname}"
                fi
            done
            echo "" >> "${MD_FILE}"
        fi

        # Listen ports
        local ports_val
        ports_val=$(get_val "$i" "NET_LISTEN_PORTS")
        if [ -n "${ports_val}" ]; then
            echo "**监听端口：** ${ports_val}" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
        fi

        # DNS
        local dns_val
        dns_val=$(get_val "$i" "NET_DNS_RESOLVE")
        if [ -n "${dns_val}" ]; then
            echo "**DNS 解析：** ${dns_val}" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
        fi

        # Firewall
        local fw_val
        fw_val=$(get_val "$i" "NET_FIREWALL")
        echo "**防火墙状态：** ${fw_val:-N/A}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"

        # Route
        local route_val
        route_val=$(get_val "$i" "NET_ROUTE")
        if [ -n "${route_val}" ]; then
            echo "**默认路由：** ${route_val}" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
        fi
    done
}

# =============================================================================
# Markdown generation — 3.3 Process & Java
# =============================================================================

generate_process_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.3 进程与 Java 应用

EOF

    # Process overview per server
    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        echo "### ${hostname}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"

        # Service status
        local svc_val
        svc_val=$(get_val "$i" "SERVICE_STATUS")
        if [ -n "${svc_val}" ]; then
            echo "**服务状态：** ${svc_val}" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
        fi

        # Process counts
        local proc_total proc_zombie proc_running proc_sleeping
        proc_total=$(get_val "$i" "PROCESS_TOTAL")
        proc_zombie=$(get_val "$i" "PROCESS_ZOMBIE")
        proc_running=$(get_val "$i" "PROCESS_RUNNING")
        proc_sleeping=$(get_val "$i" "PROCESS_SLEEPING")

        echo "**进程统计：** 总计 ${proc_total:-N/A}，运行 ${proc_running:-N/A}，休眠 ${proc_sleeping:-N/A}，僵尸 ${proc_zombie:-N/A}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"

        # Check zombie threshold
        local zombie_status
        zombie_status=$(check_threshold "ZOMBIE_COUNT" "${proc_zombie}")
        [ "${zombie_status}" != "OK" ] && add_issue "${zombie_status}" "Zombie 进程数 ${proc_zombie} (${zombie_status})" "${hostname}"

        # CPU Top5
        local top5_cpu
        top5_cpu=$(get_val "$i" "PROCESS_TOP5_CPU")
        if [ -n "${top5_cpu}" ]; then
            echo "**CPU Top5 进程：**" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
            echo "| PID | 进程名 | CPU% |" >> "${MD_FILE}"
            echo "|-----|--------|------|" >> "${MD_FILE}"
            IFS='|' read -ra parts <<< "${top5_cpu}"
            for part in "${parts[@]}"; do
                [ -z "${part}" ] && continue
                local pid name cpu
                pid=$(echo "${part}" | cut -d: -f2)
                name=$(echo "${part}" | cut -d: -f3)
                cpu=$(echo "${part}" | cut -d: -f4)
                printf "| %s | %s | %s |\n" "${pid}" "${name}" "${cpu}" >> "${MD_FILE}"
            done
            echo "" >> "${MD_FILE}"
        fi

        # MEM Top5
        local top5_mem
        top5_mem=$(get_val "$i" "PROCESS_TOP5_MEM")
        if [ -n "${top5_mem}" ]; then
            echo "**内存 Top5 进程：**" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
            echo "| PID | 进程名 | 内存 |" >> "${MD_FILE}"
            echo "|-----|--------|------|" >> "${MD_FILE}"
            IFS='|' read -ra parts <<< "${top5_mem}"
            for part in "${parts[@]}"; do
                [ -z "${part}" ] && continue
                local pid name mem
                pid=$(echo "${part}" | cut -d: -f2)
                name=$(echo "${part}" | cut -d: -f3)
                mem=$(echo "${part}" | cut -d: -f4)
                printf "| %s | %s | %s |\n" "${pid}" "${name}" "${mem}" >> "${MD_FILE}"
            done
            echo "" >> "${MD_FILE}"
        fi

        # Java processes
        local java_count
        java_count=$(get_val "$i" "PROCESS_JAVA_COUNT")
        if [ -n "${java_count}" ] && [ "${java_count}" != "0" ]; then
            echo "**Java 进程（${java_count} 个）：**" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"

            local j
            for j in $(seq 1 "${java_count}"); do
                local java_cmd java_jvm_args java_gc java_oom java_log
                java_cmd=$(get_val "$i" "JAVA_CMD_${j}")
                java_jvm_args=$(get_val "$i" "JAVA_JVM_XMS_XMX_${j}")
                java_gc=$(get_val "$i" "JAVA_JVM_GC_DETAIL_${j}")
                java_oom=$(get_val "$i" "JAVA_JVM_OOM_DUMP_${j}")
                java_log=$(get_val "$i" "JAVA_LOG_COLLECT_${j}")

                echo "#### Java 进程 ${j}" >> "${MD_FILE}"
                echo "" >> "${MD_FILE}"
                echo "- **命令行：** \`${java_cmd:-N/A}\`" >> "${MD_FILE}"
                echo "- **JVM 参数：** \`${java_jvm_args:-N/A}\`" >> "${MD_FILE}"
                echo "- **GC 统计：** ${java_gc:-N/A}" >> "${MD_FILE}"
                echo "- **OOM Dump：** ${java_oom:-N/A}" >> "${MD_FILE}"
                echo "- **日志路径：** ${java_log:-N/A}" >> "${MD_FILE}"
                echo "" >> "${MD_FILE}"
            done
        else
            echo "**Java 进程：** 无" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
        fi
    done
}

# =============================================================================
# Markdown generation — 3.4 Middleware
# =============================================================================

generate_middleware_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.4 中间件状态

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        echo "### ${hostname}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"

        # Redis
        local redis_val
        redis_val=$(get_val "$i" "REDIS_STATUS")
        echo "- **Redis：** ${redis_val:-N/A}" >> "${MD_FILE}"

        # Nacos
        local nacos_val
        nacos_val=$(get_val "$i" "NACOS_STATUS")
        echo "- **Nacos：** ${nacos_val:-N/A}" >> "${MD_FILE}"

        # MySQL
        local mysql_val
        mysql_val=$(get_val "$i" "MYSQL_STATUS")
        echo "- **MySQL：** ${mysql_val:-N/A}" >> "${MD_FILE}"

        local mysql_repl
        mysql_repl=$(get_val "$i" "MYSQL_REPLICATION")
        [ -n "${mysql_repl}" ] && echo "  - 主从复制：${mysql_repl}" >> "${MD_FILE}"

        local mysql_buf
        mysql_buf=$(get_val "$i" "MYSQL_INNODB_BUFFER")
        [ -n "${mysql_buf}" ] && echo "  - InnoDB Buffer：${mysql_buf}" >> "${MD_FILE}"

        echo "" >> "${MD_FILE}"
    done
}

# =============================================================================
# Markdown generation — 3.5 System Security
# =============================================================================

generate_security_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.5 系统安全

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        echo "### ${hostname}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"

        # SSH config
        local ssh_val
        ssh_val=$(get_val "$i" "SSH_CONFIG")
        echo "- **SSH 配置：** ${ssh_val:-N/A}" >> "${MD_FILE}"

        # SSH failed login
        local ssh_fail
        ssh_fail=$(get_val "$i" "SSH_FAILED_LOGIN_TODAY")
        local fail_count=0
        if [ -n "${ssh_fail}" ]; then
            fail_count=$(echo "${ssh_fail}" | cut -d'|' -f1)
            echo "- **今日 SSH 登录失败：** ${fail_count}" >> "${MD_FILE}"

            local fail_status
            fail_status=$(check_threshold "LOGIN_FAILED" "${fail_count}")
            [ "${fail_status}" != "OK" ] && add_issue "${fail_status}" "SSH 登录失败 ${fail_count} 次 (${fail_status})" "${hostname}"
        fi

        # Trusted keys
        local trusted
        trusted=$(get_val "$i" "SSH_TRUSTED_KEYS")
        echo "- **SSH 信任密钥数：** ${trusted:-0}" >> "${MD_FILE}"

        # User login today
        local user_login
        user_login=$(get_val "$i" "USER_LOGIN_TODAY")
        echo "- **今日用户登录：** ${user_login:-无记录}" >> "${MD_FILE}"

        # Sudo today
        local sudo_val
        sudo_val=$(get_val "$i" "USER_SUDO_TODAY")
        echo "- **今日 Sudo 操作：** ${sudo_val:-0}" >> "${MD_FILE}"

        # Password expire
        local pass_exp
        pass_exp=$(get_val "$i" "USER_PASSWORD_EXPIRE")
        echo "- **密码过期策略：** ${pass_exp:-N/A}" >> "${MD_FILE}"

        # Locked users
        local locked
        locked=$(get_val "$i" "USER_LOCKED")
        echo "- **锁定用户数：** ${locked:-0}" >> "${MD_FILE}"

        # SELinux
        local selinux
        selinux=$(get_val "$i" "SELINUX_STATUS")
        echo "- **SELinux：** ${selinux:-N/A}" >> "${MD_FILE}"

        # Fail2ban
        local fail2ban
        fail2ban=$(get_val "$i" "FAIL2BAN_STATUS")
        echo "- **Fail2ban：** ${fail2ban:-N/A}" >> "${MD_FILE}"

        # Sysctl
        local sysctl
        sysctl=$(get_val "$i" "SYSCTL_KEY_PARAMS")
        if [ -n "${sysctl}" ]; then
            echo "- **内核关键参数：**" >> "${MD_FILE}"
            IFS='|' read -ra parts <<< "${sysctl}"
            for part in "${parts[@]}"; do
                [ -z "${part}" ] && continue
                echo "  - \`${part}\`" >> "${MD_FILE}"
            done
        fi

        # NTP
        local ntp
        ntp=$(get_val "$i" "NTP_SYNC")
        echo "- **NTP 同步：** ${ntp:-N/A}" >> "${MD_FILE}"
        [ "${ntp}" = "NOT_SYNCED" ] && add_issue "WARN" "NTP 未同步" "${hostname}"

        echo "" >> "${MD_FILE}"
    done
}

# =============================================================================
# Markdown generation — 3.6 Crontab Analysis
# =============================================================================

generate_crontab_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.6 Crontab 分析

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        echo "### ${hostname}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"

        # System crontab
        local cron_sys
        cron_sys=$(get_val "$i" "CRONTAB_SYSTEM")
        if [ -n "${cron_sys}" ]; then
            echo "**系统定时任务：**" >> "${MD_FILE}"
            echo "" >> "${MD_FILE}"
            echo "| 用户 | 来源 | 调度 | 命令 |" >> "${MD_FILE}"
            echo "|------|------|------|------|" >> "${MD_FILE}"
            # Handle || in commands: replace with placeholder, split by |, restore
            local cron_safe="${cron_sys//||/__PIPE_PIPE__}"
            IFS='|' read -ra parts <<< "${cron_safe}"
            for part in "${parts[@]}"; do
                [ -z "${part}" ] && continue
                # Restore || in the part
                part="${part//__PIPE_PIPE__/||}"
                local user source schedule cmd
                user=$(echo "${part}" | cut -d: -f1)
                source=$(echo "${part}" | cut -d: -f2)
                schedule=$(echo "${part}" | cut -d: -f3)
                # Command may contain colons, take from field 4 onwards
                cmd=$(echo "${part}" | cut -d: -f4-)
                printf "| %s | %s | %s | %s |\n" "${user}" "${source}" "${schedule}" "${cmd}" >> "${MD_FILE}"
            done
            echo "" >> "${MD_FILE}"
        fi

        # Anacron
        local anacron
        anacron=$(get_val "$i" "CRONTAB_ANACRON")
        echo "**Anacron：** ${anacron:-N/A}" >> "${MD_FILE}"

        # Analysis
        local analysis
        analysis=$(get_val "$i" "CRONTAB_ANALYSIS")
        echo "**分析结果：** ${analysis:-N/A}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
    done
}

# =============================================================================
# Markdown generation — 3.7 Logs & Alerts
# =============================================================================

generate_log_alert_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.7 日志与告警

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        echo "### ${hostname}" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"

        # Auth failures
        local auth_fail
        auth_fail=$(get_val "$i" "AUTH_FAILED_TODAY")
        local auth_count=0
        if [ -n "${auth_fail}" ]; then
            auth_count=$(echo "${auth_fail}" | cut -d'|' -f1)
        fi
        echo "- **今日认证失败：** ${auth_count}" >> "${MD_FILE}"
        local auth_status
        auth_status=$(check_threshold "AUTH_FAILED" "${auth_count}")
        [ "${auth_status}" != "OK" ] && add_issue "${auth_status}" "认证失败 ${auth_count} 次 (${auth_status})" "${hostname}"

        # Kernel errors
        local kern_err
        kern_err=$(get_val "$i" "KERNEL_ERROR_TODAY")
        echo "- **内核错误：** ${kern_err:-0}" >> "${MD_FILE}"
        local kern_status
        kern_status=$(check_threshold "KERNEL_ERROR" "${kern_err}")
        [ "${kern_status}" != "OK" ] && add_issue "${kern_status}" "内核错误 ${kern_err} 次 (${kern_status})" "${hostname}"

        # OOM
        local oom
        oom=$(get_val "$i" "OOM_KILLER_TODAY")
        echo "- **OOM Killer：** ${oom:-0}" >> "${MD_FILE}"
        [ "${oom:-0}" != "0" ] && add_issue "CRIT" "OOM Killer 今日触发 ${oom} 次" "${hostname}"

        # Segfault
        local segfault
        segfault=$(get_val "$i" "SEGFAULT_TODAY")
        echo "- **段错误：** ${segfault:-0}" >> "${MD_FILE}"

        # Syslog errors
        local syslog_err
        syslog_err=$(get_val "$i" "SYSLOG_ERROR_TODAY")
        echo "- **系统日志错误：** ${syslog_err:-0}" >> "${MD_FILE}"

        # Security alert
        local sec_alert
        sec_alert=$(get_val "$i" "SECURITY_ALERT")
        echo "- **安全告警：** ${sec_alert:-NONE}" >> "${MD_FILE}"

        # Last login
        local last_login
        last_login=$(get_val "$i" "LAST_LOGIN")
        echo "- **最近登录：** ${last_login:-N/A}" >> "${MD_FILE}"

        echo "" >> "${MD_FILE}"
    done
}

# =============================================================================
# Markdown generation — Appendix
# =============================================================================

generate_appendix() {
    cat >> "${MD_FILE}" <<EOF

# 附录

## 原始采集数据

以下为本次巡检使用的原始采集数据文件：

EOF

    for f in "${SERVER_FILES[@]}"; do
        echo "- \`${f}\`" >> "${MD_FILE}"
    done

    echo "" >> "${MD_FILE}"
    echo "---" >> "${MD_FILE}"
    echo "" >> "${MD_FILE}"
    echo "*报告由 AutoSystemCheck report.sh v${VERSION} 自动生成*" >> "${MD_FILE}"
}

# =============================================================================
# Pandoc conversion
# =============================================================================

ensure_pandoc() {
    if ! command -v pandoc >/dev/null 2>&1; then
        log_error "pandoc is not installed. Install it with:"
        log_error "  Ubuntu/Debian: sudo apt install pandoc"
        log_error "  CentOS/RHEL:   sudo yum install pandoc"
        log_error "  macOS:         brew install pandoc"
        log_error ""
        log_error "Markdown file has been generated: ${MD_FILE}"
        exit 1
    fi
    log_info "pandoc found: $(pandoc --version | head -1)"
}

convert_to_docx() {
    ensure_pandoc

    mkdir -p "${OUTPUT_DIR}"

    log_info "Converting Markdown to Word..."
    pandoc "${MD_FILE}" \
        -o "${OUTPUT_FILE}" \
        --toc \
        --toc-depth=3 \
        -V lang=zh-CN \
        -V mainfont="SimSun" \
        --standalone

    if [ -f "${OUTPUT_FILE}" ]; then
        log_info "Report generated: ${OUTPUT_FILE}"
    else
        log_error "Failed to generate report"
        exit 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    load_thresholds
    load_all_dat

    # Prepare working directory
    mkdir -p "${OUTPUT_DIR}"

    log_info "Generating Markdown report..."

    # Phase 1: Generate detail sections first (collects issues along the way)
    local details_md="${OUTPUT_DIR}/.details_temp.md"
    MD_FILE="${details_md}"
    : > "${MD_FILE}"

    generate_resource_section
    generate_network_section
    generate_process_section
    generate_middleware_section
    generate_security_section
    generate_crontab_section
    generate_log_alert_section

    # Phase 2: Now that issues are collected, generate overview and issues summary
    local overview_md="${OUTPUT_DIR}/.overview_temp.md"
    MD_FILE="${overview_md}"
    : > "${MD_FILE}"

    generate_cover
    generate_overview
    generate_issues_summary

    # Phase 3: Generate appendix
    local appendix_md="${OUTPUT_DIR}/.appendix_temp.md"
    MD_FILE="${appendix_md}"
    : > "${MD_FILE}"

    generate_appendix

    # Phase 4: Assemble final Markdown in correct order
    MD_FILE="${OUTPUT_DIR}/.report_temp.md"
    cat "${overview_md}" "${details_md}" "${appendix_md}" > "${MD_FILE}"
    rm -f "${overview_md}" "${details_md}" "${appendix_md}"

    log_info "Markdown report generated: ${MD_FILE}"

    # Convert to docx
    convert_to_docx

    # Keep the .md file for reference
    local md_keep="${OUTPUT_DIR}/巡检报告_$(date +%Y%m%d).md"
    cp "${MD_FILE}" "${md_keep}"
    rm -f "${MD_FILE}"

    log_info "Markdown saved: ${md_keep}"
    log_info "Done!"
}

main "$@"
