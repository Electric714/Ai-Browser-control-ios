import Foundation

public struct ActionPlan: Codable, Sendable {
    public let actions: [AgentAction]
    public let notes: String?
}

public struct AgentAction: Codable, Equatable, Sendable {
    public enum ActionType: String, Codable, Sendable {
        case click
        case scroll
    }

    public let type: ActionType
    public let id: String?
    public let dx: Double?
    public let dy: Double?
    public let selector: String?
    public let mode: ScrollMode?

    public enum ScrollMode: String, Codable, Sendable {
        case window
        case element
        case auto
    }
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
