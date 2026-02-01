import Foundation

enum AgentParserError: LocalizedError, Sendable {
    case emptyResponse
    case invalidJSON
    case missingActionID
    case invalidActionType
    case unknownActionID(String)
    case missingActionTarget
    case invalidScrollAmount
    case invalidScrollDirection
    case invalidWaitDuration
    case invalidURL
    case missingQuestion
    case missingSummary

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Model returned an empty response."
        case .invalidJSON:
            return "Model returned invalid JSON."
        case .missingActionID:
            return "Model returned a click action without an id."
        case .invalidActionType:
            return "Model returned an unsupported action type."
        case let .unknownActionID(id):
            return "Model returned an action with unknown id \(id)."
        case .missingActionTarget:
            return "Model returned a type action without an id or selector."
        case .invalidScrollAmount:
            return "Model returned an invalid scroll amount."
        case .invalidScrollDirection:
            return "Model returned an invalid scroll direction."
        case .invalidWaitDuration:
            return "Model returned an invalid wait duration."
        case .invalidURL:
            return "Model returned an invalid URL."
        case .missingQuestion:
            return "Model returned an ask_user action without a question."
        case .missingSummary:
            return "Model returned a done action without a summary."
        }
    }
}

struct AgentParser {
    struct RawActionPlan: Decodable {
        struct RawAction: Decodable {
            let type: String?
            let id: String?
            let selector: String?
            let text: String?
            let direction: String?
            let amount: Int?
            let ms: Int?
            let url: String?
            let question: String?
            let summary: String?
        }

        let actions: [RawAction]?
        let notes: String?
        let reasoning: String?
        let error: String?
    }

    func parseActionPlan(from text: String, clickMap: PageSnapshot) throws -> ActionPlan {
        let trimmed = stripCodeFences(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentParserError.emptyResponse
        }

        let jsonText = extractJSON(from: trimmed)
        guard let data = jsonText.data(using: .utf8) else {
            throw AgentParserError.invalidJSON
        }

        let rawPlan: RawActionPlan
        do {
            rawPlan = try JSONDecoder().decode(RawActionPlan.self, from: data)
        } catch {
            throw AgentParserError.invalidJSON
        }

        if let error = rawPlan.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            return ActionPlan(actions: [], notes: rawPlan.notes, reasoning: rawPlan.reasoning, error: error)
        }

        let validIds = Set(clickMap.clickables.map(\.id))
        let actions = try (rawPlan.actions ?? []).compactMap { rawAction -> AgentAction? in
            guard let type = rawAction.type?.lowercased() else {
                throw AgentParserError.invalidActionType
            }

            switch type {
            case "click":
                guard let id = rawAction.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                    throw AgentParserError.missingActionID
                }
                guard validIds.contains(id) else {
                    throw AgentParserError.unknownActionID(id)
                }
                return .click(id: id)
            case "type":
                let id = rawAction.id?.trimmingCharacters(in: .whitespacesAndNewlines)
                let selector = rawAction.selector?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (id?.isEmpty == false) || (selector?.isEmpty == false) else {
                    throw AgentParserError.missingActionTarget
                }
                if let id, !id.isEmpty, !validIds.contains(id) {
                    throw AgentParserError.unknownActionID(id)
                }
                guard let text = rawAction.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    throw AgentParserError.missingActionTarget
                }
                return .type(id: id?.isEmpty == true ? nil : id, selector: selector?.isEmpty == true ? nil : selector, text: text)
            case "scroll":
                guard let direction = rawAction.direction?.lowercased() else {
                    throw AgentParserError.invalidScrollDirection
                }
                guard let amount = rawAction.amount, (50...2000).contains(amount) else {
                    throw AgentParserError.invalidScrollAmount
                }
                switch direction {
                case "up":
                    return .scroll(direction: .up, amount: amount)
                case "down":
                    return .scroll(direction: .down, amount: amount)
                default:
                    throw AgentParserError.invalidScrollDirection
                }
            case "wait":
                let ms = rawAction.ms ?? 1000
                let clamped = min(max(ms, 50), 15000)
                return .wait(ms: clamped)
            case "navigate":
                guard let url = rawAction.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
                    throw AgentParserError.invalidURL
                }
                guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                    throw AgentParserError.invalidURL
                }
                return .navigate(url: url)
            case "ask_user":
                guard let question = rawAction.question?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty else {
                    throw AgentParserError.missingQuestion
                }
                return .askUser(question: question)
            case "done":
                guard let summary = rawAction.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty else {
                    throw AgentParserError.missingSummary
                }
                return .done(summary: summary)
            default:
                throw AgentParserError.invalidActionType
            }
        }

        return ActionPlan(actions: actions, notes: rawPlan.notes, reasoning: rawPlan.reasoning, error: rawPlan.error)
    }

    private func stripCodeFences(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("```") else { return trimmed }
        if trimmed.hasPrefix("```") {
            var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            if let first = lines.first, first.starts(with: "```") {
                lines.removeFirst()
            }
            if let last = lines.last, last.starts(with: "```") {
                lines.removeLast()
            }
            return lines.joined(separator: "\n")
        }
        if let start = trimmed.range(of: "```"), let end = trimmed.range(of: "```", options: .backwards), start.lowerBound != end.lowerBound {
            let inside = trimmed[start.upperBound..<end.lowerBound]
            return String(inside)
        }
        return trimmed
    }

    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        guard let startIndex = trimmed.firstIndex(of: "{") else {
            return trimmed
        }

        var depth = 0
        var index = startIndex
        while index < trimmed.endIndex {
            let char = trimmed[index]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    let endIndex = trimmed.index(after: index)
                    return String(trimmed[startIndex..<endIndex])
                }
            }
            index = trimmed.index(after: index)
        }

        return trimmed
    }

#if DEBUG
    static let sampleResponseJSON = """
    {"actions":[{"type":"click","id":"e1"}],"notes":"example"}
    """

    static func debugSelfCheck() -> Bool {
        let clickMap = PageSnapshot(
            url: "https://example.com",
            title: "Example",
            clickables: [
                Clickable(
                    id: "e1",
                    role: "button",
                    label: "Submit",
                    rect: ClickRect(x: 0.1, y: 0.2, w: 0.3, h: 0.1),
                    href: nil,
                    tag: "BUTTON",
                    disabled: false
                )
            ]
        )
        do {
            _ = try AgentParser().parseActionPlan(from: sampleResponseJSON, clickMap: clickMap)
            return true
        } catch {
            return false
        }
    }
#endif
}
