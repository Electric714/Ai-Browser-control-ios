import Foundation

struct Flow: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var startURL: String
    var steps: [FlowStep] = []
    var inputDefinitions: [FlowInputDefinition] = []
    var outputDefinitions: [FlowOutputDefinition] = []
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

struct FlowStep: Identifiable, Codable, Hashable {
    enum StepType: String, Codable, CaseIterable {
        case click
        case typeText
        case wait
        case extractText
    }

    var id: UUID = UUID()
    var order: Int
    var type: StepType
    var locator: Locator?
    var inputValue: String?
    var inputBindingKey: String?
    var outputKey: String?
    var options: StepOptions = .init()
}

struct StepOptions: Codable, Hashable {
    var continueOnFailure: Bool = false
    var delayMilliseconds: Int = 1200
}

struct Locator: Codable, Hashable {
    var primaryCSSSelector: String?
    var elementID: String?
    var tagName: String?
    var classes: [String] = []
    var ariaLabel: String?
    var dataAttributes: [String: String] = [:]
    var textSnippet: String?
    var siblingIndex: Int?
    var parentTrail: [String] = []
    var framePath: [String] = []
    var shadowHostID: String?
}

struct FlowInputDefinition: Codable, Hashable {
    enum InputType: String, Codable, Hashable, CaseIterable {
        case text, number, boolean, barcode
    }

    var key: String
    var type: InputType
    var defaultValue: String?
    var required: Bool
}

struct FlowOutputDefinition: Codable, Hashable {
    enum OutputType: String, Codable, Hashable, CaseIterable {
        case text, number, boolean
    }

    var key: String
    var type: OutputType
    var extractionRule: String
}

struct FlowRunResult: Codable, Hashable {
    var success: Bool
    var logs: [String]
    var outputs: [String: String]
    var failedStepIndex: Int?
}

struct ClickedElementPayload: Codable, Hashable {
    var cssSelector: String?
    var elementID: String?
    var tagName: String?
    var classes: [String]
    var ariaLabel: String?
    var dataAttributes: [String: String]
    var textSnippet: String?
    var siblingIndex: Int?
    var parentTrail: [String]
    var framePath: [String]
    var shadowHostID: String?
    var outerHTML: String?
    var inputValue: String?
}
