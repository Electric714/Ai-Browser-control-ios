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

struct ClickMap: Codable {
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
    private let extractJS = """
    (function() {
      const selector = 'a[href],button,input[type="button"],input[type="submit"],[onclick],[role="button"],[role="link"]';
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
        const op = parseFloat(cs.opacity || '1');
        if (isNaN(op) || op <= 0.05) return false;
        if (r.bottom < 0 || r.right < 0 || r.top > h || r.left > w) return false;
        return true;
      }

      let idx = 0;
      const clickables = [];

      for (const el of els) {
        const r = el.getBoundingClientRect();
        if (!isVisible(el, r)) continue;

        if (!el.dataset.aiId) {
          idx += 1;
          el.dataset.aiId = 'e' + idx;
        }

        const tag = (el.tagName || '').toUpperCase();
        const roleAttr = (el.getAttribute('role') || '').toLowerCase();
        const role = roleAttr || (tag === 'A' ? 'link' : (tag === 'BUTTON' ? 'button' : (tag === 'INPUT' ? 'input' : 'other')));
        const disabled = !!(el.disabled || el.getAttribute('aria-disabled') === 'true');
        const href = (el.getAttribute('href') || '').trim() || null;
        const label = labelFor(el);

        clickables.push({
          id: el.dataset.aiId,
          role,
          label,
          rect: { x: r.left / w, y: r.top / h, w: r.width / w, h: r.height / h },
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

    func extractClickMap(webView: WKWebView) async throws -> ClickMap {
        let result = try await webView.evalJS(extractJS)
        guard let json = result as? String else { throw ClickMapError.jsReturnedNil }
        guard let data = json.data(using: .utf8) else { throw ClickMapError.decodeFailed }
        return try JSONDecoder().decode(ClickMap.self, from: data)
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
