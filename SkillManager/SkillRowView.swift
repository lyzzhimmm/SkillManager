import SwiftUI

// MARK: - Agent Badge

struct AgentBadge: View {
    let agent: Agent
    let isDeployed: Bool
    var isInteractive: Bool = true
    let onTap: () -> Void

    var body: some View {
        Circle()
            .fill(isDeployed ? agent.color : Color.clear)
            .frame(width: 20, height: 20)
            .overlay(
                Circle()
                    .stroke(isDeployed ? Color.clear : agent.color.opacity(0.4), lineWidth: 1.5)
            )
            .overlay(
                Text(agent.shortLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isDeployed ? .white : agent.color.opacity(0.6))
            )
            .opacity(isInteractive ? 1.0 : 0.6)
            .onTapGesture { if isInteractive { onTap() } }
            .help(agent.displayName)
    }
}

// MARK: - Frequency Badge

struct FrequencyBadge: View {
    let frequency: Frequency

    var body: some View {
        Text(frequency.rawValue)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(frequencyColor.opacity(0.08))
            .foregroundColor(frequencyColor)
            .cornerRadius(10)
    }

    private var frequencyColor: Color {
        switch frequency {
        case .high:   return Theme.freqHigh
        case .medium: return Theme.freqMedium
        case .low:    return Theme.freqLow
        }
    }
}
