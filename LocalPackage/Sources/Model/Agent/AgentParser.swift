import Foundation

enum AgentParserError: LocalizedError, Sendable {
    case emptyResponse
    case invalidJSON
    case missingActionID

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Model returned an empty response."
        case .invalidJSON:
            return "Model returned invalid JSON."
        case .missingActionID:
            return "Model returned a click action without an id."
        }
    }
}

struct AgentParser {
    struct RawActionPlan: Decodable {
        struct RawAction: Decodable {
            let type: String?
            let id: String?
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

        let actions = try rawPlan.actions.compactMap { rawAction -> AgentAction? in
            guard let type = rawAction.type?.lowercased() else {
                return nil
            }
            guard type == "click" else {
                return nil
            }
            guard let id = rawAction.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                throw AgentParserError.missingActionID
            }
            return AgentAction(type: .click, id: id)
        }

        return ActionPlan(actions: actions, notes: rawPlan.notes)
    }
}
