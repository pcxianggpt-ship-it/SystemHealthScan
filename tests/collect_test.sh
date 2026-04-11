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
    local missing_keys=()
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
    local missing_keys=()
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
