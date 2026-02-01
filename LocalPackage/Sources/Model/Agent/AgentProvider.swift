import Foundation

public enum AgentProvider: String, CaseIterable, Identifiable, Sendable {
    case openRouter = "openrouter"
    case onDevice = "on-device"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openRouter:
            return "OpenRouter"
        case .onDevice:
            return "On-Device (Apple)"
        }
    }
}
