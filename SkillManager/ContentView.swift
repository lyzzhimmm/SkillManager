import SwiftUI

struct ContentView: View {
    @StateObject private var store = SkillStore()
    @State private var filter = FilterState()
    @State private var selectedSkillIds: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\Skill.name)]
    @State private var showDeployConfirm = false
    @State private var pendingDeployAgent: Agent?
    @State private var inventoryPath: String = {
        let vaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".skill-vault/inventory/Agents Skill 跨平台对比清单.md").path
        if FileManager.default.fileExists(atPath: vaultPath) {
            return vaultPath
        }
        return UserDefaults.standard.string(forKey: "inventoryPath")
            ?? "/Volumes/PJSSD/通用skill及指南/Skill 清单/Agents Skill 跨平台对比清单.md"
    }()
    @State private var showToast = false
    @State private var toastMessage = ""
    @Environment(\.colorScheme) private var scheme
    private var isDark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                filter: $filter,
                skillCounts: store.categoryCounts,
                totalCount: store.skills.count,
                onReload: { store.load() },
                vaultStatus: store.vaultStatus,
                isProcessing: store.isProcessing,
                onPull: { store.pull() },
                onCleanPull: { store.cleanPull() },
                onPush: { store.push() },
                onCollect: { store.collect() },
                onGenerate: { store.generate() },
                onMatch: { store.match() }
            )

            mainContent
        }
        .frame(minWidth: 1100, minHeight: 600)
        .onAppear { store.load() }
        .onChange(of: store.lastError) { _, newError in
            if let err = newError {
                toast(err)
                store.lastError = nil
            }
        }
        .alert("确认部署", isPresented: $showDeployConfirm) {
            Button("取消", role: .cancel) {}
            Button("部署") {
                if let agent = pendingDeployAgent {
                    executeBatchDeploy(agent: agent)
                }
            }
        } message: {
            if let agent = pendingDeployAgent {
                let info = batchDeployInfo(agent: agent)
                Text(info.message)
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Search bar using native NSSearchField
            HStack(spacing: 8) {
                SearchField(text: $filter.searchText, placeholder: "搜索 Skill...")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if filteredSkills.isEmpty && !store.skills.isEmpty {
                emptyStateView
            } else {
                skillTable
            }

            if !selectedSkillIds.isEmpty {
                DeployBarView(
                    selectedSkills: store.skills.filter { selectedSkillIds.contains($0.id) },
                    onDeploy: { agent in
                        pendingDeployAgent = agent
                        showDeployConfirm = true
                    },
                    isDark: isDark
                )
            }

            StatusView(
                totalCount: store.skills.count,
                universalCount: store.skills.filter { $0.isUniversal }.count,
                claudeCount: store.countForAgent(.claude),
                codexCount: store.countForAgent(.codex),
                hermesCount: store.countForAgent(.hermes),
                isDark: isDark
            )
        }
        .background(isDark ? Color(hex: 0x1C1C1E) : Color(hex: 0xF6F6F6))
        .toast(isShowing: $showToast, message: toastMessage)
    }

    // MARK: - Table

    private var skillTable: some View {
        Table(filteredSkills, selection: $selectedSkillIds, sortOrder: $sortOrder) {
            TableColumn("Skill (\(filteredSkills.count))", value: \.name) { skill in
                HStack(spacing: 4) {
                    Text(skill.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    migrationBadge(skill.migration)
                }
            }
            .width(min: 180, ideal: 220, max: 400)

            TableColumn("描述") { skill in
                Text(skill.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("Agent") { skill in
                HStack(spacing: 4) {
                    ForEach(Agent.allCases) { agent in
                        AgentBadge(
                            agent: agent,
                            isDeployed: skill.deployedIn.contains(agent)
                        )
                    }
                }
            }
            .width(min: 72, ideal: 72, max: 80)

            TableColumn("频次", value: \.frequency) { skill in
                FrequencyBadge(frequency: skill.frequency)
            }
            .width(min: 40, ideal: 40, max: 50)

            TableColumn("来源", value: \.source) { skill in
                Text(skill.source)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 70, max: 100)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let firstId = ids.first, let skill = store.skills.first(where: { $0.id == firstId }) {
                ForEach(Agent.allCases) { agent in
                    if skill.deployedIn.contains(agent) {
                        Button("取消部署到 \(agent.displayName)") {
                            store.toggleDeploy(skillId: skill.id, agent: agent)
                        }
                    } else {
                        Button("部署到 \(agent.displayName)") {
                            handleAgentToggle(skill: skill, agent: agent)
                        }
                    }
                }
            }
        }
        .onChange(of: sortOrder) { _, newValue in store.skills.sort(using: newValue) }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(isDark ? Color(hex: 0x48484A) : Color(hex: 0xC7C7CC))
            Text("没有匹配的 Skill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isDark ? Color(hex: 0xA1A1A6) : Color(hex: 0x6E6E73))
            Text("尝试调整筛选条件或搜索关键词")
                .font(.system(size: 12))
                .foregroundColor(isDark ? Color(hex: 0x6E6E73) : Color(hex: 0xAEAEB2))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Migration Badge

    @ViewBuilder
    private func migrationBadge(_ migration: MigrationStatus) -> some View {
        switch migration {
        case .portable:
            EmptyView()
        case .needsAdaptation:
            Text("适配")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
        case .exclusive(let agent):
            let label = agent.map { "\($0.shortLabel)专属" } ?? "专属"
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.red)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
        }
    }

    // MARK: - Agent Toggle

    private func handleAgentToggle(skill: Skill, agent: Agent) {
        // Already deployed → undeploy
        if skill.deployedIn.contains(agent) {
            store.toggleDeploy(skillId: skill.id, agent: agent)
            return
        }

        // Not deployed → deploy from vault or agent directory
        store.toggleDeploy(skillId: skill.id, agent: agent)
    }

    // MARK: - Batch Deploy

    private struct BatchDeployInfo {
        let deployCount: Int
        let message: String
    }

    private func batchDeployInfo(agent: Agent) -> BatchDeployInfo {
        let selected = store.skills.filter { selectedSkillIds.contains($0.id) }
        let toDeploy = selected.filter { !$0.deployedIn.contains(agent) }
        let msg = toDeploy.isEmpty ? "所有选中的 Skill 已部署到 \(agent.displayName)" : "部署 \(toDeploy.count) 个"
        return BatchDeployInfo(deployCount: toDeploy.count, message: msg)
    }

    private func executeBatchDeploy(agent: Agent) {
        let selected = store.skills.filter { selectedSkillIds.contains($0.id) }
        let toDeployIds = selected.filter { !$0.deployedIn.contains(agent) }.map(\.id)
        store.batchDeploy(skillIds: Set(toDeployIds), to: agent)
    }

    // MARK: - Helpers

    private func toast(_ message: String) {
        toastMessage = message
        SkillManager.showToast(message, isShowing: $showToast)
    }

    private var filteredSkills: [Skill] {
        store.skills.filter { filter.matches($0) }
    }
}
