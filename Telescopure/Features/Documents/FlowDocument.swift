import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let webPuppetFlow = UTType(exportedAs: "com.webpuppet.flow")
}

struct FlowDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.webPuppetFlow, .json] }
    var flow: Flow

    init(flow: Flow) { self.flow = flow }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.flow = try JSONDecoder().decode(Flow.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder.pretty.encode(flow)
        return .init(regularFileWithContents: data)
    }
}
