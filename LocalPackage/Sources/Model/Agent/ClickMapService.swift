import Foundation
import os
import WebKit

struct ClickRect: Codable, Sendable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct Clickable: Codable, Sendable {
    let id: String
    let role: String
    let label: String
    let rect: ClickRect
    let href: String?
    let tag: String
    let disabled: Bool
}

struct PageSnapshot: Codable, Sendable {
    let url: String
    let title: String
    let clickables: [Clickable]
}

enum ClickMapError: Error {
    case jsReturnedNil
    case decodeFailed
    case elementNotFound
    case invalidTarget
}

@MainActor
final class ClickMapService {
    private let defaultSelector = "a[href],button,input,textarea,[contenteditable],[onclick],[role=\"button\"],[role=\"link\"]"
    private let logger = Logger(subsystem: "Agent", category: "ClickMap")

    private func escapeJSString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func extractJS(selector: String) -> String {
        let escapedSelector = escapeJSString(selector)
        return #"""
        (function() {
          const selector = "\#(escapedSelector)";
          const els = Array.from(document.querySelectorAll(selector));
          const w = window.innerWidth || 1;
          const h = window.innerHeight || 1;

          function labelFor(el) {
            const aria = el.getAttribute('aria-label');
            if (aria && aria.trim()) return aria.trim();
            const labelledBy = el.getAttribute('aria-labelledby');
            if (labelledBy && labelledBy.trim()) {
              const labelEl = document.getElementById(labelledBy.trim());
              const labelText = labelEl ? (labelEl.innerText || '').trim() : '';
              if (labelText) return labelText;
            }
            if (el.labels && el.labels.length) {
              const labelText = Array.from(el.labels).map(l => (l.innerText || '').trim()).filter(Boolean).join(' ');
              if (labelText) return labelText;
            }
            const placeholder = (el.getAttribute('placeholder') || '').trim();
            if (placeholder) return placeholder;
            const name = (el.getAttribute('name') || '').trim();
            if (name) return name;
            const txt = (el.innerText || '').trim();
            if (txt) return txt;
            const val = (el.value || '').trim();
            if (val) return val;
            const title = (el.getAttribute('title') || '').trim();
            if (title) return title;
            const alt = (el.getAttribute('alt') || '').trim();
            if (alt) return alt;
            const href = (el.getAttribute('href') || '').trim();
            if (href) return href;
            return '';
          }

          function isVisible(el, r) {
            if (!r || r.width <= 0 || r.height <= 0) return false;
            const cs = window.getComputedStyle(el);
            if (!cs) return false;
            if (cs.display === 'none') return false;
            if (cs.visibility === 'hidden') return false;
            if (cs.pointerEvents === 'none') return false;
            const op = parseFloat(cs.opacity || '1');
            if (isNaN(op) || op <= 0.05) return false;
            if (r.bottom < 0 || r.right < 0 || r.top > h || r.left > w) return false;
            return true;
          }

          function isInteractable(el) {
            if (el.disabled) return false;
            if (el.getAttribute('aria-disabled') === 'true') return false;
            return true;
          }

          function clamp01(value) {
            return Math.max(0, Math.min(1, value));
          }

          const usedIds = new Set();
          let maxId = 0;
          for (const el of els) {
            const existing = el.dataset.aiId;
            if (existing) {
              usedIds.add(existing);
              const match = existing.match(/^e(\d+)$/);
              if (match) {
                const num = parseInt(match[1], 10);
                if (!isNaN(num)) {
                  maxId = Math.max(maxId, num);
                }
              }
            }
          }

          const clickables = [];

          for (const el of els) {
            const r = el.getBoundingClientRect();
            if (!isVisible(el, r)) continue;
            if (!isInteractable(el)) continue;

            const tag = (el.tagName || '').toUpperCase();
            const typeAttr = (el.getAttribute('type') || '').toLowerCase();
            if (tag === 'INPUT' && (typeAttr === 'hidden' || typeAttr === 'password')) {
              continue;
            }
            if (el.hasAttribute('contenteditable') && el.getAttribute('contenteditable') === 'false') {
              continue;
            }

            if (!el.dataset.aiId) {
              do {
                maxId += 1;
              } while (usedIds.has('e' + maxId));
              const newId = 'e' + maxId;
              el.dataset.aiId = newId;
              usedIds.add(newId);
            }

            const roleAttr = (el.getAttribute('role') || '').toLowerCase();
            const role = roleAttr || (el.isContentEditable ? 'contenteditable'
              : (tag === 'TEXTAREA' ? 'textarea'
                : (tag === 'INPUT' && !['button','submit','reset','checkbox','radio','file','range','color','image'].includes(typeAttr) ? 'textbox'
                  : (tag === 'A' ? 'link' : (tag === 'BUTTON' ? 'button' : (tag === 'INPUT' && ['button','submit','reset','image'].includes(typeAttr) ? 'button' : (tag === 'INPUT' ? 'input' : 'other'))))));
            const disabled = !!(el.disabled || el.getAttribute('aria-disabled') === 'true');
            const href = (el.getAttribute('href') || '').trim() || null;
            const label = labelFor(el);

            const rect = {
              x: clamp01(r.left / w),
              y: clamp01(r.top / h),
              w: clamp01(r.width / w),
              h: clamp01(r.height / h)
            };

            clickables.push({
              id: el.dataset.aiId,
              role,
              label,
              rect,
              href,
              tag,
              disabled
            });
          }

          const payload = {
            url: String(location.href || ''),
            title: String(document.title || ''),
            clickables
          };

          return JSON.stringify(payload);
        })();
        """#
    }

    func extractClickMap(webView: WKWebView, selector: String? = nil) async throws -> PageSnapshot {
        let js = extractJS(selector: selector ?? defaultSelector)
        let json = try await webView.evalJSString(js)
        guard let data = json.data(using: .utf8) else { throw ClickMapError.decodeFailed }
        let snapshot = try JSONDecoder().decode(PageSnapshot.self, from: data)
        #if DEBUG
        let typeableRoles: Set<String> = ["textbox", "input", "textarea", "contenteditable"]
        let typeables = snapshot.clickables.filter { typeableRoles.contains($0.role) }
        if !typeables.isEmpty {
            let samples = typeables.prefix(3).map { "\($0.id)=\($0.label)" }.joined(separator: ", ")
            logger.debug("Click map typeables=\(typeables.count, privacy: .public) samples=\(samples, privacy: .public)")
        }
        #endif
        return snapshot
    }

    func click(id: String, webView: WKWebView) async throws {
        let safeId = escapeJSString(id)
        let js = """
        (function(){
          const el = document.querySelector('[data-ai-id="\(safeId)"]');
          if (!el) return "NOT_FOUND";
          el.click();
          return "OK";
        })();
        """
        let result = try await webView.evalJSString(js)
        if result == "NOT_FOUND" {
            throw ClickMapError.elementNotFound
        }
    }

    func navigate(url: String, webView: WKWebView) async throws {
        let safeUrl = url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let js = """
        (function(){
          window.location.href = "\(safeUrl)";
          return "OK";
        })();
        """
        _ = try await webView.evalJSString(js)
    }

    func executeClick(id: String, webView: WKWebView, selector: String? = nil) async throws -> PageSnapshot {
        let safeId = escapeJSString(id)
        let js = """
        (function(){
          const el = document.querySelector('[data-ai-id="\(safeId)"]');
          if (!el) return "NOT_FOUND";
          el.click();
          return "OK";
        })();
        """
        let result = try await webView.evalJSString(js)
        if result == "NOT_FOUND" {
            throw ClickMapError.elementNotFound
        }
        return try await extractClickMap(webView: webView, selector: selector)
    }

    func typeText(id: String?, selector: String?, text: String, webView: WKWebView) async throws {
        let safeId = escapeJSString(id ?? "")
        let safeSelector = escapeJSString(selector ?? "")
        let safeText = escapeJSString(text)
        let js = """
        (function(){
          let el = null;
          if ("\(safeId)".length > 0) {
            el = document.querySelector('[data-ai-id="\(safeId)"]');
          }
          if (!el && "\(safeSelector)".length > 0) {
            try { el = document.querySelector("\(safeSelector)"); } catch (e) {}
          }
          if (!el) return "NOT_FOUND";
          el.focus();
          if (el.isContentEditable) {
            el.textContent = "\(safeText)";
          } else if ('value' in el) {
            el.value = "\(safeText)";
          }
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return "OK";
        })();
        """
        let result = try await webView.evalJSString(js)
        if result == "NOT_FOUND" {
            throw ClickMapError.elementNotFound
        }
    }

    func scroll(direction: ScrollDirection, amount: Int, webView: WKWebView) async throws {
        let delta = direction == .down ? amount : -amount
        let js = """
        (function(){
          window.scrollBy(0, \(delta));
          return "OK";
        })();
        """
        _ = try await webView.evalJSString(js)
    }

    func navigate(to url: URL, webView: WKWebView) async {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

extension WKWebView {
    enum EvalJSError: LocalizedError {
        case jsReturnedNil
        case documentNotReady(String)

        var errorDescription: String? {
            switch self {
            case .jsReturnedNil:
                return "JavaScript evaluation returned nil."
            case let .documentNotReady(state):
                return "Skipped JavaScript evaluation because document.readyState=\(state)."
            }
        }
    }

    private static let jsLogger = Logger(subsystem: "Agent", category: "JavaScript")

    private static let jsExceptionMessageKey = "WKJavaScriptExceptionMessage"
    private static let jsExceptionLineNumberKey = "WKJavaScriptExceptionLineNumber"
    private static let jsExceptionColumnNumberKey = "WKJavaScriptExceptionColumnNumber"
    private static let jsExceptionSourceURLKey = "WKJavaScriptExceptionSourceURL"

    private func fetchDocumentReadyState() async -> String? {
        await withCheckedContinuation { cont in
            self.evaluateJavaScript("document.readyState") { result, _ in
                cont.resume(returning: result as? String)
            }
        }
    }

    private func formatJavaScriptError(_ error: NSError) -> (message: String, details: [String: Any]) {
        let exceptionMessage = error.userInfo[Self.jsExceptionMessageKey] as? String
        let lineNumber = error.userInfo[Self.jsExceptionLineNumberKey]
        let columnNumber = error.userInfo[Self.jsExceptionColumnNumberKey]
        let sourceURL = error.userInfo[Self.jsExceptionSourceURLKey] as? String

        var details: [String: Any] = [:]
        if let exceptionMessage { details[Self.jsExceptionMessageKey] = exceptionMessage }
        if let lineNumber { details[Self.jsExceptionLineNumberKey] = lineNumber }
        if let columnNumber { details[Self.jsExceptionColumnNumberKey] = columnNumber }
        if let sourceURL { details[Self.jsExceptionSourceURLKey] = sourceURL }

        var message = error.localizedDescription
        if !details.isEmpty {
            let rendered = [
                exceptionMessage.map { "message=\($0)" },
                sourceURL.map { "source=\($0)" },
                lineNumber.map { "line=\($0)" },
                columnNumber.map { "column=\($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
            message += " [\(rendered)]"
        }

        return (message, details)
    }

    func evalJSString(_ js: String) async throws -> String {
        let trimmed = js.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != "document.readyState" {
            let readyState = await fetchDocumentReadyState()
            if let readyState, readyState != "interactive", readyState != "complete" {
                Self.jsLogger.warning("Skipping JavaScript evaluation because document.readyState=\(readyState, privacy: .public)")
                throw EvalJSError.documentNotReady(readyState)
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            self.evaluateJavaScript(js) { result, error in
                if let error = error {
                    let nsError = error as NSError
                    let formatted = formatJavaScriptError(nsError)
                    Self.jsLogger.error("JavaScript evaluation failed: \(formatted.message, privacy: .public)")
                    let wrapped = NSError(
                        domain: "Agent.JavaScriptError",
                        code: nsError.code,
                        userInfo: nsError.userInfo
                            .merging(formatted.details, uniquingKeysWith: { current, _ in current })
                            .merging([
                                NSLocalizedDescriptionKey: formatted.message,
                                NSUnderlyingErrorKey: nsError
                            ], uniquingKeysWith: { _, new in new })
                    )
                    continuation.resume(throwing: wrapped)
                } else {
                    if let result = result as? String {
                        continuation.resume(returning: result)
                    } else if let result = result {
                        continuation.resume(returning: String(describing: result))
                    } else {
                        continuation.resume(throwing: EvalJSError.jsReturnedNil)
                    }
                }
            }
        }
    }
}
