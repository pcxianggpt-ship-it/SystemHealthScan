#!/bin/bash
set -euo pipefail

print_kv() {
    echo "$1=$2"
}

collect_system_info() {
    echo "DEBUG: Start function"
    
    local hostname=""
    echo "DEBUG: hostname variable created"
    
    if command -v hostname >/dev/null 2>&1; then
        echo "DEBUG: hostname command found"
        hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
        echo "DEBUG: hostname value: $hostname"
    fi
    print_kv "HOSTNAME" "${hostname}"
    echo "DEBUG: Printed HOSTNAME"
    
    local uname_n=""
    echo "DEBUG: uname_n variable created"
    
    if command -v uname >/dev/null 2>&1; then
        echo "DEBUG: uname command found"
        uname_n=$(uname -n 2>/dev/null || echo "unknown")
        echo "DEBUG: uname_n value: $uname_n"
    fi
    print_kv "UNAME_N" "${uname_n}"
    echo "DEBUG: Printed UNAME_N"
    
    local ip=""
    echo "DEBUG: ip variable created"
    
    if command -v ip >/dev/null 2>&1; then
        echo "DEBUG: ip command found"
        ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1 || echo "")
        echo "DEBUG: ip from ip command: $ip"
    elif command -v hostname >/dev/null 2>&1; then
        echo "DEBUG: using hostname for ip"
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo "DEBUG: ip from hostname: $ip"
    fi
    echo "DEBUG: before ip check"
    [ -z "${ip}" ] && ip="unknown"
    echo "DEBUG: ip final value: $ip"
    print_kv "IP" "${ip}"
    echo "DEBUG: Printed IP"
    
    echo "DEBUG: About to print CHECK_TIME"
    print_kv "CHECK_TIME" "$(date '+%Y-%m-%d_%H:%M:%S')"
    echo "DEBUG: Printed CHECK_TIME"
}

collect_system_info
