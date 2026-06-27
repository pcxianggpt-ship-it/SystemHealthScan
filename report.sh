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

# Filter regexps (see docs/superpowers/specs/2026-06-26-report-layout-design.md §7)
NIC_FILTER_REGEX='^(veth|br-|docker|cni|flannel|kube-ipvs|virbr|vboxnet|tap|tun)|^lo$'
MOUNT_FILTER_REGEX='/var/lib/docker/containers/.*/mounts/shm|/var/lib/kubelet/pods/|/var/lib/docker/overlay2'

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
# Layout helpers (see spec §7, §8)
# =============================================================================

# 过滤虚拟网卡：参数为网卡名，匹配 NIC_FILTER_REGEX 返回 0（要过滤），否则 1
is_virtual_nic() {
    local nic_name="$1"
    [[ "${nic_name}" =~ ${NIC_FILTER_REGEX} ]]
}

# 过滤容器挂载：参数为挂载点路径，匹配 MOUNT_FILTER_REGEX 返回 0（要过滤），否则 1
is_container_mount() {
    local mount_point="$1"
    [[ "${mount_point}" =~ ${MOUNT_FILTER_REGEX} ]]
}

# 从 Java 完整命令行提取简短进程名（≤ 50 字符）。算法见 spec §8
extract_short_process_name() {
    local cmdline="$1"
    local result=""

    # 1. 优先取 -jar <path> 的 basename
    local jar
    jar=$(echo "${cmdline}" | grep -oE -- '-jar[[:space:]]+[^[:space:]]+\.jar' | head -1 | sed 's/.*-jar[[:space:]]*//')
    if [[ -n "${jar}" ]]; then
        result=$(basename "${jar}")
    fi

    # 2. Tomcat 主类特判
    if [[ -z "${result}" ]] && echo "${cmdline}" | grep -q "org.apache.catalina.startup.Bootstrap"; then
        result="tomcat-Bootstrap"
    fi

    # 3. 取最后一个含至少 2 个 . 的 token（Java 完整包名结构 org.xxx.YYY）
    #    避免 -c broker.conf 这类参数值被误选为主类
    if [[ -z "${result}" ]]; then
        local main_class
        main_class=$(echo "${cmdline}" | tr ' ' '\n' | grep -vE '^-' | awk -F'.' 'NF>=3' | tail -1)
        if [[ -n "${main_class}" ]]; then
            result=$(echo "${main_class}" | awk -F'.' '{print $NF}')
        fi
    fi

    # 4. 否则取 java 命令 basename
    if [[ -z "${result}" ]]; then
        local first_token
        first_token=$(echo "${cmdline}" | awk '{print $1}')
        if [[ -n "${first_token}" ]]; then
            result=$(basename "${first_token}")
        else
            result="unknown"
        fi
    fi

    # 5. 若超过 50 字符，截断加 ...
    if [[ ${#result} -gt 50 ]]; then
        result="${result:0:47}..."
    fi

    echo "${result}"
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

### 3.2.1 网卡状态

| 主机 | IP | 网卡 | 状态 | 速率 |
|------|----|------|------|------|
EOF

    # 网卡表（过滤虚拟网卡）
    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local nic_val
        nic_val=$(get_val "$i" "NET_NIC_")
        [ -z "${nic_val}" ] && continue

        IFS='|' read -ra parts <<< "${nic_val}"
        for part in "${parts[@]}"; do
            [ -z "${part}" ] && continue
            local nic_name nic_status nic_speed
            nic_name=$(echo "${part}" | cut -d: -f1)
            nic_status=$(echo "${part}" | cut -d: -f2)
            nic_speed=$(echo "${part}" | cut -d: -f3)

            # 跳过虚拟网卡
            is_virtual_nic "${nic_name}" && continue

            printf "| %s | %s | %s | %s | %s |\n" \
                "${hostname}" "${ip}" "${nic_name}" "${nic_status}" "${nic_speed}" >> "${MD_FILE}"
        done
    done

    # TCP 连接表
    cat >> "${MD_FILE}" <<EOF

### 3.2.2 TCP 连接状态

| 主机 | IP | ESTABLISHED | TIME_WAIT | CLOSE_WAIT | SYN_RECV |
|------|----|-------------|-----------|------------|----------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local tcp_val
        tcp_val=$(get_val "$i" "NET_TCP_STATUS")
        [ -z "${tcp_val}" ] && continue

        # 把 "ESTABLISHED:2|TIME_WAIT:0|..." 解析为关联
        declare -A tcp_map=()
        IFS='|' read -ra parts <<< "${tcp_val}"
        for part in "${parts[@]}"; do
            [ -z "${part}" ] && continue
            local k v
            k=$(echo "${part}" | cut -d: -f1)
            v=$(echo "${part}" | cut -d: -f2)
            tcp_map["${k}"]="${v}"

            # 阈值检查（保留原行为）
            if [ "${k}" = "CLOSE_WAIT" ] || [ "${k}" = "TIME_WAIT" ]; then
                local s
                s=$(check_threshold "${k}" "${v}")
                [ "${s}" != "OK" ] && add_issue "${s}" "TCP ${k} 连接数 ${v} (${s})" "${hostname}"
            fi
        done

        printf "| %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" \
            "${tcp_map[ESTABLISHED]:-0}" \
            "${tcp_map[TIME_WAIT]:-0}" \
            "${tcp_map[CLOSE_WAIT]:-0}" \
            "${tcp_map[SYN_RECV]:-0}" >> "${MD_FILE}"
        unset tcp_map
    done

    # 监听端口（每台一段紧凑列表）
    cat >> "${MD_FILE}" <<EOF

### 3.2.3 监听端口

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local ports_val
        ports_val=$(get_val "$i" "NET_LISTEN_PORTS")
        if [[ -z "${ports_val}" ]]; then
            printf "**%s (%s)** 监听端口：（无）\n\n" "${hostname}" "${ip}" >> "${MD_FILE}"
        else
            printf "**%s (%s)** 监听端口：\n\n%s\n\n" \
                "${hostname}" "${ip}" "${ports_val}" >> "${MD_FILE}"
        fi
    done

    # 网络附属
    cat >> "${MD_FILE}" <<EOF

### 3.2.4 网络附属

| 主机 | IP | DNS 解析 | 防火墙 | 默认路由 |
|------|----|----------|--------|----------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        printf "| %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" \
            "$(get_val "$i" "NET_DNS_RESOLVE")" \
            "$(get_val "$i" "NET_FIREWALL")" \
            "$(get_val "$i" "NET_ROUTE")" >> "${MD_FILE}"
    done
}

# =============================================================================
# Markdown generation — 3.3 Process & Java
# =============================================================================

generate_process_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.3 进程与 Java 应用

### 3.3.1 进程统计

| 主机 | IP | 总计 | 运行 | 休眠 | 僵尸 |
|------|----|----|------|------|------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local total running sleeping zombie
        total=$(get_val "$i" "PROCESS_TOTAL")
        running=$(get_val "$i" "PROCESS_RUNNING")
        sleeping=$(get_val "$i" "PROCESS_SLEEPING")
        zombie=$(get_val "$i" "PROCESS_ZOMBIE")
        [[ -z "${total}" ]] && total="N/A"
        [[ -z "${running}" ]] && running="N/A"
        [[ -z "${sleeping}" ]] && sleeping="N/A"
        [[ -z "${zombie}" ]] && zombie="N/A"
        printf "| %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" "${total}" "${running}" "${sleeping}" "${zombie}" >> "${MD_FILE}"

        # 僵尸进程阈值检查（保留原行为）
        if [[ "${zombie}" =~ ^[0-9]+$ ]] && [[ "${zombie}" -gt 0 ]]; then
            local s
            s=$(check_threshold "ZOMBIE_COUNT" "${zombie}")
            [ "${s}" != "OK" ] && add_issue "${s}" "僵尸进程数 ${zombie}" "${hostname}"
        fi
    done

    # CPU Top5 + 内存 Top5：每台一段
    cat >> "${MD_FILE}" <<EOF

### 3.3.2 CPU 与内存 Top5

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"

        printf "**%s (%s) CPU Top5：**\n\n" "${hostname}" "${ip}" >> "${MD_FILE}"
        echo "| PID | 进程名 | CPU% |" >> "${MD_FILE}"
        echo "|-----|--------|------|" >> "${MD_FILE}"
        local cpu_top5
        cpu_top5=$(get_val "$i" "CPU_TOP5")
        if [[ -n "${cpu_top5}" ]]; then
            IFS='|' read -ra parts <<< "${cpu_top5}"
            for part in "${parts[@]}"; do
                [[ -z "${part}" ]] && continue
                echo "${part}" | awk -F: '{printf "| %s | %s | %s |\n", $2, $3, $4}' >> "${MD_FILE}"
            done
        fi
        echo "" >> "${MD_FILE}"

        printf "**%s (%s) 内存 Top5：**\n\n" "${hostname}" "${ip}" >> "${MD_FILE}"
        echo "| PID | 进程名 | 内存 |" >> "${MD_FILE}"
        echo "|-----|--------|------|" >> "${MD_FILE}"
        local mem_top5
        mem_top5=$(get_val "$i" "PROCESS_TOP5_MEM")
        if [[ -n "${mem_top5}" ]]; then
            IFS='|' read -ra parts <<< "${mem_top5}"
            for part in "${parts[@]}"; do
                [[ -z "${part}" ]] && continue
                echo "${part}" | awk -F: '{printf "| %s | %s | %s |\n", $2, $3, $4}' >> "${MD_FILE}"
            done
        fi
        echo "" >> "${MD_FILE}"
    done

    # 服务状态：每台一段
    cat >> "${MD_FILE}" <<EOF

### 3.3.3 服务状态

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local svc_val
        svc_val=$(get_val "$i" "SERVICE_STATUS")
        [[ -z "${svc_val}" ]] && continue

        printf "**%s (%s) 服务状态：**\n\n" "${hostname}" "${ip}" >> "${MD_FILE}"
        echo "| 服务 | 状态 |" >> "${MD_FILE}"
        echo "|------|------|" >> "${MD_FILE}"
        IFS='|' read -ra parts <<< "${svc_val}"
        for part in "${parts[@]}"; do
            [[ -z "${part}" ]] && continue
            local svc state
            svc=$(echo "${part}" | cut -d: -f1)
            state=$(echo "${part}" | cut -d: -f2)
            printf "| %s | %s |\n" "${svc}" "${state}" >> "${MD_FILE}"
        done
        echo "" >> "${MD_FILE}"
    done

    # Java 进程详情（折叠命令行）
    cat >> "${MD_FILE}" <<EOF

### 3.3.4 Java 进程详情

| 主机 | IP | PID | 进程名 | Xmx | GC Old% | OOM | 日志路径 |
|------|----|-----|--------|-----|---------|-----|----------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local java_count
        java_count=$(get_val "$i" "PROCESS_JAVA_COUNT")
        [[ -z "${java_count}" ]] && continue
        # 仅处理数字值，避免 -eq 触发算术错误
        [[ "${java_count}" =~ ^[0-9]+$ ]] || continue
        [[ "${java_count}" -eq 0 ]] && continue

        local idx=1
        while [[ ${idx} -le ${java_count} ]]; do
            local ps_field pid cmdline short_name xmx gc_old oom log_path

            # JAVA_PS_<idx> 是复合字段：USER:user|PID:12345|START:...|...
            ps_field=$(get_val "$i" "JAVA_PS_${idx}")
            pid=$(echo "${ps_field}" | grep -oE 'PID:[^|]+' | cut -d: -f2)
            [[ -z "${pid}" ]] && pid="N/A"

            cmdline=$(get_val "$i" "JAVA_CMD_${idx}")
            short_name=$(extract_short_process_name "${cmdline}")

            # JAVA_JVM_XMS_XMX_<idx>: Xms:default:Xmx:1g
            local jvm_field
            jvm_field=$(get_val "$i" "JAVA_JVM_XMS_XMX_${idx}")
            xmx=$(echo "${jvm_field}" | grep -oE 'Xmx:[^:|]+' | cut -d: -f2)
            [[ -z "${xmx}" ]] && xmx="default"

            # JAVA_JVM_GC_DETAIL_<idx>: OldGen:61.36%|Eden:..%|Survivor:..%
            local gc_field
            gc_field=$(get_val "$i" "JAVA_JVM_GC_DETAIL_${idx}")
            gc_old=$(echo "${gc_field}" | grep -oE 'OldGen:[0-9.]+%' | head -1 | cut -d: -f2)
            [[ -z "${gc_old}" ]] && gc_old="N/A"

            oom=$(get_val "$i" "JAVA_JVM_OOM_DUMP_${idx}")
            [[ -z "${oom}" ]] && oom="NONE"

            log_path=$(get_val "$i" "JAVA_LOG_COLLECT_${idx}")
            [[ -z "${log_path}" ]] && log_path="SOURCE:NOT_FOUND"

            printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n" \
                "${hostname}" "${ip}" "${pid}" "${short_name}" \
                "${xmx}" "${gc_old}" "${oom}" "${log_path}" >> "${MD_FILE}"

            idx=$((idx + 1))
        done
    done
}

# =============================================================================
# Markdown generation — 3.4 Middleware
# =============================================================================

generate_middleware_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.4 中间件状态

| 主机 | IP | Redis | Nacos | MySQL 版本 | MySQL 连接 | 复制角色 | InnoDB Buffer |
|------|----|-------|-------|-----------|-----------|---------|---------------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"

        local redis nacos mysql_ver mysql_conn repl innodb
        redis=$(get_val "$i" "REDIS_STATUS")
        nacos=$(get_val "$i" "NACOS_STATUS")
        # REDIS_STATUS 可能是 "NOT_RUNNING" 或 "RUNNING|VERSION:..."；统一显示 RUNNING/NOT_RUNNING
        [[ "${redis}" == RUNNING* ]] && redis="RUNNING"
        [[ -z "${redis}" ]] && redis="N/A"
        [[ "${nacos}" == RUNNING* ]] && nacos="RUNNING"
        [[ -z "${nacos}" ]] && nacos="N/A"

        # MYSQL_STATUS 格式：RUNNING|VERSION:5.7|CONNECTIONS:10/100|...
        local mysql_status
        mysql_status=$(get_val "$i" "MYSQL_STATUS")
        if [[ "${mysql_status}" == "RUNNING|"* ]]; then
            mysql_ver=$(echo "${mysql_status}" | grep -oE 'VERSION:[^|]+' | cut -d: -f2 || true)
            mysql_conn=$(echo "${mysql_status}" | grep -oE 'CONNECTIONS:[^|]+' | cut -d: -f2 || true)
            [[ -z "${mysql_ver}" ]] && mysql_ver="N/A"
            [[ -z "${mysql_conn}" ]] && mysql_conn="N/A"
        else
            # NOT_RUNNING / RUNNING|NO_CLIENT / 空：版本与连接都显示 N/A
            mysql_ver="N/A"
            mysql_conn="N/A"
        fi

        # MYSQL_REPLICATION 格式：ROLE:MASTER|SLAVE_STATUS:N/A|BEHIND:0s
        local repl_val
        repl_val=$(get_val "$i" "MYSQL_REPLICATION")
        repl=$(echo "${repl_val}" | grep -oE 'ROLE:[^|]+' | cut -d: -f2 || true)
        [[ -z "${repl}" ]] && repl="${repl_val:-N/A}"

        innodb=$(get_val "$i" "MYSQL_INNODB_BUFFER")
        [[ -z "${innodb}" ]] && innodb="N/A"

        printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" "${redis}" "${nacos}" \
            "${mysql_ver}" "${mysql_conn}" "${repl}" "${innodb}" >> "${MD_FILE}"
    done
}

# =============================================================================
# Markdown generation — 3.5 System Security
# =============================================================================

generate_security_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.5 系统安全

### 3.5.1 SSH 配置

| 主机 | IP | 端口 | Root 登录 | 密码认证 | 空密码 | MaxAuth |
|------|----|------|-----------|----------|--------|---------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local ssh_val
        ssh_val=$(get_val "$i" "SSH_CONFIG")
        # 格式：PORT:22|ROOT_LOGIN:yes|PASSWORD_AUTH:yes|PERMIT_EMPTY:no|MAX_AUTH:6 或 N/A
        local port="" root_login="" pass_auth="" empty_pw="" max_auth=""
        if [[ "${ssh_val}" == "PORT:"* ]]; then
            port=$(echo "${ssh_val}"        | grep -oE 'PORT:[^|]+'         | cut -d: -f2 || true)
            root_login=$(echo "${ssh_val}"  | grep -oE 'ROOT_LOGIN:[^|]+'   | cut -d: -f2 || true)
            pass_auth=$(echo "${ssh_val}"   | grep -oE 'PASSWORD_AUTH:[^|]+'| cut -d: -f2 || true)
            empty_pw=$(echo "${ssh_val}"    | grep -oE 'PERMIT_EMPTY:[^|]+' | cut -d: -f2 || true)
            max_auth=$(echo "${ssh_val}"    | grep -oE 'MAX_AUTH:[^|]+'     | cut -d: -f2 || true)
        fi
        [[ -z "${port}" ]] && port="N/A"
        [[ -z "${root_login}" ]] && root_login="N/A"
        [[ -z "${pass_auth}" ]] && pass_auth="N/A"
        [[ -z "${empty_pw}" ]] && empty_pw="N/A"
        [[ -z "${max_auth}" ]] && max_auth="N/A"
        printf "| %s | %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" "${port}" "${root_login}" "${pass_auth}" "${empty_pw}" "${max_auth}" >> "${MD_FILE}"
    done

    # 内核关键参数
    cat >> "${MD_FILE}" <<EOF

### 3.5.2 内核关键参数

| 主机 | IP | somaxconn | swappiness | file-max | tcp_syn_backlog |
|------|----|-----------|------------|----------|-----------------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local sysctl_val
        sysctl_val=$(get_val "$i" "SYSCTL_KEY_PARAMS")
        # 格式：key=value|key=value|...
        local somaxconn="" swappiness="" file_max="" tcp_syn=""
        somaxconn=$(echo "${sysctl_val}"  | grep -oE 'net\.core\.somaxconn=[^|]+'         | cut -d= -f2 || true)
        swappiness=$(echo "${sysctl_val}" | grep -oE 'vm\.swappiness=[^|]+'              | cut -d= -f2 || true)
        file_max=$(echo "${sysctl_val}"   | grep -oE 'fs\.file-max=[^|]+'                | cut -d= -f2 || true)
        tcp_syn=$(echo "${sysctl_val}"    | grep -oE 'net\.ipv4\.tcp_max_syn_backlog=[^|]+' | cut -d= -f2 || true)
        [[ -z "${somaxconn}" ]]  && somaxconn="N/A"
        [[ -z "${swappiness}" ]] && swappiness="N/A"
        [[ -z "${file_max}" ]]   && file_max="N/A"
        [[ -z "${tcp_syn}" ]]    && tcp_syn="N/A"
        printf "| %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" "${somaxconn}" "${swappiness}" "${file_max}" "${tcp_syn}" >> "${MD_FILE}"
    done

    # 安全综合状态
    cat >> "${MD_FILE}" <<EOF

### 3.5.3 安全综合状态

| 主机 | IP | SELinux | Fail2ban | NTP 同步 | 锁定用户 | Sudo 今日 |
|------|----|---------|----------|----------|----------|-----------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local selinux="" fail2ban="" ntp="" locked="" sudo_today=""
        selinux=$(get_val "$i" "SELINUX_STATUS")
        fail2ban=$(get_val "$i" "FAIL2BAN_STATUS")
        ntp=$(get_val "$i" "NTP_SYNC")
        locked=$(get_val "$i" "USER_LOCKED")
        sudo_today=$(get_val "$i" "USER_SUDO_TODAY")
        [[ -z "${selinux}" ]]   && selinux="N/A"
        [[ -z "${fail2ban}" ]]  && fail2ban="N/A"
        [[ -z "${ntp}" ]]       && ntp="N/A"
        [[ -z "${locked}" ]]    && locked="N/A"
        [[ -z "${sudo_today}" ]] && sudo_today="N/A"
        printf "| %s | %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" "${selinux}" "${fail2ban}" "${ntp}" "${locked}" "${sudo_today}" >> "${MD_FILE}"
    done

    # 今日登录用户
    cat >> "${MD_FILE}" <<EOF

### 3.5.4 今日登录用户

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local login
        login=$(get_val "$i" "USER_LOGIN_TODAY")
        [[ -z "${login}" ]] && login="无"
        printf "**%s (%s)：** %s\n\n" "${hostname}" "${ip}" "${login}" >> "${MD_FILE}"
    done
}

# =============================================================================
# Markdown generation — 3.6 Crontab Analysis
# =============================================================================

generate_crontab_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.6 Crontab 分析

| 主机 | IP | 用户 | 来源 | 调度 | 命令 |
|------|----|----|------|------|------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local cron_val
        cron_val=$(get_val "$i" "CRONTAB_SYSTEM")
        [[ -z "${cron_val}" || "${cron_val}" == "NONE" ]] && continue

        # 格式：user:source:schedule:cmd|...
        # cmd 可能含 ":"，用 awk 重构第 4 段以后的内容
        IFS='|' read -ra parts <<< "${cron_val}"
        for part in "${parts[@]}"; do
            [[ -z "${part}" ]] && continue
            local user="" source="" schedule="" cmd=""
            user=$(echo "${part}"     | awk -F: '{print $1}')
            source=$(echo "${part}"   | awk -F: '{print $2}')
            schedule=$(echo "${part}" | awk -F: '{print $3}')
            cmd=$(echo "${part}"      | awk -F: '{for(j=4;j<=NF;j++) printf "%s%s", $j, (j<NF?":":"")}')
            [[ -z "${user}" ]]     && user="N/A"
            [[ -z "${source}" ]]   && source="N/A"
            [[ -z "${schedule}" ]] && schedule="N/A"
            [[ -z "${cmd}" ]]      && cmd="N/A"
            printf "| %s | %s | %s | %s | %s | %s |\n" \
                "${hostname}" "${ip}" "${user}" "${source}" "${schedule}" "${cmd}" >> "${MD_FILE}"
        done
    done

    # Anacron 单独段落（仅有数据时输出）
    local any_anacron=0
    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local anacron_val
        anacron_val=$(get_val "$i" "CRONTAB_ANACRON")
        if [[ -n "${anacron_val}" && "${anacron_val}" != "N/A" ]]; then
            any_anacron=1
            break
        fi
    done

    if [[ ${any_anacron} -eq 1 ]]; then
        cat >> "${MD_FILE}" <<EOF

### Anacron

EOF
        for i in "${!SERVER_HOSTNAMES[@]}"; do
            local hostname="${SERVER_HOSTNAMES[$i]}"
            local ip="${SERVER_IPS[$i]:-N/A}"
            local anacron_val
            anacron_val=$(get_val "$i" "CRONTAB_ANACRON")
            [[ -z "${anacron_val}" || "${anacron_val}" == "N/A" ]] && continue
            printf "**%s (%s)：** %s\n\n" "${hostname}" "${ip}" "${anacron_val}" >> "${MD_FILE}"
        done
    fi
}

# =============================================================================
# Markdown generation — 3.7 Logs & Alerts
# =============================================================================

generate_log_alert_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.7 日志与告警

| 主机 | IP | 认证失败 | 内核错误 | OOM Killer | 段错误 | 系统日志错误 | 安全告警 | 最近登录 |
|------|----|----------|----------|-----------|--------|-------------|----------|----------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"

        local auth_fail kernel_err oom segfault syslog_err sec_alert last_login
        auth_fail=$(get_val "$i" "AUTH_FAILED_TODAY")
        kernel_err=$(get_val "$i" "KERNEL_ERROR_TODAY")
        oom=$(get_val "$i" "OOM_KILLER_TODAY")
        segfault=$(get_val "$i" "SEGFAULT_TODAY")
        syslog_err=$(get_val "$i" "SYSLOG_ERROR_TODAY")
        sec_alert=$(get_val "$i" "SECURITY_ALERT")
        last_login=$(get_val "$i" "LAST_LOGIN")

        # 提取计数（值可能含 |SRC: 等附加信息，取首段数字）
        local oom_count
        oom_count=$(echo "${oom}" | awk -F'|' '{print $1}')
        [[ -z "${oom_count}" ]] && oom_count="0"

        # OOM 触发则记录 CRIT
        if [[ "${oom_count}" =~ ^[0-9]+$ ]] && [[ "${oom_count}" -gt 0 ]]; then
            add_issue "CRIT" "OOM Killer 今日触发 ${oom} 次" "${hostname}"
        fi

        [[ -z "${auth_fail}" ]]   && auth_fail="N/A"
        [[ -z "${kernel_err}" ]]  && kernel_err="N/A"
        [[ -z "${oom}" ]]         && oom="0"
        [[ -z "${segfault}" ]]    && segfault="N/A"
        [[ -z "${syslog_err}" ]]  && syslog_err="N/A"
        [[ -z "${sec_alert}" ]]   && sec_alert="N/A"
        [[ -z "${last_login}" ]]  && last_login="N/A"

        printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" "${auth_fail}" "${kernel_err}" "${oom}" \
            "${segfault}" "${syslog_err}" "${sec_alert}" "${last_login}" >> "${MD_FILE}"
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

    # 附录 B：Java 进程完整命令行
    cat >> "${MD_FILE}" <<'EOF'

## 附录 B：Java 进程完整命令行

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local java_count
        java_count=$(get_val "$i" "PROCESS_JAVA_COUNT")
        [[ -z "${java_count}" ]] && continue
        [[ "${java_count}" =~ ^[0-9]+$ ]] || continue
        [[ "${java_count}" -eq 0 ]] && continue

        printf "### B.%d %s (%s)\n\n" $((i + 1)) "${hostname}" "${ip}" >> "${MD_FILE}"

        local idx=1
        while [[ ${idx} -le ${java_count} ]]; do
            local ps_field pid cmdline
            ps_field=$(get_val "$i" "JAVA_PS_${idx}")
            pid=$(echo "${ps_field}" | grep -oE 'PID:[^|]+' | cut -d: -f2)
            [[ -z "${pid}" ]] && pid="N/A"
            cmdline=$(get_val "$i" "JAVA_CMD_${idx}")
            [[ -z "${cmdline}" ]] && cmdline="(unknown)"
            printf "#### PID %s\n\n\`\`\`\n%s\n\`\`\`\n\n" "${pid}" "${cmdline}" >> "${MD_FILE}"
            idx=$((idx + 1))
        done
    done

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
