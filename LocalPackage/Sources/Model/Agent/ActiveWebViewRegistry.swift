import Combine
import os
import WebUI
import WebKit

@MainActor
public final class ActiveWebViewRegistry: ObservableObject {
    public static let shared = ActiveWebViewRegistry()

    @Published public private(set) var webView: WKWebView? {
        didSet {
            #if DEBUG
            if let webView {
                logger.debug("Active web view set id=\(ObjectIdentifier(webView))")
            } else {
                logger.debug("Active web view cleared")
            }
            #endif
        }
    }

    private let logger = Logger(subsystem: "Agent", category: "WebViewStore")

    public init() {}

    public func set(_ webView: WKWebView?) {
        self.webView = webView
    }

    public func current() -> WKWebView? {
        webView
    }

    public func update(from proxy: WebViewProxy) {
        if let resolved = extractWebView(from: proxy) {
            set(resolved)
        }
    }

    public func currentIdentifier() -> ObjectIdentifier? {
        webView.map(ObjectIdentifier.init)
    }

    private func extractWebView(from proxy: WebViewProxy) -> WKWebView? {
        var visited = Set<ObjectIdentifier>()
        return findWKWebView(in: proxy, visited: &visited, depth: 12)
    }

    private func findWKWebView(in value: Any, visited: inout Set<ObjectIdentifier>, depth: Int) -> WKWebView? {
        if let webView = value as? WKWebView {
            return webView
        }
        guard depth > 0 else { return nil }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .class {
            let identifier = ObjectIdentifier(value as AnyObject)
            guard !visited.contains(identifier) else { return nil }
            visited.insert(identifier)
        }

        for child in mirror.children {
            if let found = findWKWebView(in: child.value, visited: &visited, depth: depth - 1) {
                return found
            }
        }
        return nil
    }
}
