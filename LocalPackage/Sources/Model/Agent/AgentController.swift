import Combine
import Foundation
import os
import WebUI
import WebKit

@MainActor
public final class AgentController: ObservableObject {
    private enum AgentError: LocalizedError {
        case missingAPIKey
        case missingWebView
        case webViewNotLaidOut(CGSize)
        case webViewNotInWindow
        case webViewLoading(URL?)
        case pageNotReady(URL?)
        case invalidResponse
        case missingClickable
        case blockedSensitiveAction(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add an OpenRouter API key to run AI click control."
            case .missingWebView:
                return "No active web view is available for click mapping."
            case let .webViewNotLaidOut(size):
                return "Cannot extract click map: web view bounds are zero (\(Int(size.width))x\(Int(size.height)))."
            case .webViewNotInWindow:
                return "Cannot extract click map: the web view is not attached to a window."
            case let .webViewLoading(url):
                return "Cannot extract click map: the page is still loading (\(url?.absoluteString ?? "unknown URL"))."
            case let .pageNotReady(url):
                return "Cannot extract click map: the page did not finish loading in time (\(url?.absoluteString ?? "unknown URL"))."
            case .invalidResponse:
                return "Model returned invalid JSON."
            case .missingClickable:
                return "Model chose a missing clickable element."
            case let .blockedSensitiveAction(label):
                return "Blocked sensitive click for \"\(label)\". Enable sensitive clicks to continue."
            case .cancelled:
                return nil
            }
        }
    }

    private let openRouterClient: OpenRouterClient
    private let clickMapService: ClickMapService
    private let webViewRegistry: ActiveWebViewRegistry
    private var registryCancellable: AnyCancellable?
    private let keychainStore = KeychainStore()
    private let logger = Logger(subsystem: "Agent", category: "ClickMap")
    private let sensitiveClickTerms = ["pay", "purchase", "checkout", "transfer", "send money"]

    private var webViewProxy: WebViewProxy?
    private var runTask: Task<Void, Never>?
    private let maxActionsPerRun = 3

    @Published public var command: String
    @Published public var isAgentModeEnabled: Bool
    @Published public var allowSensitiveClicks: Bool
    @Published public var isRunning: Bool
    @Published public private(set) var logs: [AgentLogEntry]
    @Published public private(set) var lastModelOutput: String?
    @Published public private(set) var lastActionSummary: String?
    @Published public private(set) var lastClickablesCount: Int
    @Published public private(set) var lastError: String?
    @Published public private(set) var isWebViewAvailable: Bool

    public var activeWebViewIdentifier: ObjectIdentifier? {
        webViewRegistry.currentIdentifier()
    }
    @Published public var apiKey: String {
        didSet {
            _ = keychainStore.save(key: "openRouterAPIKey", value: apiKey)
        }
    }

    public init(command: String = "", isAgentModeEnabled: Bool = false, webViewRegistry: ActiveWebViewRegistry = .shared) {
        self.openRouterClient = OpenRouterClient()
        self.clickMapService = ClickMapService()
        self.webViewRegistry = webViewRegistry
        self.command = command
        self.isAgentModeEnabled = isAgentModeEnabled
        self.allowSensitiveClicks = false
        self.isRunning = false
        self.logs = []
        self.lastModelOutput = nil
        self.lastActionSummary = nil
        self.lastClickablesCount = 0
        self.lastError = nil
        self.apiKey = keychainStore.load(key: "openRouterAPIKey") ?? ""
        self.isWebViewAvailable = false
        registryCancellable = webViewRegistry.$webView.sink { [weak self] webView in
            guard let self else { return }
            self.refreshWebViewAvailability()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                self?.refreshWebViewAvailability()
            }
            #if DEBUG
            if let webView {
                self.logger.debug("Observed web view set id=\(ObjectIdentifier(webView))")
            } else {
                self.logger.debug("Observed web view cleared")
            }
            #endif
        }
    }

    public func attach(proxy: WebViewProxy) {
        self.webViewProxy = proxy
        webViewRegistry.update(from: proxy)
        refreshWebViewAvailability()
    }

    public func toggleAgentMode(_ enabled: Bool) {
        isAgentModeEnabled = enabled
        appendLog(.init(date: Date(), kind: .info, message: "AI click control \(enabled ? "enabled" : "disabled")"))
    }

    public func runCommand() {
        runTask?.cancel()
        lastError = nil
        lastActionSummary = nil
        runTask = Task { [weak self] in
            await self?.executeCommand()
        }
    }

    public func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        appendLog(.init(date: Date(), kind: .info, message: "AI click control stopped"))
    }

    private func executeCommand() async {
        guard isAgentModeEnabled else {
            appendLog(.init(date: Date(), kind: .warning, message: "Enable AI click control to start"))
            return
        }
        guard !command.isEmpty else {
            appendLog(.init(date: Date(), kind: .warning, message: "Enter a command for the AI"))
            return
        }
        guard isWebViewAvailable else {
            appendLog(.init(date: Date(), kind: .warning, message: "Web view is not ready"))
            return
        }
        guard !apiKey.isEmpty else {
            handleError(AgentError.missingAPIKey)
            return
        }
        guard let webView = currentWebView() else {
            handleError(AgentError.missingWebView)
            return
        }

        isRunning = true
        defer { isRunning = false }

        do {
            try await waitForWebViewReadiness(webView)
            let clickMap = try await clickMapService.extractClickMap(webView: webView)
            lastClickablesCount = clickMap.clickables.count

            let requestId = UUID().uuidString
            appendLog(.init(date: Date(), kind: .info, message: "Sending OpenRouter request id=\(requestId) key=\(redactedKey(apiKey))"))
            let payloadPreview = openRouterClient.payloadPreview(instruction: command, clickMap: clickMap, allowSensitiveClicks: allowSensitiveClicks)
            appendLog(.init(date: Date(), kind: .info, message: "OpenRouter payload preview: \(payloadPreview)"))
            let result = try await openRouterClient.generateActionPlan(
                apiKey: apiKey,
                requestId: requestId,
                instruction: command,
                clickMap: clickMap,
                allowSensitiveClicks: allowSensitiveClicks
            )
            appendLog(.init(date: Date(), kind: .info, message: "OpenRouter response id=\(result.requestId) status=\(result.statusCode) bytes=\(result.responseBytes) latency=\(result.latencyMs)ms"))
            lastModelOutput = result.rawText
            appendLog(.init(date: Date(), kind: .model, message: result.rawText))

            let plan = try AgentParser().parseActionPlan(from: result.rawText, clickMap: clickMap)
            if let error = plan.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                appendLog(.init(date: Date(), kind: .warning, message: "Model error: \(error)"))
                return
            }

            let actions = plan.actions ?? []
            guard !actions.isEmpty else {
                appendLog(.init(date: Date(), kind: .warning, message: "No actions returned"))
                return
            }

            let executedActions = try await executeActions(actions, clickMap: clickMap, webView: webView)
            if !executedActions.isEmpty {
                lastActionSummary = executedActions.joined(separator: "; ")
            }
        } catch AgentError.cancelled {
            appendLog(.init(date: Date(), kind: .warning, message: "Cancelled"))
        } catch let error as OpenRouterClient.OpenRouterClientError {
            appendLog(.init(date: Date(), kind: .error, message: error.localizedDescription))
        } catch let error as AgentParserError {
            handleError(error)
        } catch let error as AgentError {
            handleError(error)
        } catch {
            handleError(error)
        }
    }

    private func blockedLabel(for label: String) -> String? {
        guard !allowSensitiveClicks else { return nil }
        let lowered = label.lowercased()
        if let match = sensitiveClickTerms.first(where: { lowered.contains($0) }) {
            return match
        }
        return nil
    }

    private func currentWebView() -> WKWebView? {
        if let resolved = webViewRegistry.current() {
            return resolved
        }
        if let proxy = webViewProxy {
            webViewRegistry.update(from: proxy)
            return webViewRegistry.current()
        }
        return nil
    }

    private func refreshWebViewAvailability() {
        let view = webViewRegistry.current()
        isWebViewAvailable = (view != nil && view?.window != nil)
    }

    private func waitForWebViewReadiness(_ webView: WKWebView) async throws {
        let timeout: Duration = .seconds(5)
        let interval: Duration = .milliseconds(150)
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while true {
            if Task.isCancelled { throw AgentError.cancelled }

            let size = webView.bounds.size
            let isLoading = webView.isLoading
            let readyState = try? await webView.evalJSString("document.readyState")
            let isReady = readyState == nil || readyState == "complete" || readyState == "interactive"

            if size != .zero, !isLoading, isReady {
                return
            }

            if ContinuousClock.now >= deadline {
                logWebViewState(prefix: "click map: readiness timeout", webView: webView)
                if size == .zero {
                    throw AgentError.webViewNotLaidOut(size)
                }
                if isLoading {
                    throw AgentError.webViewLoading(webView.url)
                }
                throw AgentError.pageNotReady(webView.url)
            }

            try await Task.sleep(for: interval)
        }
    }

    private func waitForPageReady(_ webView: WKWebView, timeout: Duration = .seconds(6)) async throws {
        let interval: Duration = .milliseconds(200)
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while true {
            if Task.isCancelled { throw AgentError.cancelled }

            let isLoading = webView.isLoading
            let readyState = try? await webView.evalJSString("document.readyState")
            let isReady = readyState == nil || readyState == "complete" || readyState == "interactive"

            if !isLoading, isReady {
                return
            }

            if ContinuousClock.now >= deadline {
                logWebViewState(prefix: "action readiness timeout", webView: webView)
                throw AgentError.pageNotReady(webView.url)
            }

            try await Task.sleep(for: interval)
        }
    }

    private func logWebViewState(prefix: String, webView: WKWebView?) {
        let url = webView?.url?.absoluteString ?? "nil"
        let title = webView?.title ?? "nil"
        let isLoading = webView?.isLoading ?? false
        let bounds = webView?.bounds ?? .zero
        let identifier = webView.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        logger.debug("\(prefix, privacy: .public) id=\(identifier, privacy: .public) url=\(url, privacy: .public) title=\(title, privacy: .public) loading=\(isLoading) bounds=\(String(describing: bounds), privacy: .public)")
    }

    private func redactedKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return "****" }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    private func executeActions(_ actions: [AgentAction], clickMap: PageSnapshot, webView: WKWebView) async throws -> [String] {
        var summaries: [String] = []
        var currentMap = clickMap

        for action in actions.prefix(maxActionsPerRun) {
            if Task.isCancelled { throw AgentError.cancelled }

            switch action.type {
            case .click:
                guard let id = action.id else { throw AgentError.missingClickable }
                guard let clickable = currentMap.clickables.first(where: { $0.id == id }) else {
                    throw AgentError.missingClickable
                }
                if let blocked = blockedLabel(for: clickable.label) {
                    throw AgentError.blockedSensitiveAction(blocked)
                }
                currentMap = try await clickMapService.executeClick(id: id, webView: webView)
                summaries.append("clicked \(id): \"\(clickable.label)\"")
                appendLog(.init(date: Date(), kind: .action, message: "Clicked \(id)"))
                lastClickablesCount = currentMap.clickables.count
                try await waitForPageReady(webView)
            case .type:
                let id = action.id
                let selector = action.selector
                let text = action.text ?? ""
                try await clickMapService.typeText(id: id, selector: selector, text: text, webView: webView)
                summaries.append("typed \"\(text)\"")
                appendLog(.init(date: Date(), kind: .action, message: "Typed text (\(text.count) chars)"))
                currentMap = try await clickMapService.extractClickMap(webView: webView)
                lastClickablesCount = currentMap.clickables.count
                try await waitForPageReady(webView)
            case .scroll:
                let direction = action.direction ?? .down
                let amount = action.amount ?? 0
                try await clickMapService.scroll(direction: direction, amount: amount, webView: webView)
                summaries.append("scrolled \(direction.rawValue) \(amount)")
                appendLog(.init(date: Date(), kind: .action, message: "Scrolled \(direction.rawValue) \(amount)"))
                currentMap = try await clickMapService.extractClickMap(webView: webView)
                lastClickablesCount = currentMap.clickables.count
                try await waitForPageReady(webView)
            case .wait:
                let ms = action.ms ?? 0
                appendLog(.init(date: Date(), kind: .action, message: "Waiting \(ms)ms"))
                try await Task.sleep(for: .milliseconds(ms))
                summaries.append("waited \(ms)ms")
            case .navigate:
                guard let urlString = action.url, let url = URL(string: urlString) else {
                    throw AgentParserError.invalidAction("navigate missing url")
                }
                appendLog(.init(date: Date(), kind: .action, message: "Navigating to \(urlString)"))
                await clickMapService.navigate(to: url, webView: webView)
                try await waitForPageReady(webView, timeout: .seconds(10))
                currentMap = try await clickMapService.extractClickMap(webView: webView)
                lastClickablesCount = currentMap.clickables.count
                summaries.append("navigated to \(urlString)")
            case .ask_user:
                let question = action.question ?? "Need clarification."
                appendLog(.init(date: Date(), kind: .result, message: question))
                summaries.append("asked user: \(question)")
                return summaries
            case .done:
                let summary = action.summary ?? "Done."
                appendLog(.init(date: Date(), kind: .result, message: summary))
                summaries.append(summary)
                return summaries
            }
        }
        return summaries
    }

    private func handleError(_ error: Error) {
        let message = (error as? AgentError)?.errorDescription ?? error.localizedDescription
        if !message.isEmpty {
            lastError = message
            appendLog(.init(date: Date(), kind: .error, message: message))
        }
    }

    private func appendLog(_ entry: AgentLogEntry) {
        logs.append(entry)
    }
}
