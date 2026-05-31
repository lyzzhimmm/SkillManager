import SwiftUI

struct StatusView: View {
    let totalCount: Int
    let universalCount: Int
    let claudeCount: Int
    let codexCount: Int
    let hermesCount: Int
    let isDark: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("共 \(totalCount) 个 Skill")
            Text("·").foregroundColor(isDark ? Color(hex: 0x38383A) : Color(hex: 0xE5E5E7))
            Text("通用 \(universalCount)")
                .foregroundColor(Color(hex: 0x30D158))
            Text("·").foregroundColor(isDark ? Color(hex: 0x38383A) : Color(hex: 0xE5E5E7))
            agentCount(label: "Claude", count: claudeCount, color: Theme.claude)
            Text("·").foregroundColor(isDark ? Color(hex: 0x38383A) : Color(hex: 0xE5E5E7))
            agentCount(label: "Codex", count: codexCount, color: Theme.codex)
            Text("·").foregroundColor(isDark ? Color(hex: 0x38383A) : Color(hex: 0xE5E5E7))
            agentCount(label: "Hermes", count: hermesCount, color: Theme.hermes)
        }
        .font(.system(size: 11))
        .foregroundColor(isDark ? Color(hex: 0xA1A1A6) : Color(hex: 0x6E6E73))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isDark ? Color(hex: 0x2C2C2E) : Color(hex: 0xFFFFFF))
        .overlay(Rectangle().fill(isDark ? Color(hex: 0x38383A) : Color(hex: 0xE5E5E7)).frame(height: 1), alignment: .top)
    }

    private func agentCount(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(count)")
        }
    }
}
