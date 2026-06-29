# 工程协作规范 skill 设计

| 项目 | 值 |
|------|----|
| 日期 | 2026-06-29 |
| 版本 | v1.0 |
| 状态 | 待评审 |
| 影响范围 | 新增用户级全局 skill，跨项目复用 |

## 1. 背景

当前项目（SystemHealthScan）的 `CLAUDE.md` 沉淀了一套协作规范（LF 换行符、中文 Conventional Commits、命令执行白名单等），这些规范与具体业务无关，适用于任何项目。但在开下一个项目时，这些规范散落在项目级配置里，需要手工复制，容易遗漏、重复踩坑（CRLF 混入、英文 commit、AI 滥用重构等）。

需要把这些通用规范提炼成一个**用户级全局 skill**，在新项目里一键落地，避免重复踩坑。

## 2. 目标

- 把通用工程协作规范（与业务无关的部分）提炼为可复用 skill
- skill 既包含**规范条文**（AI 协作时遵循），也包含**落地脚手架**（新项目一键生成配置文件）
- 跨项目、跨语言可用，不绑定 Linux 巡检业务
- 新项目 5 分钟内完成规范落地

## 3. 非目标

- 不包含任何业务领域规范（不涉及巡检键名、报告排版等）
- 不替代项目的 `CLAUDE.md` 业务部分，仅提供协作规范片段
- 不做规范检查工具（扫描 CRLF/英文 commit 的自动检查脚本），仅靠 AI 读取 skill 后自觉遵循
- 不绑定具体 AI 工具（skill 内容通用，但落地产物会同时生成 `CLAUDE.md` 和 `AGENTS.md`）

## 4. skill 元信息

| 字段 | 值 |
|------|-----|
| skill 名称 | `engineering-conventions` |
| 存放位置 | 用户级全局：`~/.claude/skills/engineering-conventions/SKILL.md`（即 `C:\Users\amarsoft\.claude\skills\engineering-conventions\SKILL.md`） |
| 触发场景（description） | "新项目初始化时生成协作规范配置文件；提交代码、编辑文件、执行命令前校验是否遵循 LF 换行符、中文 Conventional Commits、命令执行白名单、AI 代码克制等规范" |
| skill 类型 | Flexible（原则指导型，按上下文应用） |

## 5. 规范条文（7 条）

每条采用 `规则 / Why / How to apply` 三段式。

### 5.1 换行符统一 LF

- **规则**：仓库所有文本文件（`.md` / `.sh` / `.conf` / `.json` / `.txt` / `.yml` / `.yaml` / `.py` / `.js` 等）统一使用 LF 换行符，禁止 CRLF；根目录 `.gitattributes` 配置 `* text=auto eol=lf`，由 git 在 commit/checkout 时自动归一化。
- **Why**：Windows 编辑器默认 CRLF，混入仓库会导致 diff 噪声、shell 脚本执行失败（行尾 `\r`）、patch 不干净、跨平台协作冲突。
- **How to apply**：新项目第一步写 `.gitattributes`；AI 创建或修改任何文本文件时用 LF；编辑时发现 CRLF 先转 LF 再提交。

### 5.2 Git 提交中文 + Conventional Commits

- **规则**：commit message 用中文撰写；格式 `<类型>：<简要描述>`，类型取自 `feat` / `fix` / `docs` / `refactor` / `test` / `chore` / `perf` / `style`；标题行 ≤50 字符；正文另起空行补充动机、影响范围、验证方式；多项改动拆分为多次提交，每次提交语义单一。
- **Why**：中文团队可读性高；统一前缀便于生成 changelog 和按类型检索；语义单一的提交便于 review 和回滚。
- **How to apply**：提交前自问"这次改动是不是单一意图"，不是就拆分；标题用中文动词短语。

### 5.3 命令执行白名单

- **规则**：
  - **直接执行**（无需逐步确认）：所有只读/列表/安全命令 —— `ls` / `cat` / `head` / `tail` / `pwd` / `echo` / `find` / `grep` / `git status` / `git diff` / `git log` / `git add` / `git commit` / `git pull` / `git push` / `git branch` / `git checkout` / `git merge`，以及 `.claude/settings.local.json` 白名单内的命令。
  - **必须先确认**：`git push --force` / `git reset --hard` / `git rebase` / `rm -rf` / 删除文件类命令 / 任何破坏性或不可逆操作。
- **Why**：常规命令频繁确认打断节奏；破坏性操作误触代价大（丢工作、覆盖远端、删库）。
- **How to apply**：AI 自行判断命令属于哪类；灰区时默认询问；白名单通过 `.claude/settings.local.json` 的 `permissions.allow` 显式声明。
- **白名单与确认规则的关系**：`.claude/settings.local.json` 的 `Bash(git:*)` 等通配规则是**工具层默认放行**（免弹确认框），**不等于 AI 可以跳过确认**；AI 仍须按本条规则主动识别破坏性子命令（`push --force` / `reset --hard` / `rebase` 等）并先询问用户。工具放行 + AI 主动克制，两层叠加才是完整策略。

### 5.4 AI 代码克制原则

- **规则**：不过度设计；不为不可能发生的场景加错误处理/校验/降级；不添加未被要求的注释、docstring、类型注解；不引入未被使用的依赖；不做未被要求的重构；不写向后兼容 shim（直接改代码）；三行相似代码优于过早抽象；不加 feature flag。
- **Why**：被要求的改动才该发生；额外"顺手改"污染 diff、增加 review 负担、引入隐藏风险；投机性抽象日后反而成为负担。
- **How to apply**：动手前对齐"这次被要求改什么"，边界外不动；只在系统边界（用户输入、外部 API）做校验；删除代码就彻底删，不留 `// removed` 占位。

### 5.5 先读后改

- **规则**：修改文件前先 `Read` 该文件，理解现有命名、结构、风格；新增检查项/配置项时同步更新关联的配置和文档；遵循项目既有约定（命名、目录、模式）。
- **Why**：盲改易破坏既有约定；配置与代码不同步是常见线上隐患；与现有风格一致的代码才易维护。
- **How to apply**：任何 `Edit` 前先 `Read` 目标文件；改阈值/键名/接口时检查所有关联文件（配置、文档、测试）。

### 5.6 不创建非必要文件

- **规则**：不主动创建 README、文档、脚手架、工具脚本、helper 文件，除非用户明确要求；默认编辑现有文件优于新建文件。
- **Why**：文件膨胀难维护；未被要求的文档会快速过时；一次性操作的 helper 不该沉淀为永久抽象。
- **How to apply**：确需新建文件先和用户对齐；优先在现有文件里完成改动。

### 5.7 AI 指令文件双写同步

- **规则**：`CLAUDE.md` 和 `AGENTS.md` 同时存在时，协作规范部分内容必须同步；新建项目时两个文件一起生成；修改任一方的协作规范条款，立即同步另一方，并在同一次提交里完成。
- **Why**：Claude 读 `CLAUDE.md`，Codex / Copilot / Gemini 等读 `AGENTS.md`；不同步会导致不同 AI 行为不一致，重复踩同一批坑。
- **How to apply**：脚手架阶段双写；后续每次改协作规范，两个文件一起改、一起提交；业务专属内容可只在对应文件写。

## 6. 落地脚手架

skill 内嵌以下模板，新项目按 `§7 落地 checklist` 顺序生成。

### 6.1 `.gitattributes`

```gitattributes
# 统一换行符为 LF
* text=auto eol=lf

# 显式声明常见文本类型（可选，增强跨平台一致性）
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

# 二进制文件不做换行符归一化
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

### 6.2 `.editorconfig`

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

### 6.3 `CLAUDE.md` 协作规范片段

```markdown
## 协作规范

### 文件换行符
- 仓库所有文本文件统一使用 LF 换行符，禁止 CRLF
- 根目录 `.gitattributes` 配置 `* text=auto eol=lf`，git 自动归一化
- AI 创建/修改任何文本文件时必须用 LF

### Git 提交规范
- commit message 必须用中文
- 格式：`<类型>：<简要描述>`，类型参考 feat / fix / docs / refactor / test / chore / perf / style
- 标题行 ≤50 字符；多项改动拆分多次提交，每次语义单一

### 命令执行白名单
- 只读/安全命令（ls/cat/grep/git status/git diff/git log/git add/git commit/git pull/git push/git checkout 等）直接执行
- 破坏性命令（git push --force / git reset --hard / git rebase / rm -rf / 删除文件）必须先确认

### AI 代码克制
- 不过度设计、不加未被要求的注释/依赖、不做未被要求的重构
- 修改前先读文件，遵循现有风格
- 不主动创建非必要文件（README/文档/脚本），除非明确要求

### AI 指令文件同步
- 修改 CLAUDE.md 的协作规范时，同步更新 AGENTS.md，同一次提交
```

### 6.4 `AGENTS.md`

与 `CLAUDE.md` 的"协作规范"章节内容完全一致（业务专属章节按需各自补充）。

### 6.5 `.claude/settings.local.json`

分两层：**基础通用**（任何项目都需要）+ **项目扩展**（按项目技术栈追加）。

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

**项目扩展占位**（按技术栈追加到 `allow` 数组）：
- 文档转换类：`Bash(pandoc:*)`
- 十六进制查看：`Bash(xxd:*)`
- 容器类：`Bash(docker:*)`、`Bash(docker-compose:*)`
- 包管理类：`Bash(npm:*)`、`Bash(pnpm:*)`、`Bash(yarn:*)`、`Bash(pip:*)`、`Bash(pipx:*)`
- 测试/构建类：`Bash(make:*)`、`Bash(pytest:*)`、`Bash(jest:*)`

### 6.6 落地 checklist

| 步骤 | 动作 | 验证 |
|------|------|------|
| 1 | `git init`（若尚未初始化） | `.git/` 目录存在 |
| 2 | 写 `.gitattributes`（§6.1） | `git check-attr text -- <file>` 返回 `text: set` |
| 3 | 写 `.editorconfig`（§6.2） | 编辑器识别 LF |
| 4 | 双写 `CLAUDE.md` + `AGENTS.md` 协作规范（§6.3、§6.4） | 两文件协作规范章节内容一致 |
| 5 | 写 `.claude/settings.local.json`（§6.5） | `git status` 等命令免确认 |
| 6 | 首次提交（中文 + Conventional Commits 格式） | `git log` 显示 `chore：初始化协作规范` |

## 7. skill 文件结构

```
~/.claude/skills/engineering-conventions/
└── SKILL.md      # 含 frontmatter（name/description）+ 7 条规范 + 脚手架模板 + checklist
```

`SKILL.md` 内容组织：
1. frontmatter（`name` / `description`）
2. "何时触发此 skill"（trigger 场景）
3. 规范条文（7 条三段式，§5 内容）
4. 新项目落地（脚手架模板 §6 + checklist §6.6）
5. 现有项目应用（仅遵循规范条文，不重复生成配置）

## 8. 验证策略

- **skill 可被发现**：在 `~/.claude/skills/engineering-conventions/SKILL.md` 创建后，新会话里 AI 能在"提交代码/编辑文件/执行命令/新项目初始化"场景自动激活
- **脚手架可用**：在空白目录跑一遍 checklist，生成 5 个文件，`git check-attr` / `git log` 验证通过
- **规范可遵循**：AI 读取 skill 后，提交信息自动用中文 Conventional Commits、编辑文件用 LF、破坏性命令先确认
- **跨项目复用**：在非 Linux 巡检项目（如纯 Python/Web 项目）里也能无修改落地

## 9. 后续可扩展

- 规范检查脚本（扫描 CRLF 混入 / 英文 commit / 缺失 `.gitattributes`，pre-commit hook 形态）
- `.gitignore` 通用模板（按语言/技术栈分类的预设片段）
- commit message 模板文件（`.gitmessage`）
