import Model
import SwiftUI

struct AgentPanelView: View {
    @ObservedObject var controller: AgentController
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Form {
                    Section("Enable") {
                        Toggle("Enable AI click control", isOn: $controller.isAgentModeEnabled)
                        Toggle("Allow sensitive clicks", isOn: $controller.allowSensitiveClicks)
                    }

                    Section("OpenRouter API Key") {
                        SecureField("sk-or-…", text: $controller.apiKey)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        if controller.apiKey.isEmpty {
                            Text("Add your OpenRouter API key to enable requests.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("AI Command") {
                        TextField("Describe what to click", text: $controller.command, axis: .vertical)
                            .lineLimit(1...3)
                    }

                    Section("Controls") {
                        HStack {
                            Button(controller.isRunning ? "Running..." : "Run") {
                                controller.runCommand()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunDisabled)

                            Button("Stop") {
                                controller.stop()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!controller.isRunning)
                        }
                    }

                    Section("Status") {
                        Text("WebView ready: \(controller.isWebViewAvailable ? "Yes" : "No")")
                        Text("Last extracted clickables count: \(controller.lastClickablesCount)")
                        if let lastActionSummary = controller.lastActionSummary, !lastActionSummary.isEmpty {
                            Text("Last executed action: \(lastActionSummary)")
                        }
                        if let lastError = controller.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .foregroundStyle(.red)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Live Log")
                            .font(.headline)
                        Spacer()
                        if controller.isRunning {
                            ProgressView()
                        }
                    }
                    LogListView(entries: controller.logs)
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                        .padding(.bottom, 8)
                    if let last = controller.lastModelOutput, !last.isEmpty {
                        Text("Last model output: \n\(last)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("AI Click Control")
        }
    }

    private var isRunDisabled: Bool {
        controller.isRunning
            || !controller.isAgentModeEnabled
            || controller.apiKey.isEmpty
            || isCommandEmpty
            || !controller.isWebViewAvailable
    }

    private var isCommandEmpty: Bool {
        controller.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct LogListView: View {
    let entries: [AgentLogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("[\(entry.kind.rawValue.uppercased())] \(entry.message)")
                                .font(.callout)
                                .foregroundStyle(color(for: entry.kind))
                        }
                        .id(entry.id)
                        Divider()
                    }
                }
                .padding(8)
            }
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last?.id {
                    withAnimation {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func color(for kind: AgentLogEntry.Kind) -> Color {
        switch kind {
        case .error: return .red
        case .warning: return .orange
        case .model: return .blue
        case .action: return .purple
        case .result: return .green
        case .info: return .primary
        }
    }
}
