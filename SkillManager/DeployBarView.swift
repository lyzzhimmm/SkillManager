import SwiftUI

struct DeployBarView: View {
    let selectedSkills: [Skill]
    let onDeploy: (Agent) -> Void
    let isDark: Bool

    var body: some View {
        let hasAnyUndeployed = selectedSkills.contains { skill in
            Agent.allCases.contains { agent in !skill.deployedIn.contains(agent) }
        }

        return Group {
            if hasAnyUndeployed {
                HStack(spacing: 12) {
                    Text("已选 \(selectedSkills.count) 个")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDark ? Color(hex: 0xA1A1A6) : Color(hex: 0x6E6E73))
                    Text("部署到：")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDark ? Color(hex: 0xA1A1A6) : Color(hex: 0x6E6E73))
                    ForEach(Agent.allCases) { agent in
                        let allDeployed = selectedSkills.allSatisfy { $0.deployedIn.contains(agent) }
                        if !allDeployed {
                            Button(action: { onDeploy(agent) }) {
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
                .background(isDark ? Color(hex: 0x2C2C2E) : Color(hex: 0xFFFFFF))
                .overlay(Rectangle().fill(isDark ? Color(hex: 0x38383A) : Color(hex: 0xE5E5E7)).frame(height: 1), alignment: .top)
            }
        }
    }
}
