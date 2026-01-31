import Foundation

public struct ActionPlan: Codable, Sendable {
    public let actions: [AgentAction]
    public let notes: String?
}

public struct AgentAction: Codable, Equatable, Sendable {
    public let type: String
    public let id: String
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
