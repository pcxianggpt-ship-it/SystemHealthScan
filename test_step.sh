#!/bin/bash
set -euo pipefail

echo "=== Test 1: hostname ==="
command -v hostname >/dev/null 2>&1 && hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown") || hostname="unknown"
echo "hostname: $hostname"

echo "=== Test 2: IP ==="
ip=""
if command -v ip >/dev/null 2>&1; then
    ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1)
elif command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
[ -z "${ip}" ] && ip="unknown"
echo "IP: $ip"

echo "=== Test 3: date ==="
echo "CHECK_TIME: $(date '+%Y-%m-%d_%H:%M:%S')"

echo "=== Test 4: OS ==="
os=""
if [ -f /etc/os-release ]; then
    os=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
elif [ -f /etc/redhat-release ]; then
    os=$(cat /etc/redhat-release)
elif [ -f /etc/lsb-release ]; then
    os=$(grep "^DISTRIB_DESCRIPTION=" /etc/lsb-release | cut -d'"' -f2)
fi
[ -z "${os}" ] && os="Unknown Linux"
echo "OS: $os"

echo "=== Test 5: uname ==="
kernel=$(uname -r 2>/dev/null || echo "unknown")
echo "KERNEL: $kernel"

arch=$(uname -m 2>/dev/null || echo "unknown")
echo "ARCH: $arch"

echo "=== All tests passed ==="
