import Model
import SwiftUI
import WebUI

struct BrowserView: View {
    @StateObject var store: Browser
    @StateObject private var webViewRegistry: ActiveWebViewRegistry
    @StateObject private var agentController: AgentController
    @State private var isPresentingAgentPanel = false
    @FocusState private var isCommandFocused: Bool

    init(store: Browser) {
        _store = StateObject(wrappedValue: store)
        let registry = ActiveWebViewRegistry()
        _webViewRegistry = StateObject(wrappedValue: registry)
        _agentController = StateObject(wrappedValue: AgentController(webViewRegistry: registry))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WebViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    webContainer(proxy: proxy)
                    floatingControls
                }
            }
        }
        .ignoresSafeArea(.container, edges: store.isPresentedToolbar ? [] : .all)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(item: $store.settings) { store in
            SettingsView(store: store)
        }
        .sheet(isPresented: $isPresentingAgentPanel) {
            AgentPanelView(controller: agentController)
                .presentationDetents([.fraction(0.35), .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.35)))
        }
        .sheet(item: $store.bookmarkManagement) { store in
            BookmarkManagementView(store: store)
        }
        .webDialog(
            isPresented: $store.isPresentedWebDialog,
            presenting: store.webDialog,
            promptInput: $store.promptInput,
            okButtonTapped: { await store.send(.dialogOKButtonTapped) },
            cancelButtonTapped: { await store.send(.dialogCancelButtonTapped) },
            onChangeIsPresented: { await store.send(.onChangeIsPresentedWebDialog($0)) }
        )
        .externalAppConfirmationDialog(
            isPresented: $store.isPresentedConfirmationDialog,
            presenting: store.customSchemeURL,
            okButtonTapped: { await store.send(.confirmButtonTapped($0)) }
        )
        .alert(
            Text("failedToOpenExternalApp", bundle: .module),
            isPresented: $store.isPresentedAlert,
            actions: {}
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isCommandFocused = false
                }
            }
        }
        .onOpenURL { url in
            Task {
                await store.send(.onOpenURL(url))
            }
        }
        .animation(.easeIn(duration: 0.2), value: store.isPresentedToolbar)
    }

    @ViewBuilder
    private func webContainer(proxy: WebViewProxy) -> some View {
        VStack(spacing: 0) {
            toolbar(proxy: proxy)
            webContent(proxy: proxy)
            footer(proxy: proxy)
        }
        .background(Color(.secondarySystemBackground))
        .simultaneousGesture(TapGesture().onEnded {
            isCommandFocused = false
        })
        .task {
            updateActiveWebView(proxy: proxy)
            await store.send(.task(
                String(describing: Self.self),
                .init(getResourceURL: { Bundle.module.url(forResource: $0, withExtension: $1) }),
                proxy
            ))
        }
        .onChange(of: proxy.url) { _, newValue in
            updateActiveWebView(proxy: proxy)
            Task {
                await store.send(.onChangeURL(newValue))
            }
        }
        .onChange(of: proxy.title) { _, newValue in
            Task {
                await store.send(.onChangeTitle(newValue))
            }
        }
    }

    @ViewBuilder
    private func toolbar(proxy: WebViewProxy) -> some View {
        if store.isPresentedToolbar {
            Header(store: store, openAgentPanel: { isPresentingAgentPanel = true })
                .transition(.move(edge: .top))
                .environment(\.isLoading, proxy.isLoading)
                .environment(\.estimatedProgress, proxy.estimatedProgress)
        }
    }

    @ViewBuilder
    private func webContent(proxy: WebViewProxy) -> some View {
        ZStack(alignment: .bottom) {
            WebView(configuration: .forTelescopure)
                .navigationDelegate(store.navigationDelegate)
                .uiDelegate(store.uiDelegate)
                .refreshable()
                .allowsBackForwardNavigationGestures(true)
                .allowsOpaqueDrawing(proxy.url != nil)
                .allowsInspectable(true)
                .pageScaleFactor(store.pageScale.value)
                .overlay {
                    if proxy.url == nil {
                        LogoView()
                    }
                }
                .onAppear {
                    updateActiveWebView(proxy: proxy)
                }

            CommandOverlayView(controller: agentController, isCommandFocused: $isCommandFocused)
                .padding(.horizontal, 12)
                .padding(.bottom, store.isPresentedToolbar ? 70 : 16)
        }
    }

    @ViewBuilder
    private func footer(proxy: WebViewProxy) -> some View {
        if store.isPresentedToolbar {
            Footer(store: store)
                .transition(.move(edge: .bottom))
                .environment(\.canGoBack, proxy.canGoBack)
                .environment(\.canGoForward, proxy.canGoForward)
        }
    }

    @ViewBuilder
    private var floatingControls: some View {
        if !store.isPresentedToolbar {
            VStack(spacing: 12) {
                Button {
                    isPresentingAgentPanel = true
                } label: {
                    Image(systemName: "sparkles")
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                ShowToolbarButton(store: store)
            }
            .padding(20)
            .transition(.move(edge: .bottom))
        }
    }
}

extension Browser: ObservableObject {}
extension BrowserNavigation: ObservableObject {}
extension BrowserUI: ObservableObject {}

private struct CommandOverlayView: View {
    @ObservedObject var controller: AgentController
    @Binding var isCommandFocused: Bool
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Command", text: $controller.command)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        controller.runCommand()
                    }

                Button(controller.isRunning ? "Running..." : "Send") {
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

            HStack(spacing: 8) {
                Menu {
                    Picker("Run Mode", selection: $controller.runMode) {
                        ForEach(AgentController.RunMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } label: {
                    Text("Mode: \(controller.runMode.label)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.isRunning {
                    ProgressView()
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: isFieldFocused) { _, newValue in
            isCommandFocused = newValue
        }
        .onChange(of: isCommandFocused) { _, newValue in
            if newValue != isFieldFocused {
                isFieldFocused = newValue
            }
        }
    }

    private var isRunDisabled: Bool {
        controller.isRunning
            || !controller.isAgentModeEnabled
            || controller.apiKey.isEmpty
            || controller.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !controller.isWebViewAvailable
    }
}

private extension BrowserView {
    func updateActiveWebView(proxy: WebViewProxy) {
        webViewRegistry.update(from: proxy)
        agentController.attach(proxy: proxy)
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            webViewRegistry.update(from: proxy)
            agentController.attach(proxy: proxy)
        }
    }
}

#Preview(traits: .landscapeRight) {
    BrowserView(store: .init(.testDependencies()))
}
