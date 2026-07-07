# 巡检报告排版优化设计

| 项目 | 值 |
|------|----|
| 日期 | 2026-06-26 |
| 版本 | v1.0 |
| 状态 | 待评审 |
| 影响范围 | `report.sh` 全部章节生成函数 |

## 1. 背景

当前 `report.sh` 生成的报告存在两个核心问题：

1. **3.2 网络 ~ 3.7 日志告警 全部按服务器分章节**：6 个章节里每台服务器独立小节（`### k8sn1` / `### support-61011`），运维人员想横向对比两台服务器的网卡/TCP/服务状态/中间件配置时，需要在多个小节间反复跳转。
2. **冗余项淹没关键信息**：
   - `k8sn1` 报告里 70+ 个虚拟网卡（`veth*`、`br-*`、`docker0`、`cni*`、`flannel*`）刷屏
   - `k8sn1` 报告里 70+ 个 docker container `/var/lib/docker/containers/*/mounts/shm` 和 `/var/lib/kubelet/pods/*` 挂载点占满磁盘表
   - Java 进程命令行单条 400+ 字符（如 Pulsar、RocketMQ Broker），表格被撑宽不可读
3. **网卡表无 IP 列**：同机房存在多台同名主机时无法区分。

3.1 资源章节（CPU/内存/磁盘/IO）**已经是横向融合**，是本设计的参考样板。

## 2. 目标

- 3.2 ~ 3.7 所有章节改为**横向融合**：一张表同时容纳多台服务器数据
- 每张融合表的前两列固定为 `主机 | IP`，防止主机名重复无法区分
- 默认过滤无诊断价值的冗余项（虚拟网卡、容器挂载、Java 命令行噪声）
- 单表列数稳定在 5-9 列，兼容 30+ 台大规模巡检的 Word 渲染
- **不动 `collect.sh`**：所有改动仅在 `report.sh` 端，数据源字段不变

## 3. 非目标

- 不改 `collect.sh` 采集逻辑（已确认）
- 不引入新的依赖或外部工具
- 不改报告目录结构（仍是 封面 → 概览 → 问题 → 应用巡检 → 附录）
- 不实现报告样式美化（字体、颜色），仅优化信息组织

## 4. 关键决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 融合范围 | 全部章节（3.2-3.7） | 用户选 B |
| 矩阵 vs 行型 | 全行型 | 实际巡检 10-30+ 台，矩阵 30 列会折行 |
| 虚拟网卡 | 默认过滤 | 避免刷屏 |
| 容器/kubelet 挂载 | 默认过滤 | 避免刷屏 |
| Java 命令行 | 折叠到关键字段 | 单条 400+ 字符无法入表 |
| 服务状态 | 按主机分组、每服务一行 | 矩阵型不可行；按主机分组保持上下文 |
| IP 列来源 | 现有 `IP=` 字段（每台主 IP） | 不改 collect.sh |

## 5. 整体策略

### 5.1 表格类型约定

- **行型表**：每行表示"一台主机的一个实体"（一台主机一行，或一台主机的一个网卡/进程/任务一行）。列固定，行数随规模线性增长。
- **不使用矩阵型表**（主机作列）：30+ 台会折行。

### 5.2 表头约定

所有融合表的前两列固定为 `| 主机 | IP |`，后续列按章节定义。

`IP` 取自 `collect.sh` 输出的 `IP=` 字段（每台服务器的主 IP），同一主机在多行中重复出现。

### 5.3 排序约定

- 跨主机：按 `服务器清单`（1.1 节）顺序，与原始 `.dat` 文件传入顺序一致
- 同主机多行：按采集项原始顺序（如 Java 进程按 PID 升序、Crontab 按文件+行号）

## 6. 详细设计

### 6.1 章节调整总览

| 章节 | 改动 | 新结构 |
|------|------|--------|
| 3.2 网络状态 | 重写 `generate_network_section` | 4 张行型表（网卡/TCP/网络附属）+ 监听端口按主机分段 |
| 3.3 进程与 Java | 重写 `generate_process_section` | 5 个子节（统计/Top5/服务/Java 详情/完整命令行附录链接） |
| 3.4 中间件 | 重写 `generate_middleware_section` | 1 张行型表 |
| 3.5 安全 | 重写 `generate_security_section` | 3 张行型表 + 今日登录小节 |
| 3.6 Crontab | 重写 `generate_crontab_section` | 1 张行型表 |
| 3.7 日志告警 | 重写 `generate_log_alert_section` | 1 张行型表 |
| 附录 B（新增） | 新增 `generate_java_command_lines_appendix` | 所有 Java 进程完整命令行 |

### 6.2 3.2 网络状态

**6.2.1 网卡表**

```
| 主机 | IP | 网卡 | 状态 | 速率 |
```

数据：`NET_NIC_` 字段，按 `|` 分隔，每项格式 `name:STATUS:SPEED`。

过滤规则（**虚拟网卡**，正则匹配网卡名即过滤）：
```
^(veth|br-|docker|cni|flannel|kube-ipvs|virbr|vboxnet|tap|tun)
^lo$
```

预期效果：`k8sn1` 从 70 行网卡降至 2-3 行（物理网卡 + loopback 视情况保留）。

**6.2.2 TCP 连接表**

```
| 主机 | IP | ESTABLISHED | TIME_WAIT | CLOSE_WAIT | SYN_RECV |
```

数据：`NET_TCP_STATUS` 字段，按 `|` 分隔，每项 `KEY:VALUE`。

**6.2.3 监听端口**

每台主机一段紧凑列表（避免每端口一行导致 50+ 行）：

```
**k8sn1 (10.1.11.21)** 监听端口：
22(sshd) | 2379(etcd) | 6443(kube-apiserver) | 10250(kubelet) | ...

**support-61011 (192.168.61.11)** 监听端口：
22(unknown) | 25(unknown) | 53(unknown) | ...
```

数据：`NET_LISTEN_PORTS` 字段，原格式 `port(proc)|port(proc)|...`。

**6.2.4 网络附属**

```
| 主机 | IP | DNS 解析 | 防火墙 | 默认路由 |
```

字段：`NET_DNS_RESOLVE` / `NET_FIREWALL` / `NET_ROUTE`。

### 6.3 3.3 进程与 Java 应用

**6.3.1 进程统计**

```
| 主机 | IP | 总计 | 运行 | 休眠 | 僵尸 |
```

字段：`PROCESS_TOTAL` / `PROCESS_RUNNING` / `PROCESS_SLEEPING` / `PROCESS_ZOMBIE`。

**6.3.2 CPU Top5 / 内存 Top5**

每台主机一段 5 行小表，字段不变：

```
**k8sn1 (10.1.11.21) CPU Top5:**
| PID | 进程名 | CPU% |
| ... |

**k8sn1 (10.1.11.21) 内存 Top5:**
| PID | 进程名 | 内存 |
| ... |
```

**6.3.3 服务状态（按主机分组）**

每台主机一段，每服务一行：

```
**k8sn1 (10.1.11.21) 服务状态:**
| 服务 | 状态 |
| sshd | RUNNING |
| docker | RUNNING |
| mongod | STOPPED |
```

字段：`SERVICE_STATUS`，原格式 `name:STATE|name:STATE|...`。

**6.3.4 Java 进程详情（折叠命令行）**

```
| 主机 | IP | PID | 进程名 | Xmx | GC Old% | OOM | 日志路径 |
```

- **进程名**：从完整命令行提取，按优先级：
  1. `-jar xxx.jar` 的 `xxx.jar` 文件名
  2. `--class xxx` 或最后一个非选项参数的主类名（取最后一段 `.` 后的简短名）
  3. 否则取 `java` 或绝对路径的 basename
- **Xmx**：从 `JAVA_PS_<idx>_JVM` 提取，格式 `Xms:..:Xmx:..`，显示 Xmx 部分（如 `1g` / `256M` / `default`）
- **GC Old%**：从 `JAVA_PS_<idx>_GC` 提取 OldGen 百分比
- **OOM**：`JAVA_PS_<idx>_OOM_DUMP`
- **日志路径**：`JAVA_PS_<idx>_LOG`，简化为 `SOURCE:NOT_FOUND` 或实际路径

**6.3.5 附录 B：Java 完整命令行**

新增附录章节，按主机分小节，仅列出完整命令行供查阅：

```
## 附录 B：Java 进程完整命令行

### B.1 k8sn1 (10.1.11.21)

#### PID 47654
java -XX:MaxHeapSize=256M -Drocketmq.namesrv.addr=... -jar /rocketmq-dashboard.jar

#### PID 64876
...
```

### 6.4 3.4 中间件状态

```
| 主机 | IP | Redis | Nacos | MySQL 版本 | MySQL 连接 | 复制角色 | InnoDB Buffer |
```

字段映射：
- Redis → `REDIS_STATUS`
- Nacos → `NACOS_STATUS`
- MySQL 综合 → 从 `MYSQL_STATUS` / `MYSQL_REPLICATION` / `MYSQL_INNODB_BUFFER` 拆分
- 不可用时显示 `N/A`

### 6.5 3.5 系统安全

**6.5.1 SSH 配置**

```
| 主机 | IP | 端口 | Root 登录 | 密码认证 | 空密码 | MaxAuth |
```

字段：`SSH_CONFIG`，原格式 `PORT:22|ROOT_LOGIN:yes|...`。

**6.5.2 内核关键参数**

```
| 主机 | IP | 连接队列(somaxconn) | Swap 倾向(swappiness) | 系统文件句柄(file-max) | 打开文件数(ulimit -n) | SYN 队列(tcp_syn_backlog) |
```

字段：`SYSCTL_KEY_PARAMS`，原格式 `key=value|key=value|...`；`打开文件数(ulimit -n)` 来自 `ULIMIT_NOFILE`。

**6.5.3 安全综合状态**

```
| 主机 | IP | SELinux | Fail2ban | NTP 同步 | 锁定用户 | Sudo 今日 |
```

字段：`SELINUX_STATUS` / `FAIL2BAN_STATUS` / `NTP_SYNC` / `USER_LOCKED` / `USER_SUDO_TODAY`。

**6.5.4 今日登录用户**

每台主机一段，行格式：

```
**k8sn1 (10.1.11.21) 今日登录：** root, root, root, root
**support-61011 (192.168.61.11) 今日登录：** pcxiang, wbhan
```

字段：`USER_LOGIN_TODAY`。

### 6.6 3.6 Crontab

```
| 主机 | IP | 用户 | 来源 | 调度 | 命令 |
```

字段：`CRONTAB_SYSTEM`，原格式 `user:source:schedule:cmd|...`。

**Anacron** 单独一段文字（每台一行），字段 `CRONTAB_ANACRON`。

### 6.7 3.7 日志与告警

```
| 主机 | IP | 认证失败 | 内核错误 | OOM Killer | 段错误 | 系统日志错误 | 安全告警 | 最近登录 |
```

字段：`LOG_AUTH_FAIL_TODAY` / `LOG_KERNEL_ERROR` / `LOG_OOM_KILLER` / `LOG_SEGFAULT` / `LOG_SYSLOG_ERROR` / `LOG_SECURITY_ALERT` / `LOG_LAST_LOGIN`。

`OOM Killer` 字段保留 `count|KILLED:proc` 原始格式，便于看出 killed 进程。

## 7. 过滤规则集中定义

为避免散落在各函数里，统一在 `report.sh` 顶部定义：

```bash
# 虚拟网卡过滤正则（匹配网卡名即过滤）
NIC_FILTER_REGEX='^(veth|br-|docker|cni|flannel|kube-ipvs|virbr|vboxnet|tap|tun)|^lo$'

# 容器/kubelet 挂载过滤正则（匹配挂载点路径即过滤）
MOUNT_FILTER_REGEX='(/var/lib/docker/containers/.*/mounts/shm|/var/lib/kubelet/pods/|/var/lib/docker/overlay2)'
```

## 8. Java 命令行折叠算法

```
输入：完整命令行字符串
输出：表格用的简短进程名（≤ 50 字符）

1. 若包含 `-jar <path>`：取 path 的 basename（如 `/rocketmq-dashboard.jar` → `rocketmq-dashboard.jar`）
2. 否则若包含 org.apache.catalina.startup.Bootstrap → `tomcat-Bootstrap`
3. 否则取最后一个非 `-` 开头的 token，按 `.` 分割取最后一段（如 `org.apache.rocketmq.broker.BrokerStartup` → `BrokerStartup`）
4. 否则取 java 命令的 basename（如 `/opt/jdk1.8.0_162/bin/java` → `java`）
5. 若结果超过 50 字符，截断并加 `...`
```

## 9. 实施范围

| 函数 | 行号（当前） | 改动类型 |
|------|------------|---------|
| `generate_network_section` | 627 | 重写 |
| `generate_process_section` | 725 | 重写（拆出 Java 命令行附录） |
| `generate_middleware_section` | 837 | 重写 |
| `generate_security_section` | 880 | 重写 |
| `generate_crontab_section` | 971 | 重写 |
| `generate_log_alert_section` | 1026 | 重写 |
| `generate_appendix` | 1092 | 增加 Java 命令行附录 B |
| 顶部常量 | 9-46 区域 | 新增 `NIC_FILTER_REGEX` / `MOUNT_FILTER_REGEX` |
| 新增 helper | - | `extract_short_process_name()` / `filter_virtual_nics()` / `filter_container_mounts()` |

`generate_overview`（1.x）、`generate_issues_summary`（2.x）、`generate_resource_section`（3.1）保持不变，它们已经是横向融合。

## 10. 验证策略

- **语法层**：`bash -n report.sh` 通过；`dash -n report.sh` 通过（保持 POSIX 兼容性，但 report.sh 内部用了关联数组，本身就是 bash 脚本）
- **数据层**：使用现有 `output/*.dat`（包括 `linux_test_20260413_111730.dat`、`server_20260626.dat` 等）作为测试数据，跑 `bash report.sh` 生成 Markdown，肉眼检查：
  - 所有融合表前两列是 `主机 | IP`
  - 虚拟网卡、容器挂载确实被过滤
  - Java 进程表无 400+ 字符的命令行
  - 附录 B 包含完整命令行
- **回归**：与现有 `.report_temp.md` 对比，确保没有信息丢失（只是排版变化）
- **pandoc 渲染**：跑 `pandoc` 转 `.docx`，确认表格列数在 5-9 之间，不会折行

## 11. 后续可扩展

设计完成后，未来的扩展点：
- 在 `config/checks.conf` 增加 `report.exclude_nics` / `report.exclude_mounts` 让过滤规则可配置
- 矩阵型表（30 列）作可选模式，由 `--matrix` 参数开启
- Java 命令行折叠规则可配置（如显示前 100 字符 vs jar 名）
