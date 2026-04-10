# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目愿景

**AutoSystemCheck** -- Linux 服务器自动健康巡检工具。通过 Shell 脚本采集服务器状态（本机或 SSH 远程），汇总生成 Word 巡检报告。目标是零依赖采集端 + pandoc 报告端的轻量级方案。

## 项目阶段

**设计阶段（Pre-MVP）**。当前仓库仅包含设计规格文档，尚无可执行代码。编码实现应严格遵循 `docs/superpowers/specs/2026-04-09-linux-health-check-design.md` 中的架构与数据格式定义。

## 架构总览

```
AutoCheck/
├── collect.sh              # 采集脚本（本机/远程通用）
├── report.sh               # 汇总报告生成脚本
├── config/
│   ├── servers.conf        # 服务器列表（IP、端口、用户名、标签）
│   └── checks.conf         # 自定义检查项阈值
├── output/                 # 采集结果 .dat 文件
└── report/                 # 最终 .docx 报告输出
```

工作流：读取 servers.conf -> SSH/本机执行 collect.sh -> 键值对 .dat 存入 output/ -> report.sh 解析 .dat 生成 Markdown -> pandoc 转 Word。

## 技术栈

| 层面 | 技术选型 |
|------|----------|
| 采集脚本 | 纯 Bash（兼容 POSIX，无额外依赖） |
| 报告生成 | Bash + Markdown 中间文件 + pandoc 转 .docx |
| 远程执行 | SSH（支持密码和密钥认证） |
| JVM 诊断 | jstat / jcmd / /proc/PID/（JRE 环境自动降级） |
| 配置管理 | 纯文本键值对配置文件 |

## 设计规格要点

- **采集数据格式**：统一键值对（`KEY=VALUE`），按模块分段输出到 stdout
- **采集模块**（共 10 个）：系统信息、基础资源、网络状态、进程与服务、Java 进程详情、中间件（Redis/Nacos/MySQL）、系统安全、Crontab 分析、日志与告警、环境信息（Docker/Java/Python/Node）
- **告警阈值**：可配置，默认分警告/严重两级（如 CPU >70%/90%，磁盘 >80%/90%）
- **报告结构**：封面 -> 巡检概览 -> 问题汇总（严重/警告/建议三级）-> 应用巡检详章 -> 附录
- **兼容性**：CentOS 6-9、Ubuntu 18.04+、Debian 10+、KylinOS v10；容器环境自动跳过不可用检查项

## 后续迭代计划

- Kubernetes 平台巡检（kubectl 检测后自动启用）
- 数据库巡检（Oracle/MySQL/PostgreSQL）
- 历史数据对比
- Web 报告查看、消息通知（邮件/钉钉/企业微信）

## 目录结构

```
SystemHealthScan/
├── README.md
├── CLAUDE.md                          # 本文件
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-04-09-linux-health-check-design.md   # 核心设计文档
└── .claude/
    └── index.json                     # 扫描索引
```

## 编码规范（设计文档约定）

- collect.sh 中所有检查项通过函数封装，每个函数负责一个模块
- 输出统一写入 stdout，由调用方重定向到文件
- 中间件检查先检测进程是否存在，再尝试连接获取详细信息
- 日志收集使用 `tar czf` 打包，单包上限 500M
- Java 进程按序号索引，每个进程采集完整信息（命令行、JVM 参数、GC、OOM Dump、日志路径）

## AI 使用指引

- 实现任何模块前，先通读设计文档中对应的章节，确保输出格式与键名完全一致
- collect.sh 和 report.sh 是项目核心入口，修改时保持"采集与报告分离"的架构原则
- 新增检查项时同步更新 checks.conf 中的阈值配置和报告模板中的对应章节
- 采集脚本必须兼容 CentOS/Ubuntu/Debian，避免使用发行版特有的命令或路径
