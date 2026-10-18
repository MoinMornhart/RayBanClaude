import Foundation
import Combine
import UIKit
import MWDATCore

enum SessionState: String {
    case disconnected = "Getrennt"
    case idle = "Bereit"
    case listening = "Hört zu"
    case thinking = "Denkt nach"
    case speaking = "Spricht"
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var state: SessionState = .disconnected
    @Published private(set) var transcript: [TranscriptMessage] = []
    @Published private(set) var currentTranscription: String = ""
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var notice: String?

    @Published var config: ClaudeConfig {
        didSet {
            guard config != oldValue else { return }
            applyConfig()
            config.save()
        }
    }

    @Published var activeFrameSource: FrameSourceType = .iPhone {
        didSet { if activeFrameSource != oldValue { switchFrameSource() } }
    }
    @Published private(set) var frameSourceStatus: FrameSourceStatus = .disconnected

    /// Kopplung aus QR-Code – wartet auf Bestätigung
    @Published var pendingPairing: PairingRequest?
    /// Tool-Freigabe von Claude Code – wartet auf Erlauben/Ablehnen
    @Published private(set) var pendingPermission: PermissionRequest?

    @Published var codeToast: DetectedCode?

    let modeManager = ModeManager()
    let bridge: ClaudeBridge
    let speechManager = SpeechManager()
    let cameraManager = CameraManager()
    let rayBanManager = RayBanManager()

    private var cancellables = Set<AnyCancellable>()
    private var watchdog: Task<Void, Never>?
    private var lastGatewayMode: String?

    /// Ohne Zustellbestätigung gilt eine Nachricht nach dieser Zeit als verloren
    private let ackTimeout: UInt64 = 10_000_000_000
    /// Ohne Antwort von Claude wird „Denkt nach“ nach dieser Zeit beendet
    private let replyTimeout: UInt64 = 180_000_000_000

    init(config: ClaudeConfig = ClaudeConfig.load()) {
        self.config = config
        self.bridge = ClaudeBridge(config: config)
        applyConfig()
        setupBindings()
        setupBridgeCallbacks()
        setupSpeechCallbacks()
        rayBanManager.startMonitoringRegistration()
    }

    // MARK: - Einrichtung

    private func applyConfig() {
        bridge.updateConfig(config)
        speechManager.setLanguage(config.speechLanguage)
        speechManager.setPauseThreshold(config.speechPauseThreshold)
        speechManager.configureElevenLabs(apiKey: config.elevenLabsAPIKey, voiceId: config.elevenLabsVoiceId)
        cameraManager.configure(frameInterval: config.videoFrameInterval, jpegQuality: config.videoJPEGQuality)
        rayBanManager.configure(frameInterval: config.videoFrameInterval, jpegQuality: config.videoJPEGQuality)
    }

    private func setupBindings() {
        // Modus-Änderungen an die Oberfläche weiterreichen (früher aktualisierte sich die
        // Modus-Auswahl nicht). Die Brille wird bewusst NICHT weitergereicht – sonst würde
        // jedes Videobild die ganze Oberfläche neu berechnen; dafür gibt es eigene Teilansichten.
        modeManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        bridge.$state
            .sink { [weak self] state in self?.bridgeStateChanged(state) }
            .store(in: &cancellables)

        rayBanManager.$connectionStatus
            .sink { [weak self] status in
                guard let self, self.activeFrameSource == .rayBan else { return }
                self.frameSourceStatus = status
            }
            .store(in: &cancellables)

        cameraManager.$connectionStatus
            .sink { [weak self] status in
                guard let self, self.activeFrameSource == .iPhone else { return }
                self.frameSourceStatus = status
            }
            .store(in: &cancellables)

        speechManager.$transcribedText
            .sink { [weak self] text in self?.currentTranscription = text }
            .store(in: &cancellables)

        cameraManager.$lastDetectedCode
            .compactMap { $0 }
            .sink { [weak self] code in self?.handleDetectedCode(code) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .audioInterruptionBegan)
            .sink { [weak self] _ in
                self?.speechManager.stopListening()
                self?.speechManager.stopSpeaking()
                if self?.isConnected == true { self?.state = .idle }
            }
            .store(in: &cancellables)
    }

    private func bridgeStateChanged(_ bridgeState: ClaudeBridge.ConnectionState) {
        isConnected = bridgeState == .connected
        switch bridgeState {
        case .connected:
            errorMessage = nil
        case .failed(let message):
            errorMessage = message
            fallthrough
        case .disconnected, .connecting:
            finishProcessing()
            pendingPermission = nil
            if state != .disconnected {
                speechManager.stopListening()
                state = .disconnected
            }
        }
    }

    private func setupBridgeCallbacks() {
        bridge.onConnected = { [weak self] in
            guard let self else { return }
            self.state = .idle
            try? AudioSessionManager.shared.configureForVoiceChat()
            self.startActiveFrameSource()
        }
        bridge.onReply = { [weak self] reply in self?.handleReply(reply) }
        bridge.onEdit = { [weak self] id, text in
            guard let self, let index = self.transcript.firstIndex(where: { $0.id == id }) else { return }
            self.transcript[index].text = text
        }
        bridge.onAck = { [weak self] id in
            guard let self, let index = self.transcript.firstIndex(where: { $0.id == id }) else { return }
            self.transcript[index].delivered = true
            self.armWatchdog(replyTimeout: true)
        }
        bridge.onCaptureRequest = { [weak self] id, reason in
            Task { await self?.handleCaptureRequest(id: id, reason: reason) }
        }
        bridge.onPermissionRequest = { [weak self] request in self?.handlePermissionRequest(request) }
        bridge.onPermissionResolved = { [weak self] id in
            if self?.pendingPermission?.id == id { self?.pendingPermission = nil }
        }
        bridge.onServerError = { [weak self] message in
            self?.errorMessage = message
            self?.finishProcessing()
        }
    }

    private func setupSpeechCallbacks() {
        speechManager.onSpeechPause = { [weak self] text in
            Task { await self?.handleUserSpeech(text) }
        }
        speechManager.onSpeechFinished = { [weak self] in
            guard let self, self.state == .speaking else { return }
            self.state = self.isConnected ? .idle : .disconnected
            if self.config.autoListen && self.isConnected { self.startListening() }
        }
        // Erkennung vom System beendet → Zustand nicht mehr fälschlich auf „Hört zu“
        speechManager.onListeningStopped = { [weak self] _ in
            guard let self, self.state == .listening else { return }
            self.state = self.isConnected ? .idle : .disconnected
        }
    }

    // MARK: - Verbindung

    func connect() async {
        errorMessage = nil
        guard config.baseURL != nil, !config.channelToken.isEmpty else {
            errorMessage = "Noch nicht gekoppelt – QR-Code im PC-Dashboard mit der iPhone-Kamera scannen"
            return
        }
        await bridge.connect()
    }

    func disconnect() {
        speechManager.stopListening()
        speechManager.stopSpeaking()
        cameraManager.stop()
        rayBanManager.stop()
        bridge.disconnect()
        frameSourceStatus = .disconnected
        state = .disconnected
    }

    /// Links an die App: Kopplung (`raybanclaude://pair?…`) oder Rückruf der Meta-AI-App.
    func handleIncomingURL(_ url: URL) {
        if let pairing = PairingRequest(url: url) {
            pendingPairing = pairing
            return
        }
        guard URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .contains(where: { $0.name == "metaWearablesAction" }) == true else {
            if url.host == PairingRequest.urlHost {
                errorMessage = "Ungültiger Kopplungs-Code – im Dashboard neu erzeugen"
            }
            return
        }
        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
            } catch {
                errorMessage = "Meta-AI-Rückmeldung fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func confirmPairing() {
        guard let pairing = pendingPairing else { return }
        pendingPairing = nil
        var updated = config
        updated.gatewayHost = pairing.host
        updated.gatewayPort = pairing.port
        updated.channelToken = pairing.token
        updated.connectionMode = .channel
        config = updated
        notice = "Gekoppelt mit \(pairing.host)"
        Task { await connect() }
    }

    func connectGlasses() async {
        await rayBanManager.register()
    }

    // MARK: - Bildquelle

    private func switchFrameSource() {
        cameraManager.stop()
        rayBanManager.stop()
        frameSourceStatus = .disconnected
        if isConnected { startActiveFrameSource() }
    }

    private func startActiveFrameSource() {
        do {
            switch activeFrameSource {
            case .iPhone: try cameraManager.start()
            case .rayBan: try rayBanManager.start()
            }
        } catch {
            frameSourceStatus = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private var activeSource: any FrameSource {
        switch activeFrameSource {
        case .iPhone: return cameraManager
        case .rayBan: return rayBanManager
        }
    }

    // MARK: - QR-/Barcodes

    private func handleDetectedCode(_ code: DetectedCode) {
        if modeManager.activeMode.id == VisionMode.qrScanner.id {
            Task { await sendText("Ich habe einen \(code.typeLabel)-Code gescannt: \(code.value). Was ist das?") }
            return
        }
        codeToast = code
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.codeToast?.timestamp == code.timestamp { self?.codeToast = nil }
        }
    }

    func sendCodeToChat(_ code: DetectedCode) {
        codeToast = nil
        Task { await sendText("Ich habe einen \(code.typeLabel)-Code gescannt: \(code.value). Was ist das?") }
    }

    func copyCodeToClipboard(_ code: DetectedCode) {
        UIPasteboard.general.string = code.value
        codeToast = nil
        notice = "Kopiert"
    }

    // MARK: - Sprache

    func toggleListening() {
        if speechManager.isListening {
            speechManager.stopListening()
            state = isConnected ? .idle : .disconnected
        } else {
            startListening()
        }
    }

    func startListening() {
        do {
            try speechManager.startListening()
            state = .listening
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            state = isConnected ? .idle : .disconnected
        }
    }

    func interruptSpeaking() {
        speechManager.stopSpeaking()
        state = isConnected ? .idle : .disconnected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startListening()
        }
    }

    // MARK: - Senden

    func sendText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await handleUserSpeech(trimmed)
    }

    private func handleUserSpeech(_ text: String) async {
        // Offene Freigabe? Dann ist „ja“/„nein“ die Antwort darauf.
        if let request = pendingPermission, let allow = Self.interpretYesNo(text) {
            await answerPermission(request, allow: allow)
            return
        }
        guard !isProcessing else {
            notice = "Claude antwortet noch – kurz warten"
            return
        }
        guard isConnected else {
            errorMessage = "Nicht verbunden – erst mit dem PC verbinden"
            return
        }

        let id = "ios-\(UUID().uuidString.prefix(8))"
        transcript.append(TranscriptMessage(id: id, role: .user, text: text, delivered: config.connectionMode == .gateway))
        currentTranscription = ""
        isProcessing = true
        state = .thinking
        errorMessage = nil
        let image = activeSource.consumeFrame()

        switch config.connectionMode {
        case .channel:
            do {
                armWatchdog(replyTimeout: false)
                try await bridge.send(.init(id: id, text: text, source: activeFrameSource, mode: modeManager.activeMode, image: image))
            } catch {
                errorMessage = error.localizedDescription
                finishProcessing()
            }
        case .gateway:
            await sendViaGateway(text: text, image: image)
        }
    }

    private func sendViaGateway(text: String, image: Data?) async {
        let mode = modeManager.activeMode
        // Modus-Kontext nur beim Wechsel mitschicken (die Konversation merkt ihn sich)
        let prefix = lastGatewayMode == mode.id ? "" : "[Modus „\(mode.name)“: \(mode.systemPrompt)]\n\n"
        lastGatewayMode = mode.id
        do {
            let response = try await bridge.chatREST(text: prefix + text, images: image.map { [$0] } ?? [])
            transcript.append(TranscriptMessage(role: .assistant, text: response.text, toolCalls: response.tool_calls.map(\.name)))
            finishProcessing()
            speak(response.text, audioPath: nil)
        } catch {
            errorMessage = error.localizedDescription
            finishProcessing()
        }
    }

    private func handleReply(_ reply: ClaudeBridge.Reply) {
        transcript.append(TranscriptMessage(id: reply.id, role: .assistant, text: reply.text, attachments: reply.attachments))
        finishProcessing()
        speak(reply.text, audioPath: reply.audioPath)
    }

    private func speak(_ text: String, audioPath: String?) {
        speechManager.stopListening()
        state = .speaking
        if let audioPath, let request = bridge.fileRequest(audioPath) {
            speechManager.playRemoteAudio(request: request, fallbackText: text)
        } else {
            speechManager.speak(text)
        }
    }

    private func finishProcessing() {
        watchdog?.cancel()
        watchdog = nil
        isProcessing = false
        if state == .thinking { state = isConnected ? .idle : .disconnected }
    }

    /// Früher blieb die App ohne Antwort für immer bei „Denkt nach“ hängen.
    private func armWatchdog(replyTimeout: Bool) {
        watchdog?.cancel()
        let delay = replyTimeout ? self.replyTimeout : ackTimeout
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.isProcessing else { return }
            self.errorMessage = replyTimeout
                ? "Keine Antwort von Claude – läuft Claude Code noch? Im Terminal nach Freigaben schauen."
                : "Nachricht nicht angekommen – läuft Claude Code mit dem Channel?"
            self.finishProcessing()
        }
    }

    // MARK: - Foto auf Anfrage (Tool request_photo)

    private func handleCaptureRequest(id: String, reason: String?) async {
        notice = "📸 Claude macht ein Foto" + (reason.map { ": \($0)" } ?? "")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard let photo = await activeSource.capturePhoto() else {
            errorMessage = "Foto nicht möglich – ist die Kamera aktiv?"
            return
        }
        transcript.append(TranscriptMessage(role: .system, text: "📸 Foto an Claude gesendet" + (reason.map { " (\($0))" } ?? "")))
        do {
            try await bridge.send(.init(id: "photo-\(UUID().uuidString.prefix(8))", text: "", source: activeFrameSource,
                                        mode: modeManager.activeMode, image: photo, inReplyTo: id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Freigaben (Permission-Relay)

    private func handlePermissionRequest(_ request: PermissionRequest) {
        pendingPermission = request
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        // Freihändig: Frage vorlesen, danach mit „ja“/„nein“ antworten
        let question = "Claude möchte \(request.toolName) ausführen. \(request.description). Erlauben?"
        speak(question, audioPath: nil)
    }

    func answerPermission(_ request: PermissionRequest, allow: Bool) async {
        pendingPermission = nil
        do {
            try await bridge.sendPermission(requestId: request.id, allow: allow)
            transcript.append(TranscriptMessage(role: .system, text: allow ? "✅ \(request.toolName) erlaubt" : "⛔ \(request.toolName) abgelehnt"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let yesWords = ["ja", "jawohl", "jo", "erlauben", "erlaube", "okay", "ok", "klar", "mach", "yes", "gerne"]
    private static let noWords = ["nein", "nö", "ne", "nicht", "ablehnen", "lehne", "stopp", "stop", "no", "abbrechen"]

    /// „Ja“/„Nein“ aus einer gesprochenen Antwort lesen (nil = unklar)
    static func interpretYesNo(_ text: String) -> Bool? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let saysNo = words.contains { noWords.contains($0) }
        let saysYes = words.contains { yesWords.contains($0) }
        if saysNo { return false } // im Zweifel ablehnen
        return saysYes ? true : nil
    }

    // MARK: - Verlauf

    func resetConversation() {
        transcript.removeAll()
        bridge.resetConversation()
        lastGatewayMode = nil
        errorMessage = nil
    }
}
