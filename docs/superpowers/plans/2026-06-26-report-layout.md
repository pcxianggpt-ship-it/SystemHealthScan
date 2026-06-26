# 报告排版优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `report.sh` 中 3.2-3.7 章节从"按服务器分章节"改为"横向融合行型表"，并默认过滤虚拟网卡/容器挂载、折叠 Java 命令行。

**Architecture:** 仅修改 `report.sh`（不动 `collect.sh`）。每章节重写 `generate_*_section` 函数，所有融合表前两列固定为 `主机 | IP`。新增 3 个 helper（过滤虚拟网卡/容器挂载/折叠 Java 进程名）。新增附录 B 容纳完整 Java 命令行。

**Tech Stack:** Bash 4+（关联数组、`[[ ]]`、`<<<`），Markdown 表格，pandoc 转 .docx。

**Spec:** `docs/superpowers/specs/2026-06-26-report-layout-design.md`

---

## File Structure

| 文件 | 责任 | 改动 |
|------|------|------|
| `report.sh` | 报告生成主脚本 | 顶部加常量 + 新增 3 helpers + 重写 6 章节函数 + 新增附录 B 函数 + 改 append 函数 |
| `tests/report_layout_test.sh` | 排版集成测试（新增） | 创建：跑 `report.sh` + grep 验证 markdown 含期望表头/字段 |
| `output/*.dat` | 采集数据 | 不动 |

## 测试约定

由于 `report.sh` 是 bash 脚本、没有装 bats 等单元测试框架，**采用集成测试**：每个 task 完成后，跑 `bash report.sh` 生成 markdown，用 `grep` 验证关键内容。

**测试数据准备**（一次性，所有 task 共用）：
- `output/server_20260626.dat`（已存在，含 k8sn1 完整数据）
- `output/61.11_server.dat`（已存在，含 support-61011 完整数据）

**测试 fixture 命令**（每个 task 复用）：
```bash
# 跑一次报告生成（仅 markdown，跳过 pandoc 加速）
bash report.sh -i output/ -o report/.test_report.docx 2>&1 | tail -5

# 找到生成的 markdown（report.sh 把它复制成 巡检报告_YYYYMMDD.md）
LATEST_MD=$(ls -t report/巡检报告_*.md | head -1)
```

---

## Task 1: 新增过滤常量与 helper 函数

**Files:**
- Modify: `report.sh:9-46`（顶部全局区，加常量）
- Modify: `report.sh:295-309`（`parse_compound` 后，加 helpers）
- Test: `tests/report_layout_test.sh`（创建）

### Step 1: 创建测试文件框架

- [ ] **Step 1: 创建 tests/report_layout_test.sh 骨架**

```bash
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
```

赋可执行权限：`chmod +x tests/report_layout_test.sh`

- [ ] **Step 2: 跑测试骨架，验证 0 个测试通过**

```bash
bash tests/report_layout_test.sh
```
Expected: `总计: 0  通过: 0  失败: 0` + exit 0

- [ ] **Step 3: 在 report.sh 顶部全局区追加过滤常量**

位置：`report.sh` 中 `declare -A THRESHOLD=()` 之后、`declare -a ISSUES_CRIT=()` 之前。

```bash
# Filter regexps (see docs/superpowers/specs/2026-06-26-report-layout-design.md §7)
NIC_FILTER_REGEX='^(veth|br-|docker|cni|flannel|kube-ipvs|virbr|vboxnet|tap|tun)|^lo$'
MOUNT_FILTER_REGEX='/var/lib/docker/containers/.*/mounts/shm|/var/lib/kubelet/pods/|/var/lib/docker/overlay2'
```

- [ ] **Step 4: 在 parse_compound 函数后追加 3 个 helpers**

位置：`report.sh` 中 `parse_compound` 函数结束后（约 line 309 之后），加：

```bash
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

    # 1. 优先取 -jar <path> 的 basename
    local jar
    jar=$(echo "${cmdline}" | grep -oE -- '-jar[[:space:]]+[^[:space:]]+\.jar' | head -1 | sed 's/.*-jar[[:space:]]*//')
    if [[ -n "${jar}" ]]; then
        local base
        base=$(basename "${jar}")
        echo "${base}"
        return
    fi

    # 2. 取最后一个非 - 开头的 token，按 . 分割取最后一段（主类简写）
    local last_token
    last_token=$(echo "${cmdline}" | tr ' ' '\n' | grep -vE '^-' | grep -vE '^$' | tail -1)
    if [[ -n "${last_token}" && "${last_token}" == *.* ]]; then
        local simple
        simple=$(echo "${last_token}" | awk -F'.' '{print $NF}')
        echo "${simple}"
        return
    fi

    # 3. 否则取 java 命令 basename
    local first_token
    first_token=$(echo "${cmdline}" | awk '{print $1}')
    if [[ -n "${first_token}" ]]; then
        basename "${first_token}"
        return
    fi

    echo "unknown"
}
```

- [ ] **Step 5: 在 tests/report_layout_test.sh 加入 helper 单元测试**

在 `echo ""` 之前（即"总计"输出之前）插入：

```bash
# === Helper unit tests ===

# 加载 report.sh 中的函数（不执行 main）
REPORT_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/report.sh"
# 用 awk 取 helpers 定义，临时执行验证
# is_virtual_nic 测试
TOTAL=$((TOTAL + 4))
for nic in "eth0" "eno1" "enp65s0f1"; do
    if bash -c "source <(sed -n '/^# Layout helpers/,/^extract_short_process_name/p' \"${REPORT_SCRIPT}\"); [[ \"\${NIC_FILTER_REGEX}\" ]] && echo ok" >/dev/null 2>&1; then
        # 这里简化测试：直接验证正则
        :
    fi
    PASSED=$((PASSED + 1))
done
```

> **简化**：bash helper 单元测试需要把 report.sh 重构为可 source 的形式（避免 main 自动执行）。本计划走集成测试路线，helper 通过最终 markdown 输出间接验证。删除上面这段代码，仅保留骨架。

- [ ] **Step 6: 简化测试文件，删除上一步骤的代码**

保持 tests/report_layout_test.sh 只有测试框架（Step 1 的版本），等待 Task 2 起加入真正的集成测试。

- [ ] **Step 7: 跑语法检查**

```bash
bash -n report.sh && echo "✓ report.sh syntax OK"
bash -n tests/report_layout_test.sh && echo "✓ test syntax OK"
```
Expected: 两个 ✓

- [ ] **Step 8: Commit**

```bash
git add report.sh tests/report_layout_test.sh
git commit -m "$(cat <<'EOF'
chore：新增报告排版过滤常量与 helper 函数

- NIC_FILTER_REGEX：虚拟网卡过滤正则
- MOUNT_FILTER_REGEX：容器/kubelet 挂载过滤正则
- is_virtual_nic / is_container_mount / extract_short_process_name
- tests/report_layout_test.sh：集成测试骨架

详见 docs/superpowers/specs/2026-06-26-report-layout-design.md

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: 重写 generate_network_section

**Files:**
- Modify: `report.sh:627-719`（整个 `generate_network_section` 函数）
- Test: `tests/report_layout_test.sh`（追加测试）

**期望的 Markdown 输出**（spec §6.2）：
- 网卡表：`| 主机 | IP | 网卡 | 状态 | 速率 |`，过滤虚拟网卡
- TCP 表：`| 主机 | IP | ESTABLISHED | TIME_WAIT | CLOSE_WAIT | SYN_RECV |`
- 监听端口：每台一段紧凑列表
- 网络附属：`| 主机 | IP | DNS 解析 | 防火墙 | 默认路由 |`

- [ ] **Step 1: 在 tests/report_layout_test.sh 追加 Task 2 集成测试**

在 `echo ""` 之前插入：

```bash
# === Task 2: Network section 网络章节排版 ===

# 先生成报告（一次生成，多次断言）
REPORT_OUT=$(bash report.sh -i output/ -o report/.test_report.docx 2>&1 | tail -3) || true
LATEST_MD=$(ls -t report/巡检报告_*.md 2>/dev/null | head -1)

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
    assert_match "${LATEST_MD}" '\| eth0 \|' "网卡表包含 eth0 物理网卡"
fi
```

- [ ] **Step 2: 跑测试，确认 Task 2 测试失败**

```bash
bash tests/report_layout_test.sh 2>&1 | tail -20
```
Expected: `Task 2` 相关断言 FAIL（因为现在还是旧版按服务器分章节格式）

- [ ] **Step 3: 用新版完全替换 generate_network_section 函数**

从 `report.sh` 中找到 `generate_network_section() {` 开始，到对应的 `}` 结束（line 627-719），整体替换为：

```bash
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
        [ -z "${ports_val}" ] && ports_val="N/A"
        printf "**%s (%s)** 监听端口：\n\n%s\n\n" \
            "${hostname}" "${ip}" "${ports_val}" >> "${MD_FILE}"
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
```

- [ ] **Step 4: 跑测试，验证 Task 2 通过**

```bash
bash tests/report_layout_test.sh 2>&1 | tail -15
```
Expected: `Task 2` 全部 PASS

- [ ] **Step 5: 人工检查生成的 markdown**

```bash
LATEST_MD=$(ls -t report/巡检报告_*.md | head -1)
grep -A 20 "## 3.2 网络状态" "${LATEST_MD}" | head -30
```
检查：网卡表前两列是 `主机 | IP`，无 veth/docker0；TCP 表行型；监听端口按主机分段。

- [ ] **Step 6: Commit**

```bash
git add report.sh tests/report_layout_test.sh
git commit -m "$(cat <<'EOF'
refactor：3.2 网络章节改为横向融合行型表

- 网卡表加 主机|IP 列，过滤虚拟网卡（veth/br-/docker 等）
- TCP 连接改行型：主机|IP|ESTAB|TIME_WAIT|CLOSE_WAIT|SYN_RECV
- 监听端口按主机分段紧凑显示
- 新增网络附属行型表：DNS/防火墙/默认路由

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: 重写 generate_process_section

**Files:**
- Modify: `report.sh:725-836`（整个 `generate_process_section` 函数）
- Test: `tests/report_layout_test.sh`

**期望输出**（spec §6.3）：
- 进程统计：`| 主机 | IP | 总计 | 运行 | 休眠 | 僵尸 |`
- CPU Top5 / 内存 Top5：每台一段 5 行小表
- 服务状态：每台一段 `| 服务 | 状态 |`
- Java 进程详情：`| 主机 | IP | PID | 进程名 | Xmx | GC Old% | OOM | 日志路径 |`

- [ ] **Step 1: 追加 Task 3 集成测试**

在 `# === Task 2` 段后插入：

```bash
# === Task 3: Process & Java section 进程与 Java 章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 3: 报告未生成"
else
    # 进程统计表头
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 总计 \| 运行 \| 休眠 \| 僵尸 \|' "进程统计表头"

    # Java 进程详情表头（折叠命令行）
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| PID \| 进程名 \| Xmx \| GC Old% \| OOM \| 日志路径 \|' "Java 详情表头"

    # 折叠后的 Java 进程名应包含 jar 名（不应包含超长 classpath）
    assert_match "${LATEST_MD}" 'rocketmq-dashboard\.jar|nexus|tomcat|BrokerStartup' "Java 进程名被折叠"

    # Java 详情表不应包含超长 classpath 字符串
    assert_not_contains "${LATEST_MD}" "BOOT-INF/classes" "Java 详情表不应有完整 classpath"
fi
```

- [ ] **Step 2: 跑测试，确认 Task 3 测试失败**

```bash
bash tests/report_layout_test.sh 2>&1 | grep -E "Task 3|FAIL" | head -10
```
Expected: Task 3 相关 FAIL

- [ ] **Step 3: 完全替换 generate_process_section**

从 `report.sh:725` `generate_process_section() {` 到对应 `}`，整体替换为：

```bash
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
        printf "| %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" \
            "$(get_val "$i" "PROCESS_TOTAL")" \
            "$(get_val "$i" "PROCESS_RUNNING")" \
            "$(get_val "$i" "PROCESS_SLEEPING")" \
            "$(get_val "$i" "PROCESS_ZOMBIE")" >> "${MD_FILE}"

        # 僵尸进程阈值检查
        local zombie
        zombie=$(get_val "$i" "PROCESS_ZOMBIE")
        local s
        s=$(check_threshold "ZOMBIE" "${zombie}")
        [ "${s}" != "OK" ] && add_issue "${s}" "僵尸进程数 ${zombie}" "${hostname}"
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
        [ -z "${svc_val}" ] && continue

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
        [[ "${java_count}" -eq 0 ]] && continue

        local idx=1
        while [[ ${idx} -le ${java_count} ]]; do
            local pid cmdline short_name xmx gc_old oom log_path
            pid=$(get_val "$i" "JAVA_PS_${idx}_PID")
            cmdline=$(get_val "$i" "JAVA_PS_${idx}_CMDLINE")
            short_name=$(extract_short_process_name "${cmdline}")

            # JVM 参数格式：Xms:default:Xmx:1g
            local jvm
            jvm=$(get_val "$i" "JAVA_PS_${idx}_JVM")
            xmx=$(echo "${jvm}" | awk -F: '{print $4}')
            [[ -z "${xmx}" ]] && xmx="default"

            # GC 格式：OldGen:61.36%|Eden:0.00%|Survivor:8.07% 或 N/A
            local gc
            gc=$(get_val "$i" "JAVA_PS_${idx}_GC")
            gc_old=$(echo "${gc}" | grep -oE 'OldGen:[0-9.]+%' | head -1 | cut -d: -f2)
            [[ -z "${gc_old}" ]] && gc_old="N/A"

            oom=$(get_val "$i" "JAVA_PS_${idx}_OOM_DUMP")
            [[ -z "${oom}" ]] && oom="NONE"
            log_path=$(get_val "$i" "JAVA_PS_${idx}_LOG")
            [[ -z "${log_path}" ]] && log_path="N/A"

            printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n" \
                "${hostname}" "${ip}" "${pid}" "${short_name}" \
                "${xmx}" "${gc_old}" "${oom}" "${log_path}" >> "${MD_FILE}"

            idx=$((idx + 1))
        done
    done
}
```

> **注意**：原函数中 Java 进程的"完整命令行"显示被移除（移到附录 B，Task 4 实现）。

- [ ] **Step 4: 跑测试，验证 Task 3 通过**

```bash
bash tests/report_layout_test.sh 2>&1 | grep -E "Task 3|FAIL" | head -10
```
Expected: Task 3 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add report.sh tests/report_layout_test.sh
git commit -m "$(cat <<'EOF'
refactor：3.3 进程与 Java 章节改为横向融合行型表

- 进程统计行型表：主机|IP|总计|运行|休眠|僵尸
- CPU/内存 Top5 保留按主机分段小表
- 服务状态按主机分段
- Java 进程详情折叠命令行到 jar 名/主类简写
- 完整命令行移到附录 B（下一个 task 实现）

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 新增附录 B + 改 generate_appendix

**Files:**
- Modify: `report.sh:1092-1100`（`generate_appendix` 函数）
- 新增逻辑：在 `generate_appendix` 中追加附录 B 子节
- Test: `tests/report_layout_test.sh`

- [ ] **Step 1: 追加 Task 4 集成测试**

```bash
# === Task 4: 附录 B Java 完整命令行 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 4: 报告未生成"
else
    assert_match "${LATEST_MD}" '## 附录 B：Java 进程完整命令行' "附录 B 标题存在"
    # 附录 B 应包含原始的长命令行片段（如完整 -classpath）
    assert_match "${LATEST_MD}" 'org\.apache\.catalina\.startup\.Bootstrap|org\.apache\.rocketmq\.broker\.BrokerStartup' "附录 B 含完整主类名"
fi
```

- [ ] **Step 2: 跑测试，确认 Task 4 失败**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 4"
```
Expected: FAIL

- [ ] **Step 3: 在 generate_appendix 函数末尾追加附录 B**

读取 `report.sh` 中 `generate_appendix` 函数，在最后 `}` 之前追加：

```bash
    # 附录 B：Java 进程完整命令行
    cat >> "${MD_FILE}" <<EOF

## 附录 B：Java 进程完整命令行

EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local java_count
        java_count=$(get_val "$i" "PROCESS_JAVA_COUNT")
        [[ "${java_count}" -eq 0 ]] && continue

        printf "### B.%d %s (%s)\n\n" $((i + 1)) "${hostname}" "${ip}" >> "${MD_FILE}"

        local idx=1
        while [[ ${idx} -le ${java_count} ]]; do
            local pid cmdline
            pid=$(get_val "$i" "JAVA_PS_${idx}_PID")
            cmdline=$(get_val "$i" "JAVA_PS_${idx}_CMDLINE")
            printf "#### PID %s\n\n```\n%s\n```\n\n" "${pid}" "${cmdline}" >> "${MD_FILE}"
            idx=$((idx + 1))
        done
    done
```

- [ ] **Step 4: 跑测试，验证 Task 4 通过**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 4"
```
Expected: 2 个 PASS

- [ ] **Step 5: Commit**

```bash
git add report.sh tests/report_layout_test.sh
git commit -m "$(cat <<'EOF'
feat：新增附录 B 容纳 Java 进程完整命令行

3.3.4 Java 进程详情表已折叠命令行，原始 400+ 字符的完整命令行
（含 classpath、JVM 参数、主类）移到附录 B，按主机分小节，
供运维人员必要时查阅。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 重写 generate_middleware_section

**Files:**
- Modify: `report.sh:837-879`（整个 `generate_middleware_section`）
- Test: `tests/report_layout_test.sh`

**期望输出**（spec §6.4）：单张行型表 `| 主机 | IP | Redis | Nacos | MySQL 版本 | MySQL 连接 | 复制角色 | InnoDB Buffer |`

- [ ] **Step 1: 追加 Task 5 集成测试**

```bash
# === Task 5: Middleware section 中间件章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 5: 报告未生成"
else
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| Redis \| Nacos \| MySQL 版本 \| MySQL 连接 \| 复制角色 \| InnoDB Buffer \|' "中间件表头"
fi
```

- [ ] **Step 2: 跑测试确认失败**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 5"
```

- [ ] **Step 3: 完全替换 generate_middleware_section**

```bash
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
        [[ -z "${redis}" ]] && redis="N/A"
        [[ -z "${nacos}" ]] && nacos="N/A"

        # MYSQL_STATUS 格式：RUNNING|VERSION:5.5.68|CONNECTIONS:0/0|...
        local mysql_status
        mysql_status=$(get_val "$i" "MYSQL_STATUS")
        if [[ "${mysql_status}" == RUNNING* ]]; then
            mysql_ver=$(echo "${mysql_status}" | grep -oE 'VERSION:[^|]+' | cut -d: -f2)
            mysql_conn=$(echo "${mysql_status}" | grep -oE 'CONNECTIONS:[^|]+' | cut -d: -f2)
        else
            mysql_ver="N/A"
            mysql_conn="N/A"
        fi

        # MYSQL_REPLICATION 格式：ROLE:MASTER|SLAVE_STATUS:N/A|...
        local repl_val
        repl_val=$(get_val "$i" "MYSQL_REPLICATION")
        repl=$(echo "${repl_val}" | grep -oE 'ROLE:[^|]+' | cut -d: -f2)
        [[ -z "${repl}" ]] && repl="N/A"

        innodb=$(get_val "$i" "MYSQL_INNODB_BUFFER")
        [[ -z "${innodb}" ]] && innodb="N/A"

        printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" "${redis}" "${nacos}" \
            "${mysql_ver}" "${mysql_conn}" "${repl}" "${innodb}" >> "${MD_FILE}"
    done
}
```

- [ ] **Step 4: 跑测试通过 + Commit**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 5"
git add report.sh tests/report_layout_test.sh
git commit -m "refactor：3.4 中间件章节改为横向融合行型表

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 6: 重写 generate_security_section

**Files:**
- Modify: `report.sh:880-970`
- Test: `tests/report_layout_test.sh`

**期望输出**（spec §6.5）：3 张行型表 + 今日登录小节
- SSH 配置：`| 主机 | IP | 端口 | Root 登录 | 密码认证 | 空密码 | MaxAuth |`
- 内核参数：`| 主机 | IP | somaxconn | swappiness | file-max | tcp_syn_backlog |`
- 安全综合：`| 主机 | IP | SELinux | Fail2ban | NTP 同步 | 锁定用户 | Sudo 今日 |`
- 今日登录：每台一段

- [ ] **Step 1: 追加 Task 6 集成测试**

```bash
# === Task 6: Security section 安全章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 6: 报告未生成"
else
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 端口 \| Root 登录 \| 密码认证 \| 空密码 \| MaxAuth \|' "SSH 配置表头"
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| somaxconn \| swappiness \| file-max \| tcp_syn_backlog \|' "内核参数表头"
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| SELinux \| Fail2ban \| NTP 同步 \| 锁定用户 \| Sudo 今日 \|' "安全综合表头"
fi
```

- [ ] **Step 2: 跑测试确认失败**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 6"
```

- [ ] **Step 3: 完全替换 generate_security_section**

```bash
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
        # 格式：PORT:22|ROOT_LOGIN:yes|PASSWORD_AUTH:yes|PERMIT_EMPTY:no|MAX_AUTH:6
        declare -A ssh_map=()
        IFS='|' read -ra parts <<< "${ssh_val}"
        for part in "${parts[@]}"; do
            [[ -z "${part}" ]] && continue
            local k v
            k=$(echo "${part}" | cut -d: -f1)
            v=$(echo "${part}" | cut -d: -f2)
            ssh_map["${k}"]="${v}"
        done
        printf "| %s | %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" \
            "${ssh_map[PORT]:-N/A}" \
            "${ssh_map[ROOT_LOGIN]:-N/A}" \
            "${ssh_map[PASSWORD_AUTH]:-N/A}" \
            "${ssh_map[PERMIT_EMPTY]:-N/A}" \
            "${ssh_map[MAX_AUTH]:-N/A}" >> "${MD_FILE}"
        unset ssh_map
    done

    # 内核参数
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
        declare -A sysctl_map=()
        IFS='|' read -ra parts <<< "${sysctl_val}"
        for part in "${parts[@]}"; do
            [[ -z "${part}" ]] && continue
            local k v
            k=$(echo "${part}" | cut -d= -f1)
            v=$(echo "${part}" | cut -d= -f2)
            sysctl_map["${k}"]="${v}"
        done
        printf "| %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" \
            "${sysctl_map[net.core.somaxconn]:-N/A}" \
            "${sysctl_map[vm.swappiness]:-N/A}" \
            "${sysctl_map[fs.file-max]:-N/A}" \
            "${sysctl_map[net.ipv4.tcp_max_syn_backlog]:-N/A}" >> "${MD_FILE}"
        unset sysctl_map
    done

    # 安全综合
    cat >> "${MD_FILE}" <<EOF

### 3.5.3 安全综合状态

| 主机 | IP | SELinux | Fail2ban | NTP 同步 | 锁定用户 | Sudo 今日 |
|------|----|---------|----------|----------|----------|-----------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        printf "| %s | %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" \
            "$(get_val "$i" "SELINUX_STATUS")" \
            "$(get_val "$i" "FAIL2BAN_STATUS")" \
            "$(get_val "$i" "NTP_SYNC")" \
            "$(get_val "$i" "USER_LOCKED")" \
            "$(get_val "$i" "USER_SUDO_TODAY")" >> "${MD_FILE}"
    done

    # 今日登录（每台一段）
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
```

- [ ] **Step 4: 跑测试通过 + Commit**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 6"
git add report.sh tests/report_layout_test.sh
git commit -m "refactor：3.5 安全章节改为横向融合行型表

- SSH 配置、内核参数、安全综合 3 张行型表
- 今日登录按主机分段

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 7: 重写 generate_crontab_section

**Files:**
- Modify: `report.sh:971-1025`
- Test: `tests/report_layout_test.sh`

**期望输出**（spec §6.6）：单张行型表 `| 主机 | IP | 用户 | 来源 | 调度 | 命令 |`

- [ ] **Step 1: 追加 Task 7 集成测试**

```bash
# === Task 7: Crontab 章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 7: 报告未生成"
else
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 用户 \| 来源 \| 调度 \| 命令 \|' "Crontab 表头"
fi
```

- [ ] **Step 2: 跑测试确认失败**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 7"
```

- [ ] **Step 3: 完全替换 generate_crontab_section**

```bash
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
        [[ -z "${cron_val}" || "${cron_val}" = "NONE" ]] && continue

        # 格式：user:source:schedule:cmd|user:source:schedule:cmd|...
        # 但 cmd 含空格，需要特殊处理：用 | 分段，再对每段按 ":" 限定分割
        IFS='|' read -ra parts <<< "${cron_val}"
        for part in "${parts[@]}"; do
            [[ -z "${part}" ]] && continue
            # 用 awk 限定分割：前 3 个 : 切 user/source/schedule，剩下都是 cmd
            local user source schedule cmd
            user=$(echo "${part}" | awk -F: '{print $1}')
            source=$(echo "${part}" | awk -F: '{print $2}')
            schedule=$(echo "${part}" | awk -F: '{print $3}')
            cmd=$(echo "${part}" | awk -F: '{for(i=4;i<=NF;i++) printf "%s%s", $i, (i<NF?":":"")}')
            printf "| %s | %s | %s | %s | %s | %s |\n" \
                "${hostname}" "${ip}" "${user}" "${source}" "${schedule}" "${cmd}" >> "${MD_FILE}"
        done
    done

    # Anacron 单独段落
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
            [[ -z "${anacron_val}" || "${anacron_val}" = "N/A" ]] && continue
            printf "**%s (%s)：** %s\n\n" "${hostname}" "${ip}" "${anacron_val}" >> "${MD_FILE}"
        done
    fi
}
```

- [ ] **Step 4: 跑测试通过 + Commit**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 7"
git add report.sh tests/report_layout_test.sh
git commit -m "refactor：3.6 Crontab 章节改为横向融合行型表

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 8: 重写 generate_log_alert_section

**Files:**
- Modify: `report.sh:1026-1091`
- Test: `tests/report_layout_test.sh`

**期望输出**（spec §6.7）：单张行型表 `| 主机 | IP | 认证失败 | 内核错误 | OOM Killer | 段错误 | 系统日志错误 | 安全告警 | 最近登录 |`

- [ ] **Step 1: 追加 Task 8 集成测试**

```bash
# === Task 8: Log & Alert 章节 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 8: 报告未生成"
else
    assert_match "${LATEST_MD}" '\| 主机 \| IP \| 认证失败 \| 内核错误 \| OOM Killer \| 段错误 \| 系统日志错误 \| 安全告警 \| 最近登录 \|' "日志告警表头"
fi
```

- [ ] **Step 2: 跑测试确认失败**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 8"
```

- [ ] **Step 3: 完全替换 generate_log_alert_section**

```bash
generate_log_alert_section() {
    cat >> "${MD_FILE}" <<EOF

## 3.7 日志与告警

| 主机 | IP | 认证失败 | 内核错误 | OOM Killer | 段错误 | 系统日志错误 | 安全告警 | 最近登录 |
|------|----|----------|----------|-----------|--------|-------------|----------|----------|
EOF

    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local ip="${SERVER_IPS[$i]:-N/A}"
        local oom
        oom=$(get_val "$i" "LOG_OOM_KILLER")
        [[ -z "${oom}" ]] && oom="0"

        # OOM 触发则记录 CRIT
        if [[ "${oom}" != "0" ]]; then
            add_issue "CRIT" "OOM Killer 今日触发 ${oom} 次" "${hostname}"
        fi

        printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" \
            "${hostname}" "${ip}" \
            "$(get_val "$i" "LOG_AUTH_FAIL_TODAY")" \
            "$(get_val "$i" "LOG_KERNEL_ERROR")" \
            "${oom}" \
            "$(get_val "$i" "LOG_SEGFAULT")" \
            "$(get_val "$i" "LOG_SYSLOG_ERROR")" \
            "$(get_val "$i" "LOG_SECURITY_ALERT")" \
            "$(get_val "$i" "LOG_LAST_LOGIN")" >> "${MD_FILE}"
    done
}
```

- [ ] **Step 4: 跑测试通过 + Commit**

```bash
bash tests/report_layout_test.sh 2>&1 | grep "Task 8"
git add report.sh tests/report_layout_test.sh
git commit -m "refactor：3.7 日志告警章节改为横向融合行型表

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 9: 集成验收与回归

**Files:**
- 全部前述 task 完成后的最终验证

- [ ] **Step 1: 跑全部测试**

```bash
bash tests/report_layout_test.sh
```
Expected: 所有 Task 2-8 全部 PASS，无 FAIL

- [ ] **Step 2: 检查 .dat 字段命名一致性**

某些字段的精确名称可能与本计划假设不符。从 .dat 中实际抽取验证：

```bash
# 检查 Java 进程相关字段命名
grep -E "^JAVA_PS_[0-9]+_" output/server_20260626.dat | head -10
# 检查日志字段
grep -E "^LOG_" output/server_20260626.dat | head -10
```

如发现字段名不一致（如实际是 `JAVA_PS_1_CMD` 而非 `JAVA_PS_1_CMDLINE`），更新对应 task 中的代码。

- [ ] **Step 3: 完整端到端测试**

```bash
# 用真实数据跑完整流程
bash report.sh -i output/ -o report/巡检报告_最终.docx

# 检查 docx 生成成功
ls -la report/巡检报告_最终.docx
```

- [ ] **Step 4: 人工对照 spec §6 检查每个章节**

打开 `report/巡检报告_YYYYMMDD.md`，对照 spec 验证：
- 3.2 网络状态：4 个子节，前两列 `主机 | IP`，无虚拟网卡
- 3.3 进程与 Java：4 个子节 + Java 详情折叠正确
- 3.4 中间件：单行型表
- 3.5 安全：3 张行型表 + 今日登录分段
- 3.6 Crontab：单行型表
- 3.7 日志告警：单行型表
- 附录 B：完整 Java 命令行

- [ ] **Step 5: 最终 commit（如有调整）**

```bash
git status -sb
# 如有未提交的微调
git add -A
git commit -m "test：报告排版集成验收通过

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Self-Review 结果

**Spec 覆盖检查**：
- §4 决策表 → Task 1（常量/helpers）+ Task 2-8（行型表）+ Task 4（附录 B） ✓
- §6.2 网络 → Task 2 ✓
- §6.3 进程 → Task 3 + Task 4 ✓
- §6.4 中间件 → Task 5 ✓
- §6.5 安全 → Task 6 ✓
- §6.6 Crontab → Task 7 ✓
- §6.7 日志 → Task 8 ✓
- §7 过滤规则 → Task 1 ✓
- §8 Java 折叠算法 → Task 1 helper ✓
- §9 实施范围 → 全覆盖 ✓

**风险点**（Task 9 Step 2 处理）：
- `JAVA_PS_<idx>_<FIELD>` 字段精确命名待实际 .dat 验证
- `LOG_*` 字段名待实际 .dat 验证
- 如不一致，对应 Task 中代码需更新字段名

**列名一致性**：所有表前两列 `主机 | IP` 已贯穿。✓
