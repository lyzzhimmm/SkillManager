import Foundation

struct SkillScanner {

    static func scanAll(inventoryPath: String? = nil) -> [Skill] {
        // 1. Parse cross-platform inventory for metadata
        let crossPlatform = InventoryParser.parse(at: inventoryPath)

        // 2. Parse per-agent inventories for full skill lists
        let claudeInventory = InventoryParser.parseAgentInventory(agent: .claude)
        let codexInventory = InventoryParser.parseAgentInventory(agent: .codex)
        let hermesInventory = InventoryParser.parseAgentInventory(agent: .hermes)

        // 3. Scan local directories
        var localSkills: [String: (dirs: [URL], agents: Set<Agent>)] = [:]

        // Scan ~/.agents/skills/ (shared — deployed to ALL agents)
        let sharedDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills")
        scanDirectory(sharedDir, into: &localSkills, agents: Set(Agent.allCases))

        // Scan each agent's main skills directory
        for agent in Agent.allCases {
            scanDirectory(agent.skillsDirectory, into: &localSkills, agents: [agent])
        }

        // 4. Merge: start with local skills
        var skillMap: [String: Skill] = [:]

        for (name, info) in localSkills {
            if let skill = parseLocalSkill(name: name, dirs: info.dirs, agents: info.agents, crossPlatform: crossPlatform) {
                skillMap[name] = skill
            }
        }

        // 5. Add inventory-only skills (not found locally)
        let agentInventories: [(Agent, [InventoryParser.AgentInventoryEntry])] = [
            (.claude, claudeInventory),
            (.codex, codexInventory),
            (.hermes, hermesInventory),
        ]

        for (agent, entries) in agentInventories {
            for entry in entries {
                if skillMap[entry.name] != nil { continue }

                let cp = crossPlatform[entry.name]

                skillMap[entry.name] = Skill(
                    id: entry.name,
                    name: entry.name,
                    description: cp?.description ?? entry.description,
                    category: Category.classify(name: entry.name, description: cp?.description ?? entry.description),
                    filePath: URL(fileURLWithPath: "/dev/null"),
                    hasReferences: false,
                    frequency: cp?.frequency ?? entry.frequency,
                    source: cp?.source ?? entry.source,
                    isUniversal: cp?.isUniversal ?? false,
                    migration: cp?.migration ?? entry.migration,
                    originAgent: agent,
                    deployedIn: [agent],
                    isLocal: false
                )
            }
        }

        // 6. Only keep portable and needsAdaptation — drop exclusive
        let filtered = skillMap.values.filter { skill -> Bool in
            if case .exclusive = skill.migration { return false }
            return true
        }

        // 7. Sort: frequency high→medium→low, then alphabetically
        return filtered.sorted { a, b in
            if a.frequency != b.frequency { return a.frequency < b.frequency }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func parseLocalSkill(
        name: String,
        dirs: [URL],
        agents: Set<Agent>,
        crossPlatform: [String: InventoryParser.SkillMeta]
    ) -> Skill? {
        let skillMd = dirs[0].appendingPathComponent("SKILL.md")
        guard let content = try? String(contentsOf: skillMd, encoding: .utf8) else { return nil }

        var parsedName = name
        var parsedDesc = ""

        // Parse YAML frontmatter
        if let start = content.range(of: "---\n"),
           let end = content.range(of: "\n---", range: start.upperBound..<content.endIndex) {
            let frontmatter = String(content[start.upperBound..<end.lowerBound])
            var inDescription = false
            var descLines: [String] = []
            for line in frontmatter.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("name:") {
                    parsedName = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    inDescription = false
                } else if trimmed.hasPrefix("description:") {
                    let value = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty {
                        parsedDesc = value
                        inDescription = false
                    } else {
                        inDescription = true
                    }
                } else if inDescription && !trimmed.isEmpty && (trimmed.hasPrefix(" ") || trimmed.hasPrefix("\t")) {
                    descLines.append(String(trimmed).trimmingCharacters(in: .whitespaces))
                } else {
                    inDescription = false
                }
            }
            if !descLines.isEmpty {
                parsedDesc = descLines.joined(separator: " ")
            }
        }

        // Fallback description
        if parsedDesc.isEmpty {
            let lines = content.components(separatedBy: "\n")
            var passedFirstSeparator = false
            var passedSecondSeparator = false
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "---" {
                    if !passedFirstSeparator { passedFirstSeparator = true }
                    else if !passedSecondSeparator { passedSecondSeparator = true }
                    continue
                }
                if passedSecondSeparator && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    parsedDesc = trimmed
                    break
                }
            }
        }

        let hasRefs = FileManager.default.fileExists(
            atPath: dirs[0].appendingPathComponent("references").path
        )

        let meta = crossPlatform[parsedName] ?? crossPlatform[name]

        let category = Category.classify(name: parsedName, description: parsedDesc)
        let frequency = meta?.frequency ?? .low
        let source = meta?.source ?? ""
        let isUniversal = meta?.isUniversal ?? false
        let migration = meta?.migration ?? .portable

        let inventoryDesc = meta?.description.trimmingCharacters(in: .whitespaces) ?? ""
        let finalDesc = inventoryDesc.isEmpty ? parsedDesc : inventoryDesc

        return Skill(
            id: name,
            name: parsedName,
            description: finalDesc,
            category: category,
            filePath: skillMd,
            hasReferences: hasRefs,
            frequency: frequency,
            source: source,
            isUniversal: isUniversal,
            migration: migration,
            originAgent: agents.first,
            deployedIn: agents,
            isLocal: true
        )
    }

    private static func scanDirectory(
        _ dir: URL,
        into localSkills: inout [String: (dirs: [URL], agents: Set<Agent>)],
        agents: Set<Agent>
    ) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let skillMd = item.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillMd.path) else { continue }

            let name = item.lastPathComponent
            if localSkills[name] != nil {
                localSkills[name]!.dirs.append(item)
                localSkills[name]!.agents.formUnion(agents)
            } else {
                localSkills[name] = ([item], agents)
            }
        }
    }
}
