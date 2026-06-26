# collect.sh 使用说明

## 概述

`collect.sh` 是 Linux 服务器健康巡检工具的核心采集脚本，负责收集服务器基础状态信息并以键值对格式输出。

## 功能模块

1. **系统信息** - 主机名、IP、操作系统、内核、CPU信息等
2. **基础资源** - CPU使用率、负载、内存、磁盘、IO等
3. **网络状态** - 网卡状态、端口监听、TCP连接、DNS等
4. **进程与服务** - 服务状态、进程统计、Top进程等
5. **环境信息** - Docker、Java、Python、Node.js版本等

## 使用方法

### 基本用法

```bash
# 输出到标准输出
./collect.sh

# 输出到文件
./collect.sh output/server_$(date +%Y%m%d).dat

# 查看帮助
./collect.sh -h

# 查看版本
./collect.sh -v
```

### 输出格式

输出格式为 `KEY=VALUE`，每行一个键值对，模块之间用 `---` 分隔。

```
HOSTNAME=web-server-01
IP=192.168.1.10
CHECK_TIME=2026-04-11_14:30:00
OS=CentOS 7.9
KERNEL=3.10.0-1160.el7.x86_64
---
CPU_USAGE=35.2
CPU_LOAD_1=0.82
MEM_TOTAL=32768
MEM_USED=18432
...
```

## 系统兼容性

- CentOS 6/7/8/9
- Ubuntu 18.04+
- Debian 10+
- KylinOS v10

## 测试

运行测试脚本验证输出格式：

```bash
./tests/collect_test.sh
```

## 注意事项

1. 脚本需要 Bash 环境
2. 某些统计指标需要额外命令支持（如 iostat、mpstat），缺失时会显示 N/A
3. 容器环境中部分硬件信息可能不可用
4. 输出文件路径如果不存在会自动创建
