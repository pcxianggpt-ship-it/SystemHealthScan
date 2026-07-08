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

# === Task 2: Network section 网络章节排版 ===

# 先生成报告（一次生成，多次断言）
# 注意：pandoc 可能未安装，此时 report.sh 会 exit 1 但 .report_temp.md 仍生成
REPORT_OUT=$(bash report.sh -i output/ -o report/.test_report.docx 2>&1 | tail -3) || true
LATEST_MD=$(ls -t report/巡检报告_*.md 2>/dev/null | head -1 || true)
# 无 pandoc 时回退到临时 markdown 文件
[[ -z "${LATEST_MD}" ]] && LATEST_MD="report/.report_temp.md"

# === Task 1: 总体结论与章节结论 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 1: 报告未生成"
else
    assert_match "${LATEST_MD}" '## 2\.1 总体结论' "问题汇总包含总体结论"
    assert_match "${LATEST_MD}" '本次共巡检 [0-9]+ 台服务器' "总体结论包含巡检服务器数量"
    assert_match "${LATEST_MD}" '(当前.*警告项|本次未发现警告项)' "总体结论包含警告项描述"
    assert_not_contains "${LATEST_MD}" "未发现严重问题和警告项" "样例存在章节发现时总体结论不应宣称无严重问题和警告项"
    assert_not_contains "${LATEST_MD}" "本次未发现警告项" "样例存在章节警告时总体结论不应宣称无警告项"
    assert_match "${LATEST_MD}" '## 2\.2 严重问题' "严重问题章节顺延为 2.2"
    assert_not_contains "${LATEST_MD}" "无严重问题。" "样例存在章节严重发现时 2.2 不应宣称无严重问题"
    assert_match "${LATEST_MD}" '## 2\.3 警告项' "警告项章节顺延为 2.3"
    assert_not_contains "${LATEST_MD}" "无警告项。" "样例存在章节警告发现时 2.3 不应宣称无警告项"
    assert_match "${LATEST_MD}" '## 2\.4 建议优化项' "建议优化项章节顺延为 2.4"
    assert_match "${LATEST_MD}" '^- \[章节 3\.[0-9]\]' "问题汇总包含章节发现明细"
    assert_match "${LATEST_MD}" '### 3\.1\.[0-9]+ 本节小结' "资源章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.2\.[0-9]+ 本节小结' "网络章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.3\.[0-9]+ 本节小结' "进程与 Java 章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.4\.[0-9]+ 本节小结' "中间件章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.5\.[0-9]+ 本节小结' "安全章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.6\.[0-9]+ 本节小结' "Crontab 章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.7\.[0-9]+ 本节小结' "日志告警章节包含本节小结"
fi

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 2: 报告未生成"
else
    # 网卡表表头（融合）
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 网卡 \| 状态 \| 速率 \|' "网卡表头含 主机+IP+网卡+状态+速率"

    # TCP 表表头
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| ESTABLISHED' "TCP 表头含 主机+IP+ESTABLISHED"

    # 网络附属表头
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| DNS 解析 \| 防火墙 \| 默认路由 \|' "网络附属表头"

    # 虚拟网卡应被过滤
    assert_not_contains "${LATEST_MD}" "| veth" "网卡表不应包含 veth 虚拟网卡"
    assert_not_contains "${LATEST_MD}" "| docker0" "网卡表不应包含 docker0"
    assert_not_contains "${LATEST_MD}" "| flannel.1" "网卡表不应包含 flannel.1"

    # 网卡表应包含物理网卡
    assert_match "${LATEST_MD}" '\| [^|]+ \| [^|]+ \| (eth|eno|ens|enp)[^ |]* \|' "网卡表包含非虚拟物理网卡"
fi

# === Task 3: Process & Java section 进程与 Java 章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 3: 报告未生成"
else
    # 进程统计表头
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 总计 \| 运行 \| 休眠 \| 僵尸 \|' "进程统计表头"

    # CPU Top5 子节
    assert_match "${LATEST_MD}" 'CPU Top5' "CPU Top5 子节存在"

    # 服务状态子节
    assert_match "${LATEST_MD}" '服务状态' "服务状态子节存在"

    # Java 进程详情表头（折叠命令行）
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| PID \| 进程名 \| 启动时间 \| 运行时长 \| Xmx \| GC Old% \| OOM \|' "Java 详情表头含启动时间和运行时长"
    assert_not_contains "${LATEST_MD}" "| 主机 | IP | PID | 进程名 | Xmx | GC Old% | OOM | 日志路径 |" "Java 详情表头不再包含日志路径"
fi

# === Task 4: 附录 B Java 完整命令行 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 4: 报告未生成"
else
    assert_match "${LATEST_MD}" '## 附录 B：Java 进程完整命令行' "附录 B 标题存在"
fi

# === Task 5: Middleware section 中间件章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 5: 报告未生成"
else
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| Redis \| Nacos \| MySQL 版本 \| MySQL 连接 \| 复制角色 \| InnoDB Buffer \|' "中间件表头"
fi

# === Task 6: Security section 安全章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 6: 报告未生成"
else
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 端口 \| Root 登录 \| 密码认证 \| 空密码 \| MaxAuth \|' "SSH 配置表头"
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 连接队列\(somaxconn\) \| Swap 倾向\(swappiness\) \| 系统文件句柄\(file-max\) \| 打开文件数\(ulimit -n\) \| SYN 队列\(tcp_syn_backlog\) \|' "内核参数中文表头含 ulimit -n"
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| SELinux \| Fail2ban \| NTP 同步 \| 锁定用户 \| Sudo 今日 \|' "安全综合表头"
fi

# === Task 7: Crontab 章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 7: 报告未生成"
else
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 用户 \| 来源 \| 调度 \| 命令 \|' "Crontab 表头"
    # T9：cmd 含 && 或 || 时不应被错误切分（应保留在命令列）
    assert_match "${LATEST_MD}" '\| [^|]+ \| [^|]+ \| [^|]+ \| [^|]+ \| [^|]+ \| .*(\&\&|\|\|)' "Crontab cmd 保留 shell 操作符"
fi

# === Task 8: Log & Alert 章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 8: 报告未生成"
else
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 认证失败 \| 内核错误 \| OOM Killer \| 段错误 \| 系统日志错误 \| 安全告警 \| 最近登录 \|' "日志告警表头"
fi

echo ""
echo "================================"
echo "总计: ${TOTAL}  通过: ${PASSED}  失败: ${FAILED}"
[ "${FAILED}" -eq 0 ]
