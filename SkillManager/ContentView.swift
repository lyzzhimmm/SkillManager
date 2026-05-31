import SwiftUI

struct ContentView: View {
    @StateObject private var store = SkillStore()
    @State private var filter = FilterState()
    @State private var selectedSkillIds: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\Skill.name)]
    @State private var showDeployConfirm = false
    @State private var pendingDeployAgent: Agent?
    @State private var inventoryPath: String = UserDefaults.standard.string(forKey: "inventoryPath")
        ?? "/Volumes/PJSSD/通用skill及指南/Skill 清单/Agents Skill 跨平台对比清单.md"
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
                inventoryPath: $inventoryPath,
                onReload: { store.load(inventoryPath: inventoryPath) },
                syncStatus: store.syncStatus,
                isSyncing: store.isSyncing,
                onSyncPull: { store.syncPull() },
                onSyncPush: { store.syncPush() },
                onCollectPush: { store.collectAndPush() }
            )

            mainContent
        }
        .frame(minWidth: 1100, minHeight: 600)
        .onAppear { store.load(inventoryPath: inventoryPath) }
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
            TableColumn("Skill", value: \.name) { skill in
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
                            isDeployed: skill.deployedIn.contains(agent),
                            onTap: { handleAgentToggle(skill: skill, agent: agent) }
                        )
                    }
                }
            }
            .width(min: 72, ideal: 72, max: 80)

            TableColumn("频次") { skill in
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
        if skill.deployedIn.contains(agent) {
            if skill.isLocal {
                store.toggleDeploy(skillId: skill.id, agent: agent)
            }
            return
        }

        if !skill.isLocal {
            copyToClipboard(
                prompt: "请帮我安装 Skill `\(skill.name)`。\n\n描述：\(skill.description)\n来源：\(skill.originAgent?.displayName ?? "未知")\n\n请根据你的 Agent 环境创建对应的 SKILL.md 文件并安装。",
                toast: "已复制到剪贴板，请打开 \(agent.displayName) 粘贴执行安装"
            )
            return
        }

        switch skill.migration {
        case .portable:
            store.toggleDeploy(skillId: skill.id, agent: agent)
        case .needsAdaptation:
            copyToClipboard(
                prompt: "请帮我适配并安装 Skill `\(skill.name)`。\n\n源文件位置：`\(skill.filePath.path)`\n\n它目前是 \(skill.originAgent?.displayName ?? "未知") 格式，需要适配到你的运行环境。",
                toast: "已复制到剪贴板，请打开 \(agent.displayName) 粘贴执行适配"
            )
        case .exclusive(let exclusiveAgent):
            let ownerName = exclusiveAgent?.displayName ?? "其他 Agent"
            copyToClipboard(
                prompt: "Skill `\(skill.name)` 是 \(ownerName) 专属，可能无法在你的环境中运行。\n\n源文件位置：`\(skill.filePath.path)`",
                toast: "已复制到剪贴板，请打开 \(agent.displayName) 粘贴执行"
            )
        }
    }

    // MARK: - Batch Deploy

    private struct BatchDeployInfo {
        let portableCount: Int
        let clipboardCount: Int
        let message: String
    }

    private func batchDeployInfo(agent: Agent) -> BatchDeployInfo {
        let selected = store.skills.filter { selectedSkillIds.contains($0.id) }
        let portable = selected.filter { $0.isLocal && $0.migration.canDirectDeploy && !$0.deployedIn.contains(agent) }
        let clipboard = selected.filter { skill in
            !skill.deployedIn.contains(agent) && (!skill.isLocal || !skill.migration.canDirectDeploy)
        }
        var parts: [String] = []
        if !portable.isEmpty { parts.append("部署 \(portable.count) 个（symlink）") }
        if !clipboard.isEmpty { parts.append("复制 \(clipboard.count) 个到剪贴板") }
        let msg = parts.isEmpty ? "所有选中的 Skill 已部署到 \(agent.displayName)" : parts.joined(separator: "，")
        return BatchDeployInfo(portableCount: portable.count, clipboardCount: clipboard.count, message: msg)
    }

    private func executeBatchDeploy(agent: Agent) {
        let selected = store.skills.filter { selectedSkillIds.contains($0.id) }
        let portableIds = selected.filter { $0.isLocal && $0.migration.canDirectDeploy && !$0.deployedIn.contains(agent) }.map(\.id)
        store.batchDeploy(skillIds: Set(portableIds), to: agent)

        let clipboardSkills = selected.filter { skill in
            !skill.deployedIn.contains(agent) && (!skill.isLocal || !skill.migration.canDirectDeploy)
        }
        if !clipboardSkills.isEmpty {
            let prompts = clipboardSkills.map { "请安装 Skill `\($0.name)` — \($0.description)" }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompts.joined(separator: "\n\n"), forType: .string)
            toast("已复制 \(clipboardSkills.count) 个 Skill 的安装提示到剪贴板")
        }
    }

    // MARK: - Helpers

    private func copyToClipboard(prompt: String, toast message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        toast(message)
    }

    private func toast(_ message: String) {
        toastMessage = message
        SkillManager.showToast(message, isShowing: $showToast)
    }

    private var filteredSkills: [Skill] {
        store.skills.filter { filter.matches($0) }
    }
}
