import Foundation

@MainActor
final class FlowRunner {
    private let bridge: WebViewBridge
    private let logs: LogStore

    init(bridge: WebViewBridge, logs: LogStore) {
        self.bridge = bridge
        self.logs = logs
    }

    func run(flow: Flow, inputs: [String: String] = [:]) async -> FlowRunResult {
        var output: [String: String] = [:]
        var runLogs: [String] = []

        bridge.load(urlString: flow.startURL)
        try? await Task.sleep(for: .seconds(2))

        for step in flow.steps.sorted(by: { $0.order < $1.order }) {
            do {
                switch step.type {
                case .wait:
                    try await Task.sleep(for: .milliseconds(step.options.delayMilliseconds))
                    try await log("Waited \(step.options.delayMilliseconds)ms", runLogs: &runLogs)
                case .click:
                    let js = "window.__webPuppetReplay.click(\(locatorJSON(step.locator)));"
                    _ = try await bridge.evaluate(js)
                    try await log("Clicked step \(step.order)", runLogs: &runLogs)
                case .typeText:
                    let text = step.inputBindingKey.flatMap { inputs[$0] } ?? step.inputValue ?? ""
                    let escaped = text.replacingOccurrences(of: "'", with: "\\'")
                    let js = "window.__webPuppetReplay.typeText(\(locatorJSON(step.locator)), '\(escaped)');"
                    _ = try await bridge.evaluate(js)
                    try await log("Typed text at step \(step.order)", runLogs: &runLogs)
                case .extractText:
                    let js = "window.__webPuppetReplay.extractText(\(locatorJSON(step.locator)));"
                    let result = try await bridge.evaluate(js) as? String ?? ""
                    if let outputKey = step.outputKey {
                        output[outputKey] = result
                    }
                    try await log("Extracted text '\(result)'", runLogs: &runLogs)
                }
            } catch {
                let failure = "Step \(step.order) failed: \(error.localizedDescription)"
                logs.add(failure)
                runLogs.append(failure)
                if !step.options.continueOnFailure {
                    return FlowRunResult(success: false, logs: runLogs, outputs: output, failedStepIndex: step.order)
                }
            }
        }

        return FlowRunResult(success: true, logs: runLogs, outputs: output, failedStepIndex: nil)
    }

    private func locatorJSON(_ locator: Locator?) -> String {
        guard let locator, let data = try? JSONEncoder().encode(locator), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func log(_ text: String, runLogs: inout [String]) async throws {
        logs.add(text)
        runLogs.append(text)
        try await Task.sleep(for: .milliseconds(200))
    }
}
