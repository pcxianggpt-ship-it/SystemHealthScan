#!/bin/bash
set -euo pipefail

print_kv() {
    echo "$1=$2"
}

collect_system_info() {
    local hostname=""
    if command -v hostname >/dev/null 2>&1; then
        hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    fi
    print_kv "HOSTNAME" "${hostname}"
    
    local uname_n=""
    if command -v uname >/dev/null 2>&1; then
        uname_n=$(uname -n 2>/dev/null || echo "unknown")
    fi
    print_kv "UNAME_N" "${uname_n}"
    
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1 || echo "")
    elif command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [ -z "${ip}" ] && ip="unknown"
    print_kv "IP" "${ip}"
    
    print_kv "CHECK_TIME" "$(date '+%Y-%m-%d_%H:%M:%S')"
    
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
}

main() {
    local output_file="${1:-/dev/stdout}"
    
    if [ "${output_file}" != "/dev/stdout" ]; then
        local output_dir
        output_dir=$(dirname "${output_file}")
        if [ ! -d "${output_dir}" ]; then
            mkdir -p "${output_dir}" 2>/dev/null || {
                echo "ERROR: Failed to create output directory: ${output_dir}" >&2
                return 1
            }
        fi
    fi
    
    exec 3>&1
    exec >"${output_file}"
    
    collect_system_info
    
    exec >&3
}

trap 'exec >&3' EXIT
main "$@"
