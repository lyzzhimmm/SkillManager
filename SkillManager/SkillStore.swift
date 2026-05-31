import Foundation
import SwiftUI

class SkillStore: ObservableObject {
    @Published var skills: [Skill] = []
    @Published var lastError: String?
    @Published var syncStatus: SkillSyncer.SyncStatus?
    @Published var isSyncing = false

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

    // MARK: - Load

    func load(inventoryPath: String? = nil) {
        skills = SkillScanner.scanAll(inventoryPath: inventoryPath)
        refreshSyncStatus()
    }

    // MARK: - Sync

    func refreshSyncStatus() {
        syncStatus = SkillSyncer.status()
    }

    func syncPull() {
        isSyncing = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try SkillSyncer.pull()
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.refreshSyncStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isSyncing = false
                }
            }
        }
    }

    func syncPush() {
        isSyncing = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try SkillSyncer.push()
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.refreshSyncStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isSyncing = false
                }
            }
        }
    }

    func collectAndPush() {
        isSyncing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let copied = SkillSyncer.collectToVault(skills: self.skills)
            do {
                _ = try SkillSyncer.push(message: "sync: 收集 \(copied) 个通用 Skill")
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.refreshSyncStatus()
                    self.lastError = copied > 0 ? nil : "没有新 Skill 需要推送"
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isSyncing = false
                }
            }
        }
    }

    func collect() {
        isSyncing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let copied = SkillSyncer.collectToVault(skills: self.skills)
            // Re-load skills from updated inventory
            DispatchQueue.main.async {
                self.load()
                self.isSyncing = false
                self.lastError = copied > 0 ? "已收集 \(copied) 个 Skill" : "没有新 Skill 需要收集"
            }
        }
    }

    func pushOnly() {
        isSyncing = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try SkillSyncer.push()
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.refreshSyncStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isSyncing = false
                }
            }
        }
    }

    func installFromVault(skillName: String, to agent: Agent) {
        do {
            try SkillSyncer.installFromVault(skillName: skillName, to: agent)
            load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Deploy

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
