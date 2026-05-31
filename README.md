# SkillManager

跨 Agent 通用 Skill 管理器 — 扫描、分类、部署 AI Agent Skills 到 Claude Code / Codex / Hermes。

## 功能

- 🔍 **自动扫描** — 扫描本机已安装的 Agent Skills + 跨平台清单
- 📊 **分类管理** — 按规划/开发/质量/调试/项目管理等分类，显示来源、频次
- 🚀 **一键部署** — 选中 Skill → 复制到 Claude Code / Codex / Hermes 目录
- ☁️ **云同步** — 通过 GitHub 私有仓库（skill-vault）跨 Mac 同步通用 Skill
- 🔎 **搜索过滤** — 按名称/描述搜索，按分类/频次/Agent 筛选

## 截图

打开 `/Applications/SkillManager.app` 即可使用。

## 安装

### 方式 1：直接下载

```bash
# 克隆仓库
git clone https://github.com/lyzzhimmm/SkillManager.git
cd SkillManager

# 编译运行
swift build -c release
open .build/arm64-apple-macosx/release/SkillManager
```

### 方式 2：打包为 .app

```bash
swift build -c release
# 手动创建 .app bundle，参考下方「打包」章节
```

## 使用

### 基本操作

1. 打开 APP，左侧选择分类
2. 右侧列表查看 Skill 详情（名称、描述、Agent、频次、来源）
3. 右键点击 Skill → 选择「部署到 Claude Code / Codex / Hermes」

### 云同步

```bash
# 笔记本首次使用
# 1. 确保已配置 GitHub 登录
gh auth status

# 2. 打开 APP → 云同步 → 初始化仓库
# 3. 点击「拉取」同步通用 Skill
# 4. 选中 Skill → 部署到各 Agent
```

### 维护清单

```bash
# 编辑清单文件
open ~/.skill-vault/inventory/Agents\ Skill\ 跨平台对比清单.md

# 推送更新
cd ~/.skill-vault
git add -A
git commit -m "更新清单"
git push
```

## 项目结构

```
SkillManager/
├── Package.swift
└── SkillManager/
    ├── SkillManagerApp.swift    # 入口
    ├── ContentView.swift        # 主视图
    ├── SidebarView.swift        # 侧边栏（分类/筛选）
    ├── StatusView.swift         # 底部状态栏
    ├── DeployBarView.swift      # 部署操作栏
    ├── ToastView.swift          # 提示消息
    ├── SkillRowView.swift       # Agent/Frequency Badge
    ├── SearchField.swift        # 原生搜索框
    ├── Models.swift             # 数据模型
    ├── InventoryParser.swift    # 清单解析
    ├── SkillScanner.swift       # 目录扫描
    ├── SkillStore.swift         # 数据存储
    ├── SkillDeployer.swift      # 部署（本地复制 + SSH）
    ├── SkillSyncer.swift        # Git 同步
    └── Theme.swift              # 主题色
```

## 清单文件格式

跨平台清单（`Agents Skill 跨平台对比清单.md`）结构：

```markdown
## 一、通用 Skill（纯 prompt，可迁移到任意 Agent）

### 规划 & 设计

| Skill | 来源 | 当前所在 | 频次 | 用途 |
|---|---|---|:---:|---|
| `brainstorming` | Superpower | Claude / Codex / Hermes | 高 | 创造性工作前的头脑风暴和需求澄清 |
```

- **章节标题**决定迁移状态（`通用` = 可部署，`XX 专属` = 不可迁移）
- **来源**支持：Codex、Matt、阿志、Superpower、Hermes 等
- **频次**：高 / 中 / 低

## 系统要求

- macOS 14.0+
- Swift 5.9+
- Git（用于云同步）

## License

MIT
