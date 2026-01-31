import Foundation
import WebKit

struct ClickRect: Codable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct Clickable: Codable {
    let id: String
    let role: String
    let label: String
    let rect: ClickRect
    let href: String?
    let tag: String
    let disabled: Bool
}

struct PageSnapshot: Codable {
    let url: String
    let title: String
    let clickables: [Clickable]
}

enum ClickMapError: Error {
    case jsReturnedNil
    case decodeFailed
    case elementNotFound
}

final class ClickMapService {
    private let defaultSelector = "a[href],button,input[type=\"button\"],input[type=\"submit\"],[onclick],[role=\"button\"],[role=\"link\"]"

    private func extractJS(selector: String) -> String {
        let escapedSelector = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (function() {
          const selector = "\(escapedSelector)";
          const els = Array.from(document.querySelectorAll(selector));
          const w = window.innerWidth || 1;
          const h = window.innerHeight || 1;

          function labelFor(el) {
            const aria = el.getAttribute('aria-label');
            if (aria && aria.trim()) return aria.trim();
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

            if (!el.dataset.aiId) {
              do {
                maxId += 1;
              } while (usedIds.has('e' + maxId));
              const newId = 'e' + maxId;
              el.dataset.aiId = newId;
              usedIds.add(newId);
            }

            const tag = (el.tagName || '').toUpperCase();
            const roleAttr = (el.getAttribute('role') || '').toLowerCase();
            const role = roleAttr || (tag === 'A' ? 'link' : (tag === 'BUTTON' ? 'button' : (tag === 'INPUT' ? 'input' : 'other')));
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
        """
    }

    func extractClickMap(webView: WKWebView, selector: String? = nil) async throws -> PageSnapshot {
        let js = extractJS(selector: selector ?? defaultSelector)
        let result = try await webView.evalJS(js)
        guard let json = result as? String else { throw ClickMapError.jsReturnedNil }
        guard let data = json.data(using: .utf8) else { throw ClickMapError.decodeFailed }
        return try JSONDecoder().decode(PageSnapshot.self, from: data)
    }

    func click(id: String, webView: WKWebView) async throws {
        let safeId = id.replacingOccurrences(of: "\"", with: "\\\"")
        let js = """
        (function(){
          const el = document.querySelector('[data-ai-id="\(safeId)"]');
          if (!el) return "NOT_FOUND";
          el.click();
          return "OK";
        })();
        """
        let result = try await webView.evalJS(js)
        if let s = result as? String, s == "NOT_FOUND" {
            throw ClickMapError.elementNotFound
        }
    }

    func executeClick(id: String, webView: WKWebView, selector: String? = nil) async throws -> PageSnapshot {
        let safeId = id.replacingOccurrences(of: "\"", with: "\\\"")
        let js = """
        (function(){
          const el = document.querySelector('[data-ai-id="\(safeId)"]');
          if (!el) return "NOT_FOUND";
          el.click();
          return "OK";
        })();
        """
        let result = try await webView.evalJS(js)
        if let s = result as? String, s == "NOT_FOUND" {
            throw ClickMapError.elementNotFound
        }
        return try await extractClickMap(webView: webView, selector: selector)
    }
}

extension WKWebView {
    func evalJS(_ js: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            self.evaluateJavaScript(js) { result, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: result)
                }
            }
        }
    }
}
