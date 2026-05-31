import Foundation

struct SkillDeployer {

    // MARK: - Local Deploy (Symlink)

    @discardableResult
    static func deploy(skill: Skill, to agent: Agent) throws -> Bool {
        guard skill.isLocal else { throw DeployError.notLocalSkill }

        let targetDir = agent.skillsDirectory.appendingPathComponent(skill.id)
        let sourceDir = skill.filePath.deletingLastPathComponent()

        // Already deployed to correct location?
        if FileManager.default.fileExists(atPath: targetDir.path) {
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: targetDir.path),
               existing == sourceDir.path {
                return true  // already there
            }
            try FileManager.default.removeItem(at: targetDir)
        }

        // Ensure parent directory exists
        let parent = agent.skillsDirectory
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        do {
            try FileManager.default.createSymbolicLink(at: targetDir, withDestinationURL: sourceDir)
            return true
        } catch {
            throw DeployError.symlinkFailed(error.localizedDescription)
        }
    }

    @discardableResult
    static func undeploy(skillId: String, from agent: Agent) throws -> Bool {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skillId)
        guard FileManager.default.fileExists(atPath: targetDir.path) else { return true }

        guard (try? FileManager.default.attributesOfItem(atPath: targetDir.path)[.type] as? FileAttributeType) == .typeSymbolicLink else {
            return false  // Don't remove real directories
        }

        do {
            try FileManager.default.removeItem(at: targetDir)
            return true
        } catch {
            throw DeployError.undeployFailed(error.localizedDescription)
        }
    }

    static func isSymlink(skillId: String, agent: Agent) -> Bool {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skillId)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: targetDir.path) else {
            return false
        }
        return attrs[.type] as? FileAttributeType == .typeSymbolicLink
    }

    // MARK: - Remote Deploy (SSH)

    static func deployRemote(skill: Skill, to agent: Agent, host: RemoteHost) throws {
        guard skill.isLocal else { throw DeployError.notLocalSkill }

        let sourceDir = skill.filePath.deletingLastPathComponent().path
        let targetDir = agent.skillsDirectory.appendingPathComponent(skill.id).path
        let parentDir = agent.skillsDirectory.path

        // SSH: mkdir -p parent && ln -sfn source target
        let cmd = "mkdir -p \(shellQuote(parentDir)) && ln -sfn \(shellQuote(sourceDir)) \(shellQuote(targetDir))"
        let result = runSSH(host: host.id, command: cmd)
        if !result.success {
            throw DeployError.sshFailed(result.stderr)
        }
    }

    static func undeployRemote(skillId: String, from agent: Agent, host: RemoteHost) throws {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skillId).path

        // SSH: remove only if symlink
        let cmd = "if [ -L \(shellQuote(targetDir)) ]; then rm \(shellQuote(targetDir)); fi"
        let result = runSSH(host: host.id, command: cmd)
        if !result.success {
            throw DeployError.sshFailed(result.stderr)
        }
    }

    // MARK: - SSH Helpers

    struct SSHResult {
        let success: Bool
        let stdout: String
        let stderr: String
    }

    private static func runSSH(host: String, command: String) -> SSHResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [host, command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return SSHResult(success: false, stdout: "", stderr: error.localizedDescription)
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return SSHResult(
            success: process.terminationStatus == 0,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
