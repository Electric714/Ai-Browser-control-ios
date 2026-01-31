import Foundation

enum AgentParserError: LocalizedError, Sendable {
    case emptyResponse
    case invalidJSON
    case missingActionID
    case missingScrollDelta

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Model returned an empty response."
        case .invalidJSON:
            return "Model returned invalid JSON."
        case .missingActionID:
            return "Model returned a click action without an id."
        case .missingScrollDelta:
            return "Model returned a scroll action without a dy value."
        }
    }
}

struct AgentParser {
    struct RawActionPlan: Decodable {
        struct RawAction: Decodable {
            let type: String?
            let id: String?
            let dx: Double?
            let dy: Double?
            let selector: String?
            let mode: String?
        }

        let actions: [RawAction]
        let notes: String?
    }

    func parseActionPlan(from text: String) throws -> ActionPlan {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentParserError.emptyResponse
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw AgentParserError.invalidJSON
        }
        let rawPlan: RawActionPlan
        do {
            rawPlan = try JSONDecoder().decode(RawActionPlan.self, from: data)
        } catch {
            throw AgentParserError.invalidJSON
        }

        let parsedActions = try rawPlan.actions.compactMap { rawAction -> AgentAction? in
            guard let type = rawAction.type?.lowercased() else {
                return nil
            }
            switch type {
            case "click":
                guard let id = rawAction.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                    throw AgentParserError.missingActionID
                }
                return AgentAction(type: .click, id: id, dx: nil, dy: nil, selector: nil, mode: nil)
            case "scroll":
                guard let dy = rawAction.dy, dy.isFinite else {
                    throw AgentParserError.missingScrollDelta
                }
                let mode = rawAction.mode.flatMap { AgentAction.ScrollMode(rawValue: $0.lowercased()) }
                let selector = rawAction.selector?.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedSelector = selector?.isEmpty == false ? selector : nil
                return AgentAction(
                    type: .scroll,
                    id: rawAction.id?.trimmingCharacters(in: .whitespacesAndNewlines),
                    dx: rawAction.dx,
                    dy: dy,
                    selector: normalizedSelector,
                    mode: mode
                )
            default:
                return nil
            }
        }

        let action = parsedActions.first
        return ActionPlan(actions: action.map { [$0] } ?? [], notes: rawPlan.notes)
    }
}
