#!/bin/bash
set -e

echo "开始调试..."

# 测试1: 基本变量
hostname=""
if command -v hostname >/dev/null 2>&1; then
    hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
fi
echo "HOSTNAME=${hostname}"

uname_n=""
if command -v uname >/dev/null 2>&1; then
    uname_n=$(uname -n 2>/dev/null || echo "unknown")
fi
echo "UNAME_N=${uname_n}"

# 测试2: IP地址获取
ip=""
if command -v ip >/dev/null 2>&1; then
    ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1 || echo "")
    echo "IP从ip命令: ${ip}"
elif command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "IP从hostname命令: ${ip}"
fi
[ -z "${ip}" ] && ip="unknown"
echo "IP=${ip}"

# 测试3: 时间
check_time=$(date '+%Y-%m-%d_%H:%M:%S')
echo "CHECK_TIME=${check_time}"

# 测试4: OS信息
os=""
if [ -f /etc/os-release ]; then
    echo "找到 /etc/os-release"
    os=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
    echo "OS从os-release: ${os}"
elif [ -f /etc/redhat-release ]; then
    echo "找到 /etc/redhat-release"
    os=$(cat /etc/redhat-release)
elif [ -f /etc/lsb-release ]; then
    echo "找到 /etc/lsb-release"
    os=$(grep "^DISTRIB_DESCRIPTION=" /etc/lsb-release | cut -d'"' -f2)
else
    echo "未找到OS信息文件"
fi
[ -z "${os}" ] && os="Unknown Linux"
echo "OS=${os}"

echo "调试完成"
