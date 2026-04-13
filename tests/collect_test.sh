#!/bin/bash
#
# Test script for collect.sh
# Validates output format and required keys for all 10 modules
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

# Check a list of keys exist in the output file
check_keys() {
    local module_name="$1"
    shift
    local output_file="$1"
    shift
    local keys=("$@")

    run_test
    local missing=()
    for key in "${keys[@]}"; do
        if ! grep -qiE "^${key}=" "${output_file}"; then
            missing+=("${key}")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then
        pass "[${module_name}] All required keys present (${#keys[@]} keys)"
    else
        fail "[${module_name}] Missing keys: ${missing[*]}"
    fi
}

# Main test function
main() {
    local output_file
    output_file=$(mktemp)

    info "Running collect.sh and capturing output..."
    ./collect.sh "${output_file}" >/dev/null 2>&1 || {
        fail "collect.sh execution failed"
        cat "${output_file}" 2>/dev/null || true
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

    # Test 3: Module 1 - System Information
    check_keys "4.1 System Info" "${output_file}" \
        HOSTNAME IP CHECK_TIME OS KERNEL ARCH CPU_CORES CPU_MODEL CPU_FREQ VIRTUAL_TYPE

    # Test 4: Module 2 - Basic Resources
    check_keys "4.2 Basic Resources" "${output_file}" \
        CPU_USAGE CPU_LOAD_1 CPU_LOAD_5 CPU_LOAD_15 CPU_TOP5 \
        MEM_TOTAL MEM_USED MEM_AVAILABLE MEM_PERCENT \
        SWAP_TOTAL SWAP_USED DISK_ INODE_ IO_WAIT

    # Test 5: Module 3 - Network Status
    check_keys "4.3 Network Status" "${output_file}" \
        NET_NIC_ NET_LISTEN_PORTS NET_TCP_STATUS \
        NET_DNS_RESOLVE NET_FIREWALL NET_ROUTE

    # Test 6: Module 4 - Process and Services
    check_keys "4.4 Process & Services" "${output_file}" \
        SERVICE_STATUS PROCESS_TOTAL PROCESS_ZOMBIE \
        PROCESS_RUNNING PROCESS_SLEEPING PROCESS_TOP5_CPU PROCESS_TOP5_MEM

    # Test 7: Module 5 - Java Process Details
    check_keys "4.5 Java Processes" "${output_file}" \
        PROCESS_JAVA_COUNT

    # Test 8: Module 6 - Middleware
    check_keys "4.6 Middleware" "${output_file}" \
        REDIS_STATUS NACOS_STATUS MYSQL_STATUS \
        MYSQL_REPLICATION MYSQL_INNODB_BUFFER

    # Test 9: Module 7 - System Security
    check_keys "4.7 System Security" "${output_file}" \
        SSH_CONFIG SSH_FAILED_LOGIN_TODAY SSH_TRUSTED_KEYS \
        USER_SUDO_TODAY SELINUX_STATUS FAIL2BAN_STATUS \
        SYSCTL_KEY_PARAMS NTP_SYNC

    # Test 10: Module 8 - Crontab Analysis
    check_keys "4.8 Crontab Analysis" "${output_file}" \
        CRONTAB_SYSTEM CRONTAB_ANALYSIS

    # Test 11: Module 9 - Logs and Alerts
    check_keys "4.9 Logs & Alerts" "${output_file}" \
        AUTH_FAILED_TODAY KERNEL_ERROR_TODAY OOM_KILLER_TODAY \
        SEGFAULT_TODAY SYSLOG_ERROR_TODAY SECURITY_ALERT LAST_LOGIN

    # Test 12: Module 10 - Environment Information
    check_keys "4.10 Environment Info" "${output_file}" \
        DOCKER_STATUS ENV_JAVA_VERSION ENV_PYTHON_VERSION ENV_NODE_VERSION

    # Test 13: Check module separators (now 9 separators for 10 modules)
    run_test
    local separator_count
    separator_count=$(grep -c "^---$" "${output_file}") || separator_count=0
    if [ "${separator_count}" -eq 9 ]; then
        pass "Correct number of module separators (9)"
    else
        fail "Expected 9 module separators, found ${separator_count}"
    fi

    # Test 14: Verify KEY=VALUE format (allow lowercase in key names like IO_UTIL_sda)
    run_test
    local invalid_lines
    invalid_lines=$(grep -cvE "^[A-Za-z_0-9]+=|^---$" "${output_file}") || invalid_lines=0
    if [ "${invalid_lines}" -eq 0 ]; then
        pass "All lines follow KEY=VALUE format or separator"
    else
        fail "Found ${invalid_lines} lines not following KEY=VALUE format"
        # Show the invalid lines for debugging
        grep -vE "^[A-Za-z_0-9]+=|^---$" "${output_file}" | head -5
    fi

    # Test 15: Check no multiline values (all values should be single-line)
    run_test
    local line_count
    line_count=$(wc -l < "${output_file}")
    local kv_count
    kv_count=$(grep -cE "^[A-Za-z_0-9]+=" "${output_file}") || kv_count=0
    local sep_count
    sep_count=$(grep -c "^---$" "${output_file}") || sep_count=0
    if [ "${line_count}" -eq $((kv_count + sep_count)) ]; then
        pass "No multiline values detected (${kv_count} key-value pairs)"
    else
        fail "Possible multiline values: total_lines=${line_count}, kv=${kv_count}, separators=${sep_count}"
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
