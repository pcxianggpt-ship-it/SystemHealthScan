# 工程协作规范 skill 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在用户级全局目录创建 `engineering-conventions` skill，让新项目可一键落地协作规范，并让 AI 在协作时自动遵循。

**Architecture:** 单文件 skill（`SKILL.md`），内容含 frontmatter + 7 条规范条文 + 脚手架模板 + 落地 checklist。存放在 `~/.claude/skills/engineering-conventions/`，不在项目仓库内（用户级全局），无需 git 提交；spec 设计文档已在项目仓库 `docs/superpowers/specs/` 提交。

**Tech Stack:** Markdown + YAML frontmatter（Claude Code skill 格式）

**Spec 来源:** `docs/superpowers/specs/2026-06-29-engineering-conventions-skill-design.md`

---

## 文件结构

| 路径 | 动作 | 职责 |
|------|------|------|
| `C:\Users\amarsoft\.claude\skills\engineering-conventions\SKILL.md` | 创建 | skill 主体：frontmatter + 触发说明 + 7 条规范 + 脚手架模板 + checklist |

不涉及项目仓库内的任何文件改动（spec 已提交）。

---

### Task 1: 创建 skill 目录

**Files:**
- Create dir: `C:\Users\amarsoft\.claude\skills\engineering-conventions\`

- [ ] **Step 1: 确认父目录存在**

Run: `ls "C:/Users/amarsoft/.claude/skills/" 2>/dev/null || echo "NOT_EXIST"`
Expected: 列出已有 skill 目录，或输出 `NOT_EXIST`

- [ ] **Step 2: 创建 skill 目录（含父目录）**

Run: `mkdir -p "C:/Users/amarsoft/.claude/skills/engineering-conventions"`
Expected: 无输出（成功）

- [ ] **Step 3: 验证目录已创建**

Run: `ls -la "C:/Users/amarsoft/.claude/skills/engineering-conventions/"`
Expected: 显示 `total 0` 和 `.`/`..` 两行

---

### Task 2: 写入 SKILL.md 完整内容

**Files:**
- Create: `C:\Users\amarsoft\.claude\skills\engineering-conventions\SKILL.md`

- [ ] **Step 1: 用 Write 工具创建 SKILL.md，内容如下（完整，无占位符）**

文件路径：`C:/Users/amarsoft/.claude/skills/engineering-conventions/SKILL.md`

完整内容：

````markdown
---
name: engineering-conventions
description: 新项目初始化时生成协作规范配置文件（.gitattributes/.editorconfig/CLAUDE.md/AGENTS.md/.claude/settings.local.json）；提交代码、编辑文件、执行命令前校验是否遵循 LF 换行符、中文 Conventional Commits、命令执行白名单、AI 代码克制、先读后改、不创建非必要文件、CLAUDE.md 与 AGENTS.md 双写同步等规范。用于跨项目复用工程协作规范，避免重复踩坑。
---

# 工程协作规范

## 何时触发此 skill

- **新项目初始化**：用户说"新项目""初始化协作规范""设置 CLAUDE.md"等，按"新项目落地"章节生成配置文件
- **提交代码时**：commit message 是否中文 + Conventional Commits + 语义单一
- **编辑文件时**：换行符是否 LF、是否先读后改
- **执行命令时**：破坏性命令（force push / reset --hard / rebase / rm -rf / 删除文件）是否先确认
- **新建文件时**：是否真的必要、是否同步双写 CLAUDE.md 与 AGENTS.md

## 一、规范条文

### 1. 换行符统一 LF

- **规则**：仓库所有文本文件（`.md`/`.sh`/`.conf`/`.json`/`.txt`/`.yml`/`.yaml`/`.py`/`.js` 等）用 LF，禁止 CRLF；根目录 `.gitattributes` 配 `* text=auto eol=lf` 自动归一化
- **Why**：Windows 编辑器默认 CRLF，混入会导致 diff 噪声、shell 脚本 `\r` 报错、patch 不干净、跨平台冲突
- **How**：新项目第一步写 `.gitattributes`；AI 创建/修改文本文件用 LF；发现 CRLF 先转 LF 再提交

### 2. Git 提交中文 + Conventional Commits

- **规则**：commit message 用中文；格式 `<类型>：<描述>`，类型取自 `feat`/`fix`/`docs`/`refactor`/`test`/`chore`/`perf`/`style`；标题 ≤50 字；多项改动拆多次提交，每次语义单一
- **Why**：中文团队可读；统一前缀便于 changelog 和检索；语义单一便于 review 和回滚
- **How**：提交前自问"是否单一意图"，不是就拆；标题用中文动词短语

### 3. 命令执行白名单

- **规则**：
  - **直接执行**：只读/安全命令 —— `ls`/`cat`/`head`/`tail`/`pwd`/`echo`/`find`/`grep`/`git status`/`git diff`/`git log`/`git add`/`git commit`/`git pull`/`git push`/`git branch`/`git checkout`/`git merge`，及 `.claude/settings.local.json` 白名单内命令
  - **必须先确认**：`git push --force`/`git reset --hard`/`git rebase`/`rm -rf`/删除文件类命令/任何破坏性或不可逆操作
- **Why**：常规命令频繁确认打断节奏；破坏性操作误触代价大
- **How**：AI 自行判断命令类别；灰区默认询问；白名单通过 `.claude/settings.local.json` 的 `permissions.allow` 声明
- **白名单与确认的关系**：`Bash(git:*)` 等通配是**工具层默认放行**（免弹确认框），**不等于 AI 可跳过确认**；AI 仍须主动识别破坏性子命令并先询问。工具放行 + AI 主动克制，两层叠加才是完整策略

### 4. AI 代码克制原则

- **规则**：不过度设计；不为不可能场景加错误处理/校验/降级；不加未被要求的注释/docstring/类型注解；不引入未用依赖；不做未被要求的重构；不写向后兼容 shim；三行相似代码优于过早抽象；不加 feature flag
- **Why**：被要求的改动才该发生；额外"顺手改"污染 diff、增加 review 负担、引入风险
- **How**：动手前对齐"被要求改什么"，边界外不动；只在系统边界（用户输入/外部 API）做校验；删代码彻底删，不留 `// removed` 占位

### 5. 先读后改

- **规则**：修改文件前先 `Read`，理解现有命名/结构/风格；新增配置项同步更新关联配置和文档；遵循既有约定
- **Why**：盲改易破坏约定；配置与代码不同步是常见线上隐患
- **How**：任何 `Edit` 前先 `Read`；改阈值/键名/接口时检查所有关联文件（配置/文档/测试）

### 6. 不创建非必要文件

- **规则**：不主动创建 README/文档/脚手架/工具脚本/helper，除非明确要求；默认编辑现有文件优于新建
- **Why**：文件膨胀难维护；未被要求的文档会快速过时
- **How**：确需新建先和用户对齐；优先在现有文件里完成

### 7. AI 指令文件双写同步

- **规则**：`CLAUDE.md` 和 `AGENTS.md` 同时存在时，协作规范部分必须同步；新项目两个文件一起生成；修改任一方协作规范，立即同步另一方，同一次提交完成
- **Why**：Claude 读 `CLAUDE.md`，Codex/Copilot/Gemini 读 `AGENTS.md`；不同步会导致不同 AI 行为不一致，重复踩坑
- **How**：脚手架阶段双写；改协作规范时两个文件一起改一起提交；业务专属内容可只在对应文件写

## 二、新项目落地（脚手架）

按以下顺序生成 5 个文件，生成后双写校验 CLAUDE.md 与 AGENTS.md 一致。

### 文件 1：`.gitattributes`

```gitattributes
* text=auto eol=lf

*.md     text eol=lf
*.sh     text eol=lf
*.py     text eol=lf
*.js     text eol=lf
*.ts     text eol=lf
*.json   text eol=lf
*.yml    text eol=lf
*.yaml   text eol=lf
*.conf   text eol=lf
*.txt    text eol=lf

*.png    binary
*.jpg    binary
*.jpeg   binary
*.gif    binary
*.pdf    binary
*.docx   binary
*.xlsx   binary
*.zip    binary
*.gz     binary
*.tar    binary
```

### 文件 2：`.editorconfig`

```editorconfig
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.{md,mdx,yml,yaml,json,js,ts,jsx,tsx,css,html,svg,vue}]
indent_size = 2

[*.sh]
indent_size = 4

[Makefile]
indent_style = tab

[*.{bat,cmd}]
end_of_line = crlf
```

### 文件 3：`CLAUDE.md`（协作规范片段）

```markdown
## 协作规范

### 文件换行符
- 仓库所有文本文件统一 LF，禁止 CRLF
- 根目录 `.gitattributes` 配 `* text=auto eol=lf`，git 自动归一化
- AI 创建/修改文本文件必须用 LF

### Git 提交规范
- commit message 必须用中文
- 格式：`<类型>：<描述>`，类型参考 feat/fix/docs/refactor/test/chore/perf/style
- 标题 ≤50 字；多项改动拆分多次提交，每次语义单一

### 命令执行白名单
- 只读/安全命令直接执行
- 破坏性命令（git push --force / git reset --hard / git rebase / rm -rf / 删除文件）必须先确认
- settings.local.json 的通配放行 ≠ AI 跳过确认，AI 仍须主动识别破坏性子命令

### AI 代码克制
- 不过度设计、不加未被要求的注释/依赖、不做未被要求的重构
- 修改前先读文件，遵循现有风格
- 不主动创建非必要文件，除非明确要求

### AI 指令文件同步
- 修改 CLAUDE.md 协作规范时同步更新 AGENTS.md，同一次提交
```

### 文件 4：`AGENTS.md`

与 `CLAUDE.md` 的"协作规范"章节内容**完全一致**（业务专属章节按需各自补充）。

### 文件 5：`.claude/settings.local.json`

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(bash:*)",
      "Bash(sh:*)",
      "Bash(dash:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(cp:*)",
      "Bash(mv:*)",
      "Bash(find:*)",
      "Bash(grep:*)",
      "Bash(sed:*)",
      "Bash(awk:*)",
      "Bash(cut:*)",
      "Bash(sort:*)",
      "Bash(uniq:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(xargs:*)",
      "Bash(wc:*)",
      "Bash(chmod:*)",
      "Bash(command:*)",
      "Bash(echo:*)",
      "Bash(printf:*)",
      "Bash(curl:*)"
    ]
  }
}
```

**项目扩展**（按技术栈追加到 `allow`）：`pandoc`/`xxd`/`docker`/`docker-compose`/`npm`/`pnpm`/`yarn`/`pip`/`pipx`/`make`/`pytest`/`jest`。

### 落地 checklist

| 步骤 | 动作 | 验证 |
|------|------|------|
| 1 | `git init`（若未初始化） | `.git/` 存在 |
| 2 | 写 `.gitattributes` | `git check-attr text -- <任意文本文件>` 返回 `text: set` |
| 3 | 写 `.editorconfig` | 编辑器识别 LF |
| 4 | 双写 `CLAUDE.md` + `AGENTS.md` | 两文件协作规范章节 diff 为空 |
| 5 | 写 `.claude/settings.local.json` | `git status` 等命令免确认 |
| 6 | 首次提交 | `git log` 显示 `chore：初始化协作规范` |

## 三、现有项目应用

对已存在的项目，**不重复生成配置文件**，仅遵循"一、规范条文"。若发现缺失（如无 `.gitattributes` 或 CRLF 混入），提示用户并建议补齐，不擅自批量改写。
````

- [ ] **Step 2: 验证文件已写入且 frontmatter 正确**

Run: `head -5 "C:/Users/amarsoft/.claude/skills/engineering-conventions/SKILL.md"`
Expected: 输出以 `---` 开头，第 2 行为 `name: engineering-conventions`，第 3 行以 `description:` 开头，第 5 行为 `---`

- [ ] **Step 3: 验证换行符为 LF（无 CRLF）**

Run: `file "C:/Users/amarsoft/.claude/skills/engineering-conventions/SKILL.md"` 或 `grep -c $'\r' "C:/Users/amarsoft/.claude/skills/engineering-conventions/SKILL.md"`
Expected: `grep -c` 输出 `0`（无 `\r`，纯 LF）

- [ ] **Step 4: 验证文件大小合理**

Run: `wc -l "C:/Users/amarsoft/.claude/skills/engineering-conventions/SKILL.md"`
Expected: 行数在 180-240 之间（完整 skill 内容）

---

### Task 3: 验证 skill 可被发现

**Files:**
- 无文件改动，仅验证

- [ ] **Step 1: 确认 skill 路径符合 Claude Code 全局 skill 发现规则**

Run: `ls "C:/Users/amarsoft/.claude/skills/engineering-conventions/SKILL.md"`
Expected: 文件存在，无报错

- [ ] **Step 2: 在新会话或当前会话验证 skill 进入索引**

说明：Claude Code 启动时扫描 `~/.claude/skills/*/SKILL.md`，本 skill 会在下次新会话自动进入索引。当前会话可通过 `/skills` 或等价命令确认（若环境支持）。

Expected: skill 列表含 `engineering-conventions`

- [ ] **Step 3: 向用户交付验证清单**

提示用户：
1. 关闭并重开 Claude Code 会话
2. 在新项目里说"初始化协作规范"，确认 AI 触发本 skill 并按 checklist 生成 5 个文件
3. 在现有项目里做一次提交，确认 commit message 走中文 Conventional Commits 格式

---

## Self-Review

**1. Spec 覆盖检查**：
- §4 skill 元信息 → Task 2 Step 1 frontmatter ✓
- §5.1-5.7 七条规范 → Task 2 Step 1 "一、规范条文" 1-7 ✓
- §6.1-6.5 脚手架模板 → Task 2 Step 1 "二、新项目落地" 文件 1-5 ✓
- §6.6 落地 checklist → Task 2 Step 1 "二、落地 checklist" ✓
- §7 skill 文件结构 → Task 1 + Task 2 ✓
- §8 验证策略 → Task 2 Step 2-4 + Task 3 ✓

**2. 占位符扫描**：无 TBD/TODO/"implement later"；所有脚手架模板均为可直接复制的完整内容 ✓

**3. 类型/命名一致性**：
- skill 名 `engineering-conventions` 在 frontmatter、目录名、计划标题中一致 ✓
- 5 个脚手架文件名与 spec §6 一致 ✓
- 规范条文编号 1-7 与 spec §5.1-5.7 一致 ✓

无问题，计划可执行。
