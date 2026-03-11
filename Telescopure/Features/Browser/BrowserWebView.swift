import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var bridge: WebViewBridge

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "writeLog")
        contentController.add(context.coordinator, name: "didClickElement")

        if let scriptURL = Bundle.main.url(forResource: "Recorder", withExtension: "js", subdirectory: "Resources/InjectedJS"),
           let scriptSource = try? String(contentsOf: scriptURL) {
            let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            contentController.addUserScript(userScript)
        }

        config.userContentController = contentController
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        bridge.attach(webView: webView)
        bridge.load(urlString: bridge.currentURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let bridge: WebViewBridge

        init(bridge: WebViewBridge) {
            self.bridge = bridge
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "writeLog", let text = message.body as? String {
                bridge.log("JS: \(text)")
            }

            guard message.name == "didClickElement",
                  let object = message.body as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let payload = try? JSONDecoder().decode(ClickedElementPayload.self, from: data) else { return }
            bridge.addCapturedPayload(payload)
            bridge.log("Captured \(payload.tagName ?? "element")")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            bridge.pageTitle = webView.title ?? "WebPuppet"
            bridge.currentURL = webView.url?.absoluteString ?? bridge.currentURL
        }
    }
}
