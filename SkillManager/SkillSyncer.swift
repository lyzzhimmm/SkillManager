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

    // MARK: - Step 1: Collect (Agent dirs → Vault)

    static func collectToVault() -> Int {
        let vaultSkillsDir = (localRepoPath as NSString).appendingPathComponent("skills")

        // Ensure vault exists
        if !FileManager.default.fileExists(atPath: localRepoPath) {
            _ = try? clone()
        }
        if !FileManager.default.fileExists(atPath: vaultSkillsDir) {
            try? FileManager.default.createDirectory(atPath: vaultSkillsDir, withIntermediateDirectories: true)
        }

        var copied = 0
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Scan all agent directories
        let dirs: [(Set<Agent>, URL)] = [
            (Set(Agent.allCases), home.appendingPathComponent(".agents/skills")),
            ([.claude], home.appendingPathComponent(".claude/skills")),
            ([.codex], home.appendingPathComponent(".codex/skills")),
            (Set(Agent.allCases), home.appendingPathComponent(".hermes/skills")),
        ]

        for (agents, dir) in dirs {
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
                let targetDir = URL(fileURLWithPath: vaultSkillsDir).appendingPathComponent(name)

                // Remove old version
                if FileManager.default.fileExists(atPath: targetDir.path) {
                    try? FileManager.default.removeItem(at: targetDir)
                }

                do {
                    try FileManager.default.copyItem(at: item, to: targetDir)
                    copied += 1
                } catch {
                    // Skip failed copies
                }
            }
        }

        return copied
    }

    // MARK: - Step 2: Generate Inventory (Vault → Cross-platform inventory)

    static func generateInventory() {
        let vaultSkillsDir = (localRepoPath as NSString).appendingPathComponent("skills")
        let inventoryDir = (localRepoPath as NSString).appendingPathComponent("inventory")

        if !FileManager.default.fileExists(atPath: inventoryDir) {
            try? FileManager.default.createDirectory(atPath: inventoryDir, withIntermediateDirectories: true)
        }

        let outputPath = (inventoryDir as NSString).appendingPathComponent("Agent Skill 跨平台对比清单.md")

        // Read supplement for metadata
        let supplement = parseSupplement()

        // Scan vault to get all skills and their agents
        var allSkills: [String: (agents: Set<Agent>, skillMd: URL)] = [:]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: vaultSkillsDir),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let skillMd = item.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillMd.path) else { continue }

            let name = item.lastPathComponent
            // Check which agent directories have this skill
            var agents = Set<Agent>()
            for agent in Agent.allCases {
                let agentDir = agent.skillsDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: agentDir.path) {
                    agents.insert(agent)
                }
            }
            // Check shared dir
            let sharedDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".agents/skills/\(name)")
            if FileManager.default.fileExists(atPath: sharedDir.path) {
                agents = Set(Agent.allCases)
            }

            allSkills[name] = (agents, skillMd)
        }

        // Classify
        var universal: [(name: String, agents: Set<Agent>)] = []
        var claudeOnly: [String] = []
        var codexOnly: [String] = []
        var hermesOnly: [String] = []

        for (name, info) in allSkills {
            if info.agents == Set(Agent.allCases) {
                universal.append((name, info.agents))
            } else if info.agents == [.claude] {
                claudeOnly.append(name)
            } else if info.agents == [.codex] {
                codexOnly.append(name)
            } else if info.agents == [.hermes] {
                hermesOnly.append(name)
            } else {
                // Multiple but not all — classify by which ones
                universal.append((name, info.agents))
            }
        }

        // Generate markdown
        var md = "# Agent Skill 跨平台对比清单\n\n"
        md += "> 自动生成 — 从 Agent 目录扫描\n\n"

        // Universal
        md += "## 一、通用 Skill\n\n"
        md += "| Skill | 来源 | 当前所在 | 频次 | 用途 |\n"
        md += "|---|---|---|:---:|---|\n"
        for item in universal.sorted(by: { $0.name < $1.name }) {
            let sup = supplement[item.name]
            let agents = item.agents.sorted(by: { $0.rawValue < $1.rawValue })
                .map { $0.displayName }.joined(separator: " / ")
            let source = sup?.source ?? ""
            let freq = sup?.frequency ?? .low
            let desc = sup?.description ?? ""
            md += "| `\(item.name)` | \(source) | \(agents) | \(freq.rawValue) | \(desc) |\n"
        }

        // Codex exclusive
        if !codexOnly.isEmpty {
            md += "\n## 二、Codex 专属\n\n"
            md += "| Skill | 频次 | 用途 |\n"
            md += "|---|:---:|---|\n"
            for name in codexOnly.sorted() {
                let sup = supplement[name]
                let freq = sup?.frequency ?? .low
                let desc = sup?.description ?? ""
                md += "| `\(name)` | \(freq.rawValue) | \(desc) |\n"
            }
        }

        // Claude exclusive
        if !claudeOnly.isEmpty {
            md += "\n## 三、Claude 专属\n\n"
            md += "| Skill | 频次 | 用途 |\n"
            md += "|---|:---:|---|\n"
            for name in claudeOnly.sorted() {
                let sup = supplement[name]
                let freq = sup?.frequency ?? .low
                let desc = sup?.description ?? ""
                md += "| `\(name)` | \(freq.rawValue) | \(desc) |\n"
            }
        }

        // Hermes exclusive
        if !hermesOnly.isEmpty {
            md += "\n## 四、Hermes 专属\n\n"
            md += "| Skill | 频次 | 用途 |\n"
            md += "|---|:---:|---|\n"
            for name in hermesOnly.sorted() {
                let sup = supplement[name]
                let freq = sup?.frequency ?? .low
                let desc = sup?.description ?? ""
                md += "| `\(name)` | \(freq.rawValue) | \(desc) |\n"
            }
        }

        // Summary
        md += "\n---\n\n"
        md += "| 分类 | 数量 |\n|---|---|\n"
        md += "| 通用 | \(universal.count) |\n"
        md += "| Codex 专属 | \(codexOnly.count) |\n"
        md += "| Claude 专属 | \(claudeOnly.count) |\n"
        md += "| Hermes 专属 | \(hermesOnly.count) |\n"
        md += "| **合计** | **\(allSkills.count)** |\n"

        try? md.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Step 3: Match (Apply supplement metadata to skills)

    struct SupplementEntry {
        let category: String
        let frequency: Frequency
        let description: String
        let source: String
    }

    static func parseSupplement() -> [String: SupplementEntry] {
        let supplementPath = (localRepoPath as NSString).appendingPathComponent("inventory/supplement.md")
        guard let content = try? String(contentsOfFile: supplementPath, encoding: .utf8) else {
            return [:]
        }

        var result: [String: SupplementEntry] = [:]
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { continue }
            if trimmed.contains("---") { continue }

            let cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 4 else { continue }

            let name = cells[0].replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "Skill" else { continue }

            let category = cells[1]

            var frequency: Frequency = .low
            if cells[2] == "高" { frequency = .high }
            else if cells[2] == "中" { frequency = .medium }

            let description = cells[3]
            let source = cells.count >= 5 ? cells[4] : ""

            result[name] = SupplementEntry(
                category: category,
                frequency: frequency,
                description: description,
                source: source
            )
        }
        return result
    }

    // MARK: - Vault Status

    struct VaultStatus {
        let isCloned: Bool
        let skillCount: Int
        let lastCommit: String?
    }

    static func vaultStatus() -> VaultStatus {
        let gitDir = (localRepoPath as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir) else {
            return VaultStatus(isCloned: false, skillCount: 0, lastCommit: nil)
        }

        let skillsDir = (localRepoPath as NSString).appendingPathComponent("skills")
        let count = (try? FileManager.default.contentsOfDirectory(atPath: skillsDir))?.count ?? 0

        let lastCommit = runGit(args: ["log", "-1", "--format=%h %s"], cwd: localRepoPath).stdout

        return VaultStatus(
            isCloned: true,
            skillCount: count,
            lastCommit: lastCommit.isEmpty ? nil : lastCommit
        )
    }

    // MARK: - Git Operations

    @discardableResult
    static func clone() throws -> String {
        let parent = (localRepoPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: parent) {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }
        let result = runProcess("/usr/bin/git", args: ["clone", repoURL, localRepoPath])
        guard result.success else { throw SyncError.cloneFailed(result.stderr) }
        return "克隆成功"
    }

    @discardableResult
    static func pull() throws -> String {
        if !FileManager.default.fileExists(atPath: (localRepoPath as NSString).appendingPathComponent(".git")) {
            try clone()
            return "首次克隆完成"
        }
        let result = runGit(args: ["pull", "--rebase"], cwd: localRepoPath)
        guard result.success else { throw SyncError.pullFailed(result.stderr) }
        return result.stdout.isEmpty ? "已是最新" : result.stdout
    }

    @discardableResult
    static func push(message: String = "sync: 更新 Skill") throws -> String {
        let addResult = runGit(args: ["add", "-A"], cwd: localRepoPath)
        guard addResult.success else { throw SyncError.commitFailed(addResult.stderr) }

        let diffResult = runGit(args: ["diff", "--cached", "--quiet"], cwd: localRepoPath)
        if diffResult.success { return "没有需要推送的变更" }

        let commitResult = runGit(args: ["commit", "-m", message], cwd: localRepoPath)
        guard commitResult.success else { throw SyncError.commitFailed(commitResult.stderr) }

        let pushResult = runGit(args: ["push"], cwd: localRepoPath)
        guard pushResult.success else { throw SyncError.pushFailed(pushResult.stderr) }
        return "推送成功"
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
        if let cwd = cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

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
