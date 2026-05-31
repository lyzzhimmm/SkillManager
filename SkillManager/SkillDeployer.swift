import Foundation

struct SkillDeployer {

    /// Deploy a skill to an agent (create symlink)
    @discardableResult
    static func deploy(skill: Skill, to agent: Agent) -> Bool {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skill.id)
        let sourceDir = skill.filePath.deletingLastPathComponent()

        // Already deployed?
        if FileManager.default.fileExists(atPath: targetDir.path) {
            // Check if it's already a symlink pointing to the right place
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: targetDir.path),
               existing == sourceDir.path {
                return true
            }
            // Remove existing (symlink or real dir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        // Ensure parent directory exists
        let parent = agent.skillsDirectory
        if !FileManager.default.fileExists(atPath: parent.path) {
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        // Create symlink
        do {
            try FileManager.default.createSymbolicLink(at: targetDir, withDestinationURL: sourceDir)
            return true
        } catch {
            print("Deploy failed: \(error)")
            return false
        }
    }

    /// Undeploy a skill from an agent (remove symlink)
    @discardableResult
    static func undeploy(skillId: String, from agent: Agent) -> Bool {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skillId)
        guard FileManager.default.fileExists(atPath: targetDir.path) else { return true }

        // Only remove if it's a symlink
        if (try? FileManager.default.attributesOfItem(atPath: targetDir.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
            do {
                try FileManager.default.removeItem(at: targetDir)
                return true
            } catch {
                print("Undeploy failed: \(error)")
                return false
            }
        }
        return false // Don't remove real directories
    }

    /// Check if a skill directory is a symlink
    static func isSymlink(skillId: String, agent: Agent) -> Bool {
        let targetDir = agent.skillsDirectory.appendingPathComponent(skillId)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: targetDir.path) else {
            return false
        }
        return attrs[.type] as? FileAttributeType == .typeSymbolicLink
    }
}
