import Foundation

protocol AIService {
    func suggestLocatorRepair(for failedStep: FlowStep, logs: [String]) async throws -> Locator?
}

struct NoopAIService: AIService {
    func suggestLocatorRepair(for failedStep: FlowStep, logs: [String]) async throws -> Locator? { nil }
}
