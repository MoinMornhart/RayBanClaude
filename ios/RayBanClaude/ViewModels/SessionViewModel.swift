import Foundation
import Combine
import SwiftUI
import UIKit
import MWDATCore

enum SessionState: String {
    case disconnected = "Getrennt"
    case idle = "Bereit"
    case standby = "Sag „Hey Claude“"
    case listening = "Hört zu"
    case thinking = "Denkt nach"
    case speaking = "Spricht"
}

/// Über welchen Weg eine Frage gerade an Claude geht
enum Route: Equatable {
    /// PC: Claude Code (Channel) oder Gateway
    case pc
    /// Ohne PC: direkt an die Claude-API
    case direct
    /// Weder PC erreichbar noch API-Key vorhanden
    case none
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
            if config.wakeWordEnabled != oldValue.wakeWordEnabled, state == .idle || state == .standby { goIdle() }
            if config.memoryEnabled != oldValue.memoryEnabled { syncMemory() }
        }
    }

    /// Verbunden über Tailscale (unterwegs) statt übers Heim-WLAN
    @Published private(set) var viaTailscale = false

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
    let phoneActions = PhoneActionHandler()
    let directClient = DirectClaudeClient()
    /// Was Claude sich über dich merkt – im Demo-Modus nur im Arbeitsspeicher
    let memory = MemoryStore(persistent: !DemoMode.isActive)

    private var cancellables = Set<AnyCancellable>()
    private var watchdog: Task<Void, Never>?
    private var lastGatewayMode: String?
    /// Gateway-Gespräch kennt das Gedächtnis schon
    private var gatewayMemorySent = false
    /// Das Foto, das Claude zuletzt bekommen hat (für „Mach ein Foto“ → in der Mediathek sichern)
    private var lastPhoto: (data: Data, date: Date)?
    /// So lange gilt das letzte Foto noch als „das Foto von eben“
    private let lastPhotoValidity: TimeInterval = 120
    /// Weg der Frage, die gerade bearbeitet wird
    private var processingRoute: Route = .none

    /// Ohne Zustellbestätigung gilt eine Nachricht nach dieser Zeit als verloren
    private let ackTimeout: UInt64 = 10_000_000_000
    /// Ohne Antwort von Claude wird „Denkt nach“ nach dieser Zeit beendet
    private let replyTimeout: UInt64 = 180_000_000_000
    /// Nach einer Antwort so lange auf eine Rückfrage warten, dann wieder aufs Weckwort
    private let followUpTimeout: TimeInterval = 8

    init(config: ClaudeConfig = ClaudeConfig.load()) {
        self.config = config
        self.bridge = ClaudeBridge(config: config)
        applyConfig()
        setupBindings()
        setupBridgeCallbacks()
        setupSpeechCallbacks()
        setupPhoneActions()
        memory.onChange = { [weak self] in self?.syncMemory() }
        if DemoMode.isActive {
            loadDemo()
        } else {
            rayBanManager.startMonitoringRegistration()
            // Die Brille hat Vorrang: ist sie gekoppelt, ist sie die Kamera (iPhone nur als Ersatz)
            if rayBanManager.isRegistered { activeFrameSource = .rayBan }
        }
    }

    /// Beispielgespräch für Screenshots (`-demo`): nichts wird gestartet oder gesendet
    private func loadDemo() {
        activeFrameSource = .rayBan
        isConnected = true
        frameSourceStatus = .connected
        modeManager.setActiveMode(VisionMode.hvac)
        transcript = [
            TranscriptMessage(role: .user, text: "Wie alt ist die Therme und was heißt F28?"),
            TranscriptMessage(role: .assistant, text: "Eine Thermavia CondensPro 24 von 2014, also gut zwölf Jahre alt. F28 bedeutet: Zündung fehlgeschlagen – prüf zuerst, ob der Gashahn offen ist."),
            TranscriptMessage(role: .user, text: "Stell einen Timer auf zehn Minuten für die Nudeln."),
            TranscriptMessage(role: .system, text: "📱 Timer „Nudeln“ für 10 Min gestellt"),
            TranscriptMessage(role: .assistant, text: "Läuft – in zehn Minuten sag ich Bescheid."),
        ]
        var confirmation: ActionConfirmation?
        if DemoMode.showConfirmation {
            transcript.append(TranscriptMessage(role: .user, text: "Ruf Mama an."))
            transcript.append(TranscriptMessage(role: .system, text: "📱 Rückfrage auf dem iPhone: Anruf an Mama (Mobil)"))
            confirmation = ActionConfirmation(kind: .call, title: "Anruf an Mama?",
                                              options: [.init(label: "Mama (Mobil)", value: "+490000000000")])
        }
        phoneActions.showDemo(timerLabel: "Nudeln", seconds: 9 * 60 + 41, confirmation: confirmation)
        memory.loadDemo(["Tochter heißt Mia, Geburtstag am 3. Mai", "Trinkt Espresso ohne Zucker", "Arbeitet als Heizungsbauer"])
        state = .standby
    }

    // MARK: - Einrichtung

    private func applyConfig() {
        bridge.updateConfig(config)
        speechManager.setLanguage(config.speechLanguage)
        speechManager.setPauseThreshold(config.speechPauseThreshold)
        speechManager.configureElevenLabs(apiKey: config.elevenLabsAPIKey, voiceId: config.elevenLabsVoiceId)
        speechManager.wakeWordEnabled = config.wakeWordEnabled
        phoneActions.memory = config.memoryEnabled ? memory : nil
        cameraManager.configure(frameInterval: config.videoFrameInterval, jpegQuality: config.videoJPEGQuality)
        rayBanManager.configure(frameInterval: config.videoFrameInterval, jpegQuality: config.videoJPEGQuality)
    }

    private func setupBindings() {
        // Modus- und Aktions-Änderungen an die Oberfläche weiterreichen. Die Brille wird bewusst
        // NICHT weitergereicht – sonst würde jedes Videobild die ganze Oberfläche neu berechnen.
        [modeManager.objectWillChange, phoneActions.objectWillChange, memory.objectWillChange].forEach { publisher in
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }

        bridge.$state
            .sink { [weak self] state in self?.bridgeStateChanged(state) }
            .store(in: &cancellables)

        bridge.$isRemote
            .sink { [weak self] remote in self?.viaTailscale = remote }
            .store(in: &cancellables)

        // Brille später gekoppelt → ab sofort die Brille nehmen
        rayBanManager.$isRegistered
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in self?.activeFrameSource = .rayBan }
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
            .sink { [weak self] text in
                guard let self else { return }
                self.currentTranscription = text
                // Kamera schon wecken, während die Frage noch läuft („Was steht auf dem …“) – spart Wartezeit
                if self.speechManager.listenMode == .command, VisionIntent.needsImage(text) {
                    self.activeSource.prepareCapture()
                }
            }
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

        // Nach einem Anruf o. Ä. wieder aufs Weckwort hören
        NotificationCenter.default.publisher(for: .audioInterruptionEnded)
            .sink { [weak self] _ in self?.goIdle() }
            .store(in: &cancellables)
    }

    private func bridgeStateChanged(_ bridgeState: ClaudeBridge.ConnectionState) {
        isConnected = bridgeState == .connected
        switch bridgeState {
        case .connected:
            errorMessage = nil
        case .failed(let message):
            if route == .direct {
                notice = "PC nicht erreichbar – ich frage direkt"
            } else {
                errorMessage = message
            }
            fallthrough
        case .disconnected, .connecting:
            if processingRoute == .pc { finishProcessing() }
            pendingPermission = nil
            if route == .direct {
                activateDirect()
            } else if state != .disconnected {
                speechManager.releaseMicrophone()
                state = .disconnected
            }
        }
    }

    private func setupBridgeCallbacks() {
        bridge.onConnected = { [weak self] in
            guard let self else { return }
            try? AudioSessionManager.shared.configureForVoiceChat()
            self.syncMemory() // Claude am PC bekommt die Merkliste mit der ersten Nachricht
            if !self.activeSource.isRunning { self.startActiveFrameSource() }
            self.goIdle()
        }
        bridge.onMemory = { [weak self] op, items in self?.applyMemoryFromPC(op: op, items: items) }
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
        bridge.onPhoneAction = { [weak self] action in
            Task { await self?.handlePhoneAction(action) }
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
        speechManager.onWakeWord = { [weak self] in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self?.state = .listening
        }
        speechManager.onSpeechFinished = { [weak self] in
            guard let self, self.state == .speaking else { return }
            // canTalk statt isConnected – sonst gab es ohne PC (direkt) nie eine Rückfrage
            if self.config.autoListen && self.canTalk {
                // Kurz auf eine Rückfrage warten – mit Weckwort danach wieder in Bereitschaft
                self.startListening(noSpeechTimeout: self.config.wakeWordEnabled ? self.followUpTimeout : nil)
            } else {
                self.goIdle()
            }
        }
        // Zuhören ohne Befehl beendet (Stille, Fehler) → zurück in Bereitschaft
        speechManager.onListeningStopped = { [weak self] _ in
            guard let self, self.state == .listening else { return }
            self.goIdle()
        }
    }

    private func setupPhoneActions() {
        phoneActions.latestPhoto = { [weak self] in
            guard let self else { return nil }
            if let recent = self.lastPhoto, Date().timeIntervalSince(recent.date) < self.lastPhotoValidity {
                return recent.data
            }
            return await self.takePhoto()
        }
        phoneActions.onTimerFired = { [weak self] timer in
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            let text = timer.isAlarm ? "Wecker: \(timer.label)." : "Dein Timer \(timer.label) ist abgelaufen."
            self?.transcript.append(TranscriptMessage(role: .system, text: "⏱ \(text)"))
            self?.speak(text, audioPath: nil)
        }
    }

    /// PC verbunden → PC; sonst (wenn erlaubt und API-Key da) direkt; sonst nichts
    var route: Route {
        if config.connectionMode == .direct { return config.hasDirectKey ? .direct : .none }
        if isConnected { return .pc }
        return config.directFallback && config.hasDirectKey ? .direct : .none
    }

    /// Kann gerade gefragt werden (PC oder direkt)?
    var canTalk: Bool { route != .none }

    /// Ruhezustand ohne laufende Aufnahme: mit Weckwort „Sag Hey Claude“, sonst „Bereit“
    private var restingState: SessionState {
        guard canTalk else { return .disconnected }
        return config.wakeWordEnabled ? .standby : .idle
    }

    /// Zurück in den Ruhezustand – mit Weckwort hört die App wieder auf „Hey Claude“.
    func goIdle() {
        guard !speechManager.isSpeaking else { return }
        if canTalk && config.wakeWordEnabled {
            speechManager.enterStandby()
        } else {
            speechManager.releaseMicrophone() // ohne Weckwort braucht niemand das Mikrofon
        }
        state = isProcessing ? .thinking : restingState
    }

    // MARK: - Vordergrund / Hintergrund

    /// Gesperrt oder in der Tasche: Mit Hosentaschen-Modus hört die App über die Brille weiter
    /// (Hintergrund-Audio), sonst gibt sie das Mikrofon frei. Zurück im Vordergrund geht es weiter.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if !config.listenWhenLocked {
                speechManager.releaseMicrophone()
                // Brillen-Sitzung vor dem Anhalten der App sauber beenden – sonst kann die Brille hängen bleiben
                rayBanManager.releaseCamera()
                if state == .standby || state == .listening { state = .idle }
            }
        case .active:
            Task { await phoneActions.refreshTimers() }
            if !speechManager.isSpeaking, !speechManager.isListening, state != .disconnected { goIdle() }
        default:
            break
        }
    }

    // MARK: - Verbindung

    func connect() async {
        errorMessage = nil
        if config.connectionMode.usesPC {
            if config.baseURL != nil, !config.channelToken.isEmpty {
                await bridge.connect()
            } else if !config.hasDirectKey {
                errorMessage = "Noch nicht gekoppelt – QR-Code im PC-Dashboard scannen oder in den Einstellungen „Ohne PC“ einrichten"
            }
        }
        if route == .direct { activateDirect() }
        if route == .none && config.connectionMode == .direct {
            errorMessage = DirectError.missingKey.localizedDescription
        }
    }

    /// Ohne PC loslegen: Kamera starten und aufs Weckwort hören
    private func activateDirect() {
        if !activeSource.isRunning { startActiveFrameSource() }
        if state == .disconnected || state == .idle || state == .standby { goIdle() }
    }

    func disconnect() {
        speechManager.releaseMicrophone()
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
        updated.remoteHost = pairing.remote ?? ""
        updated.gatewayPort = pairing.port
        updated.channelToken = pairing.token
        updated.connectionMode = .channel
        config = updated
        notice = pairing.remote == nil
            ? "Gekoppelt mit \(pairing.host)"
            : "Gekoppelt – zu Hause über WLAN, unterwegs über Tailscale"
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
        if canTalk { startActiveFrameSource() }
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

    /// Mikrofon-Knopf: in Bereitschaft oder Ruhe sofort zuhören, beim Zuhören abbrechen
    func toggleListening() {
        if speechManager.listenMode == .command {
            speechManager.stopListening()
            goIdle()
        } else {
            startListening()
        }
    }

    func startListening(noSpeechTimeout: TimeInterval? = nil) {
        do {
            try speechManager.startListening(mode: .command, noSpeechTimeout: noSpeechTimeout)
            state = .listening
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            goIdle()
        }
    }

    func interruptSpeaking() {
        speechManager.stopSpeaking()
        state = restingState
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
        // Offene Freigabe oder Rückfrage? Dann ist „ja“/„nein“ die Antwort darauf.
        if let request = pendingPermission, let allow = Self.interpretYesNo(text) {
            await answerPermission(request, allow: allow)
            goIdle()
            return
        }
        if let confirmation = phoneActions.confirmation, confirmation.options.count == 1, let yes = Self.interpretYesNo(text) {
            if yes { confirmAction(confirmation.options[0]) } else { dismissAction() }
            goIdle()
            return
        }
        guard !isProcessing else {
            notice = "Claude antwortet noch – kurz warten"
            goIdle()
            return
        }
        // Früher stand hier „guard isConnected“ – das hat den Weg ohne PC (direkt) komplett blockiert
        let currentRoute = route
        guard currentRoute != .none else {
            errorMessage = "Nicht verbunden – mit dem PC koppeln oder „Ohne PC“ einrichten"
            return
        }

        let id = "ios-\(UUID().uuidString.prefix(8))"
        let viaChannel = currentRoute == .pc && config.connectionMode == .channel
        transcript.append(TranscriptMessage(id: id, role: .user, text: text, delivered: !viaChannel))
        currentTranscription = ""
        isProcessing = true
        processingRoute = currentRoute
        errorMessage = nil
        goIdle() // während Claude nachdenkt, reagiert die App weiter auf „Hey Claude“
        // Wie Meta AI: Foto nur, wenn die Frage eins braucht – sonst bleibt die Kamera aus
        let image = VisionIntent.needsImage(text) ? await photoForQuestion() : nil

        if currentRoute == .direct {
            await sendDirect(text: text, image: image)
        } else if viaChannel {
            do {
                armWatchdog(replyTimeout: false)
                try await bridge.send(.init(id: id, text: text, source: activeFrameSource, mode: modeManager.activeMode, image: image))
            } catch {
                errorMessage = error.localizedDescription
                finishProcessing()
            }
        } else {
            await sendViaGateway(text: text, image: image)
        }
    }

    /// Foto für eine Frage: iPhone-Sucher → aktuelles Bild; Brille → kurz Kamera an, Foto, wieder aus
    private func photoForQuestion() async -> Data? {
        if activeFrameSource == .iPhone, let frame = activeSource.consumeFrame() {
            lastPhoto = (frame, Date())
            return frame
        }
        let photo = await takePhoto()
        if photo == nil {
            notice = activeFrameSource == .rayBan
                ? "Brille konnte kein Foto machen – ich frage ohne Bild"
                : "Kein Kamerabild – ich frage ohne Bild"
        }
        return photo
    }

    /// Frisches Foto aufnehmen und als „Foto von eben“ merken. Erst die Brille – kann sie gerade nicht,
    /// springt (bei offener App) die iPhone-Kamera ein.
    private func takePhoto() async -> Data? {
        var captured = await activeSource.capturePhoto()
        if captured == nil, activeFrameSource == .rayBan, let fallback = await iPhoneFallbackPhoto() {
            notice = "Brille nicht bereit – Foto mit der iPhone-Kamera"
            captured = fallback
        }
        guard let photo = captured else { return nil }
        lastPhoto = (photo, Date())
        transcript.append(TranscriptMessage(role: .system, text: "📸 Foto an Claude"))
        return photo
    }

    /// Ersatz-Foto mit der iPhone-Kamera (nur wenn die App im Vordergrund ist – sonst sperrt iOS die Kamera)
    private func iPhoneFallbackPhoto() async -> Data? {
        guard UIApplication.shared.applicationState == .active else { return nil }
        let wasRunning = cameraManager.isRunning
        if !wasRunning {
            guard (try? cameraManager.start()) != nil else { return nil }
            // Kamera kurz anlaufen und belichten lassen (max. 2 s)
            for _ in 0..<20 where !cameraManager.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let photo = await cameraManager.capturePhoto()
        if !wasRunning { cameraManager.stop() }
        return photo
    }

    /// Ohne PC: direkt an die Claude-API; Handy-Aktionen und Fotos laufen lokal
    private func sendDirect(text: String, image: Data?) async {
        do {
            let answer = try await directClient.ask(text, image: image, mode: modeManager.activeMode, config: config,
                                                    memory: config.memoryEnabled ? memory.texts : nil) { [weak self] name, input in
                await self?.executeDirectTool(name: name, input: input)
                    ?? DirectClaudeClient.ToolOutput(text: "App nicht verfügbar", isError: true)
            }
            transcript.append(TranscriptMessage(role: .assistant, text: answer.text, toolCalls: answer.toolsUsed))
            finishProcessing()
            speak(answer.text, audioPath: nil)
        } catch {
            errorMessage = error.localizedDescription
            finishProcessing()
        }
    }

    private func executeDirectTool(name: String, input: [String: Any]) async -> DirectClaudeClient.ToolOutput {
        switch name {
        case "take_photo":
            guard let photo = await takePhoto() else {
                return DirectClaudeClient.ToolOutput(text: "Kein Kamerabild verfügbar (Brille nicht bereit oder iPhone-Kamera aus)", isError: true)
            }
            return DirectClaudeClient.ToolOutput(text: "Aktuelles Foto", imageJPEG: photo)
        case "phone_action":
            guard let kind = (input["action"] as? String).flatMap(PhoneAction.Kind.init(rawValue:)) else {
                return DirectClaudeClient.ToolOutput(text: "Unbekannte Aktion", isError: true)
            }
            let action = PhoneAction(
                id: UUID().uuidString, kind: kind,
                durationSeconds: input["duration_seconds"] as? Int,
                time: input["time"] as? String,
                date: input["date"] as? String,
                label: input["label"] as? String,
                contact: input["contact"] as? String,
                number: input["number"] as? String,
                text: input["text"] as? String,
                destination: input["destination"] as? String
            )
            let result = await phoneActions.handle(action)
            transcript.append(TranscriptMessage(role: .system, text: (result.ok ? "📱 " : "⚠️ ") + result.message))
            return DirectClaudeClient.ToolOutput(text: result.message, isError: !result.ok)
        case "remember":
            guard config.memoryEnabled, let saved = memory.add(input["fact"] as? String ?? "") else {
                return DirectClaudeClient.ToolOutput(text: "Nichts gespeichert (leer oder Gedächtnis aus)", isError: true)
            }
            directClient.acknowledgeMemory(memory.texts)
            transcript.append(TranscriptMessage(role: .system, text: "🧠 Gemerkt: \(saved)"))
            return DirectClaudeClient.ToolOutput(text: "Gemerkt – \(memory.items.count) Einträge im Gedächtnis.")
        case "forget":
            let removed = memory.forget(matching: input["fact"] as? String ?? "")
            guard !removed.isEmpty else { return DirectClaudeClient.ToolOutput(text: "Dazu ist nichts gespeichert.") }
            directClient.acknowledgeMemory(memory.texts)
            transcript.append(TranscriptMessage(role: .system, text: "🧠 Vergessen: \(removed.joined(separator: ", "))"))
            return DirectClaudeClient.ToolOutput(text: "Gelöscht: \(removed.joined(separator: " | "))")
        default:
            return DirectClaudeClient.ToolOutput(text: "Unbekanntes Werkzeug \(name)", isError: true)
        }
    }

    private func sendViaGateway(text: String, image: Data?) async {
        let mode = modeManager.activeMode
        // Modus-Kontext nur beim Wechsel mitschicken (die Konversation merkt ihn sich)
        var prefix = lastGatewayMode == mode.id ? "" : "[Modus „\(mode.name)“: \(mode.systemPrompt)]\n\n"
        lastGatewayMode = mode.id
        // Gedächtnis einmal pro Gespräch (das Gateway merkt sich den Verlauf); Merken geht dort nur in der App
        if config.memoryEnabled, !gatewayMemorySent, !memory.items.isEmpty {
            prefix = MemoryStore.promptBlock(memory.texts) + "\n" + prefix
        }
        gatewayMemorySent = true
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
        if state == .thinking { state = restingState }
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
        let photo = await takePhoto()
        if photo == nil { notice = "Foto nicht möglich – Brille bereit?" }
        do {
            // Auch ohne Foto antworten – sonst wartet Claude vergeblich
            try await bridge.send(.init(id: "photo-\(UUID().uuidString.prefix(8))",
                                        text: photo == nil ? "(Foto nicht möglich – Kamera nicht bereit)" : "",
                                        source: activeFrameSource, mode: modeManager.activeMode, image: photo, inReplyTo: id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Handy-Aktionen (Tool phone_action)

    private func handlePhoneAction(_ action: PhoneAction) async {
        let result = await phoneActions.handle(action)
        transcript.append(TranscriptMessage(role: .system, text: (result.ok ? "📱 " : "⚠️ ") + result.message))
        if phoneActions.confirmation != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        do {
            try await bridge.sendActionResult(id: action.id, result: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmAction(_ option: ActionConfirmation.Option) {
        transcript.append(TranscriptMessage(role: .system, text: "✅ \(option.label)"))
        phoneActions.confirm(option)
    }

    func dismissAction() {
        phoneActions.dismissConfirmation()
        transcript.append(TranscriptMessage(role: .system, text: "⛔ Abgebrochen"))
    }

    // MARK: - Gedächtnis

    /// Merkliste an Claude am PC schicken (nur Channel; Direkt und Gateway bekommen sie mit der Frage)
    private func syncMemory() {
        gatewayMemorySent = false
        Task {
            do {
                try await bridge.sendMemory(memory.texts, enabled: config.memoryEnabled)
            } catch {
                print("[Gedächtnis] Abgleich mit dem PC fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }

    /// Claude am PC hat sich etwas gemerkt oder vergessen
    private func applyMemoryFromPC(op: String, items: [String]) {
        guard config.memoryEnabled else { return }
        switch op {
        case "add":
            items.forEach { memory.add($0, notify: false) }
            transcript.append(TranscriptMessage(role: .system, text: "🧠 Gemerkt: \(items.joined(separator: ", "))"))
        case "remove":
            memory.remove(texts: items, notify: false)
            transcript.append(TranscriptMessage(role: .system, text: "🧠 Vergessen: \(items.joined(separator: ", "))"))
        default:
            break
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

    private static let yesWords = ["ja", "jawohl", "jo", "erlauben", "erlaube", "okay", "ok", "klar", "mach", "yes", "gerne", "anrufen", "senden", "los"]
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
        directClient.reset()
        lastGatewayMode = nil
        gatewayMemorySent = false
        errorMessage = nil
    }
}
