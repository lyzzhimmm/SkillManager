import Foundation
import SwiftUI

class SkillStore: ObservableObject {
    @Published var skills: [Skill] = []
    @Published var lastError: String?
    @Published var vaultStatus: SkillSyncer.VaultStatus?
    @Published var isProcessing = false

    // Installed counts (from local agent directories)
    var installedCounts: [Agent: Int] {
        var counts: [Agent: Int] = [:]
        for skill in skills {
            for agent in skill.deployedIn {
                counts[agent, default: 0] += 1
            }
        }
        return counts
    }

    var categoryCounts: [Category: Int] {
        var counts: [Category: Int] = [:]
        for skill in skills {
            counts[skill.category, default: 0] += 1
        }
        return counts
    }

    func countForAgent(_ agent: Agent) -> Int {
        installedCounts[agent] ?? 0
    }

    // MARK: - Load

    func load() {
        skills = SkillScanner.scanAll()
        refreshVaultStatus()
    }

    func refreshVaultStatus() {
        vaultStatus = SkillSyncer.vaultStatus()
    }

    // MARK: - Step 1: Collect

    func collect() {
        isProcessing = true
        lastError = "收集中..."
        DispatchQueue.global(qos: .userInitiated).async {
            let copied = SkillSyncer.collectToVault()
            DispatchQueue.main.async {
                self.isProcessing = false
                self.refreshVaultStatus()
                self.lastError = copied > 0 ? "已收集 \(copied) 个 Skill 到仓库" : "没有新 Skill 需要收集"
            }
        }
    }

    // MARK: - Step 2: Generate Inventory

    func generate() {
        isProcessing = true
        lastError = "生成清单中..."
        DispatchQueue.global(qos: .userInitiated).async {
            SkillSyncer.generateInventory()
            DispatchQueue.main.async {
                self.isProcessing = false
                self.lastError = "清单已生成"
            }
        }
    }

    // MARK: - Step 3: Match

    func match() {
        isProcessing = true
        lastError = "匹配中..."
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.load()
                self.isProcessing = false
                self.lastError = "匹配完成，已刷新列表"
            }
        }
    }

    // MARK: - Pull

    func pull() {
        isProcessing = true
        lastError = "拉取中..."
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try SkillSyncer.pull()
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.load()
                    self.lastError = "拉取成功"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Push

    func push() {
        isProcessing = true
        lastError = "推送中..."
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try SkillSyncer.push()
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.refreshVaultStatus()
                    self.lastError = "推送成功"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                }
            }
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
