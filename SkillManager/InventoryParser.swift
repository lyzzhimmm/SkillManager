import Foundation

struct InventoryParser {

    struct SkillMeta {
        let frequency: Frequency
        let source: String
        let isUniversal: Bool
        let description: String
        let migration: MigrationStatus
        let compatibleWith: Set<Agent>
    }

    struct AgentInventoryEntry {
        let name: String
        let description: String
        let source: String
        let frequency: Frequency
        let migration: MigrationStatus
    }

    // MARK: - Paths

    static let inventoryDir: String = {
        // Prefer vault repo path, fallback to local path
        let vaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".skill-vault/inventory").path
        if FileManager.default.fileExists(atPath: vaultDir) {
            return vaultDir
        }
        return "/Volumes/PJSSD/通用skill及指南/Skill 清单"
    }()

    static var inventoryPath: String {
        UserDefaults.standard.string(forKey: "inventoryPath")
            ?? "\(inventoryDir)/Agents Skill 跨平台对比清单.md"
    }

    static func defaultAgentInventoryPaths() -> [Agent: String] {
        [
            .claude: "\(inventoryDir)/Claude Code Skill 完整清单.md",
            .codex:  "\(inventoryDir)/Codex Skill 完整清单.md",
            .hermes: "\(inventoryDir)/Hermes Skill 完整清单.md",
        ]
    }

    // MARK: - Shared Cell Parsing

    struct ParsedCells {
        var frequency: Frequency = .low
        var source: String = ""
        var migration: MigrationStatus = .portable
        var description: String = ""
        var compatibleWith: Set<Agent> = Set(Agent.allCases)
    }

    static func parseCells(_ cells: [String]) -> ParsedCells {
        var result = ParsedCells()
        var descCandidate: String?

        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)

            // Frequency
            if c == "高" { result.frequency = .high; continue }
            if c == "中" { result.frequency = .medium; continue }
            if c == "低" { result.frequency = .low; continue }

            // Source
            if c == "ECC" || c == "ECC（阿志）" { result.source = "ECC"; continue }
            if c == "阿志" { result.source = "阿志"; continue }
            if c == "Superpower" { result.source = "Superpower"; continue }
            if c == "Matt Pocock" || c == "Matt" { result.source = "Matt"; continue }
            if c == "Codex 插件" || c == "本机 Codex" || c == "Codex 系统" { result.source = "Codex"; continue }
            if c == "gstack" || c.contains("gstack") { result.source = "gstack"; continue }
            if c == "Codex" || c.hasPrefix("Codex（") { result.source = "Codex"; continue }
            if c.hasPrefix("Hermes（") || c == "Hermes 内置" || c.contains("hermes") { result.source = "Hermes"; continue }

            // Compatible agents (from "当前所在" column)
            if c.contains("Claude") && c.contains("Codex") && c.contains("Hermes") {
                result.compatibleWith = Set(Agent.allCases)
            } else if c.contains("Claude") && c.contains("Codex") {
                result.compatibleWith = [.claude, .codex]
            } else if c.contains("Claude") && c.contains("Hermes") {
                result.compatibleWith = [.claude, .hermes]
            } else if c.contains("Codex") && c.contains("Hermes") {
                result.compatibleWith = [.codex, .hermes]
            } else if c.contains("Claude") {
                result.compatibleWith = [.claude]
            } else if c.contains("Codex") {
                result.compatibleWith = [.codex]
            } else if c.contains("Hermes") {
                result.compatibleWith = [.hermes]
            }

            // Migration markers in cells (fallback, section heading takes priority)
            if c.contains("可迁移") && !c.contains("不") { result.migration = .portable; continue }
            if c.contains("需适配") || c.contains("需验证") { result.migration = .needsAdaptation; continue }
            if c == "❌ Claude 专用" || c == "❌ Claude 专属" { result.migration = .exclusive(.claude); continue }
            if c == "❌ Codex 专用" || c == "❌ Codex 专属" || c == "❌ 插件专用" { result.migration = .exclusive(.codex); continue }
            if c == "❌ Hermes 专用" || c == "❌ Hermes 专属" { result.migration = .exclusive(.hermes); continue }
            if c.contains("❌") { result.migration = .exclusive(nil); continue }

            // Description candidate: longest meaningful text
            if c.count > 2,
               !c.contains("✅"), !c.contains("⚠️"), !c.contains("❌"),
               !c.contains("可迁移"), !c.contains("需适配"),
               !c.contains("专用"), !c.contains("专属"),
               c != "Skill", c != "Skill/Command", c != "用途",
               c != "来源", c != "频次", c != "分类", c != "状态" {
                if descCandidate == nil || c.count > descCandidate!.count {
                    descCandidate = c
                }
            }
        }

        result.description = descCandidate ?? ""
        return result
    }

    // MARK: - Cross-platform Inventory

    static func parse(at path: String? = nil) -> [String: SkillMeta] {
        let filePath = path ?? inventoryPath
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return [:]
        }

        var universalNames = Set<String>()
        var dict: [String: SkillMeta] = [:]
        var seen = Set<String>()

        // Determine migration from section heading
        var currentMigration: MigrationStatus = .portable
        var inUniversalSection = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Section headings drive migration status
            if trimmed.hasPrefix("## ") {
                let heading = trimmed.lowercased()
                if heading.contains("通用") {
                    currentMigration = .portable
                    inUniversalSection = true
                } else if heading.contains("claude") && heading.contains("专属") {
                    currentMigration = .exclusive(.claude)
                    inUniversalSection = false
                } else if heading.contains("codex") && heading.contains("专属") {
                    currentMigration = .exclusive(.codex)
                    inUniversalSection = false
                } else if heading.contains("hermes") && heading.contains("专属") {
                    currentMigration = .exclusive(.hermes)
                    inUniversalSection = false
                } else {
                    inUniversalSection = false
                }
                continue
            }
            if trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") { continue }

            guard trimmed.hasPrefix("|") else { continue }
            if trimmed.contains("---") { continue }

            let cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 2 else { continue }

            let name = cells[0].replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty && name.count < 80 else { continue }
            if !isValidSkillName(name) { continue }
            if seen.contains(name) { continue }
            seen.insert(name)

            if inUniversalSection {
                universalNames.insert(name)
            }

            let parsed = parseCells(cells)

            // Section heading overrides cell-level migration
            let migration: MigrationStatus
            switch currentMigration {
            case .portable:
                migration = parsed.migration == .needsAdaptation ? .needsAdaptation : .portable
            default:
                migration = currentMigration
            }

            // 通用 Skill = 纯 prompt，适配所有 Agent
            let compatibleWith: Set<Agent> = universalNames.contains(name) ? Set(Agent.allCases) : parsed.compatibleWith

            dict[name] = SkillMeta(
                frequency: parsed.frequency,
                source: parsed.source,
                isUniversal: universalNames.contains(name),
                description: parsed.description,
                migration: migration,
                compatibleWith: compatibleWith
            )
        }

        return dict
    }

    // MARK: - Per-agent Inventories

    static func parseAgentInventory(agent: Agent, path: String? = nil) -> [AgentInventoryEntry] {
        let filePath = path ?? defaultAgentInventoryPaths()[agent]
        guard let filePath = filePath,
              let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return []
        }

        var entries: [AgentInventoryEntry] = []
        var seen = Set<String>()
        var inSkillSection = true

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                let heading = trimmed.lowercased()
                inSkillSection = !heading.contains("自动化") && !heading.contains("automation")
                    && !heading.contains("command") && !heading.contains("命令")
                    && !heading.contains("总览") && !heading.contains("汇总")
                    && !heading.contains("迁移建议") && !heading.contains("按频次")
                continue
            }
            if !inSkillSection { continue }

            guard trimmed.hasPrefix("|") else { continue }
            if trimmed.contains("---") { continue }

            let cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 2 else { continue }

            let rawName = cells[0].replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !rawName.isEmpty, rawName.count < 80 else { continue }
            if !isValidSkillName(rawName) { continue }
            if seen.contains(rawName) { continue }
            seen.insert(rawName)

            let parsed = parseCells(cells)

            entries.append(AgentInventoryEntry(
                name: rawName,
                description: parsed.description,
                source: parsed.source,
                frequency: parsed.frequency,
                migration: parsed.migration
            ))
        }

        return entries
    }

    // MARK: - Validation

    private static let headerNames: Set<String> = [
        "Skill", "Skill/Command", "分类", "标记", "含义", "来源", "名称",
        "用途", "频次", "迁移性", "自动化", "已安装总计", "状态"
    ]

    static func isValidSkillName(_ name: String) -> Bool {
        if headerNames.contains(name) { return false }
        if name.hasPrefix("/") { return false }
        if name.contains("**") { return false }
        if name.contains(" / ") { return false }
        if name.unicodeScalars.contains(where: {
            $0.value == 0x26A0 || $0.value == 0x2705 || $0.value == 0x274C ||
            $0.value == 0x1F4E6 || $0.value == 0x1F534 || $0.value == 0x1F7E2
        }) { return false }
        if name.unicodeScalars.contains(where: {
            ($0.value >= 0x3000 && $0.value <= 0x303F) ||
            $0.value == 0xFF0C || $0.value == 0x3002 ||
            $0.value == 0xFF1B || $0.value == 0xFF1A
        }) { return false }
        if name.count < 2 { return false }
        return true
    }
}
