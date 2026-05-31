import Foundation

struct SkillSyncer {

    enum SyncError: LocalizedError {
        case gitNotFound
        case cloneFailed(String)
        case pullFailed(String)
        case pushFailed(String)
        case commitFailed(String)

        var errorDescription: String? {
            switch self {
            case .gitNotFound:              return "未安装 Git"
            case .cloneFailed(let e):       return "克隆失败: \(e)"
            case .pullFailed(let e):        return "拉取失败: \(e)"
            case .pushFailed(let e):        return "推送失败: \(e)"
            case .commitFailed(let e):      return "提交失败: \(e)"
            }
        }
    }

    static let repoURL = "https://github.com/lyzzhimmm/skill-vault.git"

    static var localRepoPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".skill-vault").path
    }

    // MARK: - Status

    struct SyncStatus {
        let isCloned: Bool
        let lastCommit: String?
        let behind: Int
        let ahead: Int
        let skillCount: Int
    }

    static func status() -> SyncStatus {
        let repoDir = localRepoPath
        let gitDir = (repoDir as NSString).appendingPathComponent(".git")

        guard FileManager.default.fileExists(atPath: gitDir) else {
            return SyncStatus(isCloned: false, lastCommit: nil, behind: 0, ahead: 0, skillCount: 0)
        }

        let lastCommit = runGit(args: ["log", "-1", "--format=%h %s"], cwd: repoDir).stdout
        let behind = Int(runGit(args: ["rev-list", "--count", "HEAD..@{u}"], cwd: repoDir).stdout) ?? 0
        let ahead = Int(runGit(args: ["rev-list", "--count", "@{u}..HEAD"], cwd: repoDir).stdout) ?? 0

        let skillsDir = (repoDir as NSString).appendingPathComponent("skills")
        let count = (try? FileManager.default.contentsOfDirectory(atPath: skillsDir))?.count ?? 0

        return SyncStatus(
            isCloned: true,
            lastCommit: lastCommit.isEmpty ? nil : lastCommit,
            behind: behind,
            ahead: ahead,
            skillCount: count
        )
    }

    // MARK: - Clone

    @discardableResult
    static func clone() throws -> String {
        let parent = (localRepoPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: parent) {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }

        let result = runProcess("/usr/bin/git", args: ["clone", repoURL, localRepoPath])
        guard result.success else {
            throw SyncError.cloneFailed(result.stderr)
        }
        return "克隆成功"
    }

    // MARK: - Pull

    @discardableResult
    static func pull() throws -> String {
        guard FileManager.default.fileExists(atPath: (localRepoPath as NSString).appendingPathComponent(".git")) else {
            try clone()
            return "首次克隆完成"
        }

        let result = runGit(args: ["pull", "--rebase"], cwd: localRepoPath)
        guard result.success else {
            throw SyncError.pullFailed(result.stderr)
        }
        return result.stdout.isEmpty ? "已是最新" : result.stdout
    }

    // MARK: - Push (add + commit + push)

    @discardableResult
    static func push(message: String = "sync: 更新通用 Skill") throws -> String {
        // Stage all changes
        let addResult = runGit(args: ["add", "-A"], cwd: localRepoPath)
        guard addResult.success else {
            throw SyncError.commitFailed(addResult.stderr)
        }

        // Check if there's anything to commit
        let diffResult = runGit(args: ["diff", "--cached", "--quiet"], cwd: localRepoPath)
        if diffResult.success {
            return "没有需要推送的变更"
        }

        // Commit
        let commitResult = runGit(args: ["commit", "-m", message], cwd: localRepoPath)
        guard commitResult.success else {
            throw SyncError.commitFailed(commitResult.stderr)
        }

        // Push
        let pushResult = runGit(args: ["push"], cwd: localRepoPath)
        guard pushResult.success else {
            throw SyncError.pushFailed(pushResult.stderr)
        }
        return "推送成功"
    }

    // MARK: - List Remote Skills

    static func listVaultSkills() -> [String] {
        let skillsDir = (localRepoPath as NSString).appendingPathComponent("skills")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: skillsDir) else {
            return []
        }
        return contents.filter { name in
            let skillFile = (skillsDir as NSString).appendingPathComponent(name).appending("/SKILL.md")
            return FileManager.default.fileExists(atPath: skillFile)
        }.sorted()
    }

    // MARK: - Collect ALL Skills → Vault

    static func collectToVault(skills: [Skill]) -> Int {
        let vaultSkillsDir = (localRepoPath as NSString).appendingPathComponent("skills")

        // Ensure vault exists
        if !FileManager.default.fileExists(atPath: localRepoPath) {
            _ = try? clone()
        }
        if !FileManager.default.fileExists(atPath: vaultSkillsDir) {
            try? FileManager.default.createDirectory(atPath: vaultSkillsDir, withIntermediateDirectories: true)
        }

        var copied = 0
        var allNames = Set<String>()

        // Collect ALL local skills (universal + exclusive)
        for skill in skills {
            guard skill.isLocal else { continue }
            allNames.insert(skill.name)

            let sourceDir = skill.filePath.deletingLastPathComponent()
            let targetDir = URL(fileURLWithPath: vaultSkillsDir).appendingPathComponent(skill.name)

            // Remove old version if exists
            if FileManager.default.fileExists(atPath: targetDir.path) {
                try? FileManager.default.removeItem(at: targetDir)
            }

            do {
                try FileManager.default.copyItem(at: sourceDir, to: targetDir)
                copied += 1
            } catch {
                // Skip failed copies silently
            }
        }

        // Clean up vault entries that no longer exist locally
        if let existing = try? FileManager.default.contentsOfDirectory(atPath: vaultSkillsDir) {
            for name in existing {
                if !allNames.contains(name) {
                    try? FileManager.default.removeItem(
                        atPath: (vaultSkillsDir as NSString).appendingPathComponent(name)
                    )
                }
            }
        }

        // Auto-generate inventory from scan results
        generateInventory(skills: skills)

        return copied
    }

    // MARK: - Supplement Inventory Parser

    struct SupplementEntry {
        let frequency: Frequency
        let description: String
    }

    static func parseSupplement() -> [String: SupplementEntry] {
        let supplementPath = (localRepoPath as NSString).appendingPathComponent("inventory/supplement.md")
        guard let content = try? String(contentsOfFile: supplementPath, encoding: .utf8) else {
            return [:]
        }

        var result: [String: SupplementEntry] = [:]
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") || trimmed.hasPrefix("`") else { continue }
            if trimmed.contains("---") { continue }

            let cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 3 else { continue }

            let name = cells[0].replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "Skill" else { continue }

            var frequency: Frequency = .low
            if cells[1] == "高" { frequency = .high }
            else if cells[1] == "中" { frequency = .medium }

            let description = cells[2]

            result[name] = SupplementEntry(frequency: frequency, description: description)
        }
        return result
    }

    // MARK: - Auto-generate Complete Inventory from Scan Results

    static func generateInventory(skills: [Skill]) {
        // Load supplement for frequency/description
        let supplement = parseSupplement()
        let inventoryDir = (localRepoPath as NSString).appendingPathComponent("inventory")
        if !FileManager.default.fileExists(atPath: inventoryDir) {
            try? FileManager.default.createDirectory(atPath: inventoryDir, withIntermediateDirectories: true)
        }

        let outputPath = (inventoryDir as NSString).appendingPathComponent("Agent Skill 跨平台对比清单.md")

        // Classify skills by universal flag and exclusive status
        var universal: [Skill] = []
        var claudeOnly: [Skill] = []
        var codexOnly: [Skill] = []
        var hermesOnly: [Skill] = []

        for skill in skills {
            if skill.isUniversal {
                universal.append(skill)
            } else if case .exclusive(let agent) = skill.migration {
                switch agent {
                case .claude: claudeOnly.append(skill)
                case .codex: codexOnly.append(skill)
                case .hermes: hermesOnly.append(skill)
                default: universal.append(skill)
                }
            } else {
                // Not universal, not exclusive — classify by where it's installed
                if skill.deployedIn.contains(.claude) { claudeOnly.append(skill) }
                if skill.deployedIn.contains(.codex) { codexOnly.append(skill) }
                if skill.deployedIn.contains(.hermes) { hermesOnly.append(skill) }
            }
        }

        // Category display names
        let categoryNames: [Category: String] = [
            .planning: "规划 & 设计",
            .dev: "开发 & 构建",
            .quality: "代码质量 & 审查",
            .debug: "调试 & 测试",
            .project: "项目管理",
            .web: "网页 & 搜索",
            .content: "内容 & 文档",
            .arch: "架构 & 模式",
            .other: "其他",
        ]
        let categoryOrder: [Category] = [.planning, .quality, .debug, .project, .web, .content, .arch, .dev, .other]

        var md = "# Agent Skill 跨平台对比清单\n\n"
        md += "> 自动生成 — 从三个 Agent 目录扫描，按适配性分类\n\n"

        // Helper to render a skill table
        func renderTable(_ skills: [Skill], showAgents: Bool) {
            md += "| Skill | 来源 | 频次 |"
            if showAgents { md += " 适配 |" }
            md += " 用途 |\n"
            md += "|---|---|:---:|"
            if showAgents { md += "---|" }
            md += "---|\n"
            for skill in skills.sorted(by: { $0.name < $1.name }) {
                let freq = supplement[skill.name]?.frequency ?? skill.frequency
                let desc = supplement[skill.name]?.description ?? skill.description
                md += "| `\(skill.name)` | \(skill.source) | \(freq.rawValue) |"
                if showAgents {
                    let agents = skill.compatibleWith
                        .sorted(by: { $0.rawValue < $1.rawValue })
                        .map { $0.displayName }
                        .joined(separator: " / ")
                    md += " \(agents) |"
                }
                md += " \(desc) |\n"
            }
            md += "\n"
        }

        // Render by category for universal
        md += "## 一、通用 Skill\n\n"
        for cat in categoryOrder {
            let catSkills = universal.filter { $0.category == cat }
            if catSkills.isEmpty { continue }
            let name = categoryNames[cat] ?? cat.rawValue
            md += "### \(name)\n\n"
            renderTable(catSkills, showAgents: true)
        }

        // Agent exclusives
        if !codexOnly.isEmpty {
            md += "## 二、Codex 专属\n\n"
            for cat in categoryOrder {
                let catSkills = codexOnly.filter { $0.category == cat }
                if catSkills.isEmpty { continue }
                let name = categoryNames[cat] ?? cat.rawValue
                md += "### \(name)\n\n"
                renderTable(catSkills, showAgents: false)
            }
        }
        if !claudeOnly.isEmpty {
            md += "## 三、Claude 专属\n\n"
            for cat in categoryOrder {
                let catSkills = claudeOnly.filter { $0.category == cat }
                if catSkills.isEmpty { continue }
                let name = categoryNames[cat] ?? cat.rawValue
                md += "### \(name)\n\n"
                renderTable(catSkills, showAgents: false)
            }
        }
        if !hermesOnly.isEmpty {
            md += "## 四、Hermes 专属\n\n"
            for cat in categoryOrder {
                let catSkills = hermesOnly.filter { $0.category == cat }
                if catSkills.isEmpty { continue }
                let name = categoryNames[cat] ?? cat.rawValue
                md += "### \(name)\n\n"
                renderTable(catSkills, showAgents: false)
            }
        }

        // Summary
        md += "---\n\n"
        md += "| 分类 | 数量 |\n|---|---|\n"
        md += "| 通用 | \(universal.count) |\n"
        md += "| Codex 专属 | \(codexOnly.count) |\n"
        md += "| Claude 专属 | \(claudeOnly.count) |\n"
        md += "| Hermes 专属 | \(hermesOnly.count) |\n"
        md += "| **合计** | **\(universal.count + codexOnly.count + claudeOnly.count + hermesOnly.count)** |\n"

        try? md.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Install from Vault to Agent

    static func installFromVault(skillName: String, to agent: Agent) throws {
        let sourceFile = (localRepoPath as NSString)
            .appendingPathComponent("skills")
            .appending("/\(skillName)/SKILL.md")

        guard FileManager.default.fileExists(atPath: sourceFile) else {
            throw DeployError.notLocalSkill
        }

        let targetDir = agent.skillsDirectory.appendingPathComponent(skillName)
        let targetFile = targetDir.appendingPathComponent("SKILL.md")

        // Create target directory
        if !FileManager.default.fileExists(atPath: targetDir.path) {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        // Copy SKILL.md
        if FileManager.default.fileExists(atPath: targetFile.path) {
            try FileManager.default.removeItem(at: targetFile)
        }
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: sourceFile),
            to: targetFile
        )
    }

    // MARK: - Helpers

    @discardableResult
    private static func runGit(args: [String], cwd: String) -> (success: Bool, stdout: String, stderr: String) {
        runProcess("/usr/bin/git", args: args, cwd: cwd)
    }

    @discardableResult
    private static func runProcess(_ path: String, args: [String], cwd: String? = nil) -> (success: Bool, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, "", error.localizedDescription)
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return (
            process.terminationStatus == 0,
            stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
