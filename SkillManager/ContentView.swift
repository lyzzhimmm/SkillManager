import SwiftUI

struct ContentView: View {
    @StateObject private var store = SkillStore()
    @State private var filter = FilterState()
    @State private var selectedSkillIds: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\Skill.name)]
    @State private var showDeployConfirm = false
    @State private var pendingDeployAgent: Agent?
    @State private var inventoryPath: String = UserDefaults.standard.string(forKey: "inventoryPath")
        ?? "/Volumes/PJSSD/Agents Skill 跨平台对比清单.md"
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
                onReload: { store.load(inventoryPath: inventoryPath) }
            )

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(isDark ? Color(0x6E6E73) : Color(0xAEAEB2))
                        TextField("搜索 Skill...", text: $filter.searchText)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isDark ? Color(0x2C2C2E) : Color(0xE8E8EA))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    Divider()

                    if filteredSkills.isEmpty && !store.skills.isEmpty {
                        emptyStateView
                    } else {
                        Table(filteredSkills, selection: $selectedSkillIds, sortOrder: $sortOrder) {
                            TableColumn("Skill", value: \.name) { skill in
                                HStack(spacing: 4) {
                                    Text(skill.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    migrationBadge(skill.migration)
                                }
                            }
                            .width(min: 160, ideal: 180, max: 240)

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
                                            isInteractive: isAgentBadgeInteractive(skill: skill),
                                            onTap: { handleAgentToggle(skill: skill, agent: agent) }
                                        )
                                    }
                                }
                            }
                            .width(min: 72, ideal: 72, max: 72)

                            TableColumn("频次") { skill in
                                FrequencyBadge(frequency: skill.frequency)
                            }
                            .width(min: 40, ideal: 40, max: 40)

                            TableColumn("来源", value: \.source) { skill in
                                Text(skill.source)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            .width(min: 60, ideal: 65, max: 80)
                        }
                        .contextMenu(forSelectionType: String.self) { ids in
                            if let firstId = ids.first, let skill = store.skills.first(where: { $0.id == firstId }) {
                                ForEach(Agent.allCases) { agent in
                                    if skill.deployedIn.contains(agent) {
                                        if skill.isLocal {
                                            Button("取消部署到 \(agent.displayName)") {
                                                store.toggleDeploy(skillId: skill.id, agent: agent)
                                            }
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

                    if !selectedSkillIds.isEmpty { deployBar }
                    statusBar
                }
                .background(isDark ? Color(0x1C1C1E) : Color(0xF6F6F6))

                if showToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .onAppear { store.load(inventoryPath: inventoryPath) }
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

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(isDark ? Color(0x48484A) : Color(0xC7C7CC))
            Text("没有匹配的 Skill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isDark ? Color(0xA1A1A6) : Color(0x6E6E73))
            Text("尝试调整筛选条件或搜索关键词")
                .font(.system(size: 12))
                .foregroundColor(isDark ? Color(0x6E6E73) : Color(0xAEAEB2))
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

    // MARK: - Agent Badge Interactivity

    private func isAgentBadgeInteractive(skill: Skill) -> Bool {
        // Inventory-only skills: badge is informational, not clickable for undeploy
        if !skill.isLocal { return true }  // can still click to copy prompt
        return true
    }

    // MARK: - Agent Toggle Logic

    private func handleAgentToggle(skill: Skill, agent: Agent) {
        // Already deployed → undeploy (only for local skills with real symlinks)
        if skill.deployedIn.contains(agent) {
            if skill.isLocal {
                store.toggleDeploy(skillId: skill.id, agent: agent)
            }
            return
        }

        // Not deployed → deploy or copy prompt
        if !skill.isLocal {
            let prompt = "请帮我安装 Skill `\(skill.name)`。\n\n描述：\(skill.description)\n来源：\(skill.originAgent?.displayName ?? "未知")\n\n请根据你的 Agent 环境创建对应的 SKILL.md 文件并安装。"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            toast("已复制到剪贴板，请打开 \(agent.displayName) 粘贴执行安装")
            return
        }

        switch skill.migration {
        case .portable:
            store.toggleDeploy(skillId: skill.id, agent: agent)
        case .needsAdaptation:
            let prompt = "请帮我适配并安装 Skill `\(skill.name)`。\n\n源文件位置：`\(skill.filePath.path)`\n\n它目前是 \(skill.originAgent?.displayName ?? "未知") 格式，需要适配到你的运行环境。请读取 SKILL.md 的内容，根据你的 Agent 系统做必要的路径和格式调整后安装。"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            toast("已复制到剪贴板，请打开 \(agent.displayName) 粘贴执行适配")
        case .exclusive(let exclusiveAgent):
            let ownerName = exclusiveAgent?.displayName ?? "其他 Agent"
            let prompt = "Skill `\(skill.name)` 是 \(ownerName) 专属，可能无法在你的环境中运行。\n\n源文件位置：`\(skill.filePath.path)`\n\n如果你仍想尝试安装，请读取 SKILL.md 并根据你的环境做适配。"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            toast("已复制到剪贴板，请打开 \(agent.displayName) 粘贴执行")
        }
    }

    // MARK: - Batch Deploy Logic

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
        // Deploy portable via symlink
        let portableIds = selected.filter { $0.isLocal && $0.migration.canDirectDeploy && !$0.deployedIn.contains(agent) }.map(\.id)
        store.batchDeploy(skillIds: Set(portableIds), to: agent)
        // Copy prompts for non-portable
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

    // MARK: - Toast

    private var toastView: some View {
        Text(toastMessage)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .cornerRadius(10)
            .padding(.bottom, 60)
    }

    private func toast(_ message: String) {
        toastMessage = message
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showToast = false }
        }
    }

    // MARK: - Deploy Bar

    private var deployBar: some View {
        let selected = store.skills.filter { selectedSkillIds.contains($0.id) }
        let hasAnyUndeployed = selected.contains { skill in
            Agent.allCases.contains { agent in !skill.deployedIn.contains(agent) }
        }

        return Group {
            if hasAnyUndeployed {
                HStack(spacing: 12) {
                    Text("已选 \(selected.count) 个")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDark ? Color(0xA1A1A6) : Color(0x6E6E73))
                    Text("部署到：")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDark ? Color(0xA1A1A6) : Color(0x6E6E73))
                    ForEach(Agent.allCases) { agent in
                        let allDeployed = selected.allSatisfy { $0.deployedIn.contains(agent) }
                        if !allDeployed {
                            Button(action: {
                                pendingDeployAgent = agent
                                showDeployConfirm = true
                            }) {
                                HStack(spacing: 6) {
                                    Circle().fill(agent.color).frame(width: 10, height: 10)
                                    Text(agent.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(agent.color)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isDark ? Color(0x2C2C2E) : Color(0xFFFFFF))
                .overlay(Rectangle().fill(isDark ? Color(0x38383A) : Color(0xE5E5E7)).frame(height: 1), alignment: .top)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Text("共 \(store.skills.count) 个 Skill")
            Text("·").foregroundColor(isDark ? Color(0x38383A) : Color(0xE5E5E7))
            HStack(spacing: 4) {
                Circle().fill(Theme.claude).frame(width: 6, height: 6)
                Text("Claude \(store.countForAgent(.claude))")
            }
            Text("·").foregroundColor(isDark ? Color(0x38383A) : Color(0xE5E5E7))
            HStack(spacing: 4) {
                Circle().fill(Theme.codex).frame(width: 6, height: 6)
                Text("Codex \(store.countForAgent(.codex))")
            }
            Text("·").foregroundColor(isDark ? Color(0x38383A) : Color(0xE5E5E7))
            HStack(spacing: 4) {
                Circle().fill(Theme.hermes).frame(width: 6, height: 6)
                Text("Hermes \(store.countForAgent(.hermes))")
            }
        }
        .font(.system(size: 11))
        .foregroundColor(isDark ? Color(0xA1A1A6) : Color(0x6E6E73))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isDark ? Color(0x2C2C2E) : Color(0xFFFFFF))
        .overlay(Rectangle().fill(isDark ? Color(0x38383A) : Color(0xE5E5E7)).frame(height: 1), alignment: .top)
    }

    // MARK: - Computed

    private var filteredSkills: [Skill] {
        store.skills.filter { filter.matches($0) }
    }
}
