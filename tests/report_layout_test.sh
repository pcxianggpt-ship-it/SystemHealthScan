#!/usr/bin/env bash
# 集成测试：验证 report.sh 生成的 markdown 排版符合设计
# 用法: bash tests/report_layout_test.sh
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
TOTAL=0; PASSED=0; FAILED=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; ((PASSED++)) || true; }
fail() { echo -e "${RED}FAIL${NC}: $1"; ((FAILED++)) || true; }
run_test() { ((TOTAL++)) || true; }

# 断言：markdown 文件中包含指定字符串
assert_contains() {
    local md_file="$1"
    local pattern="$2"
    local label="$3"
    run_test
    if grep -qF "${pattern}" "${md_file}" 2>/dev/null; then
        pass "${label}"
    else
        fail "${label} (未找到: ${pattern})"
    fi
}

# 断言：markdown 文件中包含正则
assert_match() {
    local md_file="$1"
    local regex="$2"
    local label="$3"
    run_test
    if grep -qE "${regex}" "${md_file}" 2>/dev/null; then
        pass "${label}"
    else
        fail "${label} (正则未匹配: ${regex})"
    fi
}

# 断言：markdown 文件中不包含
assert_not_contains() {
    local md_file="$1"
    local pattern="$2"
    local label="$3"
    run_test
    if grep -qF "${pattern}" "${md_file}" 2>/dev/null; then
        fail "${label} (不应包含: ${pattern})"
    else
        pass "${label}"
    fi
}

echo -e "${YELLOW}=== Report Layout Tests ===${NC}"
echo ""

# Task 1 helpers 测试占位（后续 task 会扩展）

echo ""
echo "================================"
echo "总计: ${TOTAL}  通过: ${PASSED}  失败: ${FAILED}"
[ "${FAILED}" -eq 0 ]
