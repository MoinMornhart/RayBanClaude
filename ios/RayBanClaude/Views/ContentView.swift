import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var textInput = ""
    @State private var hasRequestedPermissions = false
    @State private var showQuickActions = false

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
                LinearGradient(colors: [.clear, Color.hudBackground.opacity(0.65), Color.hudBackground.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 460)
            }
            VStack {
                LinearGradient(colors: [Color.hudBackground.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
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
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? Color.hudInk : mode.swiftColor)
                Text(mode.name)
                    .font(.hudMono(11, weight: .semibold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isActive ? Color.hudInk : Color.hudMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isActive ? mode.swiftColor.opacity(0.3) : Color.hudPanel,
                        in: RoundedRectangle(cornerRadius: HUDMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HUDMetrics.radius, style: .continuous)
                .strokeBorder(isActive ? mode.swiftColor : Color.hudLine, lineWidth: HUDMetrics.hairline))
            .shadow(color: isActive ? mode.swiftColor.opacity(0.6) : .clear, radius: 8)
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
                        let color = viewModel.modeManager.activeMode.swiftColor
                        Text(action)
                            .font(.hudMono(11, weight: .medium))
                            .foregroundStyle(Color.hudInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .hudPanel(border: color.opacity(0.6), tint: color)
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
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(routeColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: routeColor, radius: 4)
                Image(systemName: routeIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.hudCyan)
                Text(routeLabel)
                    .font(.hudMono(11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: viewModel.activeFrameSource.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(frameSourceColor)
                if viewModel.activeFrameSource == .rayBan {
                    BatteryBadge(rayBanManager: viewModel.rayBanManager)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .hudPanel(border: .hudLineStrong)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(routeAccessibility)

            HStack(spacing: 6) {
                stateIcon
                    .font(.system(size: 11, weight: .medium))
                    .hudGlow(stateColor, radius: 4)
                Text(viewModel.state.rawValue)
                    .font(.hudMono(11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(stateColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .hudPanel(border: stateColor.opacity(0.5))

            Spacer(minLength: 0)

            Button {
                haptic(.light)
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.hudCyan)
                    .hudGlow(radius: 4)
                    .frame(width: 36, height: 36)
                    .hudPanel(border: .hudLineStrong)
            }
            .accessibilityLabel("Einstellungen")
        }
        .foregroundStyle(Color.hudInk)
    }

    private var pairingHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 26))
                .foregroundStyle(Color.hudCyan)
                .hudGlow()
            VStack(alignment: .leading, spacing: 4) {
                Text("Mit deinem PC koppeln")
                    .font(.hudDisplay(14))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInk)
                Text("Auf dem PC Claude starten, Dashboard öffnen (localhost:18790) und den QR-Code mit der iPhone-Kamera scannen.")
                    .font(.caption)
                    .foregroundStyle(Color.hudMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(border: .hudLineStrong, glow: .hudGlow, accent: .hudCyan)
    }

    // MARK: - Banner

    private var liveTranscriptionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.hudCyan)
                .hudGlow(radius: 4)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(viewModel.currentTranscription)
                .font(.subheadline)
                .foregroundStyle(Color.hudInk)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(border: .hudLineStrong, accent: .hudCyan)
    }

    private func codeToastBanner(_ code: DetectedCode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "qrcode").foregroundStyle(Color.hudOK).hudGlow(.hudOK, radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(code.typeLabel)
                    .font(.hudMono(10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.hudOK.opacity(0.85))
                Text(code.value).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.hudInk).lineLimit(2)
            }
            Spacer()
            Button { viewModel.copyCodeToClipboard(code) } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(Color.hudOK)
                    .frame(width: 30, height: 30)
                    .hudPanel(border: Color.hudOK.opacity(0.5))
            }
            .accessibilityLabel("Code kopieren")
            Button { viewModel.sendCodeToChat(code) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.hudBackground)
                    .frame(width: 30, height: 30)
                    .background(Color.hudOK, in: RoundedRectangle(cornerRadius: HUDMetrics.radius))
                    .hudGlow(.hudOK)
            }
            .accessibilityLabel("Code an Claude senden")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hudPanel(border: Color.hudOK.opacity(0.5), accent: .hudOK)
    }

    private func noticeBanner(_ text: String) -> some View {
        Text(text)
            .font(.hudMono(11, weight: .medium))
            .foregroundStyle(Color.hudInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .hudPanel(border: .hudLineStrong)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.hudBad)
                .hudGlow(.hudBad, radius: 4)
            Text(error).font(.caption).foregroundStyle(Color.hudInk).lineLimit(3)
            Spacer()
            Button { viewModel.errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.hudBad)
                    .frame(width: 22, height: 22)
                    .hudPanel(border: Color.hudBad.opacity(0.6))
            }
            .accessibilityLabel("Meldung schließen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hudPanel(border: .hudBad, glow: Color.hudBad.opacity(0.35), accent: .hudBad, tint: .hudBad)
    }

    // MARK: - Eingabe

    private var textInputBar: some View {
        HStack(spacing: 8) {
            Text("›")
                .font(.hudMono(17, weight: .bold))
                .foregroundStyle(Color.hudCyan)
                .hudGlow(radius: 4)
                .accessibilityHidden(true)
            TextField("Nachricht", text: $textInput,
                      prompt: Text("Nachricht …").foregroundStyle(Color.hudMuted), axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.hudInk)
                .tint(.hudCyan)
                .onSubmit(sendTextInput)
            if !textInput.isEmpty {
                Button(action: sendTextInput) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.hudBackground)
                        .frame(width: 30, height: 30)
                        .background(Color.hudCyan, in: RoundedRectangle(cornerRadius: HUDMetrics.radius))
                        .hudGlow()
                }
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .hudPanel(border: .hudLineStrong)
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
                    Text("Neu").font(.hudMono(10, weight: .semibold)).textCase(.uppercase).tracking(1)
                }
                .foregroundStyle(Color.hudMuted)
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Gespräch zurücksetzen")

            micButton

            Button {
                haptic(.light)
                viewModel.activeFrameSource = viewModel.activeFrameSource == .iPhone ? .rayBan : .iPhone
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.activeFrameSource.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(frameSourceColor)
                        .hudGlow(frameSourceColor, radius: 4)
                    Text(viewModel.activeFrameSource.shortLabel)
                        .font(.hudMono(10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.hudMuted)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Kamera wechseln, aktuell \(viewModel.activeFrameSource.rawValue)")
        }
        .padding(.horizontal, 24)
        // Platz für die Reaktor-Ringe um den Mikrofon-Knopf
        .padding(.vertical, 18)
        .hudPanel(border: .hudLineStrong)
        .overlay(HUDCorners(length: 10).stroke(Color.hudCyan.opacity(0.8), lineWidth: 1.5))
        .padding(.horizontal, 12)
    }

    /// Mikrofon-Knopf; im Bereitschafts-Zustand („Sag ‚Hey Claude‘“) drehen sich Reaktor-Ringe darum
    private var micButton: some View {
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
                Circle()
                    .fill(RadialGradient(colors: [micButtonColor, micButtonColor.opacity(0.55)],
                                         center: .center, startRadius: 6, endRadius: 40))
                    .overlay(Circle().strokeBorder(micButtonColor, lineWidth: 1.5))
                    .shadow(color: micButtonColor.opacity(micIsDimmed ? 0 : 0.6), radius: 16)
                if viewModel.isProcessing && viewModel.state == .thinking {
                    ProgressView().tint(micIconColor)
                } else {
                    Image(systemName: micButtonIcon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(micIconColor)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 72, height: 72)
            .background { micHalo }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(micAccessibilityLabel)
    }

    @ViewBuilder
    private var micHalo: some View {
        switch viewModel.state {
        case .standby:
            ReactorRings(diameter: 112).transition(.opacity)
        case .listening:
            ListeningPulse(color: .hudBad)
        default:
            Circle()
                .strokeBorder(Color.hudLineStrong, lineWidth: HUDMetrics.hairline)
                .frame(width: 88, height: 88)
                .allowsHitTesting(false)
        }
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
        case .disconnected: return .hudBad
        case .idle: return .hudOK
        case .standby: return .hudCyan
        case .listening: return .hudBad
        case .thinking: return .hudWarn
        case .speaking: return .hudCyan
        }
    }

    /// Ohne Verbindung ist der Knopf gedimmt (tippen verbindet neu)
    private var micIsDimmed: Bool {
        switch viewModel.state {
        case .listening, .thinking, .speaking: return false
        default: return !viewModel.canTalk
        }
    }

    private var micButtonColor: Color {
        switch viewModel.state {
        case .listening: return .hudBad
        case .thinking: return .hudGold
        case .speaking: return .hudCyan
        default: return micIsDimmed ? .hudLineStrong : .hudCyan
        }
    }

    /// Nachtblaues Symbol auf leuchtendem Knopf, helles auf gedimmtem
    private var micIconColor: Color {
        micIsDimmed ? .hudInk : .hudBackground
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
        case .pc: return .hudOK
        case .direct: return .hudWarn
        case .none: return .hudBad
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
        case .connected: return .hudOK
        case .standby: return .hudOK.opacity(0.7)
        case .connecting: return .hudWarn
        case .error: return .hudBad
        case .disconnected: return .hudMuted
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
        VStack(alignment: .leading, spacing: 10) {
            Label("Claude möchte \(request.toolName) ausführen", systemImage: "lock.shield.fill")
                .font(.hudDisplay(13))
                .textCase(.uppercase)
                .foregroundStyle(Color.hudGold)
                .hudGlow(.hudGold, radius: 4)
            if !request.description.isEmpty {
                Text(request.description).font(.caption).foregroundStyle(Color.hudInk)
            }
            if !request.inputPreview.isEmpty {
                Text(request.inputPreview)
                    .font(.hudMono(11, weight: .regular))
                    .foregroundStyle(Color.hudInk)
                    .lineLimit(4)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.hudBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: HUDMetrics.radius))
                    .overlay(RoundedRectangle(cornerRadius: HUDMetrics.radius).strokeBorder(Color.hudLine, lineWidth: HUDMetrics.hairline))
            }
            HStack {
                Button(role: .destructive) { answer(false) } label: {
                    Label("Ablehnen", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(HUDButtonStyle(color: .hudBad))
                Button { answer(true) } label: {
                    Label("Erlauben", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(HUDButtonStyle(color: .hudOK, filled: true))
            }
            Text("Oder einfach „Ja“ bzw. „Nein“ sagen.").font(.hudMono(10)).foregroundStyle(Color.hudMuted)
        }
        .padding(14)
        .hudPanel(border: Color.hudGold.opacity(0.7), glow: Color.hudGold.opacity(0.3), accent: .hudGold, tint: .hudGold)
    }
}

// MARK: - Mikrofon hört zu

/// Pulsierender Ring, solange das Mikrofon offen ist (steht bei „Bewegung reduzieren“ still)
struct ListeningPulse: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.5), lineWidth: 3)
            .frame(width: 84, height: 84)
            .scaleEffect(pulse ? 1.25 : 1.0)
            .opacity(pulse ? 0 : 1)
            .shadow(color: color, radius: 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                pulse = false
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
            }
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
                HUDBackdrop()
                VStack(spacing: 18) {
                    lens
                    if status == .standby && isConnected {
                        HUDLabel("Kamera aus")
                        Text("Die Brille fotografiert nur auf Zuruf – wenn du etwas zeigst oder fragst („Was ist das?“).")
                            .font(.subheadline)
                            .foregroundStyle(Color.hudMuted)
                            .multilineTextAlignment(.center)
                    } else if status.isConnected {
                        ProgressView().tint(.hudCyan)
                        HUDLabel("Empfange Bild der Brille …")
                    } else {
                        Text(isConnected ? status.label : "Erst mit dem PC verbinden")
                            .font(.hudMono(13))
                            .foregroundStyle(Color.hudMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
                .overlay(HUDCorners(length: 18).stroke(Color.hudCyan.opacity(0.7), lineWidth: 2))
                .padding(.horizontal, 32)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Brillen-Symbol in einer stillstehenden Linse aus Haarlinien
    private var lens: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.hudGlow, .clear], center: .center, startRadius: 0, endRadius: 64))
            Circle()
                .strokeBorder(Color.hudLineStrong, lineWidth: HUDMetrics.hairline)
            Circle()
                .stroke(Color.hudRing, style: StrokeStyle(lineWidth: HUDMetrics.hairline, dash: [3, 4]))
                .padding(10)
            Image(systemName: "eyeglasses")
                .font(.system(size: 46, weight: .thin))
                .foregroundStyle(Color.hudCyan)
                .hudGlow(radius: 10)
        }
        .frame(width: 128, height: 128)
        .accessibilityHidden(true)
    }
}

struct BatteryBadge: View {
    @ObservedObject var rayBanManager: RayBanManager

    var body: some View {
        if let battery = rayBanManager.batteryLevel {
            Text("\(battery) %")
                .font(.hudMono(11, weight: .medium))
                .foregroundStyle(battery < 15 ? Color.hudBad : Color.hudInk)
                .accessibilityLabel("Akku der Brille \(battery) Prozent")
        }
    }
}

struct RayBanVideoView: UIViewRepresentable {
    @ObservedObject var rayBanManager: RayBanManager

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.backgroundColor = UIColor(Color.hudBackground)
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
                        .font(.hudMono(12, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .hudPanel(border: Color.hudGold.opacity(0.7), glow: Color.hudGold.opacity(0.25), tint: .hudGold)
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
        VStack(alignment: .leading, spacing: 10) {
            Label(confirmation.title, systemImage: icon)
                .font(.hudDisplay(14))
                .textCase(.uppercase)
                .foregroundStyle(Color.hudOK)
                .hudGlow(.hudOK, radius: 4)
            if case .message(let text) = confirmation.kind {
                Text("„\(text)“").font(.caption).foregroundStyle(Color.hudInk).lineLimit(3)
            }
            ForEach(confirmation.options) { option in
                Button { onSelect(option) } label: {
                    Label(option.label, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HUDButtonStyle(color: .hudOK, filled: true))
            }
            Button(role: .cancel, action: onCancel) {
                Text("Abbrechen").frame(maxWidth: .infinity)
            }
            .buttonStyle(HUDButtonStyle(color: .hudMuted))
            if confirmation.options.count == 1 {
                Text("Oder einfach „Ja“ bzw. „Nein“ sagen.").font(.hudMono(10)).foregroundStyle(Color.hudMuted)
            }
        }
        .padding(14)
        .hudPanel(border: Color.hudOK.opacity(0.7), glow: Color.hudOK.opacity(0.25), accent: .hudOK, tint: .hudOK)
    }
}
