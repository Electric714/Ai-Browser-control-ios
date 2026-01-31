import Foundation

public struct ActionPlan: Codable, Sendable {
    public let actions: [AgentAction]?
    public let error: String?
    public let reasoning: String?
}

public struct AgentAction: Codable, Equatable, Sendable {
    public enum ActionType: String, Codable, Sendable {
        case click
        case type
        case scroll
        case wait
        case navigate
        case ask_user
        case done
    }

    public let type: ActionType
    public let id: String?
    public let selector: String?
    public let text: String?
    public let direction: ScrollDirection?
    public let amount: Int?
    public let ms: Int?
    public let url: String?
    public let question: String?
    public let summary: String?
}

public enum ScrollDirection: String, Codable, Sendable {
    case up
    case down
}

public struct AgentLogEntry: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case info
        case model
        case action
        case result
        case error
        case warning
    }

    public let id = UUID()
    public let date: Date
    public let kind: Kind
    public let message: String
}
