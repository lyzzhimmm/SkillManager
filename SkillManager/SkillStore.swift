import Foundation
import SwiftUI

class SkillStore: ObservableObject {
    @Published var skills: [Skill] = []

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
            SkillDeployer.undeploy(skillId: skillId, from: agent)
            skills[index].deployedIn.remove(agent)
        } else {
            SkillDeployer.deploy(skill: skills[index], to: agent)
            skills[index].deployedIn.insert(agent)
        }
    }

    func batchDeploy(skillIds: Set<String>, to agent: Agent) {
        for id in skillIds {
            guard let index = skills.firstIndex(where: { $0.id == id }) else { continue }
            if !skills[index].deployedIn.contains(agent) {
                SkillDeployer.deploy(skill: skills[index], to: agent)
                skills[index].deployedIn.insert(agent)
            }
        }
    }
}
