import Foundation

@MainActor
final class FlowRepository: ObservableObject {
    @Published private(set) var flows: [Flow] = []

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("webpuppet-flows.json")
        load()
    }

    func save(flow: Flow) {
        if let index = flows.firstIndex(where: { $0.id == flow.id }) {
            var updated = flow
            updated.updatedAt = .now
            flows[index] = updated
        } else {
            flows.append(flow)
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        flows.remove(atOffsets: offsets)
        persist()
    }

    func replace(with flow: Flow) {
        save(flow: flow)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Flow].self, from: data) else { return }
        flows = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder.pretty.encode(flows) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
