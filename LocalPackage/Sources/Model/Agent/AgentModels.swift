import Foundation

public struct ActionPlan: Codable, Sendable {
    public let actions: [AgentAction]
    public let notes: String?
    public let reasoning: String?
    public let error: String?
}

public enum ScrollDirection: String, Codable, Sendable {
    case up
    case down
}

public enum AgentAction: Codable, Equatable, Sendable {
    case click(id: String)
    case type(id: String?, selector: String?, text: String)
    case scroll(direction: ScrollDirection, amount: Int)
    case wait(ms: Int)
    case navigate(url: String)
    case askUser(question: String)
    case done(summary: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case selector
        case text
        case direction
        case amount
        case ms
        case url
        case question
        case summary
    }

    private enum ActionType: String, Codable {
        case click
        case type
        case scroll
        case wait
        case navigate
        case ask_user
        case done
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        switch type {
        case .click:
            let id = try container.decode(String.self, forKey: .id)
            self = .click(id: id)
        case .type:
            let id = try container.decodeIfPresent(String.self, forKey: .id)
            let selector = try container.decodeIfPresent(String.self, forKey: .selector)
            let text = try container.decode(String.self, forKey: .text)
            self = .type(id: id, selector: selector, text: text)
        case .scroll:
            let direction = try container.decode(ScrollDirection.self, forKey: .direction)
            let amount = try container.decode(Int.self, forKey: .amount)
            self = .scroll(direction: direction, amount: amount)
        case .wait:
            let ms = try container.decode(Int.self, forKey: .ms)
            self = .wait(ms: ms)
        case .navigate:
            let url = try container.decode(String.self, forKey: .url)
            self = .navigate(url: url)
        case .ask_user:
            let question = try container.decode(String.self, forKey: .question)
            self = .askUser(question: question)
        case .done:
            let summary = try container.decode(String.self, forKey: .summary)
            self = .done(summary: summary)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .click(id):
            try container.encode(ActionType.click, forKey: .type)
            try container.encode(id, forKey: .id)
        case let .type(id, selector, text):
            try container.encode(ActionType.type, forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(selector, forKey: .selector)
            try container.encode(text, forKey: .text)
        case let .scroll(direction, amount):
            try container.encode(ActionType.scroll, forKey: .type)
            try container.encode(direction, forKey: .direction)
            try container.encode(amount, forKey: .amount)
        case let .wait(ms):
            try container.encode(ActionType.wait, forKey: .type)
            try container.encode(ms, forKey: .ms)
        case let .navigate(url):
            try container.encode(ActionType.navigate, forKey: .type)
            try container.encode(url, forKey: .url)
        case let .askUser(question):
            try container.encode(ActionType.ask_user, forKey: .type)
            try container.encode(question, forKey: .question)
        case let .done(summary):
            try container.encode(ActionType.done, forKey: .type)
            try container.encode(summary, forKey: .summary)
        }
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
