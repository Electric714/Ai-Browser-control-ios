import Foundation
import WebKit

struct ScrollResult: Codable, Sendable {
    struct ScrollPosition: Codable, Sendable {
        let x: Double
        let y: Double
    }

    struct ScrollBounds: Codable, Sendable {
        let maxX: Double
        let maxY: Double
    }

    let didScroll: Bool
    let position: ScrollPosition
    let bounds: ScrollBounds
    let atTop: Bool
    let atBottom: Bool
}

@MainActor
final class ScrollService {
    private func jsonLiteral(for value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return String(data: data ?? Data(), encoding: .utf8) ?? "\"\""
    }

    func scroll(dx: Double?, dy: Double, selector: String?, mode: AgentAction.ScrollMode?, webView: WKWebView) async throws -> ScrollResult {
        let dxValue = dx ?? 0
        let modeValue = mode?.rawValue ?? "auto"
        let selectorLiteral = selector.map { jsonLiteral(for: $0) } ?? "null"
        let modeLiteral = jsonLiteral(for: modeValue)
        let js = """
        (function() {
          const dx = \(dxValue);
          const dy = \(dy);
          const selector = \(selectorLiteral);
          const mode = \(modeLiteral);

          function clampNonNegative(value) {
            return Math.max(0, value);
          }

          function windowBounds() {
            const doc = document.documentElement || document.body;
            const maxX = clampNonNegative((doc.scrollWidth || 0) - (window.innerWidth || 0));
            const maxY = clampNonNegative((doc.scrollHeight || 0) - (window.innerHeight || 0));
            return { maxX, maxY };
          }

          function windowPosition() {
            return { x: window.scrollX || 0, y: window.scrollY || 0 };
          }

          function setWindowResult(didScroll) {
            const position = windowPosition();
            const bounds = windowBounds();
            const atTop = position.y <= 0;
            const atBottom = position.y >= bounds.maxY;
            return {
              didScroll,
              position,
              bounds,
              atTop,
              atBottom
            };
          }

          function elementBounds(el) {
            const maxX = clampNonNegative((el.scrollWidth || 0) - (el.clientWidth || 0));
            const maxY = clampNonNegative((el.scrollHeight || 0) - (el.clientHeight || 0));
            return { maxX, maxY };
          }

          function elementPosition(el) {
            return { x: el.scrollLeft || 0, y: el.scrollTop || 0 };
          }

          function setElementResult(el, didScroll) {
            if (!el) return setWindowResult(didScroll);
            const position = elementPosition(el);
            const bounds = elementBounds(el);
            const atTop = position.y <= 0;
            const atBottom = position.y >= bounds.maxY;
            return {
              didScroll,
              position,
              bounds,
              atTop,
              atBottom
            };
          }

          function scrollWindow() {
            const before = windowPosition();
            window.scrollBy(dx, dy);
            const after = windowPosition();
            return before.x !== after.x || before.y !== after.y;
          }

          function isScrollable(el) {
            if (!el) return false;
            const style = window.getComputedStyle(el);
            if (!style) return false;
            const overflowY = style.overflowY || style.overflow || '';
            const overflowX = style.overflowX || style.overflow || '';
            const canScrollY = /auto|scroll|overlay/.test(overflowY) && el.scrollHeight > el.clientHeight;
            const canScrollX = /auto|scroll|overlay/.test(overflowX) && el.scrollWidth > el.clientWidth;
            return canScrollY || canScrollX;
          }

          function nearestScrollable(el) {
            let current = el;
            while (current && current !== document.body && current !== document.documentElement) {
              if (isScrollable(current)) return current;
              current = current.parentElement;
            }
            return null;
          }

          function resolveElement() {
            if (selector) {
              const target = document.querySelector(selector);
              if (target) return target;
            }
            const center = document.elementFromPoint((window.innerWidth || 0) / 2, (window.innerHeight || 0) / 2);
            return nearestScrollable(center);
          }

          function scrollElement(el) {
            const before = elementPosition(el);
            el.scrollBy({ left: dx, top: dy });
            const after = elementPosition(el);
            return before.x !== after.x || before.y !== after.y;
          }

          let result;
          if (mode === 'window') {
            const didScroll = scrollWindow();
            result = setWindowResult(didScroll);
          } else if (mode === 'element') {
            const target = resolveElement();
            const didScroll = target ? scrollElement(target) : false;
            result = setElementResult(target, didScroll);
          } else {
            const didScroll = scrollWindow();
            if (didScroll) {
              result = setWindowResult(true);
            } else {
              const target = resolveElement();
              const didScrollElement = target ? scrollElement(target) : false;
              result = setElementResult(target, didScrollElement);
            }
          }

          return JSON.stringify(result);
        })();
        """
        let json = try await webView.evalJSString(js)
        guard let data = json.data(using: .utf8) else {
            throw ClickMapError.decodeFailed
        }
        return try JSONDecoder().decode(ScrollResult.self, from: data)
    }
}
