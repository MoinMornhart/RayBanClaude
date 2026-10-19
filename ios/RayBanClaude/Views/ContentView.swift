import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var textInput = ""
    @State private var hasRequestedPermissions = false
    @State private var showQuickActions = false
    @State private var pulse = false

    var body: some View {
        layeredContent
            .sheet(item: messageDraftBinding) { draft in
                MessageComposeView(draft: draft) { viewModel.phoneActions.messageDraft = nil }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel, rayBanManager: viewModel.rayBanManager, modeManager: viewModel.modeManager)
            }
            .alert("Mit PC koppeln?", isPresented: pairingBinding) {
                Button("Koppeln") { viewModel.confirmPairing() }
                Button("Abbrechen", role: .cancel) { viewModel.pendingPairing = nil }
            } message: {
                Text(pairingMessage)
            }
            .onChange(of: viewModel.modeManager.activeMode.id) { _, _ in showQuickActionsTemporarily() }
            .onChange(of: viewModel.notice) { _, notice in hideNoticeLater(notice) }
            .onAppear {
                // Standard: iPhone darf sich sperren – die App hört über die Brille weiter (Hosentaschen-Modus)
                UIApplication.shared.isIdleTimerDisabled = viewModel.config.keepScreenOn
                if DemoMode.showSettings { showSettings = true }
            }
            .onChange(of: viewModel.config.keepScreenOn) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
            .onChange(of: scenePhase) { _, phase in viewModel.scenePhaseChanged(phase) }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .task { await requestPermissionsAndConnect() }
    }

    // MARK: - Aufbau

    private var layeredContent: some View {
        ZStack {
            cameraLayer.ignoresSafeArea()
            gradients
            mainColumn
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.transcript.count)
        .animation(.easeInOut(duration: 0.2), value: viewModel.state)
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
        .animation(.easeInOut(duration: 0.2), value: viewModel.pendingPermission)
    }

    private var gradients: some View {
        ZStack {
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 460)
            }
            VStack {
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            headerSection
            Spacer()
            cardsSection
            textInputBar.padding(.horizontal, 16).padding(.top, 10)
            bottomControls.padding(.vertical, 8)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 0) {
            topBar.padding(.horizontal, 16).padding(.top, 4)
            modeSelector.padding(.top, 6)
            if !viewModel.phoneActions.timers.isEmpty {
                TimersBar(timers: viewModel.phoneActions.timers) { viewModel.phoneActions.cancel($0) }
                    .padding(.top, 6)
            }
            if showQuickActions {
                quickActionBar.padding(.top, 6).transition(.opacity)
            }
            if !viewModel.canTalk && !viewModel.config.isConfigured && !viewModel.config.hasDirectKey {
                pairingHint.padding(.horizontal, 16).padding(.top, 12)
            }
        }
    }

    private var cardsSection: some View {
        VStack(spacing: 0) {
            if !viewModel.transcript.isEmpty {
                TranscriptView(messages: viewModel.transcript, fileRequest: viewModel.bridge.fileRequest)
                    .frame(maxHeight: 300)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !viewModel.currentTranscription.isEmpty {
                liveTranscriptionBanner.padding(.horizontal, 16).padding(.top, 8)
            }
            promptCards
            bannerStack
        }
    }

    /// Rückfragen: Anruf/Nachricht/Navigation und Werkzeug-Freigaben
    private var promptCards: some View {
        VStack(spacing: 0) {
            if let confirmation = viewModel.phoneActions.confirmation {
                ActionConfirmationCard(confirmation: confirmation,
                                       onSelect: { viewModel.confirmAction($0) },
                                       onCancel: { viewModel.dismissAction() })
                    .padding(.horizontal, 16).padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let request = viewModel.pendingPermission {
                PermissionCard(request: request) { allow in
                    Task { await viewModel.answerPermission(request, allow: allow) }
                }
                .padding(.horizontal, 16).padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var bannerStack: some View {
        VStack(spacing: 0) {
            if let code = viewModel.codeToast {
                codeToastBanner(code).padding(.horizontal, 16).padding(.top, 6)
            }
            if let notice = viewModel.notice {
                noticeBanner(notice).padding(.horizontal, 16).padding(.top, 6)
            }
            if let error = viewModel.errorMessage {
                errorBanner(error).padding(.horizontal, 16).padding(.top, 6)
            }
        }
    }

    // MARK: - Bindungen und Abläufe

    private var messageDraftBinding: Binding<MessageDraft?> {
        Binding(get: { viewModel.phoneActions.messageDraft }, set: { viewModel.phoneActions.messageDraft = $0 })
    }

    private var pairingBinding: Binding<Bool> {
        Binding(get: { viewModel.pendingPairing != nil }, set: { if !$0 { viewModel.pendingPairing = nil } })
    }

    private var pairingMessage: String {
        let host = viewModel.pendingPairing?.host ?? ""
        let port = viewModel.pendingPairing.map { String($0.port) } ?? ""
        return "RayBan Claude verbindet sich mit \(host):\(port). Nur bestätigen, wenn du den QR-Code gerade in deinem eigenen Dashboard gescannt hast."
    }

    private func hideNoticeLater(_ notice: String?) {
        guard notice != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if viewModel.notice == notice { viewModel.notice = nil }
        }
    }

    private func requestPermissionsAndConnect() async {
        guard !hasRequestedPermissions, !DemoMode.isActive else { return }
        hasRequestedPermissions = true
        if await viewModel.speechManager.requestAuthorization() {
            await viewModel.connect()
        } else {
            viewModel.errorMessage = "Mikrofon/Spracherkennung nicht erlaubt – in den iOS-Einstellungen freigeben"
        }
    }

    // MARK: - Kamera

    @ViewBuilder
    private var cameraLayer: some View {
        if DemoMode.isActive {
            DemoSceneView()
        } else if viewModel.activeFrameSource == .iPhone {
            CameraPreviewView(session: viewModel.cameraManager.captureSession)
        } else {
            RayBanLayer(
                rayBanManager: viewModel.rayBanManager,
                status: viewModel.frameSourceStatus,
                isConnected: viewModel.canTalk
            )
        }
    }

    // MARK: - Modi

    private var modeSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.modeManager.visibleModes) { mode in
                        modePill(mode).id(mode.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: viewModel.modeManager.activeMode.id) { _, newId in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(newId, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(viewModel.modeManager.activeMode.id, anchor: .center) }
        }
    }

    private func modePill(_ mode: VisionMode) -> some View {
        let isActive = viewModel.modeManager.activeMode.id == mode.id
        return Button {
            haptic(.light)
            viewModel.modeManager.setActiveMode(mode)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon).font(.system(size: 11, weight: .semibold))
                Text(mode.name).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(isActive ? mode.swiftColor.opacity(0.85) : .white.opacity(0.1)))
            .overlay(Capsule().strokeBorder(isActive ? mode.swiftColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modus \(mode.name)\(isActive ? ", aktiv" : "")")
    }

    private var quickActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.modeManager.activeMode.quickActions, id: \.self) { action in
                    Button {
                        haptic(.light)
                        Task { await viewModel.sendText(action) }
                    } label: {
                        Text(action)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.modeManager.activeMode.swiftColor.opacity(0.3), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func showQuickActionsTemporarily() {
        withAnimation { showQuickActions = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeOut(duration: 0.5)) { showQuickActions = false }
        }
    }

    // MARK: - Statusleiste

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(routeColor)
                    .frame(width: 8, height: 8)
                Image(systemName: routeIcon)
                    .font(.system(size: 11, weight: .medium))
                Text(routeLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Image(systemName: viewModel.activeFrameSource.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(frameSourceColor)
                if viewModel.activeFrameSource == .rayBan {
                    BatteryBadge(rayBanManager: viewModel.rayBanManager)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(routeAccessibility)

            HStack(spacing: 5) {
                stateIcon.font(.system(size: 11, weight: .medium)).foregroundStyle(stateColor)
                Text(viewModel.state.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                haptic(.light)
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Einstellungen")
        }
        .foregroundStyle(.white)
    }

    private var pairingHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder").font(.system(size: 26)).foregroundStyle(Color.anthropicOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mit deinem PC koppeln").font(.headline)
                Text("Auf dem PC Claude starten, Dashboard öffnen (localhost:18790) und den QR-Code mit der iPhone-Kamera scannen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Banner

    private var liveTranscriptionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.anthropicOrange)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(viewModel.currentTranscription).font(.subheadline).lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func codeToastBanner(_ code: DetectedCode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "qrcode").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(code.typeLabel).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.green.opacity(0.8))
                Text(code.value).font(.system(size: 13, weight: .medium)).lineLimit(2)
            }
            Spacer()
            Button { viewModel.copyCodeToClipboard(code) } label: {
                Image(systemName: "doc.on.doc").frame(width: 30, height: 30).background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Code kopieren")
            Button { viewModel.sendCodeToChat(code) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 24)).foregroundStyle(.green)
            }
            .accessibilityLabel("Code an Claude senden")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func noticeBanner(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(error).font(.caption).lineLimit(3)
            Spacer()
            Button { viewModel.errorMessage = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22).background(.white.opacity(0.2), in: Circle())
            }
            .accessibilityLabel("Meldung schließen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Eingabe

    private var textInputBar: some View {
        HStack(spacing: 8) {
            TextField("Nachricht …", text: $textInput, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .tint(.anthropicOrange)
                .onSubmit(sendTextInput)
            if !textInput.isEmpty {
                Button(action: sendTextInput) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).foregroundStyle(Color.anthropicOrange)
                }
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func sendTextInput() {
        let text = textInput
        textInput = ""
        haptic(.light)
        Task { await viewModel.sendText(text) }
    }

    private var bottomControls: some View {
        HStack(spacing: 0) {
            Button {
                haptic(.medium)
                viewModel.resetConversation()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 18, weight: .medium))
                    Text("Neu").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Gespräch zurücksetzen")

            Button {
                haptic(viewModel.state == .speaking ? .rigid : .medium)
                if viewModel.state == .speaking {
                    viewModel.interruptSpeaking()
                } else if viewModel.canTalk {
                    viewModel.toggleListening()
                } else {
                    Task { await viewModel.connect() }
                }
            } label: {
                ZStack {
                    if viewModel.state == .listening {
                        Circle()
                            .stroke(Color.red.opacity(0.4), lineWidth: 3)
                            .frame(width: 82, height: 82)
                            .scaleEffect(pulse ? 1.2 : 1.0)
                            .opacity(pulse ? 0 : 1)
                            .onAppear {
                                pulse = false
                                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
                            }
                    }
                    Circle()
                        .fill(micButtonColor.gradient)
                        .frame(width: 72, height: 72)
                        .shadow(color: micButtonColor.opacity(0.4), radius: 12, y: 4)
                    if viewModel.isProcessing && viewModel.state == .thinking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: micButtonIcon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(micAccessibilityLabel)

            Button {
                haptic(.light)
                viewModel.activeFrameSource = viewModel.activeFrameSource == .iPhone ? .rayBan : .iPhone
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.activeFrameSource.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(frameSourceColor)
                    Text(viewModel.activeFrameSource.shortLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Kamera wechseln, aktuell \(viewModel.activeFrameSource.rawValue)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
    }

    // MARK: - Hilfen

    @ViewBuilder
    private var stateIcon: some View {
        switch viewModel.state {
        case .disconnected: Image(systemName: "wifi.slash")
        case .idle: Image(systemName: "checkmark")
        case .standby: Image(systemName: "ear")
        case .listening: Image(systemName: "waveform")
        case .thinking: Image(systemName: "brain")
        case .speaking: Image(systemName: "speaker.wave.2.fill")
        }
    }

    private var stateColor: Color {
        switch viewModel.state {
        case .disconnected: return .red
        case .idle: return .green
        case .standby: return .mint
        case .listening: return .anthropicOrange
        case .thinking: return .yellow
        case .speaking: return .blue
        }
    }

    private var micButtonColor: Color {
        switch viewModel.state {
        case .listening: return .red
        case .thinking: return .anthropicOrange
        case .speaking: return .blue
        default: return viewModel.canTalk ? .anthropicOrange : .gray
        }
    }

    private var micButtonIcon: String {
        switch viewModel.state {
        case .listening: return "mic.fill"
        case .thinking: return "ellipsis"
        case .speaking: return "stop.fill"
        case .disconnected: return "wifi.slash"
        case .idle, .standby: return "mic"
        }
    }

    private var micAccessibilityLabel: String {
        switch viewModel.state {
        case .listening: return "Zuhören beenden"
        case .speaking: return "Sprechen unterbrechen"
        case .disconnected: return "Verbinden"
        case .standby: return "Sprechen – oder einfach „Hey Claude“ sagen"
        default: return "Sprechen"
        }
    }

    private var routeColor: Color {
        switch viewModel.route {
        case .pc: return .green
        case .direct: return .orange
        case .none: return .red
        }
    }

    private var routeIcon: String {
        switch viewModel.route {
        case .pc: return "desktopcomputer"
        case .direct: return "antenna.radiowaves.left.and.right"
        case .none: return "wifi.slash"
        }
    }

    private var routeLabel: String {
        switch viewModel.route {
        case .pc: return viewModel.viaTailscale ? "PC · unterwegs" : "PC"
        case .direct: return "Direkt"
        case .none: return "Offline"
        }
    }

    private var routeAccessibility: String {
        switch viewModel.route {
        case .pc: return viewModel.viaTailscale ? "Unterwegs über Tailscale mit dem PC verbunden" : "Mit dem PC verbunden"
        case .direct: return "Ohne PC, direkt mit Claude verbunden"
        case .none: return "Nicht verbunden"
        }
    }

    private var frameSourceColor: Color {
        switch viewModel.frameSourceStatus {
        case .connected: return .green
        case .standby: return .green.opacity(0.7)
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .white.opacity(0.5)
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Freigabe-Karte (Permission-Relay)

struct PermissionCard: View {
    let request: PermissionRequest
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Claude möchte \(request.toolName) ausführen", systemImage: "lock.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.anthropicOrange)
            if !request.description.isEmpty {
                Text(request.description).font(.caption)
            }
            if !request.inputPreview.isEmpty {
                Text(request.inputPreview)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(4)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button(role: .destructive) { answer(false) } label: {
                    Label("Ablehnen", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { answer(true) } label: {
                    Label("Erlauben", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            Text("Oder einfach „Ja“ bzw. „Nein“ sagen.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.anthropicOrange.opacity(0.6)))
    }
}

// MARK: - Vorschau iPhone-Kamera

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass ist oben auf AVCaptureVideoPreviewLayer gesetzt
            layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
        }
    }
}

// MARK: - Vorschau Brille

/// Eigene Teilansicht, damit nur sie bei jedem Videobild neu gezeichnet wird.
struct RayBanLayer: View {
    @ObservedObject var rayBanManager: RayBanManager
    let status: FrameSourceStatus
    let isConnected: Bool

    var body: some View {
        ZStack {
            RayBanVideoView(rayBanManager: rayBanManager)
            if rayBanManager.latestImage == nil {
                Color.black
                VStack(spacing: 16) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 52, weight: .thin))
                        .foregroundStyle(Color.anthropicOrange.opacity(0.6))
                    if status == .standby && isConnected {
                        Text("Kamera aus – die Brille fotografiert nur, wenn du etwas zeigst oder fragst („Was ist das?“).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    } else if status.isConnected {
                        ProgressView().tint(.anthropicOrange)
                        Text("Empfange Bild der Brille …").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text(isConnected ? status.label : "Erst mit dem PC verbinden")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
            }
        }
    }
}

struct BatteryBadge: View {
    @ObservedObject var rayBanManager: RayBanManager

    var body: some View {
        if let battery = rayBanManager.batteryLevel {
            Text("\(battery) %")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .accessibilityLabel("Akku der Brille \(battery) Prozent")
        }
    }
}

struct RayBanVideoView: UIViewRepresentable {
    @ObservedObject var rayBanManager: RayBanManager

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.backgroundColor = .black
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    /// Wird bei jedem neuen Bild aufgerufen (früher lief dafür ein Display-Link,
    /// der pro Bildschirm-Frame eine Task erzeugte).
    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = rayBanManager.latestImage
    }
}


// MARK: - Laufende Timer

struct TimersBar: View {
    let timers: [RunningTimer]
    let onCancel: (RunningTimer) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(timers) { timer in
                    Button { onCancel(timer) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: timer.isAlarm ? "alarm.fill" : "timer")
                            Text(timer.label).lineLimit(1)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(Self.remaining(until: timer.fireDate, now: context.date, isAlarm: timer.isAlarm))
                                    .monospacedDigit()
                            }
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).opacity(0.6)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.35), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(timer.isAlarm ? "Wecker" : "Timer") \(timer.label), tippen zum Löschen")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    static func remaining(until date: Date, now: Date, isAlarm: Bool) -> String {
        if isAlarm {
            return date.formatted(date: .omitted, time: .shortened)
        }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Rückfrage vor Anruf, Nachricht, Navigation

struct ActionConfirmationCard: View {
    let confirmation: ActionConfirmation
    let onSelect: (ActionConfirmation.Option) -> Void
    let onCancel: () -> Void

    private var icon: String {
        switch confirmation.kind {
        case .call: return "phone.fill"
        case .message: return "message.fill"
        case .navigate: return "map.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(confirmation.title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            if case .message(let text) = confirmation.kind {
                Text("„\(text)“").font(.caption).lineLimit(3)
            }
            ForEach(confirmation.options) { option in
                Button { onSelect(option) } label: {
                    Label(option.label, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            Button(role: .cancel, action: onCancel) {
                Text("Abbrechen").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if confirmation.options.count == 1 {
                Text("Oder einfach „Ja“ bzw. „Nein“ sagen.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.green.opacity(0.6)))
    }
}
