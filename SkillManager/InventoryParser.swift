import Foundation

struct InventoryParser {

    struct SkillMeta {
        let frequency: Frequency
        let source: String
        let isUniversal: Bool
        let description: String
        let migration: MigrationStatus
    }

    /// Per-agent inventory entry (from Claude/Codex/Hermes complete lists)
    struct AgentInventoryEntry {
        let name: String
        let description: String
        let source: String
        let frequency: Frequency
        let migration: MigrationStatus
    }

    // MARK: - Cross-platform inventory (Agents Skill 跨平台对比清单.md)

    static var inventoryPath: String {
        UserDefaults.standard.string(forKey: "inventoryPath")
            ?? "/Volumes/PJSSD/Agents Skill 跨平台对比清单.md"
    }

    static func parse(at path: String? = nil) -> [String: SkillMeta] {
        let filePath = path ?? inventoryPath
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return [:]
        }

        var universalNames = Set<String>()
        var inUniversalSection = false

        // Pass 1: collect all skill names that appear in the universal section
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                let heading = trimmed.lowercased()
                inUniversalSection = heading.contains("通用")
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

            if inUniversalSection {
                universalNames.insert(name)
            }
        }

        // Pass 2: parse all table rows for metadata
        var seen = Set<String>()
        var dict: [String: SkillMeta] = [:]
        inUniversalSection = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                inUniversalSection = trimmed.lowercased().contains("通用")
                continue
            }
            if trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") { continue }

            guard trimmed.hasPrefix("|") else { continue }
            if trimmed.contains("---") { continue }

            let cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 2 else { continue }

            let rawName = cells[0].replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !rawName.isEmpty && rawName.count < 80 else { continue }
            if !isValidSkillName(rawName) { continue }
            if seen.contains(rawName) { continue }
            seen.insert(rawName)

            var frequency: Frequency = .low
            var source = ""
            var description = ""
            var migration: MigrationStatus = .portable

            for cell in cells {
                let c = cell.trimmingCharacters(in: .whitespaces)

                if c == "高" { frequency = .high }
                else if c == "中" { frequency = .medium }
                else if c == "低" { frequency = .low }
                else if c == "ECC" || c == "ECC（阿志）" { source = "ECC" }
                else if c == "Matt Pocock" || c == "Matt" { source = "Matt" }
                else if c == "Codex 插件" { source = "Codex 插件" }
                else if c == "gstack" { source = "gstack" }
                else if c == "Codex" { source = "Codex" }
                else if c.hasPrefix("Codex（") { source = "Codex" }
                else if c.hasPrefix("Hermes（") { source = "Hermes" }
                else if c.contains("可迁移") && !c.contains("不") { migration = .portable }
                else if c.contains("需适配") { migration = .needsAdaptation }
                else if c == "❌ Claude 专用" || c == "❌ Claude 专属" { migration = .exclusive(.claude) }
                else if c == "❌ Codex 专用" || c == "❌ Codex 专属" || c == "❌ 插件专用" { migration = .exclusive(.codex) }
                else if c == "❌ Hermes 专用" || c == "❌ Hermes 专属" { migration = .exclusive(.hermes) }
                else if c.contains("❌") { migration = .exclusive(nil) }
            }

            // Description: last meaningful text cell
            for cell in cells.reversed() {
                let c = cell.trimmingCharacters(in: .whitespaces)
                guard !c.isEmpty, c.count > 2, !c.contains("|"),
                      c != "高", c != "中", c != "低",
                      c != "ECC", c != "Matt", c != "Codex", c != "Matt Pocock",
                      c != "Codex 插件", c != "gstack",
                      !c.hasPrefix("Codex（"), !c.hasPrefix("Hermes（"),
                      !c.contains("✅"), !c.contains("⚠️"), !c.contains("❌"),
                      !c.contains("可迁移"), !c.contains("需适配"),
                      !c.contains("专用"), !c.contains("专属"),
                      c != "Skill", c != "Skill/Command", c != "用途",
                      c != "来源", c != "频次", c != "分类" else { continue }
                description = c
                break
            }

            let isUniversal = universalNames.contains(rawName)

            dict[rawName] = SkillMeta(
                frequency: frequency,
                source: source,
                isUniversal: isUniversal,
                description: description,
                migration: migration
            )
        }

        return dict
    }

    // MARK: - Per-agent inventories

    /// Default paths for per-agent inventory files (in same directory as cross-platform)
    static func defaultAgentInventoryPaths() -> [Agent: String] {
        let dir = (inventoryPath as NSString).deletingLastPathComponent
        return [
            .claude: "\(dir)/Claude Code Skill 完整清单.md",
            .codex:  "\(dir)/Codex Skill 完整清单.md",
            .hermes: "\(dir)/Hermes Skill 完整清单.md",
        ]
    }

    /// Parse a per-agent inventory file and return all skills listed in it
    static func parseAgentInventory(agent: Agent, path: String? = nil) -> [AgentInventoryEntry] {
        let filePath = path ?? defaultAgentInventoryPaths()[agent]
        guard let filePath = filePath,
              let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return []
        }

        var entries: [AgentInventoryEntry] = []
        var seen = Set<String>()
        var inSkillSection = true  // track whether we're in a skill section

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track ## level headings to skip non-skill sections
            if trimmed.hasPrefix("## ") {
                let heading = trimmed.lowercased()
                // Skip: automations, commands, summary tables, migration suggestions
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

            var frequency: Frequency = .low
            var source = ""
            var description = ""
            var migration: MigrationStatus = .portable

            // Claude/Codex format: | Skill | 用途 | 来源 | 频次 | 迁移性 |
            // Hermes format:       | Skill | 用途 |
            // Some tables have extra columns

            for cell in cells {
                let c = cell.trimmingCharacters(in: .whitespaces)
                if c == "高" { frequency = .high }
                else if c == "中" { frequency = .medium }
                else if c == "低" { frequency = .low }
                else if c == "ECC" || c == "ECC（阿志）" { source = "ECC" }
                else if c == "Matt Pocock" || c == "Matt" { source = "Matt" }
                else if c == "Codex 插件" || c == "本机 Codex" || c == "Codex 系统" { source = "Codex" }
                else if c == "gstack" || c.contains("gstack") { source = "gstack" }
                else if c == "Codex" { source = "Codex" }
                else if c.hasPrefix("Codex（") { source = "Codex" }
                else if c.hasPrefix("Hermes（") || c == "Hermes 内置" || c.contains("hermes") { source = "Hermes" }
                else if c.contains("可迁移") && !c.contains("不") { migration = .portable }
                else if c.contains("需适配") || c.contains("需验证") { migration = .needsAdaptation }
                else if c == "❌ Claude 专用" || c == "❌ Claude 专属" { migration = .exclusive(.claude) }
                else if c == "❌ Codex 专用" || c == "❌ Codex 专属" || c == "❌ 插件专用" { migration = .exclusive(.codex) }
                else if c == "❌ Hermes 专用" || c == "❌ Hermes 专属" { migration = .exclusive(.hermes) }
                else if c.contains("❌") { migration = .exclusive(nil) }
            }

            // Description: second cell (index 1) in | Skill | 用途 | ... format
            // Skip the skill name (cells[0]) and find the longest non-keyword cell
            if cells.count >= 2 {
                let candidate = cells[1].trimmingCharacters(in: .whitespaces)
                if candidate.count > 2,
                   !candidate.contains("✅"), !candidate.contains("⚠️"), !candidate.contains("❌"),
                   !candidate.contains("可迁移"), !candidate.contains("需适配"),
                   candidate != "用途" {
                    description = candidate
                }
            }

            entries.append(AgentInventoryEntry(
                name: rawName,
                description: description,
                source: source,
                frequency: frequency,
                migration: migration
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
        // Skip emoji legend rows (⚠️ U+26A0, ✅ U+2705, ❌ U+274C, 📦 U+1F4E6)
        if name.unicodeScalars.contains(where: {
            $0.value == 0x26A0 || $0.value == 0x2705 || $0.value == 0x274C ||
            $0.value == 0x1F4E6 || $0.value == 0x1F534 || $0.value == 0x1F7E2
        }) { return false }
        // Skip Chinese punctuation (sentences/descriptions, not skill names)
        if name.unicodeScalars.contains(where: {
            ($0.value >= 0x3000 && $0.value <= 0x303F) || // CJK punctuation
            $0.value == 0xFF0C || // ，
            $0.value == 0x3002 || // 。
            $0.value == 0xFF1B || // ；
            $0.value == 0xFF1A    // ：
        }) { return false }
        if name.count < 2 { return false }
        return true
    }
}
