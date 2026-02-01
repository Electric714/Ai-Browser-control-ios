import Model
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentPanelView: View {
    @ObservedObject var controller: AgentController
    var onRun: (() -> Void)?
    @FocusState private var isCommandFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GroupBox("Enable") {
                        Toggle("Enable AI click control", isOn: $controller.isAgentModeEnabled)
                        Toggle("Allow sensitive clicks", isOn: $controller.allowSensitiveClicks)
                    }

                    GroupBox("Provider") {
                        Picker("Provider", selection: $controller.provider) {
                            ForEach(AgentProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        if controller.provider == .onDevice,
                           let message = controller.onDeviceAvailabilityMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if controller.provider == .openRouter {
                        GroupBox("OpenRouter API Key") {
                            SecureField("sk-or-…", text: $controller.apiKey)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            if controller.apiKey.isEmpty {
                                Text("Add your OpenRouter API key to enable requests.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GroupBox("OpenRouter Model") {
                            Picker("Model", selection: $controller.openRouterModel) {
                                ForEach(openRouterModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            HStack {
                                Text("Temperature")
                                Spacer()
                                Text(String(format: "%.2f", controller.openRouterTemperature))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $controller.openRouterTemperature, in: 0...1, step: 0.05)
                        }
                    }

                    GroupBox("AI Command") {
                        ZStack(alignment: .topLeading) {
                            if controller.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Describe what to click")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $controller.command)
                                .focused($isCommandFocused)
                                .frame(minHeight: 120, maxHeight: 160)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                    }

                    Section("Model Settings") {
                        Picker("Model", selection: modelSelection) {
                            ForEach(AgentController.availableModelIds, id: \.self) { modelId in
                                Text(modelId).tag(modelId)
                            }
                            Text("Other…").tag(AgentController.customModelTag)
                        }
                        if modelSelection.wrappedValue == AgentController.customModelTag {
                            TextField("Custom model id", text: $controller.modelId)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", controller.temperature))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $controller.temperature, in: 0...2, step: 0.05)
                    }

                    Section("Controls") {
                        HStack {
                            Button(controller.isRunning ? "Running..." : "Run") {
                                controller.runCommand()
                                onRun?()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunDisabled)

                            Button("Stop") {
                                controller.stop()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!controller.isRunning)
                        }
                        Picker("Run Mode", selection: $controller.runMode) {
                            ForEach(AgentController.RunMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Active model: \(resolvedModelId)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Status") {
                        let status = runBlockers.isEmpty
                            ? "Ready"
                            : "Blocked by: \(runBlockers.joined(separator: ", "))"
                        Text("WebView ready: \(controller.isWebViewAvailable ? "Yes" : "No")")
                        Text("Run status: \(status)")
                        Text("Active WebView id: \(activeWebViewIdentifierDescription)")
                        Text("WebView bounds: \(webViewBoundsDescription)")
                        Text("WebView URL: \(controller.webViewURL ?? "nil")")
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
                .scrollDismissesKeyboard(.interactively)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Live Log")
                            .font(.headline)
                        Spacer()
                        if !controller.logs.isEmpty {
                            Button("Copy Log") {
                                copyLogEntries(controller.logs)
                            }
                        }
                        if controller.isRunning {
                            ProgressView()
                        }
                    }
                    LogListView(entries: controller.logs)
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                        .padding(.bottom, 8)
                    if let last = controller.lastModelOutput, !last.isEmpty {
                        HStack {
                            Text("Last model output")
                                .font(.headline)
                            Spacer()
                            Button("Copy Output") {
                                copyOutput(last)
                            }
                        }
                        Text(last)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                isCommandFocused = false
            }
            .navigationTitle("AI Click Control")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isCommandFocused = false
                    }
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private let openRouterModels = [
        "openai/gpt-4o-mini",
        "openai/gpt-4o",
        "anthropic/claude-3.5-sonnet"
    ]

    private var isRunDisabled: Bool {
        controller.isRunning
            || !controller.isAgentModeEnabled
            || (controller.provider == .openRouter && controller.apiKey.isEmpty)
            || isCommandEmpty
            || !controller.isWebViewAvailable
    }

    private var isCommandEmpty: Bool {
        controller.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var runBlockers: [String] {
        var blockers: [String] = []
        if controller.isRunning { blockers.append("running") }
        if !controller.isAgentModeEnabled { blockers.append("agent disabled") }
        if controller.provider == .openRouter, controller.apiKey.isEmpty { blockers.append("missing api key") }
        if isCommandEmpty { blockers.append("empty command") }
        if !controller.isWebViewAvailable { blockers.append("webView unavailable") }
        return blockers
    }

    private var activeWebViewIdentifierDescription: String {
        controller.activeWebViewIdentifier.map { String(describing: $0) } ?? "nil"
    }

    private var webViewBoundsDescription: String {
        guard let bounds = controller.webViewBounds else { return "nil" }
        let width = Int(bounds.size.width)
        let height = Int(bounds.size.height)
        return "\(width)x\(height)"
    }

    private func copyLogEntries(_ entries: [AgentLogEntry]) {
        let lines = entries.map { entry in
            let timestamp = entry.date.formatted(date: .omitted, time: .standard)
            return "\(timestamp) [\(entry.kind.rawValue.uppercased())] \(entry.message)"
        }
        let text = lines.joined(separator: "\n")
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    private func copyOutput(_ output: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = output
        #endif
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: {
                AgentController.availableModelIds.contains(controller.modelId)
                    ? controller.modelId
                    : AgentController.customModelTag
            },
            set: { selection in
                if selection == AgentController.customModelTag {
                    if AgentController.availableModelIds.contains(controller.modelId) {
                        controller.modelId = ""
                    }
                } else {
                    controller.modelId = selection
                }
            }
        )
    }

    private var resolvedModelId: String {
        let trimmed = controller.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AgentController.defaultModelId : trimmed
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
                                .textSelection(.enabled)
                            Text("[\(entry.kind.rawValue.uppercased())] \(entry.message)")
                                .font(.callout)
                                .foregroundStyle(color(for: entry.kind))
                                .textSelection(.enabled)
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
