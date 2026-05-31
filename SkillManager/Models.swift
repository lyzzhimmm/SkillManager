import Foundation
import SwiftUI

// MARK: - Agent

enum Agent: String, CaseIterable, Identifiable, Hashable {
    case claude
    case codex
    case hermes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex:  return "Codex"
        case .hermes: return "Hermes"
        }
    }

    var shortLabel: String {
        switch self {
        case .claude: return "C"
        case .codex:  return "O"
        case .hermes: return "H"
        }
    }

    var skillsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude: return home.appendingPathComponent(".claude/skills")
        case .codex:  return home.appendingPathComponent(".codex/skills")
        case .hermes: return home.appendingPathComponent(".hermes/skills")
        }
    }

    var color: Color {
        switch self {
        case .claude: return Theme.claude
        case .codex:  return Theme.codex
        case .hermes: return Theme.hermes
        }
    }
}

// MARK: - Frequency

enum Frequency: String, CaseIterable, Hashable, Comparable {
    case high   = "高"
    case medium = "中"
    case low    = "低"

    private var sortOrder: Int {
        switch self {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        }
    }

    static func < (lhs: Frequency, rhs: Frequency) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Migration Status

enum MigrationStatus: Hashable {
    case portable             // ✅ 可迁移 — can deploy anywhere
    case needsAdaptation      // ⚠️ 需适配 — copy prompt to clipboard
    case exclusive(Agent?)    // ❌ 专属 — copy prompt to clipboard

    var label: String {
        switch self {
        case .portable:          return "可迁移"
        case .needsAdaptation:   return "需适配"
        case .exclusive(let a):  if let a = a { return "\(a.displayName) 专属" }
                                 return "专属"
        }
    }

    var canDirectDeploy: Bool {
        if case .portable = self { return true }
        return false
    }
}

// MARK: - Category

enum Category: String, CaseIterable, Hashable {
    case all       = "全部"
    case planning  = "规划"
    case dev       = "开发"
    case quality   = "质量"
    case debug     = "调试"
    case project   = "项目管理"
    case web       = "网页"
    case content   = "内容"
    case arch      = "架构"
    case other     = "其他"

    static func classify(name: String, description: String) -> Category {
        let text = (name + " " + description).lowercased()
        if text.contains("plan") || text.contains("design") || text.contains("brainstorm") ||
           text.contains("grill") || text.contains("prototype") || text.contains("prd") {
            return .planning
        }
        if text.contains("build") || text.contains("tdd") || text.contains("test") ||
           text.contains("feature") {
            return .dev
        }
        if text.contains("review") || text.contains("code-review") || text.contains("quality") {
            return .quality
        }
        if text.contains("diagnose") || text.contains("debug") {
            return .debug
        }
        if text.contains("handoff") || text.contains("session") || text.contains("issue") ||
           text.contains("triage") || text.contains("project") {
            return .project
        }
        if text.contains("web") || text.contains("browser") || text.contains("search") ||
           text.contains("scrape") {
            return .web
        }
        if text.contains("doc") || text.contains("article") || text.contains("content") ||
           text.contains("writing") || text.contains("pdf") {
            return .content
        }
        if text.contains("architecture") || text.contains("pattern") || text.contains("api") ||
           text.contains("mcp") {
            return .arch
        }
        return .other
    }
}

// MARK: - Skill

struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    var category: Category
    let filePath: URL
    let hasReferences: Bool
    var frequency: Frequency
    var source: String
    var isUniversal: Bool
    var migration: MigrationStatus
    var originAgent: Agent?
    var deployedIn: Set<Agent>
    var isLocal: Bool  // true = has local directory, false = inventory only
}

// MARK: - Remote Host

struct RemoteHost: Identifiable, Hashable {
    let id: String      // SSH host alias
    let name: String
    let hostname: String
    var isConnected: Bool
}

// MARK: - Deploy Error

enum DeployError: LocalizedError {
    case alreadyDeployed
    case symlinkFailed(String)
    case undeployFailed(String)
    case sshFailed(String)
    case notLocalSkill

    var errorDescription: String? {
        switch self {
        case .alreadyDeployed:          return "已部署"
        case .symlinkFailed(let e):     return "部署失败: \(e)"
        case .undeployFailed(let e):    return "取消部署失败: \(e)"
        case .sshFailed(let e):         return "远程部署失败: \(e)"
        case .notLocalSkill:            return "非本地 Skill，无法直接部署"
        }
    }
}

// MARK: - Filter State

struct FilterState {
    var selectedCategory: Category = .all
    var selectedFrequencies: Set<Frequency> = Set(Frequency.allCases)
    var selectedAgents: Set<Agent> = Set(Agent.allCases)
    var onlyUniversal: Bool = false
    var searchText: String = ""

    func matches(_ skill: Skill) -> Bool {
        if selectedCategory != .all && skill.category != selectedCategory {
            return false
        }
        if onlyUniversal && !skill.isUniversal {
            return false
        }
        if !selectedFrequencies.contains(skill.frequency) {
            return false
        }
        if !selectedAgents.isEmpty && skill.deployedIn.isDisjoint(with: selectedAgents) {
            return false
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            if !skill.name.lowercased().contains(q) && !skill.description.lowercased().contains(q) {
                return false
            }
        }
        return true
    }
}
