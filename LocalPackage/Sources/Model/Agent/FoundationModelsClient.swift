import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsClient {
    struct Result: Sendable {
        let rawText: String
        let plan: ActionPlan
    }

    enum ClientError: LocalizedError, Sendable {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case let .unavailable(message):
                return message
            }
        }
    }

    func availabilityMessage() -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return nil
            case let .unavailable(reason):
                return unavailableReasonDescription(reason)
            @unknown default:
                return "Apple Intelligence is not available on this device."
            }
        } else {
            return "Apple Intelligence requires iOS 26 or later."
        }
        #else
        return "Apple Intelligence is not available in this build."
        #endif
    }

    func generateActionPlan(
        instruction: String,
        clickMap: PageSnapshot,
        allowSensitiveClicks: Bool
    ) async throws -> Result {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let message = availabilityMessage() {
                throw ClientError.unavailable(message)
            }

            let clickMapText = try encodeClickMap(clickMap)
            let systemPrompt = """
            You control an in-app browser and must return strict JSON only (no markdown, no prose).
            Use only the provided clickMap ids; prefer id-based actions.
            Output one of:
            {"actions":[...]} or {"error":"..."}.
            Allowed actions: click, type, scroll, wait, navigate, ask_user, done.
            For wait use {"type":"wait","ms":<integer 50..15000>} only; never use seconds or strings.
            Ask for clarification with {"actions":[{"type":"ask_user","question":"..."}]} when uncertain.
            Never click pay/checkout/confirm purchase unless allowSensitiveClicks is true.
            """

            let userPrompt = """
            Instruction: \(instruction)
            Page: \(clickMap.url) (title: \(clickMap.title))
            allowSensitiveClicks: \(allowSensitiveClicks)
            Click map JSON: \(clickMapText)
            """

            let session = LanguageModelSession(
                model: .default,
                instructions: Instructions(systemPrompt)
            )
            let response = try await session.respond(generating: ActionPlanGeneration.self) {
                Prompt(userPrompt)
            }
            let jsonString = response.rawContent.jsonString
            let plan = try AgentParser().parseActionPlan(from: jsonString, clickMap: clickMap)
            return Result(rawText: jsonString, plan: plan)
        } else {
            throw ClientError.unavailable("Apple Intelligence requires iOS 26 or later.")
        }
        #else
        throw ClientError.unavailable("Apple Intelligence is not available in this build.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func unavailableReasonDescription(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off in Settings."
        case .deviceNotEligible:
            return "This device doesn’t support Apple Intelligence."
        case .modelNotReady:
            return "Apple Intelligence is not ready yet."
        @unknown default:
            return "Apple Intelligence is not available on this device."
        }
    }
    #endif

    private func encodeClickMap(_ clickMap: PageSnapshot) throws -> String {
        let data = try JSONEncoder().encode(clickMap)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct ActionPlanGeneration: Sendable {
    @Guide(description: "List of actions to perform on the page.")
    let actions: [ActionPlanAction]
    @Guide(description: "Optional notes about the plan.")
    let notes: String?
    @Guide(description: "Optional reasoning about why actions were chosen.")
    let reasoning: String?
    @Guide(description: "Error message when the request cannot be satisfied.")
    let error: String?
}

@available(iOS 26.0, *)
@Generable
private struct ActionPlanAction: Sendable {
    @Guide(description: "Action type: click, type, scroll, wait, navigate, ask_user, done.")
    let type: ActionPlanActionType
    @Guide(description: "Clickable id for click or type.")
    let id: String?
    @Guide(description: "CSS selector for type actions when id is not available.")
    let selector: String?
    @Guide(description: "Text to type for type actions.")
    let text: String?
    @Guide(description: "Scroll direction: up or down.")
    let direction: ActionPlanScrollDirection?
    @Guide(description: "Scroll amount in pixels (50-2000).")
    let amount: Int?
    @Guide(description: "Wait duration in milliseconds (50-15000).")
    let ms: Int?
    @Guide(description: "URL to navigate to for navigate actions.")
    let url: String?
    @Guide(description: "Question for ask_user actions.")
    let question: String?
    @Guide(description: "Summary for done actions.")
    let summary: String?
}

@available(iOS 26.0, *)
@Generable
private enum ActionPlanActionType: String, Sendable {
    case click
    case type
    case scroll
    case wait
    case navigate
    case ask_user
    case done
}

@available(iOS 26.0, *)
@Generable
private enum ActionPlanScrollDirection: String, Sendable {
    case up
    case down
}
#endif
