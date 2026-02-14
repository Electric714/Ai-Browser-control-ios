import WebKit

extension WKWebView {
    override open var safeAreaInsets: UIEdgeInsets { .zero }
}

extension WKWebViewConfiguration {
    @MainActor
    static var forTelescopure: WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let jsExceptionBridge = #"""
        (function() {
          if (window.__aiJsExceptionBridgeInstalled) {
            return;
          }
          window.__aiJsExceptionBridgeInstalled = true;

          function post(payload) {
            try {
              const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsException;
              if (!handler || !handler.postMessage) {
                return;
              }
              handler.postMessage(payload);
            } catch (_) {}
          }

          const previousOnError = window.onerror;
          window.onerror = function(message, source, lineno, colno, error) {
            post({
              message: String(message || "UnknownError"),
              source: source || null,
              line: lineno == null ? null : Number(lineno),
              column: colno == null ? null : Number(colno),
              stack: error && error.stack ? String(error.stack) : null
            });
            if (typeof previousOnError === 'function') {
              return previousOnError.apply(this, arguments);
            }
            return false;
          };

          window.addEventListener('unhandledrejection', function(event) {
            post({
              message: 'UnhandledPromiseRejection',
              source: null,
              line: null,
              column: null,
              stack: event && event.reason && event.reason.stack
                ? String(event.reason.stack)
                : String((event && event.reason) || 'unknown')
            });
          });
        })();
        """#
        let script = WKUserScript(source: jsExceptionBridge, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(script)
        configuration.userContentController = controller
        configuration.allowsInlinePredictions = true
        return configuration
    }
}
