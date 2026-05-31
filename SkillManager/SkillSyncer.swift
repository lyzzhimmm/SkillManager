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
