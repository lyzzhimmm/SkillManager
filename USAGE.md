# SkillManager 使用指南

跨 Agent 通用 Skill 管理器 — 扫描、分类、部署 AI Agent Skills 到 Claude Code / Codex / Hermes。

## 快速开始

### 安装

1. 克隆仓库：
```bash
git clone https://github.com/lyzzhimmm/SkillManager.git
cd SkillManager
```

2. 编译：
```bash
swift build -c release
```

3. 创建 .app bundle 并放到 `/Applications/`：
```bash
# 创建 APP 目录结构
mkdir -p /Applications/SkillManager.app/Contents/{MacOS,Resources}

# 复制可执行文件
cp .build/arm64-apple-macosx/release/SkillManager /Applications/SkillManager.app/Contents/MacOS/

# 创建 Info.plist
cat > /Applications/SkillManager.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SkillManager</string>
    <key>CFBundleIdentifier</key><string>com.azhi.SkillManager</string>
    <key>CFBundleName</key><string>SkillManager</string>
    <key>CFBundleDisplayName</key><string>SkillManager</string>
    <key>CFBundleVersion</key><string>2.0</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
```

4. 首次运行解除签名限制：
```bash
xattr -cr /Applications/SkillManager.app
```

### 系统要求

- macOS 14.0+
- Swift 5.9+
- Git（用于云同步）
- 至少一个 Agent（Hermes / Claude Code / Codex）

---

## 核心概念

### 数据来源

| 数据 | 来源 | 说明 |
|---|---|---|
| Skill 列表（名称、分类、频次、描述、来源） | 生成的跨平台清单 | `~/.skill-vault/inventory/Agent Skill 跨平台对比清单.md` |
| 通用/专属分类 | 清单的章节标题 | `## 一、通用 Skill` / `## 二、Codex 专属` 等 |
| Agent 适配 | 清单 | 通用 Skill 适配所有 Agent，专属 Skill 只适配对应 Agent |
| Agent 已安装 | 本机目录扫描 | `~/.claude/skills/`、`~/.codex/skills/`、`~/.hermes/skills/` |
| 底部：总数 + 通用数 | 清单 | 来自生成的跨平台清单 |
| 底部：Claude/Codex/Hermes 数 | 本机目录扫描 | 各 Agent 目录里实际安装的 Skill 数量 |

### vault 仓库

`~/.skill-vault/` 是通用 Skill 的文件仓库，通过 GitHub 同步：

```
~/.skill-vault/
├── .git/
├── README.md
├── skills/          ← 所有通用 Skill 的 SKILL.md 文件
│   ├── brainstorming/
│   │   └── SKILL.md
│   ├── frontend-design/
│   │   └── SKILL.md
│   └── ...
└── inventory/       ← 清单文件
    ├── Agent Skill 跨平台对比清单.md  ← 自动生成
    └── supplement.md                 ← 手动维护
```

GitHub 仓库：`https://github.com/lyzzhimmm/skill-vault`（私有）

---

## 三步走工作流

### 1. 收集（↓ 收集）

**作用**：把本机 Agent 目录里的 Skill 复制到 vault 仓库。

**扫描目录**：
- `~/.agents/skills/`（共享，归所有 Agent）
- `~/.claude/skills/`
- `~/.codex/skills/`
- `~/.hermes/skills/`

**去重**：同名 Skill 只复制一次（优先共享目录）。

**操作**：点击侧边栏「↓ 收集」按钮。

### 2. 生成清单（📋 生成）

**作用**：根据 vault 里的 Skill 自动生成跨平台对比清单。

**分类逻辑**：

| 情况 | 分类 |
|---|---|
| Skill 在 2+ 个 Agent 目录里 | 通用 |
| 只在 `~/.agents/skills/` | 通用 |
| 只在 `~/.claude/skills/` | Claude 专属 |
| 只在 `~/.codex/skills/` | Codex 专属 |
| 只在 `~/.hermes/skills/` | Hermes 专属 |

**生成的清单格式**：

```markdown
## 一、通用 Skill

| Skill | 来源 | 当前所在 | 频次 | 用途 |
|---|---|---|:---:|---|
| `brainstorming` | 阿志 | Claude / Codex / Hermes | 高 | 创造性工作前的头脑风暴和需求澄清 |

## 二、Codex 专属

| Skill | 频次 | 用途 |
|---|:---:|---|
| `browser` | 高 | Codex 内置浏览器自动化 |
```

**输出路径**：`~/.skill-vault/inventory/Agent Skill 跨平台对比清单.md`

### 3. 匹配（🔄 匹配）

**作用**：读取补充清单，给 Skill 匹配分类、频次、描述、来源，刷新列表显示。

**补充清单** `~/.skill-vault/inventory/supplement.md` 格式：

```markdown
| Skill | 分类 | 频次 | 用途 | 来源 |
|---|---|:---:|---|---|
| `brainstorming` | 规划 & 设计 | 高 | 创造性工作前的头脑风暴和需求澄清 | 阿志 |
```

**匹配优先级**：
1. 补充清单的分类、频次、描述、来源（最高）
2. 清单里的频次和描述
3. SKILL.md 里的 tags 和 description（最低）

---

## 侧边栏功能

### 分类筛选

点击左侧分类名称，只显示该分类的 Skill。

可选分类：规划、开发、质量、调试、项目管理、网页、内容、架构、其他。

### 频次筛选

点击频次标签（高/中/低），只显示该频次的 Skill。可多选。

### Agent 适配（单选）

点击 Agent 标签，筛选兼容该 Agent 的 Skill：
- **通用 Skill**：适配所有 Agent
- **专属 Skill**：只适配对应 Agent

再点一次取消筛选。

### Agent 已安装（单选）

点击 Agent 标签，筛选本机已安装到该 Agent 目录的 Skill。
再点一次取消筛选。

### 云同步

| 按钮 | 作用 |
|---|---|
| 拉取 | 从 GitHub 拉取 vault 到 `~/.skill-vault/` |
| 🔄 清空拉取 | 删除 `~/.skill-vault/` 后重新克隆（解决冲突） |
| 推送 | 把本地 vault 推送到 GitHub |
| ↓ 收集 | 从本机 Agent 目录复制 Skill 到 vault |
| 📋 生成 | 生成跨平台对比清单 |
| 🔄 匹配 | 读取补充清单，刷新列表显示 |

---

## 表格功能

### 列说明

| 列 | 说明 |
|---|---|
| Skill | 名称 + 迁移状态标签（适配/专属） |
| 描述 | Skill 用途说明 |
| Agent | 圆形标签，实心=已安装，空心=未安装（纯展示） |
| 频次 | 高/中/低，可点击排序 |
| 来源 | 谁做的（阿志、Matt Pocock、Superpower 等） |

### 排序

- 点击「Skill」列头 → 按名称排序
- 点击「频次」列头 → 按频次排序
- 默认：频次高→低，同频次按字母序

### 右键菜单

右键点击 Skill → 部署到 Claude Code / Codex / Hermes。

### 批量部署

选中多个 Skill → 底部出现部署栏 → 选择目标 Agent → 确认部署。

---

## 部署逻辑

### 本地部署

把 Skill 从 vault 或 Agent 目录复制到目标 Agent 的 skills 目录：

```
~/.skill-vault/skills/brainstorming/ → ~/.hermes/skills/brainstorming/
```

**注意**：是复制，不是 symlink。

### 远程部署（SSH）

支持通过 SSH 部署到其他 Mac：

```swift
// 需要先配置 SSH 免密登录
// ~/.ssh/config
Host mac2
    HostName 192.168.x.x
    User your_username
```

---

## 笔记本使用流程

### 首次设置

1. 安装 SkillManager APP
2. 确保 Git 已登录 GitHub
3. 打开 APP → 点击「🔄 清空拉取」
4. 点击「📋 生成」
5. 点击「🔄 匹配」

### 日常使用

1. **查看 Skill**：打开 APP，左侧筛选
2. **部署 Skill**：选中 → 右键 → 部署到 Agent
3. **同步更新**：点击「拉取」→「📋 生成」→「🔄 匹配」

---

## 清单维护

### 补充清单（手动维护）

路径：`~/.skill-vault/inventory/supplement.md`

格式：

```markdown
| Skill | 分类 | 频次 | 用途 | 来源 |
|---|---|:---:|---|---|
| `skill-name` | 规划 & 设计 | 高 | 描述 | 阿志 |
```

**分类可选值**：
- 规划 & 设计
- 开发 & 构建
- 代码质量 & 审查
- 调试 & 测试
- 项目管理
- 网页 & 搜索
- 内容 & 文档
- 架构 & 模式
- 其他

**频次可选值**：高 / 中 / 低

### 维护流程

1. 编辑 `supplement.md`
2. 提交并推送到 GitHub：
```bash
cd ~/.skill-vault
git add -A
git commit -m "更新补充清单"
git push
```
3. 在 APP 里点击「🔄 匹配」

---

## 底部状态栏

| 显示 | 含义 | 数据来源 |
|---|---|---|
| 共 XX 个 Skill | 清单里的总 Skill 数 | 生成的清单 |
| 通用 XX | 清单里「通用」的数量 | 生成的清单 |
| Claude XX | 本机 Claude 目录安装了多少个 | 本地目录扫描 |
| Codex XX | 本机 Codex 目录安装了多少个 | 本地目录扫描 |
| Hermes XX | 本机 Hermes 目录安装了多少个 | 本地目录扫描 |

---

## 常见问题

### Q: 为什么 Skill 数量和清单对不上？

A: 底部「共 XX 个」来自清单，「Claude/Codex/Hermes XX」来自本机目录。如果某个 Skill 在清单里但本机没装，总数会大于已安装数。

### Q: 为什么点「部署到」没有反应？

A: 检查目标 Agent 目录是否存在。如果 `~/.hermes/skills/` 不存在，需要先安装 Hermes。

### Q: 笔记本拉取失败怎么办？

A: 点击「🔄 清空拉取」，会删除本地 vault 后重新克隆。

### Q: 清单里的分类不对怎么办？

A: 编辑 `~/.skill-vault/inventory/supplement.md`，修改对应 Skill 的分类，然后点「🔄 匹配」。

### Q: 通用 Skill 数量和清单对不上？

A: 通用 Skill 的判断基于清单的章节标题（`## 一、通用 Skill`），不是基于目录扫描。确保清单格式正确。

---

## 技术架构

### 文件结构

```
SkillManager/
├── Package.swift
└── SkillManager/
    ├── SkillManagerApp.swift    # 入口
    ├── ContentView.swift        # 主视图 + 表格 + 部署逻辑
    ├── SidebarView.swift        # 侧边栏（分类/筛选/云同步）
    ├── StatusView.swift         # 底部状态栏
    ├── DeployBarView.swift      # 批量部署操作栏
    ├── ToastView.swift          # 提示消息
    ├── SkillRowView.swift       # Agent/Frequency Badge
    ├── SearchField.swift        # 原生搜索框
    ├── Models.swift             # 数据模型（Agent/Frequency/Category/Skill）
    ├── SkillScanner.swift       # 清单解析 + 安装状态扫描
    ├── SkillStore.swift         # 数据存储 + 操作
    ├── SkillDeployer.swift      # 部署（本地复制 + SSH）
    ├── SkillSyncer.swift        # Git 同步 + 清单生成
    └── Theme.swift              # 主题色
```

### 数据流

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   收集       │     │   生成清单   │     │   匹配       │
│ Agent→Vault │ ──→ │ Vault→清单   │ ──→ │ 清单→显示    │
└─────────────┘     └─────────────┘     └─────────────┘
      │                   │                   │
      ▼                   ▼                   ▼
~/.skill-vault/    inventory/             APP 列表
skills/            Agent Skill            + 分类
                   跨平台对比清单.md       + 频次
                                          + 描述
                                          + 来源
```

### 清单生成逻辑详解

1. **扫描 vault 目录**：获取所有 Skill 名称
2. **检查 Agent 目录**：对每个 Skill，检查它在哪些 Agent 目录里
3. **分类**：
   - 2+ 个 Agent 有 → 通用
   - 只在一个 Agent → 该 Agent 专属
4. **读取补充清单**：获取分类、频次、描述、来源
5. **生成 Markdown**：按分类分组，输出到 `inventory/Agent Skill 跨平台对比清单.md`

### 匹配逻辑详解

1. **读取清单**：解析 `Agent Skill 跨平台对比清单.md`
2. **解析章节**：
   - `## 一、通用 Skill` → 通用（`compatibleWith = allAgents`）
   - `## 二、Codex 专属` → Codex 专属
   - `## 三、Claude 专属` → Claude 专属
   - `## 四、Hermes 专属` → Hermes 专属
3. **扫描安装状态**：检查 `~/.claude/skills/`、`~/.codex/skills/`、`~/.hermes/skills/`
4. **读取补充清单**：获取分类、频次、描述、来源
5. **合并显示**：清单数据 + 安装状态 + 补充元数据

---

## GitHub 仓库

- **SkillManager APP**：https://github.com/lyzzhimmm/SkillManager
- **Skill Vault**：https://github.com/lyzzhimmm/skill-vault（私有）

---

## 更新日志

### v2.0 (2026-06-01)

- 三步走工作流（收集→生成→匹配）
- 清单为数据源，安装状态独立扫描
- 通用 Skill 强制适配所有 Agent
- 部署改为文件复制（不再用 symlink）
- 新增「清空并拉取」按钮
- 频次列支持排序
- 补充清单自动匹配分类/频次/描述/来源
