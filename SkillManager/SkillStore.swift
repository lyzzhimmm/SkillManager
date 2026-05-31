import Foundation
import SwiftUI

class SkillStore: ObservableObject {
    @Published var skills: [Skill] = []
    @Published var lastError: String?

    var categoryCounts: [Category: Int] {
        var counts: [Category: Int] = [:]
        for skill in skills {
            counts[skill.category, default: 0] += 1
        }
        return counts
    }

    func countForAgent(_ agent: Agent) -> Int {
        skills.filter { $0.deployedIn.contains(agent) }.count
    }

    func load(inventoryPath: String? = nil) {
        skills = SkillScanner.scanAll(inventoryPath: inventoryPath)
    }

    func toggleDeploy(skillId: String, agent: Agent) {
        guard let index = skills.firstIndex(where: { $0.id == skillId }) else { return }

        if skills[index].deployedIn.contains(agent) {
            do {
                try SkillDeployer.undeploy(skillId: skillId, from: agent)
                skills[index].deployedIn.remove(agent)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        } else {
            do {
                try SkillDeployer.deploy(skill: skills[index], to: agent)
                skills[index].deployedIn.insert(agent)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func batchDeploy(skillIds: Set<String>, to agent: Agent) {
        var failed = 0
        for id in skillIds {
            guard let index = skills.firstIndex(where: { $0.id == id }) else { continue }
            if !skills[index].deployedIn.contains(agent) {
                do {
                    try SkillDeployer.deploy(skill: skills[index], to: agent)
                    skills[index].deployedIn.insert(agent)
                } catch {
                    failed += 1
                    lastError = error.localizedDescription
                }
            }
        }
        if failed > 0 {
            lastError = "\(failed) 个 Skill 部署失败"
        }
    }
}
