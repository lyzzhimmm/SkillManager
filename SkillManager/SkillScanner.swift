import Foundation

struct SkillScanner {

    static func scanAll(inventoryPath: String? = nil) -> [Skill] {
        // 1. Parse supplement for frequency/description (metadata only, not universal classification)
        let supplement = SkillSyncer.parseSupplement()

        // 2. Scan local directories — track which agents each skill is in
        var localSkills: [String: (dirs: [URL], agents: Set<Agent>)] = [:]

        // ~/.agents/skills/ → shared, deployed to ALL agents
        let sharedDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills")
        scanDirectory(sharedDir, into: &localSkills, agents: Set(Agent.allCases))

        // Each agent's main directory
        for agent in Agent.allCases {
            scanDirectory(agent.skillsDirectory, into: &localSkills, agents: [agent])
        }

        // ~/.skill-vault/skills/ → universal source
        let vaultDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".skill-vault/skills")
        scanDirectory(vaultDir, into: &localSkills, agents: Set(Agent.allCases))

        // 3. Merge and classify
        var skillMap: [String: Skill] = [:]

        for (name, info) in localSkills {
            guard let skill = parseLocalSkill(name: name, dirs: info.dirs, agents: info.agents, supplement: supplement) else {
                continue
            }

            let key = skill.name
            if var existing = skillMap[key] {
                // Merge: combine deployedIn
                existing.deployedIn.formUnion(skill.deployedIn)
                existing.compatibleWith.formUnion(skill.compatibleWith)
                skillMap[key] = existing
            } else {
                skillMap[key] = skill
            }
        }

        // 4. Classify universal AFTER merge
        //    universal = in all 3 agents OR in shared/vault directory
        for (key, skill) in skillMap {
            var updated = skill
            let inAllAgents = updated.deployedIn == Set(Agent.allCases)
            let inSharedOrVault = updated.deployedIn.contains(.claude) &&
                                  updated.deployedIn.contains(.codex) &&
                                  updated.deployedIn.contains(.hermes)

            if inAllAgents || inSharedOrVault {
                updated.isUniversal = true
                updated.compatibleWith = Set(Agent.allCases)
            }
            skillMap[key] = updated
        }

        // 5. Sort: frequency high→medium→low, then alphabetically
        return skillMap.values.sorted { a, b in
            if a.frequency != b.frequency { return a.frequency < b.frequency }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func parseLocalSkill(
        name: String,
        dirs: [URL],
        agents: Set<Agent>,
        supplement: [String: SkillSyncer.SupplementEntry] = [:]
    ) -> Skill? {
        let skillMd = dirs[0].appendingPathComponent("SKILL.md")
        guard let content = try? String(contentsOf: skillMd, encoding: .utf8) else { return nil }

        var parsedName = name
        var parsedDesc = ""
        var parsedTags: [String] = []

        // Parse YAML frontmatter
        if let start = content.range(of: "---\n"),
           let end = content.range(of: "\n---", range: start.upperBound..<content.endIndex) {
            let frontmatter = String(content[start.upperBound..<end.lowerBound])
            var inDescription = false
            var descLines: [String] = []
            var inTags = false
            for line in frontmatter.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("name:") {
                    parsedName = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    inDescription = false
                    inTags = false
                } else if trimmed.hasPrefix("description:") {
                    let value = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty {
                        parsedDesc = value
                        inDescription = false
                    } else {
                        inDescription = true
                    }
                    inTags = false
                } else if trimmed.hasPrefix("tags:") {
                    inDescription = false
                    inTags = true
                    let value = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix("[") {
                        let tagsStr = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                        parsedTags = tagsStr.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty && !$0.hasPrefix("<") }
                    }
                } else if inDescription && !trimmed.isEmpty && (trimmed.hasPrefix(" ") || trimmed.hasPrefix("\t")) {
                    descLines.append(String(trimmed).trimmingCharacters(in: .whitespaces))
                } else if inTags && trimmed.hasPrefix("- ") {
                    let tag = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !tag.isEmpty && !tag.hasPrefix("<") {
                        parsedTags.append(tag)
                    }
                } else {
                    inDescription = false
                    inTags = false
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

        // Metadata from supplement only (not from inventory for classification)
        let sup = supplement[parsedName] ?? supplement[name]
        let category = Category.classify(name: parsedName, description: parsedDesc, tags: parsedTags, supplementCategory: sup?.category ?? "")
        let frequency = sup?.frequency ?? .low
        let source = sup?.source ?? ""
        let description = sup?.description ?? parsedDesc

        // compatibleWith = which agents this skill is actually installed in
        let compatibleWith = agents

        return Skill(
            id: name,
            name: parsedName,
            description: description,
            category: category,
            filePath: skillMd,
            hasReferences: hasRefs,
            frequency: frequency,
            source: source,
            isUniversal: false,  // Will be set after merge
            migration: .portable,
            originAgent: agents.first,
            deployedIn: agents,
            isLocal: true,
            compatibleWith: compatibleWith
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
