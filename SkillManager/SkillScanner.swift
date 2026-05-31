import Foundation

struct SkillScanner {

    static func scanAll() -> [Skill] {
        // 1. Read generated inventory (source of truth for skill list)
        let inventoryPath = SkillSyncer.localRepoPath + "/inventory/Agent Skill 跨平台对比清单.md"
        let inventorySkills = parseInventory(at: inventoryPath)

        // 2. Scan local agent directories for installed status
        let installedIn = scanInstalled()

        // 3. Read supplement for extra metadata
        let supplement = SkillSyncer.parseSupplement()

        // 4. Merge: inventory skills + installed status + supplement metadata
        var result: [Skill] = []
        for inv in inventorySkills {
            let sup = supplement[inv.name]
            let installed = installedIn[inv.name] ?? []

            let skill = Skill(
                id: inv.name,
                name: inv.name,
                description: sup?.description ?? inv.description,
                category: Category.classify(name: inv.name, description: sup?.description ?? inv.description, supplementCategory: sup?.category ?? ""),
                filePath: URL(fileURLWithPath: "/dev/null"),
                hasReferences: false,
                frequency: sup?.frequency ?? inv.frequency,
                source: sup?.source ?? inv.source,
                isUniversal: inv.isUniversal,
                migration: inv.migration,
                originAgent: nil,
                deployedIn: installed,
                isLocal: !installed.isEmpty,
                compatibleWith: inv.compatibleWith
            )
            result.append(skill)
        }

        return result
    }

    // MARK: - Parse Generated Inventory

    struct InventorySkill {
        let name: String
        let isUniversal: Bool
        let compatibleWith: Set<Agent>
        let frequency: Frequency
        let source: String
        let description: String
        let migration: MigrationStatus
    }

    static func parseInventory(at path: String) -> [InventorySkill] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        var result: [InventorySkill] = []
        var inUniversalSection = false
        var inCodexSection = false
        var inClaudeSection = false
        var inHermesSection = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect sections
            if trimmed.contains("一、通用") { inUniversalSection = true; inCodexSection = false; inClaudeSection = false; inHermesSection = false; continue }
            if trimmed.contains("二、Codex") { inUniversalSection = false; inCodexSection = true; inClaudeSection = false; inHermesSection = false; continue }
            if trimmed.contains("三、Claude") { inUniversalSection = false; inCodexSection = false; inClaudeSection = true; inHermesSection = false; continue }
            if trimmed.contains("四、Hermes") { inUniversalSection = false; inCodexSection = false; inClaudeSection = false; inHermesSection = true; continue }

            // Skip non-table lines
            guard trimmed.hasPrefix("|") else { continue }
            if trimmed.contains("---") { continue }
            if trimmed.contains("Skill") && trimmed.contains("来源") { continue } // header row
            if trimmed.contains("Skill") && trimmed.contains("频次") { continue } // header row
            if trimmed.contains("分类") && trimmed.contains("数量") { continue } // summary table

            let cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 2 else { continue }

            let name = cells[0].replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "Skill", name.count < 80 else { continue }

            // Parse compatible agents from "当前所在" column (for universal skills)
            var compatibleWith: Set<Agent> = []
            if inUniversalSection && cells.count >= 3 {
                let location = cells[2]
                if location.contains("Claude") { compatibleWith.insert(.claude) }
                if location.contains("Codex") { compatibleWith.insert(.codex) }
                if location.contains("Hermes") { compatibleWith.insert(.hermes) }
                if compatibleWith.isEmpty { compatibleWith = Set(Agent.allCases) }
            } else if inCodexSection {
                compatibleWith = [.codex]
            } else if inClaudeSection {
                compatibleWith = [.claude]
            } else if inHermesSection {
                compatibleWith = [.hermes]
            }

            // Parse frequency
            var frequency: Frequency = .low
            for c in cells {
                if c == "高" { frequency = .high }
                else if c == "中" { frequency = .medium }
            }

            // Parse source (for universal skills)
            var source = ""
            if inUniversalSection && cells.count >= 2 {
                source = cells[1]
            }

            // Parse description (last meaningful cell)
            var description = ""
            for c in cells.reversed() {
                if c.count > 2 && c != "高" && c != "中" && c != "低" && !c.contains("✅") && !c.contains("❌") {
                    description = c
                    break
                }
            }

            // Migration status
            let migration: MigrationStatus
            if inUniversalSection { migration = .portable }
            else if inCodexSection { migration = .exclusive(.codex) }
            else if inClaudeSection { migration = .exclusive(.claude) }
            else if inHermesSection { migration = .exclusive(.hermes) }
            else { migration = .portable }

            result.append(InventorySkill(
                name: name,
                isUniversal: inUniversalSection,
                compatibleWith: compatibleWith,
                frequency: frequency,
                source: source,
                description: description,
                migration: migration
            ))
        }

        return result
    }

    // MARK: - Scan Installed Skills

    static func scanInstalled() -> [String: Set<Agent>] {
        var result: [String: Set<Agent>] = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser

        let dirs: [(Agent, URL)] = [
            (.claude, home.appendingPathComponent(".claude/skills")),
            (.codex, home.appendingPathComponent(".codex/skills")),
            (.hermes, home.appendingPathComponent(".hermes/skills")),
        ]

        for (agent, dir) in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                let skillMd = item.appendingPathComponent("SKILL.md")
                guard FileManager.default.fileExists(atPath: skillMd.path) else { continue }

                let name = item.lastPathComponent
                result[name, default: Set<Agent>()].insert(agent)
            }
        }

        return result
    }
}
