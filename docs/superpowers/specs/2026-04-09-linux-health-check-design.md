# Linux 服务器健康巡检工具 — 设计文档

## 1. 概述

一个纯 Shell 实现的 Linux 服务器健康巡检工具，支持本机执行和 SSH 远程执行两种模式，采集服务器状态后汇总生成 Word 巡检报告。

## 2. 架构

```
AutoCheck/
├── collect.sh              # 采集脚本（本机/远程通用）
├── report.sh               # 汇总报告生成脚本
├── config/
│   ├── servers.conf        # 服务器列表（IP、端口、用户名、标签）
│   └── checks.conf         # 可选：自定义检查项阈值
├── output/                 # 采集结果存放目录
│   ├── server1_20260409.dat
│   └── server2_20260409.dat
└── report/                 # 最终报告输出目录
    └── 巡检报告_20260409.docx
```

### 工作流程

1. 读取 `servers.conf` 获取服务器列表
2. 对每台服务器：通过 SSH 执行 `collect.sh`，或本机直接执行
3. 采集结果以结构化键值对保存到 `output/`
4. `report.sh` 读取所有 `.dat` 文件，生成 Markdown 中间文件
5. 通过 `pandoc` 转换为 Word 巡检报告

### 依赖

- 采集端：无额外依赖，仅使用 Linux 基础命令
- 报告端：需要安装 `pandoc`（一次性安装）

## 3. 服务器列表配置（servers.conf）

```
# 格式：标签 IP SSH端口 SSH用户 密码或密钥路径
# LOCAL 表示本机执行
LOCAL   web-server-01
WEB01   192.168.1.10  22  root    /root/.ssh/id_rsa
WEB02   192.168.1.11  22  root    /root/.ssh/id_rsa
DB01    192.168.1.20  22  root    ~/.ssh/db_key
APP01   192.168.1.30  22  admin   password:your_password
```

## 4. 采集数据格式

采集脚本 `collect.sh` 输出键值对格式，按模块分段。

### 4.1 系统信息

```
HOSTNAME=web-server-01
UNAME_N=web-server-01
IP=192.168.1.10
CHECK_TIME=2026-04-09_14:30:00
OS=CentOS 7.9
KERNEL=3.10.0-1160.el7.x86_64
ARCH=x86_64
UPTIME=30 days, 12:30
LAST_BOOT_TIME=2026-03-10 02:15:00
CPU_MODEL=Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz
CPU_CORES=16
CPU_SOCKETS=2
CPU_FREQ=2400.000
VIRTUAL_TYPE=VMware
```

### 4.2 基础资源

```
CPU_USAGE=35.2
CPU_LOAD_1=0.82
CPU_LOAD_5=1.05
CPU_LOAD_15=0.93
CPU_TOP5=PID:1234:java:45.2%|PID:5678:mysql:12.3%|PID:8901:nginx:8.7%|PID:2345:redis-server:5.1%|PID:6789:node:3.4%
MEM_TOTAL=32768
MEM_USED=18432
MEM_AVAILABLE=12000
MEM_BUFFERS=1200
MEM_CACHED=4500
MEM_PERCENT=56.25
SWAP_TOTAL=8192
SWAP_USED=256
DISK_=/:100G:67G:67%|/data:500G:320G:64%|/log:200G:180G:90%
INODE_=/:123456/524288:23%|/data:...
IO_UTIL_sda=2.3
IO_WAIT=1.2
IOPS_READ_sda=560
IOPS_WRITE_sda=320
```

### 4.3 网络状态

```
NET_NIC_=eth0:UP:1000Mbps:RX_ERR:0:TX_ERR:0:DROP:0
NET_LISTEN_PORTS=22(ssh)|80(nginx)|443(nginx)|3306(mysql)
NET_TCP_STATUS=ESTABLISHED:156|TIME_WAIT:89|CLOSE_WAIT:3|SYN_RECV:2
NET_DNS_RESOLVE=OK:8.8.8.8:1ms
NET_FIREWALL=iptables:ACTIVE|RULES:25
NET_ROUTE=default_via_192.168.1.1
NET_CONNECTIONS_TOP5=192.168.1.50:80:156|...
```

### 4.4 进程与服务

```
SERVICE_STATUS=nginx:RUNNING|mysql:RUNNING|docker:RUNNING|sshd:RUNNING
PROCESS_TOTAL=256
PROCESS_ZOMBIE=0
PROCESS_RUNNING=12
PROCESS_SLEEPING=244
PROCESS_TOP5_CPU=PID:1234:java:45.2%|PID:5678:mysql:12.3%|...
PROCESS_TOP5_MEM=PID:1234:java:3800M|PID:5678:mysql:1200M|...
```

### 4.5 Java 进程详细信息

每个 Java 进程按序号索引，采集完整信息：

```
# 进程概览
PROCESS_JAVA_COUNT=3

# 进程 1 — 基本信息
JAVA_PS_1=USER:root|PID:1234|START:2026-04-09_08:30:00|RUNTIME:6h12m|CPU:45.2%|MEM:3800M(11.6%)|PORT:8080,8443
JAVA_CMD_1=/usr/bin/java -Xms2g -Xmx4g -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/data/logs/oom/ -Dserver.port=8080 -Dspring.application.name=user-service -jar /data/app/user-service.jar --spring.profiles.active=prod
JAVA_CWD_1=/data/app/user-service/
JAVA_USER_1=root

# 进程 1 — JVM 参数
JAVA_JVM_XMS_XMX_1=Xms:2G:Xmx:4G
JAVA_JVM_GC_1=PS MarkSweep:count:56:time:3200ms|PS Scavenge:count:234:time:890ms
JAVA_JVM_GC_DETAIL_1=OldGen:used:1800M:max:4096M:percent:43%|Eden:used:512M:max:1536M|Survivor:used:32M:max:64M

# 进程 1 — OOM 检查
JAVA_JVM_OOM_PARAM_1=-XX:+HeapDumpOnOutOfMemoryError|-XX:HeapDumpPath=/data/logs/oom/
JAVA_JVM_OOM_DUMP_1=FOUND:2|/data/logs/oom/java_pid1234.hprof:2026-04-08:1.2G|/data/logs/oom/java_pid5678.hprof:2026-04-05:800M

# 进程 2 — ...
JAVA_PS_2=...
JAVA_CMD_2=...
...

# Java 日志收集记录
JAVA_LOG_COLLECT_1=SOURCE:/data/app/user-service/logs/:SAVED_TO:output/server01/user-service_logs.tar.gz:SIZE:45M
JAVA_LOG_COLLECT_2=SOURCE:/data/app/order-service/logs/:SAVED_TO:output/server01/order-service_logs.tar.gz:SIZE:120M
```

**JVM 信息来源：**

| 字段 | 来源 | 说明 |
|------|------|------|
| 完整命令行 | `ps -ef` 或 `/proc/PID/cmdline` | 完整启动参数 |
| 工作目录 | `pwdx PID` 或 `/proc/PID/cwd` | 应用部署路径 |
| 监听端口 | `ss -tlnp | grep PID` | 该进程监听的端口 |
| Xms/Xmx | 解析启动参数 | JVM 堆内存配置 |
| GC 统计 | `jstat -gc PID` 或 `jcmd PID GC.heap_info` | GC 次数和时间 |
| OOM 参数 | 解析启动参数中的 `-XX:+HeapDumpOnOutOfMemoryError` | 是否配置了 OOM Dump |
| OOM Dump 文件 | 根据 HeapDumpPath 检查 `.hprof` 文件 | 是否发生过 OOM |
| 日志路径 | 启动参数中的 `-Dlog.path` 或工作目录下的 logs/ | 日志文件位置 |

### 4.6 中间件

```
# Redis
REDIS_STATUS=RUNNING|VERSION:7.0|MEMORY:2.1G/8G|CONN:45|DBSIZE:128563
REDIS_SLOWLOG_COUNT_10MS=12|50MS=3|100MS=1
REDIS_REPLICATION=ROLE:MASTER|SLAVES:2|LAG:0
REDIS_KEYSPACE=db0:keys=128563,expires=45678,avg_ttl=3600

# Nacos
NACOS_STATUS=RUNNING|VERSION:2.2.3|SERVICES:45|CONFIGS:230|INSTANCES:128

# MySQL（如存在）
MYSQL_STATUS=RUNNING|VERSION:8.0.32|CONNECTIONS:45/500|SLOW_QUERIES:15|THREADS_RUNNING:8
MYSQL_REPLICATION=ROLE:MASTER|SLAVE_STATUS:OK|BEHIND:0s
MYSQL_INNODB_BUFFER=HIT_RATE:99.2%|READ:12M|WRITTEN:3M
```

### 4.7 系统安全

```
# SSH 安全
SSH_CONFIG=PORT:22|ROOT_LOGIN:no|PASSWORD_AUTH:no|PERMIT_EMPTY:no|MAX_AUTH:3
SSH_FAILED_LOGIN_TODAY=5|LAST_FROM:192.168.1.200
SSH_TRUSTED_KEYS=3

# 用户与权限
USER_LOGIN_TODAY=root:3|admin:1
USER_SUDO_TODAY=2
USER_PASSWORD_EXPIRE=root:90days|admin:never
USER_LOCKED=2

# 安全模块
SELINUX_STATUS=Enforcing
FAIL2BAN_STATUS=RUNNING|BANNED:12

# 系统配置
SYSCTL_KEY_PARAMS=net.core.somaxconn=65535|vm.swappiness=10|fs.file-max=100000
NTP_SYNC=OK|SERVER:ntp.aliyun.com|OFFSET:0.5ms
```

### 4.8 Crontab 分析

```
# 系统级 crontab
CRONTAB_SYSTEM=root:/etc/cron.d/backup:0 2 * * *:/usr/local/bin/backup.sh|root:/etc/cron.d/clean_log:0 3 * * 0:/usr/local/bin/clean_log.sh

# 用户级 crontab
CRONTAB_USER_admin=30 8 * * 1-5:/home/admin/check.sh|0 0 1 * *:/home/admin/monthly_report.sh

# Anacron
CRONTAB_ANACRON=weekly:7 days:/etc/cron.weekly/|monthly:30 days:/etc/cron.monthly/

# 分析结论
CRONTAB_ANALYSIS=WARN:found_empty_crontab_for_root|INFO:admin_has_2_cron_jobs|ERROR:script_not_found:/opt/run.sh
```

**分析维度：**
- 列出所有用户的 crontab 条目
- 列出 `/etc/cron.d/`、`/etc/cron.daily/` 等系统定时任务
- 检查脚本路径是否存在
- 标记异常项（脚本不存在、空 crontab、可疑任务等）

### 4.9 日志与告警

```
AUTH_FAILED_TODAY=5|SRC:192.168.1.200:3,10.0.0.5:2
KERNEL_ERROR_TODAY=1|LAST:OOM_KILLER:java:PID1234
OOM_KILLER_TODAY=1|KILLED:java:PID:1234
SEGFAULT_TODAY=0
SYSLOG_ERROR_TODAY=12|TOP:nginx:error_connection_reset:5
SECURITY_ALERT=NONE
LAST_LOGIN=root@192.168.1.50:2026-04-09_09:15
```

### 4.10 环境信息

```
DOCKER_STATUS=RUNNING|CONTAINERS:12|IMAGES:8|VOLUMES:5
DOCKER_CONTAINER_=nginx:RUNNING:CPU:2.1%:MEM:256M|...
ENV_JAVA_VERSION=1.8.0_381|11.0.20
ENV_PYTHON_VERSION=3.9.16
ENV_NODE_VERSION=16.20.0
```

## 5. 报告结构

生成 Word 文档（`.docx`），结构如下：

```
巡检报告_20260409.docx
│
├─ 封面
│   ├─ 标题：Linux 服务器健康巡检报告
│   ├─ 巡检日期、巡检人（配置项）
│   └─ 服务器数量概览
│
├─ 1. 巡检概览
│   ├─ 服务器清单表格（主机名/IP/系统/虚拟化类型/状态）
│   └─ 总体健康评分（正常/警告/异常 台数）
│
├─ 2. 问题汇总
│   ├─ 严重问题（需立即处理）
│   ├─ 警告项（建议处理）
│   └─ 建议优化项
│
├─ 3. 应用巡检
│   │
│   ├─ 3.1 资源使用概况
│   │   ├─ CPU 使用率汇总表（所有服务器对比）
│   │   ├─ 内存使用率汇总表
│   │   ├─ 磁盘使用率汇总表（标红 >80% 的项）
│   │   └─ IO 使用情况汇总表
│   │
│   ├─ 3.2 网络状态
│   │   ├─ 各服务器监听端口
│   │   ├─ TCP 连接状态统计
│   │   └─ 网络异常项
│   │
│   ├─ 3.3 进程与 Java 应用
│   │   ├─ 服务存活状态汇总
│   │   ├─ CPU/MEM Top5 进程
│   │   └─ Java 进程详细信息（每台服务器）
│   │       ├─ 完整命令行
│   │       ├─ JVM 参数（Xms/Xmx/GC/OOM）
│   │       ├─ GC 统计
│   │       ├─ OOM Dump 检查结果
│   │       └─ 日志收集记录
│   │
│   ├─ 3.4 中间件状态
│   │   ├─ Redis 集群状态
│   │   ├─ Nacos 注册中心状态
│   │   └─ MySQL 状态（如存在）
│   │
│   ├─ 3.5 系统安全
│   │   ├─ SSH 配置检查
│   │   ├─ 异常登录检测
│   │   ├─ 用户与权限
│   │   └─ 防火墙状态
│   │
│   ├─ 3.6 Crontab 分析
│   │   └─ 每台服务器的定时任务清单与分析
│   │
│   └─ 3.7 日志与告警
│       ├─ 系统日志异常
│       ├─ OOM 事件记录
│       └─ 安全告警
│
├─ 4. Kubernetes 平台巡检（可选，检测到 kubectl 时自动启用，后续实现）
│   ├─ 集群概览（版本、节点数、命名空间）
│   ├─ Node 状态（Ready/NotReady、资源分配率）
│   ├─ Pod 状态（Running/Pending/CrashLoopBackOff 统计）
│   ├─ Deployment/StatefulSet 副本状态
│   ├─ 资源 Limit/Request 配置检查
│   └─ 事件告警（Recent Events 中的 Warning/Error）
│
├─ 5. 数据库巡检（后续实现）
│   ├─ Oracle（后续实现）
│   ├─ MySQL（后续实现）
│   └─ PostgreSQL（后续实现）
│
└─ 附录
    ├─ Java 应用日志（打包路径说明）
    └─ 原始采集数据（.dat 文件路径）
```

## 6. 告警阈值

以下阈值可在 `checks.conf` 中自定义，默认值如下：

| 指标 | 警告 | 严重 |
|------|------|------|
| CPU 使用率 | > 70% | > 90% |
| 内存使用率 | > 80% | > 95% |
| 磁盘使用率 | > 80% | > 90% |
| Inode 使用率 | > 80% | > 90% |
| SWAP 使用率 | > 30% | > 60% |
| Zombie 进程数 | > 5 | > 20 |
| TCP CLOSE_WAIT | > 50 | > 200 |
| 登录失败次数 | > 10 | > 50 |

## 7. 技术实现要点

### 采集脚本（collect.sh）

- 所有检查项通过函数封装，每个函数负责一个模块
- 自动检测本机或远程环境，兼容 CentOS/Ubuntu/Debian
- Java 进程信息通过 `/proc/PID/` 和 `jstat`/`jcmd`（如可用）获取
- 中间件检查先检测进程是否存在，再尝试连接获取详细信息
- 日志收集使用 `tar czf` 打包，支持大小限制（默认单包最大 500M）
- 输出统一写入 stdout，由调用方重定向到文件

### 报告脚本（report.sh）

- 逐行解析 `.dat` 文件中的键值对
- 按阈值判断状态（正常/警告/严重）
- 生成 Markdown 中间文件，再用 `pandoc` 转换为 Word
- 问题汇总自动归类为严重/警告/建议三级

### 兼容性

- 支持 CentOS 6/7/8/9、Ubuntu 18.04+、Debian 10+、KylinOS v10
- 部分 Java 检查需要 JDK 环境（JRE 环境下 `jstat`/`jcmd` 可能不可用，降级为解析 `/proc` 信息）
- 容器环境中部分检查项可能不可用（如硬件信息），自动跳过并标注

## 8. 后续迭代（MVP 之后）

- Kubernetes 平台巡检（检测到 kubectl 时自动启用，Node/Pod/Deployment/事件告警）
- 数据库巡检（Oracle/MySQL/PostgreSQL，慢查询、连接池、表空间、主从延迟等）
- 历史数据对比（与上次巡检结果对比变化趋势）
- Web 报告查看
- 邮件/钉钉/企业微信自动发送报告
