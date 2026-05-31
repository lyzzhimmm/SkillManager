import SwiftUI

struct SidebarView: View {
    @Binding var filter: FilterState
    let skillCounts: [Category: Int]
    let totalCount: Int
    @Binding var inventoryPath: String
    let onReload: () -> Void
    var syncStatus: SkillSyncer.SyncStatus?
    var isSyncing: Bool = false
    var onSyncPull: (() -> Void)?
    var onSyncPush: (() -> Void)?
    var onCollect: (() -> Void)?
    var onPush: (() -> Void)?

    // Sidebar is always dark-themed
    private let bg = Color(hex: 0x1A1A1E)
    private let textPrimary = Color(hex: 0xF5F5F7)
    private let textSecondary = Color(hex: 0xA1A1A6)
    private let textMuted = Color(hex: 0x6E6E73)
    private let textDim = Color(hex: 0xB0B0B4)
    private let dividerColor = Color(hex: 0x2E2E32)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x5E5CE6), Color(hex: 0xBF5AF2)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                    .overlay(Text("S").font(.system(size: 14, weight: .semibold)).foregroundColor(.white))
                Text("Skill Manager")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .textSelection(.disabled)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Categories
            sectionTitle("分类")
            categoryItem(.all, count: totalCount)
            ForEach([Category.planning, .dev, .quality, .debug, .project, .web, .content, .arch], id: \.self) { cat in
                categoryItem(cat, count: skillCounts[cat] ?? 0)
            }

            divider

            // Universal filter
            sectionTitle("范围")
            HStack(spacing: 5) {
                let isOn = filter.onlyUniversal
                Text("仅通用")
                    .font(.system(size: 11))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(isOn ? Color(hex: 0x5E5CE6).opacity(0.2) : Color.clear)
                    .foregroundColor(isOn ? Color(hex: 0xA78BFA) : textDim)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isOn ? Color(hex: 0x5E5CE6) : Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .onTapGesture { filter.onlyUniversal.toggle() }
            }
            .padding(.horizontal, 16)

            divider

            // Frequency
            sectionTitle("频次")
            HStack(spacing: 5) {
                ForEach(Frequency.allCases, id: \.self) { freq in
                    freqChip(freq)
                }
            }
            .padding(.horizontal, 16)

            divider

            // Agent 适配
            sectionTitle("Agent 适配")
            HStack(spacing: 5) {
                ForEach(Agent.allCases) { agent in
                    compatibleAgentChip(agent)
                }
            }
            .padding(.horizontal, 16)

            divider

            // Agent 已安装
            sectionTitle("Agent 已安装")
            HStack(spacing: 5) {
                ForEach(Agent.allCases) { agent in
                    installedAgentChip(agent)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            divider

            // Sync section
            sectionTitle("云同步")
            VStack(alignment: .leading, spacing: 6) {
                if let status = syncStatus {
                    if !status.isCloned {
                        Button("初始化仓库") { onSyncPull?() }
                            .sidebarButton()
                    } else {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: 0x30D158)).frame(width: 6, height: 6)
                            Text(status.lastCommit ?? "已同步")
                                .font(.system(size: 10))
                                .foregroundColor(textDim)
                                .lineLimit(1)
                        }
                        Text("\(status.skillCount) 个通用 Skill")
                            .font(.system(size: 10))
                            .foregroundColor(textMuted)

                        HStack(spacing: 6) {
                            Button(isSyncing ? "同步中..." : "拉取") { onSyncPull?() }
                                .sidebarButton()
                                .disabled(isSyncing)
                            Button("↓ 收集") { onCollect?() }
                                .sidebarButton()
                                .disabled(isSyncing)
                            Button("↑ 推送") { onPush?() }
                                .sidebarButton()
                                .disabled(isSyncing)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            divider

            // Inventory file
            sectionTitle("清单文件")
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: inventoryPath).lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundColor(textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Button("选择文件") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.plainText]
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.message = "选择 Skill 清单 MD 文件"
                        if panel.runModal() == .OK, let url = panel.url {
                            inventoryPath = url.path
                            UserDefaults.standard.set(url.path, forKey: "inventoryPath")
                            onReload()
                        }
                    }
                    .font(.system(size: 10.5))
                    .buttonStyle(.plain)
                    .foregroundColor(Color(hex: 0xE0E0E0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)

                    Button("刷新") { onReload() }
                        .font(.system(size: 10.5))
                        .buttonStyle(.plain)
                        .foregroundColor(Color(hex: 0xE0E0E0))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 220)
        .background(bg)
    }

    // MARK: - Components

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    private func categoryItem(_ category: Category, count: Int) -> some View {
        HStack {
            Text(category.rawValue)
                .font(.system(size: 12.5))
                .foregroundColor(filter.selectedCategory == category ? .white : textDim)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10.5))
                .foregroundColor(filter.selectedCategory == category ? .white : textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(filter.selectedCategory == category ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(filter.selectedCategory == category ? Theme.sidebarActive : Color.clear)
        .cornerRadius(5)
        .contentShape(Rectangle())
        .onTapGesture { filter.selectedCategory = category }
        .padding(.horizontal, 8)
    }

    private func freqChip(_ freq: Frequency) -> some View {
        let isOn = filter.selectedFrequencies.contains(freq)
        return Text(freq.rawValue)
            .font(.system(size: 11))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(isOn ? Color(hex: 0x007AFF).opacity(0.15) : Color.clear)
            .foregroundColor(isOn ? Color(hex: 0x64D2FF) : textDim)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? Color(hex: 0x007AFF) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(12)
            .onTapGesture {
                if isOn { filter.selectedFrequencies.remove(freq) }
                else { filter.selectedFrequencies.insert(freq) }
            }
    }

    private func compatibleAgentChip(_ agent: Agent) -> some View {
        let isOn = filter.selectedCompatibleAgents.contains(agent)
        let color = agent.color
        return Text(agent.displayName.components(separatedBy: " ").first ?? agent.displayName)
            .font(.system(size: 11))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(isOn ? color.opacity(0.2) : Color.clear)
            .foregroundColor(isOn ? color : textDim)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? color : Color.white.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(12)
            .onTapGesture {
                if isOn { filter.selectedCompatibleAgents.remove(agent) }
                else { filter.selectedCompatibleAgents.insert(agent) }
            }
    }

    private func installedAgentChip(_ agent: Agent) -> some View {
        let isOn = filter.selectedInstalledAgents.contains(agent)
        let color = agent.color
        return Text(agent.displayName.components(separatedBy: " ").first ?? agent.displayName)
            .font(.system(size: 11))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(isOn ? color.opacity(0.2) : Color.clear)
            .foregroundColor(isOn ? color : textDim)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? color : Color.white.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(12)
            .onTapGesture {
                if isOn { filter.selectedInstalledAgents.remove(agent) }
                else { filter.selectedInstalledAgents.insert(agent) }
            }
    }

    private var divider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }
}

// MARK: - Sidebar Button Style

extension View {
    func sidebarButton() -> some View {
        self
            .font(.system(size: 10.5))
            .buttonStyle(.plain)
            .foregroundColor(Color(hex: 0xE0E0E0))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.08))
            .cornerRadius(4)
    }
}
