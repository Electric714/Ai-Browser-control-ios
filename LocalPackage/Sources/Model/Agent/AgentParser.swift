import Foundation

enum AgentParserError: LocalizedError, Sendable {
    case emptyResponse
    case invalidJSON
    case missingActionID
    case invalidAction(String)
    case invalidActionValue(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Model returned an empty response."
        case .invalidJSON:
            return "Model returned invalid JSON."
        case .missingActionID:
            return "Model returned a click action without an id."
        case let .invalidAction(message):
            return "Model returned an invalid action: \(message)"
        case let .invalidActionValue(message):
            return "Model returned an invalid action value: \(message)"
        }
    }
}

struct AgentParser {
    func parseActionPlan(from text: String, clickMap: PageSnapshot) throws -> ActionPlan {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentParserError.emptyResponse
        }

        let jsonText = extractJSON(from: trimmed)
        guard let data = jsonText.data(using: .utf8) else {
            throw AgentParserError.invalidJSON
        }

        let plan: ActionPlan
        do {
            plan = try JSONDecoder().decode(ActionPlan.self, from: data)
        } catch {
            throw AgentParserError.invalidJSON
        }

        let validatedActions = try validate(actions: plan.actions ?? [], clickMap: clickMap)
        return ActionPlan(actions: validatedActions, error: plan.error, reasoning: plan.reasoning)
    }

    private func extractJSON(from text: String) -> String {
        if let fenced = extractFencedJSON(from: text) {
            return fenced
        }
        if let firstBrace = text.firstIndex(of: "{"), let lastBrace = text.lastIndex(of: "}") {
            return String(text[firstBrace...lastBrace])
        }
        return text
    }

    private func extractFencedJSON(from text: String) -> String? {
        guard let startRange = text.range(of: "```") else { return nil }
        guard let endRange = text.range(of: "```", options: .backwards), startRange.lowerBound != endRange.lowerBound else {
            return nil
        }
        let innerStart = startRange.upperBound
        let inner = text[innerStart..<endRange.lowerBound]
        let lines = inner.split(separator: "\n", omittingEmptySubsequences: false)
        if let firstLine = lines.first, firstLine.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("json") {
            return lines.dropFirst().joined(separator: "\n")
        }
        return String(inner)
    }

    private func validate(actions: [AgentAction], clickMap: PageSnapshot) throws -> [AgentAction] {
        let ids = Set(clickMap.clickables.map { $0.id })
        return try actions.map { action in
            switch action.type {
            case .click:
                guard let id = action.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                    throw AgentParserError.missingActionID
                }
                guard ids.contains(id) else {
                    throw AgentParserError.invalidAction("click id \(id) not in click map")
                }
                return AgentAction(
                    type: .click,
                    id: id,
                    selector: nil,
                    text: nil,
                    direction: nil,
                    amount: nil,
                    ms: nil,
                    url: nil,
                    question: nil,
                    summary: nil
                )
            case .type:
                let trimmedText = action.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !trimmedText.isEmpty else {
                    throw AgentParserError.invalidAction("type action requires text")
                }
                let id = action.id?.trimmingCharacters(in: .whitespacesAndNewlines)
                let selector = action.selector?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (id?.isEmpty == false) || (selector?.isEmpty == false) else {
                    throw AgentParserError.invalidAction("type action requires id or selector")
                }
                if let id, !id.isEmpty, !ids.contains(id) {
                    throw AgentParserError.invalidAction("type id \(id) not in click map")
                }
                return AgentAction(
                    type: .type,
                    id: id,
                    selector: selector,
                    text: trimmedText,
                    direction: nil,
                    amount: nil,
                    ms: nil,
                    url: nil,
                    question: nil,
                    summary: nil
                )
            case .scroll:
                guard let direction = action.direction else {
                    throw AgentParserError.invalidAction("scroll requires direction")
                }
                guard let amount = action.amount, (50...2000).contains(amount) else {
                    throw AgentParserError.invalidActionValue("scroll amount must be 50..2000")
                }
                return AgentAction(
                    type: .scroll,
                    id: nil,
                    selector: nil,
                    text: nil,
                    direction: direction,
                    amount: amount,
                    ms: nil,
                    url: nil,
                    question: nil,
                    summary: nil
                )
            case .wait:
                guard let ms = action.ms, (50...15000).contains(ms) else {
                    throw AgentParserError.invalidActionValue("wait ms must be 50..15000")
                }
                return AgentAction(
                    type: .wait,
                    id: nil,
                    selector: nil,
                    text: nil,
                    direction: nil,
                    amount: nil,
                    ms: ms,
                    url: nil,
                    question: nil,
                    summary: nil
                )
            case .navigate:
                guard let urlString = action.url?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else {
                    throw AgentParserError.invalidAction("navigate requires url")
                }
                guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                    throw AgentParserError.invalidActionValue("navigate url must be http/https")
                }
                return AgentAction(
                    type: .navigate,
                    id: nil,
                    selector: nil,
                    text: nil,
                    direction: nil,
                    amount: nil,
                    ms: nil,
                    url: urlString,
                    question: nil,
                    summary: nil
                )
            case .ask_user:
                let question = action.question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !question.isEmpty else {
                    throw AgentParserError.invalidAction("ask_user requires question")
                }
                return AgentAction(
                    type: .ask_user,
                    id: nil,
                    selector: nil,
                    text: nil,
                    direction: nil,
                    amount: nil,
                    ms: nil,
                    url: nil,
                    question: question,
                    summary: nil
                )
            case .done:
                let summary = action.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
                return AgentAction(
                    type: .done,
                    id: nil,
                    selector: nil,
                    text: nil,
                    direction: nil,
                    amount: nil,
                    ms: nil,
                    url: nil,
                    question: nil,
                    summary: summary
                )
            }
        }
    }
}

#if DEBUG
extension AgentParser {
    static let debugSampleResponse = """
    {"actions":[{"type":"click","id":"e1"}],"reasoning":"Click the primary action."}
    """

    static func debugSelfCheck() -> Bool {
        let sampleMap = PageSnapshot(
            url: "https://example.com",
            title: "Example",
            clickables: [
                Clickable(
                    id: "e1",
                    role: "button",
                    label: "Continue",
                    rect: ClickRect(x: 0.1, y: 0.2, w: 0.3, h: 0.1),
                    href: nil,
                    tag: "BUTTON",
                    disabled: false
                )
            ]
        )
        do {
            _ = try AgentParser().parseActionPlan(from: debugSampleResponse, clickMap: sampleMap)
            return true
        } catch {
            return false
        }
    }
}
#endif
