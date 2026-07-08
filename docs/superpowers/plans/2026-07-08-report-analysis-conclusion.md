# Report Analysis Conclusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add template-based natural-language conclusions to the report summary and every 3.x inspection section.

**Architecture:** Keep all changes inside `report.sh` and the existing shell integration test. Section generators will record short finding messages while rendering tables, then append a standardized section conclusion at the end of each chapter. The issue summary will render an overall conclusion before the detailed severe/warning/info lists.

**Tech Stack:** Bash, existing `.dat` key-value inputs, Markdown output, existing `tests/report_layout_test.sh`.

## Global Constraints

- Always respond in Chinese-simplified when reporting progress or results.
- Do not modify `collect.sh`.
- Do not change the `.dat` key-value data format.
- Do not add external dependencies.
- Do not implement complex root-cause analysis or historical trend analysis.
- Preserve the current report flow: generate detail sections first, collect issues, then generate cover, overview, issue summary, appendix.
- Existing user changes outside this task must not be reverted.

---

## File Structure

- Modify `report.sh`: add conclusion helper arrays/functions, wire overall conclusion into `generate_issues_summary`, and append chapter conclusions in `generate_resource_section`, `generate_network_section`, `generate_process_section`, `generate_middleware_section`, `generate_security_section`, `generate_crontab_section`, and `generate_log_alert_section`.
- Modify `tests/report_layout_test.sh`: add assertions for `2.1 总体结论`, renumbered issue sections, and all `本节小结` headings.

### Task 1: Add Test Coverage For Conclusions

**Files:**
- Modify: `tests/report_layout_test.sh`

**Interfaces:**
- Consumes: existing report generation in `REPORT_OUT=$(bash report.sh -i output/ -o report/.test_report.docx 2>&1 | tail -3) || true`
- Produces: shell assertions that fail until `report.sh` emits overall and section conclusions

- [ ] **Step 1: Add failing assertions for overall conclusion**

Insert after the `LATEST_MD` fallback block and before the network section assertions:

```bash
# === Task 1: 总体结论与章节结论 ===

if [[ -z "${LATEST_MD}" ]]; then
    fail "Task 1: 报告未生成"
else
    assert_match "${LATEST_MD}" '## 2\.1 总体结论' "问题汇总包含总体结论"
    assert_match "${LATEST_MD}" '本次共巡检 [0-9]+ 台服务器' "总体结论包含巡检服务器数量"
    assert_match "${LATEST_MD}" '警告项' "总体结论包含警告项描述"
    assert_match "${LATEST_MD}" '## 2\.2 严重问题' "严重问题章节顺延为 2.2"
    assert_match "${LATEST_MD}" '## 2\.3 警告项' "警告项章节顺延为 2.3"
    assert_match "${LATEST_MD}" '## 2\.4 建议优化项' "建议优化项章节顺延为 2.4"
    assert_match "${LATEST_MD}" '### 3\.1\.[0-9]+ 本节小结' "资源章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.2\.[0-9]+ 本节小结' "网络章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.3\.[0-9]+ 本节小结' "进程与 Java 章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.4\.[0-9]+ 本节小结' "中间件章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.5\.[0-9]+ 本节小结' "安全章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.6\.[0-9]+ 本节小结' "Crontab 章节包含本节小结"
    assert_match "${LATEST_MD}" '### 3\.7\.[0-9]+ 本节小结' "日志告警章节包含本节小结"
fi
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash tests/report_layout_test.sh
```

Expected: at least the new assertions for `## 2.1 总体结论` and `本节小结` fail because `report.sh` has not been updated.

- [ ] **Step 3: Commit the failing test**

Run:

```bash
git add tests/report_layout_test.sh
git commit -m "test: 覆盖报告分析结论"
```

Expected: one commit containing only `tests/report_layout_test.sh`.

### Task 2: Add Conclusion Helper Functions

**Files:**
- Modify: `report.sh`

**Interfaces:**
- Consumes: `SERVER_HEALTH`, `SERVER_HOSTNAMES`, `ISSUES_CRIT`, `ISSUES_WARN`, `ISSUES_INFO`
- Produces:
  - `declare -A SECTION_CRIT`
  - `declare -A SECTION_WARN`
  - `section_key_count level section`
  - `add_section_finding section level message`
  - `emit_limited_section_findings section`
  - `generate_section_conclusion section normal_text`
  - `generate_overall_conclusion`

- [ ] **Step 1: Add section arrays near existing issue arrays**

After:

```bash
declare -a ISSUES_CRIT=()
declare -a ISSUES_WARN=()
declare -a ISSUES_INFO=()
```

Add:

```bash
# Section-level conclusion findings, stored as indexed values per section/level.
declare -A SECTION_CRIT=()
declare -A SECTION_WARN=()
declare -A SECTION_INFO=()
```

- [ ] **Step 2: Add helper functions after `add_issue`**

Insert after the closing brace of `add_issue()`:

```bash
section_key_count() {
    local level="$1"
    local section="$2"
    local count_key="${section}__${level}__count"

    case "${level}" in
        CRIT) echo "${SECTION_CRIT[${count_key}]:-0}" ;;
        WARN) echo "${SECTION_WARN[${count_key}]:-0}" ;;
        INFO) echo "${SECTION_INFO[${count_key}]:-0}" ;;
        *)    echo "0" ;;
    esac
}

add_section_finding() {
    local section="$1"
    local level="$2"
    local message="$3"

    [ -z "${message}" ] && return

    local count
    count=$(section_key_count "${level}" "${section}")
    count=$((count + 1))

    local count_key="${section}__${level}__count"
    local item_key="${section}__${level}__${count}"

    case "${level}" in
        CRIT)
            SECTION_CRIT["${count_key}"]="${count}"
            SECTION_CRIT["${item_key}"]="${message}"
            ;;
        WARN)
            SECTION_WARN["${count_key}"]="${count}"
            SECTION_WARN["${item_key}"]="${message}"
            ;;
        INFO)
            SECTION_INFO["${count_key}"]="${count}"
            SECTION_INFO["${item_key}"]="${message}"
            ;;
    esac
}

emit_limited_section_findings() {
    local section="$1"
    local printed=0
    local remaining=0
    local limit=5
    local level count i msg

    for level in CRIT WARN; do
        count=$(section_key_count "${level}" "${section}")
        i=1
        while [ "${i}" -le "${count}" ]; do
            case "${level}" in
                CRIT) msg="${SECTION_CRIT[${section}__${level}__${i}]:-}" ;;
                WARN) msg="${SECTION_WARN[${section}__${level}__${i}]:-}" ;;
            esac

            if [ "${printed}" -lt "${limit}" ]; then
                printf "%s%s" "$([ "${printed}" -gt 0 ] && echo "；")" "${msg}" >> "${MD_FILE}"
                printed=$((printed + 1))
            else
                remaining=$((remaining + 1))
            fi
            i=$((i + 1))
        done
    done

    if [ "${remaining}" -gt 0 ]; then
        printf "；其余 %d 项请查看本章明细表" "${remaining}" >> "${MD_FILE}"
    fi
}

generate_section_conclusion() {
    local section="$1"
    local normal_text="$2"
    local crit_count warn_count
    crit_count=$(section_key_count "CRIT" "${section}")
    warn_count=$(section_key_count "WARN" "${section}")

    if [ "${crit_count}" -gt 0 ]; then
        echo "本节发现需要优先处理的异常项：" >> "${MD_FILE}"
        emit_limited_section_findings "${section}"
        echo "。建议尽快复核并处理。" >> "${MD_FILE}"
    elif [ "${warn_count}" -gt 0 ]; then
        echo "本节整体状态可接受，但发现部分指标触发警告阈值：" >> "${MD_FILE}"
        emit_limited_section_findings "${section}"
        echo "。建议结合业务负载持续观察。" >> "${MD_FILE}"
    else
        echo "${normal_text}" >> "${MD_FILE}"
    fi
    echo "" >> "${MD_FILE}"
}

generate_overall_conclusion() {
    local total_count=${#SERVER_HOSTNAMES[@]}
    local crit_hosts=0 warn_hosts=0 ok_hosts=0
    local h

    for h in "${SERVER_HEALTH[@]}"; do
        case "${h}" in
            CRIT) crit_hosts=$((crit_hosts + 1)) ;;
            WARN) warn_hosts=$((warn_hosts + 1)) ;;
            *)    ok_hosts=$((ok_hosts + 1)) ;;
        esac
    done

    echo "## 2.1 总体结论" >> "${MD_FILE}"
    echo "" >> "${MD_FILE}"

    if [ "${#ISSUES_CRIT[@]}" -eq 0 ] && [ "${#ISSUES_WARN[@]}" -eq 0 ]; then
        printf "本次共巡检 %d 台服务器，巡检结果整体平稳，未发现严重问题和警告项。建议按常规周期持续观察。\n\n" \
            "${total_count}" >> "${MD_FILE}"
    else
        printf "本次共巡检 %d 台服务器，其中 %d 台正常、%d 台存在警告、%d 台存在异常。共发现严重问题 %d 项、警告项 %d 项、建议优化项 %d 项。" \
            "${total_count}" "${ok_hosts}" "${warn_hosts}" "${crit_hosts}" \
            "${#ISSUES_CRIT[@]}" "${#ISSUES_WARN[@]}" "${#ISSUES_INFO[@]}" >> "${MD_FILE}"

        if [ "${#ISSUES_CRIT[@]}" -gt 0 ]; then
            echo "报告中存在需要优先处理的严重问题，建议先处理严重问题，再复核警告项。" >> "${MD_FILE}"
        else
            echo "当前主要需要关注警告项，建议结合业务负载持续观察。" >> "${MD_FILE}"
        fi
        echo "" >> "${MD_FILE}"
    fi

    if [ "${#ISSUES_WARN[@]}" -gt 0 ]; then
        echo "当前警告项如下：" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
        for issue in "${ISSUES_WARN[@]}"; do
            echo "- ${issue}" >> "${MD_FILE}"
        done
        echo "" >> "${MD_FILE}"
    else
        echo "本次未发现警告项。" >> "${MD_FILE}"
        echo "" >> "${MD_FILE}"
    fi
}
```

- [ ] **Step 3: Run syntax check**

Run:

```bash
bash -n report.sh
```

Expected: no output and exit code 0.

- [ ] **Step 4: Commit helper functions**

Run:

```bash
git add report.sh
git commit -m "feat: 添加报告结论生成助手"
```

Expected: one commit containing helper arrays and functions only.

### Task 3: Add Overall Conclusion To Issue Summary

**Files:**
- Modify: `report.sh`

**Interfaces:**
- Consumes: `generate_overall_conclusion`
- Produces: second chapter with `2.1 总体结论`, `2.2 严重问题`, `2.3 警告项`, `2.4 建议优化项`

- [ ] **Step 1: Insert overall conclusion call**

In `generate_issues_summary()`, immediately after the `# 2. 问题汇总` heredoc, add:

```bash
    generate_overall_conclusion
```

- [ ] **Step 2: Renumber issue headings**

Change these heading strings:

```bash
echo "## 2.1 严重问题（需立即处理）" >> "${MD_FILE}"
echo "## 2.1 严重问题" >> "${MD_FILE}"
echo "## 2.2 警告项（建议处理）" >> "${MD_FILE}"
echo "## 2.2 警告项" >> "${MD_FILE}"
echo "## 2.3 建议优化项" >> "${MD_FILE}"
```

To:

```bash
echo "## 2.2 严重问题（需立即处理）" >> "${MD_FILE}"
echo "## 2.2 严重问题" >> "${MD_FILE}"
echo "## 2.3 警告项（建议处理）" >> "${MD_FILE}"
echo "## 2.3 警告项" >> "${MD_FILE}"
echo "## 2.4 建议优化项" >> "${MD_FILE}"
```

- [ ] **Step 3: Run tests**

Run:

```bash
bash -n report.sh
bash tests/report_layout_test.sh
```

Expected: syntax check passes. Overall conclusion assertions pass. Section conclusion assertions still fail until Task 4 and Task 5 are complete.

- [ ] **Step 4: Commit overall conclusion**

Run:

```bash
git add report.sh
git commit -m "feat: 添加问题汇总体结论"
```

Expected: one commit containing `generate_issues_summary` changes.

### Task 4: Add Findings And Conclusions For Resource, Network, Process

**Files:**
- Modify: `report.sh`

**Interfaces:**
- Consumes: `add_section_finding section level message`, `generate_section_conclusion section normal_text`
- Produces section findings for `3.1`, `3.2`, `3.3`

- [ ] **Step 1: Record 3.1 resource findings**

In `generate_resource_section()`, after each existing `add_issue` call, add matching `add_section_finding` calls:

```bash
[ "${status}" != "OK" ] && add_section_finding "3.1" "${status}" "${hostname} 的 CPU 使用率为 ${cpu_usage}%"
```

```bash
[ "${status}" != "OK" ] && add_section_finding "3.1" "${status}" "${hostname} 的内存使用率为 ${mem_percent}%"
```

```bash
[ "${status}" != "OK" ] && add_section_finding "3.1" "${status}" "${hostname} 的 SWAP 使用率为 ${swap_percent}%"
```

```bash
[ "${status}" != "OK" ] && add_section_finding "3.1" "${status}" "${hostname} 的磁盘 ${mount} 使用率为 ${percent}%"
```

For IO wait, after computing `status`:

```bash
[ "${status}" != "OK" ] && add_section_finding "3.1" "${status}" "${hostname} 的 IO Wait 为 ${io_wait}%"
```

- [ ] **Step 2: Append 3.1 conclusion**

At the end of `generate_resource_section()`, before the closing brace, add:

```bash
    cat >> "${MD_FILE}" <<EOF

### 3.1.5 本节小结

EOF
    generate_section_conclusion "3.1" "本节资源使用情况整体平稳，各服务器 CPU、内存、磁盘与 IO 指标均未触发告警阈值。"
```

- [ ] **Step 3: Record 3.2 network findings**

In `generate_network_section()`, where TCP status calls `add_issue`, replace the one-line call:

```bash
[ "${s}" != "OK" ] && add_issue "${s}" "TCP ${k} 连接数 ${v} (${s})" "${hostname}"
```

With:

```bash
if [ "${s}" != "OK" ]; then
    add_issue "${s}" "TCP ${k} 连接数 ${v} (${s})" "${hostname}"
    add_section_finding "3.2" "${s}" "${hostname} 的 TCP ${k} 连接数为 ${v}"
fi
```

- [ ] **Step 4: Append 3.2 conclusion**

At the end of `generate_network_section()`, before the closing brace, add:

```bash
    cat >> "${MD_FILE}" <<EOF

### 3.2.5 本节小结

EOF
    generate_section_conclusion "3.2" "本节网络状态整体正常，监听端口、TCP 连接和网络附属检查未发现明显异常。"
```

- [ ] **Step 5: Record 3.3 process findings**

In `generate_process_section()`, where zombie status calls `add_issue`, replace:

```bash
[ "${s}" != "OK" ] && add_issue "${s}" "僵尸进程数 ${zombie}" "${hostname}"
```

With:

```bash
if [ "${s}" != "OK" ]; then
    add_issue "${s}" "僵尸进程数 ${zombie}" "${hostname}"
    add_section_finding "3.3" "${s}" "${hostname} 的僵尸进程数为 ${zombie}"
fi
```

Inside the Java process loop, after `oom=$(get_val "$i" "JAVA_JVM_OOM_DUMP_${idx}")` and defaulting empty OOM to `NONE`, add:

```bash
if [[ "${oom}" == FOUND:* ]]; then
    add_section_finding "3.3" "CRIT" "${hostname} 的 Java 进程 ${pid} 发现 OOM Dump：${oom}"
fi
```

- [ ] **Step 6: Append 3.3 conclusion**

At the end of `generate_process_section()`, before the closing brace, add:

```bash
    cat >> "${MD_FILE}" <<EOF

### 3.3.5 本节小结

EOF
    generate_section_conclusion "3.3" "本节进程与 Java 应用检查整体平稳，未发现僵尸进程或 Java OOM 风险项。"
```

- [ ] **Step 7: Run tests**

Run:

```bash
bash -n report.sh
bash tests/report_layout_test.sh
```

Expected: syntax check passes. `3.1`、`3.2`、`3.3` 小结 assertions pass. Remaining section conclusion assertions for `3.4` to `3.7` still fail.

- [ ] **Step 8: Commit first section conclusions**

Run:

```bash
git add report.sh
git commit -m "feat: 添加资源网络进程章节小结"
```

Expected: one commit containing `3.1` to `3.3` conclusion wiring.

### Task 5: Add Findings And Conclusions For Middleware, Security, Crontab, Logs

**Files:**
- Modify: `report.sh`

**Interfaces:**
- Consumes: `add_section_finding`, `generate_section_conclusion`
- Produces section findings for `3.4`, `3.5`, `3.6`, `3.7`

- [ ] **Step 1: Record 3.4 middleware findings**

In `generate_middleware_section()`, before printing each row, add:

```bash
        if [[ "${redis}" == "NOT_RUNNING" ]]; then
            add_section_finding "3.4" "WARN" "${hostname} 的 Redis 未运行"
        fi
        if [[ "${nacos}" == "NOT_RUNNING" ]]; then
            add_section_finding "3.4" "WARN" "${hostname} 的 Nacos 未运行"
        fi
        if [[ "${mysql_status}" == "NOT_RUNNING" ]]; then
            add_section_finding "3.4" "WARN" "${hostname} 的 MySQL 未运行"
        fi
```

- [ ] **Step 2: Append 3.4 conclusion**

At the end of `generate_middleware_section()`, before the closing brace, add:

```bash
    cat >> "${MD_FILE}" <<EOF

### 3.4.1 本节小结

EOF
    generate_section_conclusion "3.4" "本节中间件状态整体正常，Redis、Nacos 与 MySQL 检查未发现明显异常。"
```

- [ ] **Step 3: Record 3.5 security findings**

In `generate_security_section()`, after parsing SSH fields and before printing the SSH row, add:

```bash
        if [[ "${root_login}" == "yes" ]]; then
            add_section_finding "3.5" "WARN" "${hostname} 允许 SSH Root 登录"
        fi
        if [[ "${pass_auth}" == "yes" ]]; then
            add_section_finding "3.5" "WARN" "${hostname} 允许 SSH 密码认证"
        fi
        if [[ "${empty_pw}" == "yes" ]]; then
            add_section_finding "3.5" "CRIT" "${hostname} 允许 SSH 空密码登录"
        fi
```

In the security summary loop, after loading `ntp`, `locked`, and `sudo_today`, add:

```bash
        if [[ "${ntp}" == ERROR* || "${ntp}" == "NOT_SYNCED" ]]; then
            add_section_finding "3.5" "WARN" "${hostname} 的 NTP 同步状态为 ${ntp}"
        fi
        if [[ "${locked}" =~ ^[0-9]+$ && "${locked}" -gt 0 ]]; then
            add_section_finding "3.5" "INFO" "${hostname} 存在 ${locked} 个锁定用户"
        fi
```

- [ ] **Step 4: Append 3.5 conclusion**

At the end of `generate_security_section()`, before the closing brace, add:

```bash
    cat >> "${MD_FILE}" <<EOF

### 3.5.5 本节小结

EOF
    generate_section_conclusion "3.5" "本节系统安全检查整体平稳，SSH 配置、时间同步和用户权限检查未发现明显风险。"
```

- [ ] **Step 5: Record 3.6 Crontab findings**

At the end of `generate_crontab_section()`, before the conclusion, loop over `CRONTAB_ANALYSIS`:

```bash
    for i in "${!SERVER_HOSTNAMES[@]}"; do
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local analysis
        analysis=$(get_val "$i" "CRONTAB_ANALYSIS")
        [[ -z "${analysis}" || "${analysis}" == "N/A" || "${analysis}" == "NONE" ]] && continue

        IFS='|' read -ra analysis_parts <<< "${analysis}"
        local part level detail
        for part in "${analysis_parts[@]}"; do
            level="${part%%:*}"
            detail="${part#*:}"
            case "${level}" in
                ERROR) add_section_finding "3.6" "CRIT" "${hostname} 的定时任务分析发现 ${detail}" ;;
                WARN)  add_section_finding "3.6" "WARN" "${hostname} 的定时任务分析发现 ${detail}" ;;
                INFO)  add_section_finding "3.6" "INFO" "${hostname} 的定时任务分析发现 ${detail}" ;;
            esac
        done
    done
```

- [ ] **Step 6: Append 3.6 conclusion**

After the `CRONTAB_ANALYSIS` loop and before the closing brace, add:

```bash
    cat >> "${MD_FILE}" <<EOF

### 3.6.1 本节小结

EOF
    generate_section_conclusion "3.6" "本节定时任务检查整体正常，未发现脚本缺失或可疑任务。"
```

- [ ] **Step 7: Record 3.7 log findings**

In `generate_log_alert_section()`, after reading `kernel_err`, `oom`, `segfault`, `syslog_err`, and `sec_alert`, add:

```bash
        local kernel_count segfault_count syslog_count
        kernel_count=$(echo "${kernel_err}" | awk -F'|' '{print $1}')
        segfault_count=$(echo "${segfault}" | awk -F'|' '{print $1}')
        syslog_count=$(echo "${syslog_err}" | awk -F'|' '{print $1}')

        if [[ "${kernel_count}" =~ ^[0-9]+$ && "${kernel_count}" -gt 0 ]]; then
            add_section_finding "3.7" "WARN" "${hostname} 今日内核错误 ${kernel_err}"
        fi
        if [[ "${segfault_count}" =~ ^[0-9]+$ && "${segfault_count}" -gt 0 ]]; then
            add_section_finding "3.7" "WARN" "${hostname} 今日段错误 ${segfault}"
        fi
        if [[ "${syslog_count}" =~ ^[0-9]+$ && "${syslog_count}" -gt 0 ]]; then
            add_section_finding "3.7" "WARN" "${hostname} 今日系统日志错误 ${syslog_err}"
        fi
        if [[ -n "${sec_alert}" && "${sec_alert}" != "NONE" && "${sec_alert}" != "N/A" ]]; then
            add_section_finding "3.7" "WARN" "${hostname} 存在安全告警 ${sec_alert}"
        fi
```

In the existing OOM branch, after `add_issue`, add:

```bash
            add_section_finding "3.7" "CRIT" "${hostname} 今日 OOM Killer 触发 ${oom}"
```

- [ ] **Step 8: Append 3.7 conclusion**

At the end of `generate_log_alert_section()`, before the closing brace, add:

```bash
    cat >> "${MD_FILE}" <<EOF

### 3.7.1 本节小结

EOF
    generate_section_conclusion "3.7" "本节日志与告警检查整体平稳，未发现 OOM、内核错误或安全告警。"
```

- [ ] **Step 9: Run tests**

Run:

```bash
bash -n report.sh
bash tests/report_layout_test.sh
```

Expected: syntax check passes and all layout tests pass.

- [ ] **Step 10: Commit remaining section conclusions**

Run:

```bash
git add report.sh
git commit -m "feat: 添加中间件安全定时任务日志小结"
```

Expected: one commit containing `3.4` to `3.7` conclusion wiring.

### Task 6: Final Verification And Cleanup

**Files:**
- Modify: no code changes expected unless verification reveals a concrete failure

**Interfaces:**
- Consumes: all previous tasks
- Produces: verified Markdown and passing test output

- [ ] **Step 1: Run full verification**

Run:

```bash
bash -n report.sh
bash tests/report_layout_test.sh
```

Expected:

```text
总计: <number>  通过: <same number>  失败: 0
```

- [ ] **Step 2: Inspect generated Markdown headings**

Run:

```bash
rg -n "总体结论|本节小结|## 2\\." report/巡检报告_*.md
```

Expected: output includes `## 2.1 总体结论`, `## 2.2 严重问题`, `## 2.3 警告项`, `## 2.4 建议优化项`, and seven `本节小结` headings.

- [ ] **Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: only expected generated report artifacts may remain untracked or modified. Source changes are committed.

- [ ] **Step 4: Final response**

Report:

```text
已完成报告分析结论实现：第二章新增总体结论，3.1-3.7 均新增模板化自然语言本节小结。验证通过：bash -n report.sh；bash tests/report_layout_test.sh。
```

## Self-Review

- Spec coverage: Task 3 implements overall conclusion. Task 4 and Task 5 implement 3.1-3.7 section conclusions. Task 1 and Task 6 cover verification.
- Placeholder scan: no task relies on vague future work; every code change includes exact snippets and commands.
- Type consistency: helper names are consistent across all tasks: `add_section_finding`, `generate_section_conclusion`, `generate_overall_conclusion`, and `section_key_count`.
