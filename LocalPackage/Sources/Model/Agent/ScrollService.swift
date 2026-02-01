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
    func scroll(dx: Double?, dy: Double, webView: WKWebView) async throws -> ScrollResult {
        let dxValue = dx ?? 0
        let js = """
        (function() {
          const dx = \(dxValue);
          const dy = \(dy);
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

          function scrollWindow() {
            const before = windowPosition();
            window.scrollBy(dx, dy);
            const after = windowPosition();
            return before.x !== after.x || before.y !== after.y;
          }
          const didScroll = scrollWindow();
          return JSON.stringify(setWindowResult(didScroll));
        })();
        """
        let json = try await webView.evalJSString(js)
        guard let data = json.data(using: .utf8) else {
            throw ClickMapError.decodeFailed
        }
        return try JSONDecoder().decode(ScrollResult.self, from: data)
    }
}
