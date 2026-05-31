import Foundation

struct SkillDeployer {

    // MARK: - Deploy (Copy SKILL.md + references/)

    @discardableResult
    static func deploy(skill: Skill, to agent: Agent) throws -> Bool {
        guard skill.isLocal else { throw DeployError.notLocalSkill }

        let sourceDir = skill.filePath.deletingLastPathComponent()
        let targetDir = agent.skillsDirectory.appendingPathComponent(skill.id)

        // Ensure parent directory exists
        let parent = agent.skillsDirectory
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        // Remove existing copy if present
        if FileManager.default.fileExists(atPath: targetDir.path) {
            try FileManager.default.removeItem(at: targetDir)
        }

        // Copy the entire skill directory (SKILL.md + references/ + scripts/ etc.)
        do {
            try FileManager.default.copyItem(at: sourceDir, to: targetDir)
            return true
        } catch {
            throw DeployError.symlinkFailed(error.localizedDescription)
        }
    }

    @discardableResult
    static func undeploy(skillId: String, from agent: Agent) throws -> Bool {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skillId)
        guard FileManager.default.fileExists(atPath: targetDir.path) else { return true }

        // Remove copied directory (don't touch real directories that weren't deployed by us)
        // Check if it was deployed by us: look for a marker or just allow removal
        do {
            try FileManager.default.removeItem(at: targetDir)
            return true
        } catch {
            throw DeployError.undeployFailed(error.localizedDescription)
        }
    }

    static func isDeployed(skillId: String, agent: Agent) -> Bool {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skillId)
        let skillMd = targetDir.appendingPathComponent("SKILL.md")
        return FileManager.default.fileExists(atPath: skillMd.path)
    }

    // MARK: - Remote Deploy (SSH + SCP)

    static func deployRemote(skill: Skill, to agent: Agent, host: RemoteHost) throws {
        guard skill.isLocal else { throw DeployError.notLocalSkill }

        let sourceDir = skill.filePath.deletingLastPathComponent().path
        let targetDir = agent.skillsDirectory.appendingPathComponent(skill.id).path
        let parentDir = agent.skillsDirectory.path

        // SSH: mkdir -p parent && rm -rf target && cp -r source target
        let cmd = "mkdir -p \(shellQuote(parentDir)) && rm -rf \(shellQuote(targetDir)) && cp -r \(shellQuote(sourceDir)) \(shellQuote(targetDir))"
        let result = runSSH(host: host.id, command: cmd)
        if !result.success {
            throw DeployError.sshFailed(result.stderr)
        }
    }

    static func undeployRemote(skillId: String, from agent: Agent, host: RemoteHost) throws {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skillId).path
        let cmd = "rm -rf \(shellQuote(targetDir))"
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
