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
        case invalidAction
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
            case .invalidAction:
                return "Model returned an unsupported action."
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
                await self?.refreshWebViewAvailability()
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

    deinit {
        registryCancellable?.cancel()
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

            let result = try await openRouterClient.generateActionPlan(apiKey: apiKey, instruction: command, clickMap: clickMap)
            lastModelOutput = result.rawText
            appendLog(.init(date: Date(), kind: .model, message: result.rawText))

            guard let action = result.plan.actions.first else {
                appendLog(.init(date: Date(), kind: .warning, message: "No actions returned"))
                return
            }
            guard action.type.lowercased() == "click" else {
                throw AgentError.invalidAction
            }
            guard let clickable = clickMap.clickables.first(where: { $0.id == action.id }) else {
                throw AgentError.missingClickable
            }
            if let blocked = blockedLabel(for: clickable.label) {
                throw AgentError.blockedSensitiveAction(blocked)
            }

            try await clickMapService.click(id: action.id, webView: webView)
            lastActionSummary = "clicked \(action.id): \"\(clickable.label)\""
            appendLog(.init(date: Date(), kind: .action, message: "Clicked \(action.id)"))

            let refreshed = try await clickMapService.extractClickMap(webView: webView)
            lastClickablesCount = refreshed.clickables.count
        } catch AgentError.cancelled {
            appendLog(.init(date: Date(), kind: .warning, message: "Cancelled"))
        } catch let error as OpenRouterClient.OpenRouterClientError {
            switch error {
            case .invalidJSON, .emptyResponse:
                handleError(AgentError.invalidResponse)
            }
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
            let readyState = try? await webView.evalJS("document.readyState") as? String

            if size != .zero, !isLoading, readyState == nil || readyState == "complete" || readyState == "interactive" {
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

    private func logWebViewState(prefix: String, webView: WKWebView?) {
        let url = webView?.url?.absoluteString ?? "nil"
        let title = webView?.title ?? "nil"
        let isLoading = webView?.isLoading ?? false
        let bounds = webView?.bounds ?? .zero
        let identifier = webView.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        logger.debug("\(prefix, privacy: .public) id=\(identifier, privacy: .public) url=\(url, privacy: .public) title=\(title, privacy: .public) loading=\(isLoading) bounds=\(String(describing: bounds), privacy: .public)")
    }

    private func handleError(_ error: Error) {
        let message = (error as? AgentError)?.errorDescription ?? error.localizedDescription
        if let message {
            lastError = message
            appendLog(.init(date: Date(), kind: .error, message: message))
        }
    }

    private func appendLog(_ entry: AgentLogEntry) {
        logs.append(entry)
    }
}
