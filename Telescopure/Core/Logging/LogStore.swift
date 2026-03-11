import Foundation

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [String] = []

    func add(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        entries.append("[\(timestamp)] \(message)")
    }

    func clear() { entries.removeAll() }
}
