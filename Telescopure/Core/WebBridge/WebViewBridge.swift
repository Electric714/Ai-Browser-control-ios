import Foundation
import WebKit

@MainActor
final class WebViewBridge: NSObject, ObservableObject {
    @Published var pageTitle: String = "WebPuppet"
    @Published var currentURL: String = "https://example.com"
    @Published var capturedPayloads: [ClickedElementPayload] = []

    private weak var webView: WKWebView?
    private let logStore: LogStore
    var onElementClick: ((ClickedElementPayload) -> Void)?

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func load(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView?.load(URLRequest(url: url))
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func injectRecorderScript(recording: Bool) {
        let escaped = recording ? "true" : "false"
        webView?.evaluateJavaScript("window.__webPuppetSetRecording(\(escaped));")
    }

    func evaluate(_ js: String) async throws -> Any? {
        try await webView?.evaluateJavaScript(js)
    }

    func addCapturedPayload(_ payload: ClickedElementPayload) {
        capturedPayloads.append(payload)
        onElementClick?(payload)
    }

    func log(_ message: String) {
        logStore.add(message)
    }
}
