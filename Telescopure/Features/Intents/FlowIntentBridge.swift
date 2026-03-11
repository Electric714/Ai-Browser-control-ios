import Foundation

struct FlowIntentBridge {
    func runFlow(named name: String, inputs: [String: String]) async -> String {
        "AppIntents hook scaffolded for flow=\(name)"
    }
}
