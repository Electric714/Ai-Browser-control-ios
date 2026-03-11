import SwiftUI

struct WebPuppetRootView: View {
    @StateObject private var logs = LogStore()
    @StateObject private var repository = FlowRepository()
    @State private var selectedFlow: Flow?

    var body: some View {
        NavigationSplitView {
            List {
                Section("Flows") {
                    ForEach(repository.flows) { flow in
                        Button(flow.name) { selectedFlow = flow }
                    }
                    .onDelete(perform: repository.delete)
                }
            }
            .toolbar {
                Button("New") {
                    let flow = Flow(name: "New Flow", startURL: "https://example.com")
                    repository.save(flow: flow)
                    selectedFlow = flow
                }
            }
        } detail: {
            if let flow = selectedFlow {
                FlowEditorView(flow: flow, repository: repository, logs: logs)
            } else {
                Text("Create or select a flow")
            }
        }
    }
}

struct FlowEditorView: View {
    @State var flow: Flow
    @ObservedObject var repository: FlowRepository
    @ObservedObject var logs: LogStore

    @StateObject private var bridge: WebViewBridge
    @State private var isRecording = false
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var runOutput = ""

    init(flow: Flow, repository: FlowRepository, logs: LogStore) {
        _flow = State(initialValue: flow)
        self.repository = repository
        self.logs = logs
        _bridge = StateObject(wrappedValue: WebViewBridge(logStore: logs))
    }

    var body: some View {
        VStack {
            HStack {
                TextField("https://", text: $flow.startURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Go") { bridge.load(urlString: flow.startURL) }
                Button("◀︎") { bridge.goBack() }
                Button("▶︎") { bridge.goForward() }
                Button("↻") { bridge.reload() }
                Toggle("Record", isOn: $isRecording)
                    .onChange(of: isRecording) { _, new in bridge.injectRecorderScript(recording: new) }
                Button("Run") { Task { await runFlow() } }
                Button("Save") { repository.save(flow: flow) }
                Button("Export") { showExporter = true }
                Button("Import") { showImporter = true }
            }
            .padding(8)

            BrowserWebView(bridge: bridge)

            List {
                Section("Captured Steps") {
                    ForEach(flow.steps.sorted(by: { $0.order < $1.order })) { step in
                        Text("#\(step.order) \(step.type.rawValue)")
                    }
                }
                Section("Run Output") { Text(runOutput) }
                Section("Logs") {
                    ForEach(logs.entries, id: \.self) { Text($0).font(.caption2.monospaced()) }
                }
            }
            .frame(maxHeight: 280)
        }
        .navigationTitle(flow.name)
        .onAppear {
            bridge.onElementClick = { payload in
                guard isRecording else { return }
                let locator = LocatorBuilder.from(payload: payload)
                flow.steps.append(FlowStep(order: flow.steps.count, type: .click, locator: locator))
                logs.add("Step appended")
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: FlowDocument(flow: flow),
            contentType: .webPuppetFlow,
            defaultFilename: flow.name.replacingOccurrences(of: " ", with: "-")
        ) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.webPuppetFlow, .json]) { result in
            guard case let .success(url) = result,
                  let data = try? Data(contentsOf: url),
                  let imported = try? JSONDecoder().decode(Flow.self, from: data) else { return }
            flow = imported
            repository.replace(with: imported)
        }
    }

    private func runFlow() async {
        let runner = FlowRunner(bridge: bridge, logs: logs)
        let result = await runner.run(flow: flow)
        runOutput = result.outputs.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }
}
