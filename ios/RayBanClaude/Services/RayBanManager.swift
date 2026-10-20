import Foundation
import Combine
import UIKit
import MWDATCore
import MWDATCamera
import MWDATInputs

/// Gesten der Brille, die die App versteht (übersetzt aus `MWDATInputs.InputEvent`)
enum GlassesGesture: Equatable {
    /// Doppeltipp auf das Touchpad (bzw. Aktionstaste): sofort zuhören, ohne Weckwort
    case listen
    /// Capture-Taste kurz gedrückt: Foto machen und „Was siehst du?“ fragen
    case photo
    /// Zurück-Geste: Antwort bzw. Zuhören abbrechen (liefern echte Brillen laut Meta noch nicht)
    case cancel
}

/// Kamera und Gesten der Ray-Ban Meta (Gen 1 und Gen 2) über das Meta Wearables DAT SDK 1.x.
///
/// Wie bei Meta AI filmt die Brille NICHT dauernd: Sie ist nur „bereit“. Die Geräte-Sitzung bleibt
/// offen, damit Touchpad und Capture-Taste ankommen (experimentelles Modul `MWDATInputs`) – die
/// Kamera aber startet nur für ein Foto (Kamera → Stream → Foto) und geht nach einer kurzen
/// Nachlaufzeit wieder aus. Sind die Gesten ausgeschaltet, geht die Sitzung mit der Kamera aus.
///
/// Ablauf laut SDK: Registrierung → Kamera-Freigabe → DeviceSession starten →
/// auf `.started` warten → Inputs anhängen · pro Foto: Kamera hinzufügen → Audio (HFP) → Stream.
@MainActor
final class RayBanManager: NSObject, ObservableObject, FrameSource {

    // MARK: FrameSource

    @Published private(set) var latestFrame: Data?
    @Published private(set) var latestImage: UIImage?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var connectionStatus: FrameSourceStatus = .disconnected
    @Published private(set) var frameCount: Int = 0
    let sourceType: FrameSourceType = .rayBan

    // MARK: Gerätestatus

    @Published private(set) var glassesName: String = "Nicht verbunden"
    @Published private(set) var deviceModel: String?
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var hingesOpen: Bool?
    @Published private(set) var hasActiveDevice: Bool = false
    @Published private(set) var isRegistered: Bool = false
    @Published private(set) var registrationLabel: String = "Nicht registriert"
    @Published private(set) var updateHint: String?

    // MARK: Gesten

    /// Touchpad und Capture-Taste kommen gerade bei der App an
    @Published private(set) var gesturesActive: Bool = false
    /// Warum die Gesten nicht gehen (z. B. nicht freigeschaltet)
    @Published private(set) var gestureHint: String?
    /// Erkannte Geste – die Ablaufsteuerung entscheidet, was passiert
    var onGesture: ((GlassesGesture) -> Void)?
    /// Gesten an: Sitzung bleibt offen. Aus: Sitzung nur fürs Foto (wie vor den Gesten).
    var gesturesEnabled = true {
        didSet {
            guard gesturesEnabled != oldValue else { return }
            gesturesEnabledChanged()
        }
    }

    // MARK: SDK-Objekte

    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private var inputs: Inputs?
    private let sessionTokens = ListenerTokenBag()
    private let streamTokens = ListenerTokenBag()
    private let inputsTokens = ListenerTokenBag()
    private let deviceTokens = ListenerTokenBag()
    private var registrationTask: Task<Void, Never>?
    /// Kamera-Start für ein Foto
    private var startTask: Task<Void, Never>?
    /// Aufbau der Sitzung – gleichzeitige Aufrufer warten auf denselben Aufbau
    private var sessionTask: Task<DeviceSession?, Never>?
    private var sessionAttempt = 0
    private var sessionRetryTask: Task<Void, Never>?
    private var inputsDrain: Task<Void, Never>?
    private var inputsAttachTask: Task<Void, Never>?
    private nonisolated let gate = FrameGate()
    private var photoWaiter: CheckedContinuation<Data?, Never>?
    /// Brille ist als Bildquelle gewählt und bereit (Kamera startet nur bei Bedarf)
    private var isArmed = false
    /// Vor dem Anhalten der App freigegeben – keine Sitzung von selbst neu öffnen
    private var isSuspended = false
    private var idleStopTask: Task<Void, Never>?
    /// Audio (HFP) wurde schon einmal eingerichtet und hatte Zeit, sich zu setzen
    private var audioSettled = false

    // MARK: Zustand von Sitzung und Gesten

    private var sessionStartedAt: Date = .distantPast
    /// Einmal auf das Touchpad getippt → Sitzung pausiert (System-Geste)
    private var sessionPaused = false
    /// Auf dieser Sitzung lief schon eine Kamera – ein Neustart kann laut Meta-Issue #260 scheitern
    private var sessionHadCamera = false
    /// Fehlgeschlagene Wiederaufbauten der Sitzung in Folge
    private var sessionFailures = 0
    /// Inputs haben den Ausgangszustand `.inactive` schon einmal verlassen
    private var inputsLeftInactive = false
    private var inputsRetries = 0
    /// Gesten für diese App/Brille nicht verfügbar – nicht weiter versuchen
    private var inputsBlocked = false

    /// Nur für Fotos: `hvc1` liefert laut Meta auch bei gesperrtem iPhone (Hintergrund) – `raw` nur im Vordergrund.
    /// Mittlere Auflösung schont Bluetooth und Akku; die Fotos selbst kommen trotzdem in 1440×1080.
    private let streamConfig = StreamConfiguration(videoCodec: .hvc1, resolution: .medium, frameRate: 15)
    /// Wie im Meta-Beispiel BirdSpotter: Touchpad und beide Tasten. Nur die Capture-Taste allein
    /// meldete dort „aktiv“, lieferte aber nichts. „Zurück“ gehört der App – sonst beendet es die Sitzung.
    private let inputsConfig = InputsConfiguration(sources: [.captouch, .captureButton, .actionButton], consumeBack: true)
    /// Meta: zwischen zwei Sitzungen mindestens 2 s Pause, sonst kann die Brille hängen bleiben
    private let sessionGap: TimeInterval = 2
    private var lastTeardown: Date = .distantPast
    private let sessionStartTimeout: TimeInterval = 20
    private let hfpSettleDelay: UInt64 = 2_000_000_000       // 2 s laut Meta-Doku
    private let photoTimeout: UInt64 = 12_000_000_000         // 12 s
    /// So lange bleibt die Kamera nach einem Foto an (für schnelle Rückfragen), dann geht sie aus
    private let cameraKeepAlive: UInt64 = 15_000_000_000      // 15 s
    /// Maximal so lange auf einen laufenden Stream warten
    private let streamReadyTimeout: TimeInterval = 15
    /// Kamera-Neustart auf der laufenden Sitzung – danach Rückfall: Sitzung neu aufbauen
    private let cameraRestartTimeout: TimeInterval = 8
    /// Belichtung nach dem Kamerastart kurz einpendeln lassen
    private let exposureSettleDelay: UInt64 = 400_000_000      // 0,4 s
    private let pollInterval: UInt64 = 100_000_000             // 0,1 s
    /// Inputs erst anhängen, wenn die Brille wirklich verbunden ist (max. so lange warten)
    private let deviceArrivalTimeout: TimeInterval = 10
    /// Pause vor dem (erneuten) Anhängen der Inputs – Wert aus dem Meta-Beispiel BirdSpotter
    private let inputsAttachDelay: UInt64 = 750_000_000        // 0,75 s
    private let maxInputsRetries = 5
    /// Abgebrochene Sitzung (Tippen und Halten, Bügel zu) nach dieser Pause wieder aufbauen
    private let sessionRetryDelay: UInt64 = 5_000_000_000      // 5 s
    private let maxSessionRetries = 3
    /// Lief eine Sitzung so lange, zählen frühere Fehlversuche nicht mehr
    private let stableSessionDuration: TimeInterval = 60

    private static let pausedMessage = "Pausiert – zum Fortsetzen auf das Touchpad der Brille tippen"

    private var wearables: any WearablesInterface { Wearables.shared }

    /// Sitzung bleibt nach dem Foto offen (für die Gesten) – sonst geht sie mit der Kamera aus
    private var keepsSession: Bool { gesturesEnabled && deviceSession != nil }

    /// Status ohne laufende Kamera
    private var restingStatus: FrameSourceStatus { sessionPaused ? .error(Self.pausedMessage) : .standby }

    func configure(frameInterval: TimeInterval = 1.0, jpegQuality: CGFloat = 0.85) {
        gate.update(frameInterval: frameInterval, jpegQuality: jpegQuality)
    }

    // MARK: - Registrierung (einmalig, über die Meta-AI-App)

    func startMonitoringRegistration() {
        guard WearablesSupport.isConfigured else {
            registrationLabel = "Meta-SDK nicht verfügbar"
            return
        }
        updateRegistration(wearables.registrationState)
        registrationTask?.cancel()
        registrationTask = Task { [weak self] in
            guard let stream = self?.wearables.registrationStateStream() else { return }
            for await state in stream {
                self?.updateRegistration(state)
            }
        }
    }

    private func updateRegistration(_ state: RegistrationState) {
        switch state {
        case .registered:
            isRegistered = true
            registrationLabel = "Registriert"
        case .registering:
            isRegistered = false
            registrationLabel = "Registrierung läuft …"
        case .available:
            isRegistered = false
            registrationLabel = "Nicht registriert"
        case .unavailable:
            isRegistered = false
            registrationLabel = "Meta-AI-App fehlt"
        @unknown default:
            isRegistered = false
            registrationLabel = "Unbekannt"
        }
    }

    func register() async {
        guard !isRegistered, WearablesSupport.isConfigured else { return }
        do {
            connectionStatus = .connecting
            try await wearables.startRegistration()
        } catch {
            connectionStatus = .error("Registrierung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    func unregister() async {
        stop()
        do {
            try await wearables.startUnregistration()
        } catch {
            connectionStatus = .error("Abmelden fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: - FrameSource

    /// Brille als Bildquelle wählen: prüft Registrierung und Kamera-Freigabe und öffnet (mit Gesten)
    /// die Sitzung – filmt aber noch nicht.
    func start() throws {
        isArmed = true
        isSuspended = false
        guard startTask == nil, sessionTask == nil, deviceSession == nil else { return } // läuft schon / startet gerade
        Task { [weak self] in
            guard let self, await self.ensureAccess(), self.isArmed, self.deviceSession == nil else { return }
            self.connectionStatus = .standby
            self.ensureGestureSession(resetRetries: true)
        }
    }

    func stop() {
        isArmed = false
        cancelPendingWork()
        teardown(status: .disconnected)
    }

    /// Nur ein frisches Bild aus einer gerade laufenden Aufnahme – nie ein altes
    func consumeFrame() -> Data? {
        isRunning ? latestFrame : nil
    }

    /// Kamera schon mal starten (z. B. während der Nutzer noch „Was steht auf …“ sagt)
    func prepareCapture() {
        guard isArmed else { return }
        scheduleIdleStop()
        // Läuft schon, startet gerade (Stream noch nicht „streaming“) oder Sitzung wird aufgebaut
        guard camera == nil, startTask == nil else { return }
        startTask = Task { [weak self] in
            await self?.startStreaming()
            self?.startTask = nil
        }
    }

    /// Foto direkt auf der Brille auslösen (schärfer als ein Videobild). Startet die Kamera bei
    /// Bedarf und schaltet sie nach einer kurzen Nachlaufzeit wieder ab.
    func capturePhoto() async -> Data? {
        guard isArmed else { return nil }
        if !isRunning {
            guard await bringUpCamera() else {
                scheduleIdleStop()
                return nil
            }
            try? await Task.sleep(nanoseconds: exposureSettleDelay)
        }
        idleStopTask?.cancel()
        let photo = await takePhoto()
        scheduleIdleStop()
        return photo
    }

    /// Kamera starten und auf den Stream warten. Startet sie auf der weiterlaufenden Sitzung nicht neu
    /// (Meta-Issue #260), wird einmal die ganze Sitzung neu aufgebaut (mit mind. 2 s Pause).
    private func bringUpCamera() async -> Bool {
        let reused = sessionHadCamera && deviceSession != nil
        prepareCapture()
        idleStopTask?.cancel() // während des Starts nicht abschalten
        if await waitForStreaming(timeout: reused ? cameraRestartTimeout : streamReadyTimeout) { return true }
        guard reused, isArmed, !isRunning, !sessionPaused else { return false }
        print("[Brille] Kamera startet auf der laufenden Sitzung nicht neu – Sitzung wird neu aufgebaut")
        startTask?.cancel()
        startTask = nil
        teardown(status: .connecting)
        prepareCapture()
        idleStopTask?.cancel()
        return await waitForStreaming(timeout: streamReadyTimeout)
    }

    private func waitForStreaming(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isRunning { return true }
            // Start ist durch, aber ohne Kamera oder mit Fehler → nicht weiter warten
            if startTask == nil {
                if camera == nil { return false }
                if case .error = connectionStatus { return false }
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return isRunning
    }

    /// Nach der Nachlaufzeit ohne weiteres Foto: Kamera (und ohne Gesten auch die Sitzung) freigeben
    private func scheduleIdleStop() {
        idleStopTask?.cancel()
        idleStopTask = Task { [weak self, cameraKeepAlive] in
            try? await Task.sleep(nanoseconds: cameraKeepAlive)
            guard !Task.isCancelled, let self, self.isArmed else { return }
            self.startTask?.cancel()
            self.startTask = nil
            if self.keepsSession {
                self.stopCamera(status: self.restingStatus)
            } else {
                self.teardown(status: .standby)
            }
        }
    }

    private func takePhoto() async -> Data? {
        guard let stream = camera?.stream, stream.state == .streaming else { return latestFrame }
        photoWaiter?.resume(returning: nil)
        let photo: Data? = await withCheckedContinuation { continuation in
            photoWaiter = continuation
            if !stream.capturePhoto(format: .jpeg) {
                resolvePhoto(nil)
                return
            }
            Task { [weak self, photoTimeout] in
                try? await Task.sleep(nanoseconds: photoTimeout)
                self?.resolvePhoto(nil)
            }
        }
        return photo ?? latestFrame
    }

    private func resolvePhoto(_ data: Data?) {
        photoWaiter?.resume(returning: data)
        photoWaiter = nil
    }

    // MARK: - Ablauf

    /// SDK bereit, Brille registriert, Kamera freigegeben? (Freigabe öffnet ggf. einmalig die Meta-AI-App)
    private func ensureAccess() async -> Bool {
        guard WearablesSupport.isConfigured else {
            connectionStatus = .error("Meta-SDK nicht verfügbar – App neu starten")
            return false
        }
        guard wearables.registrationState == .registered else {
            connectionStatus = .error("Brille erst verbinden: Einstellungen → „Brille über Meta AI verbinden“")
            await register()
            return false
        }
        do {
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                guard try await wearables.requestPermission(.camera) == .granted else {
                    connectionStatus = .error("Kamera-Freigabe abgelehnt – in der Meta-AI-App erlauben")
                    return false
                }
            }
        } catch {
            connectionStatus = .error("Kamera-Freigabe nicht möglich: \(error.localizedDescription)")
            return false
        }
        return true
    }

    /// Gestartete Sitzung holen – baut sie bei Bedarf auf. Gleichzeitige Aufrufer (Foto und Gesten)
    /// warten auf denselben Aufbau, damit nie zwei Sitzungen entstehen.
    private func startedSession() async -> DeviceSession? {
        if let session = deviceSession, sessionTask == nil {
            switch session.state {
            case .started:
                return session
            case .paused:
                connectionStatus = .error(Self.pausedMessage)
                return nil
            default:
                // Hängengeblieben oder schon beendet → sauber abbauen und neu aufbauen
                teardown(status: .connecting)
            }
        }
        if let pending = sessionTask { return await pending.value }
        sessionAttempt += 1
        let attempt = sessionAttempt
        let task = Task { [weak self] () -> DeviceSession? in
            let session = await self?.openSession()
            if self?.sessionAttempt == attempt { self?.sessionTask = nil }
            return session
        }
        sessionTask = task
        return await task.value
    }

    /// Sitzung erstellen, starten und (mit Gesten) die Inputs anhängen
    private func openSession() async -> DeviceSession? {
        connectionStatus = .connecting

        // 1. Registrierung und Kamera-Freigabe
        guard await ensureAccess(), !Task.isCancelled else { return nil }
        let sinceLast = Date().timeIntervalSince(lastTeardown)
        if sinceLast < sessionGap {
            try? await Task.sleep(nanoseconds: UInt64((sessionGap - sinceLast) * 1_000_000_000))
        }
        guard !Task.isCancelled, isArmed else { return nil }

        // 2. Geräte-Sitzung
        let session: DeviceSession
        do {
            session = try wearables.createSession(deviceSelector: AutoDeviceSelector(wearables: wearables))
        } catch {
            connectionStatus = .error(describe(error))
            return nil
        }
        deviceSession = session
        // Vor start() abonnieren – Publisher wiederholen nichts
        session.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in self?.handle(sessionState: state, of: session) }
        }.store(in: sessionTokens)
        do {
            try session.start()
        } catch {
            teardown(status: .error(describe(error)))
            await handleUpdateRequirement(error)
            return nil
        }
        guard await waitUntilStarted(session), deviceSession === session else {
            if deviceSession === session {
                teardown(status: .error("Brille antwortet nicht. Eingeschaltet, Bügel offen, in Bluetooth-Reichweite?"))
            }
            return nil
        }
        sessionStartedAt = Date()
        observeDevice(session.device)

        // 3. Gesten – unabhängig vom Foto, das ggf. schon wartet
        if gesturesEnabled { scheduleInputsAttach(to: session, waitForDevice: true) }
        return session
    }

    private func waitUntilStarted(_ session: DeviceSession) async -> Bool {
        let deadline = Date().addingTimeInterval(sessionStartTimeout)
        while Date() < deadline, !Task.isCancelled {
            switch session.state {
            case .started, .paused: return true
            case .stopping, .stopped: return false
            case .idle, .starting: try? await Task.sleep(nanoseconds: pollInterval)
            }
        }
        return false
    }

    private func startStreaming() async {
        connectionStatus = .connecting

        // 1.–2. Registrierung, Freigabe und Sitzung (läuft für die Gesten meist schon)
        guard let session = await startedSession(), !Task.isCancelled, camera == nil else { return }

        // 3. Kamera + Stream – eine gestoppte Kamera ist ungültig, daher für jedes Foto neu hinzufügen
        let cam: Camera
        do {
            guard let created = try session.addCamera(config: streamConfig) else {
                failCamera("Kamera der Brille nicht verfügbar")
                return
            }
            cam = created
        } catch {
            failCamera(describe(error))
            return
        }
        camera = cam
        sessionHadCamera = true
        subscribe(to: cam)

        // 4. Audio über die Brille (HFP) VOR dem Streamstart einrichten und beim ersten Mal kurz setzen lassen
        try? AudioSessionManager.shared.configureForVoiceChat()
        if !audioSettled {
            try? await Task.sleep(nanoseconds: hfpSettleDelay)
            audioSettled = true
        }
        guard !Task.isCancelled, camera === cam else { return }
        cam.stream.start()
    }

    private func subscribe(to cam: Camera) {
        let stream = cam.stream
        // Alte Rückmeldungen einer schon gestoppten Kamera ignorieren – die Kamera kommt und geht
        stream.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.camera === cam else { return }
                self.handle(state: state)
            }
        }.store(in: streamTokens)

        stream.videoFramePublisher.listen { [weak self, gate] frame in
            // Umwandlung abseits des Main-Threads, nur das Ergebnis geht an die UI
            guard let image = frame.makeUIImage() else { return }
            let jpeg = gate.jpegIfDue(image)
            Task { @MainActor [weak self] in
                guard let self, self.camera === cam else { return }
                self.latestImage = image
                self.frameCount += 1
                if let jpeg { self.latestFrame = jpeg }
            }
        }.store(in: streamTokens)

        stream.photoDataPublisher.listen { [weak self] photo in
            let data = photo.data
            Task { @MainActor [weak self] in
                guard let self, self.camera === cam else { return }
                self.resolvePhoto(data)
            }
        }.store(in: streamTokens)

        stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.camera === cam else { return }
                self.handle(error: error)
            }
        }.store(in: streamTokens)
    }

    private func handle(state: StreamState) {
        switch state {
        case .streaming:
            isRunning = true
            connectionStatus = .connected
        case .paused:
            // Einmal auf das Touchpad getippt → Stream pausiert; nicht neu starten
            connectionStatus = .error(Self.pausedMessage)
        case .waitingForDevice, .starting, .stopping:
            connectionStatus = .connecting
        case .stopped:
            isRunning = false
            if isArmed {
                // Von außen beendet (z. B. Bügel zu) → Kamera abbauen, das nächste Foto startet sie neu
                let status = connectionStatus.isReady || connectionStatus == .connecting ? restingStatus : connectionStatus
                if keepsSession { stopCamera(status: status) } else { teardown(status: status) }
            } else if connectionStatus == .connecting || connectionStatus == .connected {
                connectionStatus = .disconnected
            }
        @unknown default:
            break
        }
    }

    private func handle(error: StreamError) {
        if error == .photoCaptureFailed {
            resolvePhoto(nil)
            return // Stream läuft weiter
        }
        let message = describe(error)
        print("[Brille] Fehler: \(message)")
        failCamera(message)
    }

    /// Kamera ist gescheitert: nur sie abbauen (Sitzung bleibt für die Gesten) – ohne Gesten alles
    private func failCamera(_ message: String) {
        if keepsSession {
            stopCamera(status: .error(message))
        } else {
            teardown(status: .error(message))
        }
    }

    /// Kamera und Sitzung sofort freigeben (z. B. bevor iOS die App anhält), bleibt aber bereit.
    /// Zurück im Vordergrund holt `restoreGestureSession()` die Gesten wieder.
    func releaseCamera() {
        isSuspended = true
        cancelPendingWork()
        guard deviceSession != nil else { return }
        teardown(status: isArmed ? .standby : .disconnected)
    }

    /// Gesten-Sitzung wieder aufbauen (z. B. wenn die App in den Vordergrund kommt)
    func restoreGestureSession() {
        isSuspended = false
        ensureGestureSession(resetRetries: true)
    }

    private func cancelPendingWork() {
        idleStopTask?.cancel()
        idleStopTask = nil
        startTask?.cancel()
        startTask = nil
        sessionRetryTask?.cancel()
        sessionRetryTask = nil
        sessionTask?.cancel()
        sessionTask = nil
        sessionAttempt += 1
    }

    /// Nur die Kamera freigeben – die Sitzung (und damit die Gesten) bleibt offen
    private func stopCamera(status: FrameSourceStatus) {
        resolvePhoto(nil)
        streamTokens.clear()
        camera?.stop()
        camera = nil
        isRunning = false
        latestFrame = nil
        latestImage = nil
        connectionStatus = status
    }

    /// Alles abbauen, von oben nach unten: Inputs → Kamera → Sitzung
    private func teardown(status: FrameSourceStatus) {
        if deviceSession != nil { lastTeardown = Date() }
        inputsAttachTask?.cancel()
        inputsAttachTask = nil
        detachInputs(from: deviceSession)
        inputsRetries = 0
        inputsBlocked = false
        stopCamera(status: status)
        sessionTokens.clear()
        deviceSession?.stop()
        deviceSession = nil
        sessionHadCamera = false
        sessionPaused = false
    }

    // MARK: - Dauersitzung für die Gesten

    /// Sitzung für die Gesten aufbauen, falls keine läuft (idempotent)
    private func ensureGestureSession(resetRetries: Bool = false) {
        if resetRetries { sessionFailures = 0 }
        guard isArmed, !isSuspended, gesturesEnabled, deviceSession == nil, sessionTask == nil, startTask == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            guard await self.startedSession() != nil else {
                self.scheduleSessionRetry()
                return
            }
            if self.camera == nil, self.startTask == nil { self.connectionStatus = self.restingStatus }
        }
    }

    /// Abgebrochene oder gescheiterte Sitzung nach einer Pause wieder aufbauen – begrenzt, damit die
    /// App nicht endlos mit einer anderen App (z. B. Meta AI) um die Brille ringt
    private func scheduleSessionRetry() {
        // Bügel zu: nicht probieren – beim Aufklappen baut `apply` die Sitzung neu auf
        guard isArmed, !isSuspended, gesturesEnabled, hingesOpen != false, sessionFailures < maxSessionRetries else { return }
        // Schon geplant (z. B. Startfehler meldet sich über den Status und den Rückgabewert) → nur einmal zählen
        guard sessionRetryTask == nil else { return }
        sessionFailures += 1
        sessionRetryTask = Task { [weak self, sessionRetryDelay] in
            try? await Task.sleep(nanoseconds: sessionRetryDelay)
            guard !Task.isCancelled, let self else { return }
            self.sessionRetryTask = nil
            self.ensureGestureSession()
        }
    }

    private func handle(sessionState state: DeviceSessionState, of session: DeviceSession) {
        guard deviceSession === session else { return } // alte Sitzung
        switch state {
        case .paused:
            sessionPaused = true
            connectionStatus = .error(Self.pausedMessage)
        case .started:
            guard sessionPaused else { return }
            sessionPaused = false
            connectionStatus = isRunning ? .connected : .standby
            if gesturesEnabled, inputs == nil { scheduleInputsAttach(to: session, waitForDevice: true) }
        case .stopped:
            // Von außen beendet: Tippen und Halten am Touchpad, Bügel zu, Brille aus
            sessionEnded()
        case .idle, .starting, .stopping:
            break
        }
    }

    private func sessionEnded() {
        if Date().timeIntervalSince(sessionStartedAt) > stableSessionDuration { sessionFailures = 0 }
        idleStopTask?.cancel()
        idleStopTask = nil
        startTask?.cancel()
        startTask = nil
        let status: FrameSourceStatus = isArmed
            ? (connectionStatus.isReady || connectionStatus == .connecting ? .standby : connectionStatus)
            : .disconnected
        teardown(status: status)
        scheduleSessionRetry()
    }

    private func gesturesEnabledChanged() {
        if gesturesEnabled {
            ensureGestureSession(resetRetries: true)
            if let session = deviceSession, inputs == nil { scheduleInputsAttach(to: session, waitForDevice: false) }
            return
        }
        inputsAttachTask?.cancel()
        inputsAttachTask = nil
        sessionRetryTask?.cancel()
        sessionRetryTask = nil
        detachInputs(from: deviceSession)
        gestureHint = nil
        // Ohne Gesten wie früher: Sitzung nur, solange die Kamera läuft
        if camera == nil, startTask == nil, deviceSession != nil {
            teardown(status: isArmed ? .standby : .disconnected)
        }
    }

    // MARK: - Gesten (MWDATInputs, experimentell)

    /// Inputs (erneut) anhängen – nach einer kurzen Pause, wenn die Brille wirklich da ist und gerade
    /// kein Foto übertragen wird. Zu früh angehängt scheitern sie einmal still (`deviceDisconnected`).
    private func scheduleInputsAttach(to session: DeviceSession, waitForDevice: Bool) {
        guard gesturesEnabled, !inputsBlocked, inputsAttachTask == nil else { return }
        inputsAttachTask = Task { [weak self, inputsAttachDelay, pollInterval, deviceArrivalTimeout] in
            try? await Task.sleep(nanoseconds: inputsAttachDelay)
            if waitForDevice {
                let deadline = Date().addingTimeInterval(deviceArrivalTimeout)
                while session.device?.linkState != .connected, Date() < deadline, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: pollInterval)
                }
            }
            // Während ein Foto über Bluetooth kommt, nichts anfassen – sonst fällt es gleich wieder aus
            while self?.photoWaiter != nil, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollInterval)
            }
            guard !Task.isCancelled, let self else { return }
            self.inputsAttachTask = nil
            guard self.isArmed, self.gesturesEnabled, self.deviceSession === session, session.state == .started else { return }
            self.detachInputs(from: session)
            self.attachInputs(to: session)
        }
    }

    private func attachInputs(to session: DeviceSession) {
        guard inputs == nil else { return }
        let attached: Inputs?
        do {
            attached = try session.addInputs(configuration: inputsConfig)
        } catch {
            print("[Brille] Gesten nicht angehängt: \(error.localizedDescription)")
            retryInputs(on: session)
            return
        }
        guard let attached else {
            // Sitzung läuft, aber die Brille bietet keine Gesten an – eine Tatsache, kein Fehler
            gestureHint = "Diese Brille meldet keine Gesten"
            return
        }
        inputs = attached
        inputsLeftInactive = false
        // Gleich abonnieren – auch diese Publisher wiederholen nichts
        attached.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in self?.handle(inputsState: state, of: attached) }
        }.store(in: inputsTokens)
        attached.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in self?.handle(inputsError: error, of: attached) }
        }.store(in: inputsTokens)
        let events = attached.events
        inputsDrain = Task { [weak self] in
            for await event in events {
                self?.handle(inputEvent: event)
            }
            // Strom zu Ende (z. B. nach einem Fehler) – die Fähigkeit bleibt angehängt, also neu anhängen
            guard !Task.isCancelled, let self, self.inputs === attached, let session = self.deviceSession else { return }
            self.retryInputs(on: session)
        }
    }

    /// Inputs neu anhängen, höchstens `maxInputsRetries`-mal in Folge (zurückgesetzt, sobald sie aktiv sind)
    private func retryInputs(on session: DeviceSession) {
        guard !inputsBlocked, inputsAttachTask == nil else { return }
        guard inputsRetries < maxInputsRetries else {
            gestureHint = "Gesten der Brille reagieren nicht – Brille aus- und einschalten"
            return
        }
        inputsRetries += 1
        scheduleInputsAttach(to: session, waitForDevice: false)
    }

    private func detachInputs(from session: DeviceSession?) {
        inputsDrain?.cancel()
        inputsDrain = nil
        inputsTokens.clear()
        if inputs != nil { try? session?.removeInputs() }
        inputs = nil
        inputsLeftInactive = false
        gesturesActive = false
    }

    private func handle(inputsState state: InputsState, of capability: Inputs) {
        guard inputs === capability, let session = deviceSession else { return }
        switch state {
        case .active:
            inputsLeftInactive = true
            inputsRetries = 0
            gesturesActive = true
            gestureHint = nil
        case .activating, .deactivating:
            inputsLeftInactive = true
        case .inactive:
            gesturesActive = false
            // „inactive“ ist auch der Ausgangszustand – nur ein Rückfall zählt (z. B. nach einem Foto
            // oder einer Aktivierung, die nach 10 s abgelaufen ist)
            guard inputsLeftInactive else { return }
            retryInputs(on: session)
        @unknown default:
            break
        }
    }

    private func handle(inputsError error: InputsError, of capability: Inputs) {
        guard inputs === capability else { return }
        print("[Brille] Gesten-Fehler: \(error.description)")
        switch error {
        case .permissionDenied:
            inputsBlocked = true
            gesturesActive = false
            gestureHint = "Gesten nicht freigeschaltet – Entwicklermodus in der Meta-AI-App an?"
        case .capabilityUnavailable:
            inputsBlocked = true
            gesturesActive = false
            gestureHint = "Diese Brille bietet Apps keine Gesten an"
        default:
            // Alles andere fängt das Neu-Anhängen ab (Fehler lassen die Fähigkeit angehängt)
            if let session = deviceSession { retryInputs(on: session) }
        }
    }

    /// Eine Geste der Brille in die Sprache der App übersetzen. Alles wird geloggt – wie die echte
    /// Brille Doppeldruck und Wischen zerlegt, ist auf Hardware noch nicht nachgemessen.
    private func handle(inputEvent event: InputEvent) {
        print("[Brille] Geste: \(event)")
        switch event {
        case .select:
            // Doppeltipp auf das Touchpad (Einzeltipp und Halten bleiben beim System)
            onGesture?(.listen)
        case .capture(let pressType, _, _):
            // Nur kurz drücken – Halten und Doppeldruck bleiben ungenutzt
            guard pressType == .shortPress else { return }
            onGesture?(.photo)
        case .button:
            // Aktionstaste (Oakley Meta Vanguard) wie Doppeltipp
            onGesture?(.listen)
        case .back:
            onGesture?(.cancel)
        case .nav, .drag:
            // Wischen (sonst Lautstärke der Brille) – bewusst ohne Aktion
            break
        @unknown default:
            break
        }
    }

    // MARK: - Gerätezustand (Name, Akku, Bügel)

    private func observeDevice(_ device: Device?) {
        deviceTokens.clear()
        guard let device else { return }
        hasActiveDevice = true
        glassesName = device.name.isEmpty ? device.nameOrId() : device.name
        deviceModel = Self.modelName(device.deviceType())
        apply(DeviceState(linkState: device.linkState, batteryLevel: device.batteryLevel, hingeState: device.hingeState))
        switch device.compatibility() {
        case .deviceUpdateRequired: updateHint = "Brillen-Update nötig: Meta-AI-App öffnen und Firmware aktualisieren."
        case .sdkUpdateRequired: updateHint = "Diese App-Version ist zu alt für die Brillen-Firmware – bitte RayBan Claude aktualisieren."
        default: updateHint = nil
        }
        device.addDeviceStateListener { [weak self] state in
            Task { @MainActor [weak self] in self?.apply(state) }
        }.store(in: deviceTokens)
    }

    private func apply(_ state: DeviceState) {
        // Bügel wieder auf oder Brille wieder verbunden → Gesten-Sitzung neu aufbauen
        let returned = (state.hingeState == .open && hingesOpen == false)
            || (state.linkState == .connected && !hasActiveDevice)
        batteryLevel = state.batteryLevel
        hasActiveDevice = state.linkState == .connected
        switch state.hingeState {
        case .open: hingesOpen = true
        case .closed: hingesOpen = false
        default: hingesOpen = nil
        }
        // Die Kamera startet beim nächsten Foto ohnehin neu – nur die Sitzung für die Gesten kommt zurück
        if returned { ensureGestureSession(resetRetries: true) }
    }

    static func modelName(_ type: DeviceType) -> String {
        switch type {
        case .rayBanMeta: return "Ray-Ban Meta"
        case .rayBanMetaOptics: return "Ray-Ban Meta Optics"
        case .metaRayBanDisplay: return "Meta Ray-Ban Display"
        case .oakleyMetaHSTN: return "Oakley Meta HSTN"
        case .oakleyMetaVanguard: return "Oakley Meta Vanguard"
        case .metaGlasses: return "Meta-Brille"
        default: return "Unbekannte Brille"
        }
    }

    // MARK: - Fehlertexte

    private func handleUpdateRequirement(_ error: DeviceSessionError) async {
        guard error == .datAppOnTheGlassesUpdateRequired else { return }
        try? await wearables.openDATGlassesAppUpdate()
    }

    private func describe(_ error: DeviceSessionError) -> String {
        switch error {
        case .noEligibleDevice: return "Keine Brille gefunden. Einschalten, Bügel öffnen, in der Meta-AI-App verbunden?"
        case .sessionAlreadyExists: return "Die Brille wird schon von einer anderen App genutzt."
        case .thermalCritical, .thermalEmergency: return "Brille zu warm – kurz abkühlen lassen."
        case .batteryCritical: return "Akku der Brille fast leer – bitte laden."
        case .peakPowerShutdown: return "Brille hat wegen Leistungsspitze abgeschaltet – kurz warten."
        case .datAppOnTheGlassesUpdateRequired: return "Update auf der Brille nötig – die Meta-AI-App öffnet sich."
        case .insufficientSDKVersion: return "Diese App-Version ist zu alt für die Brille – bitte RayBan Claude aktualisieren."
        case .dwaUnavailable, .dwaOutOfStuRange: return "Brillen-Software meldet ein Problem – Meta-AI-App öffnen und Brille aktualisieren."
        default: return "Brillen-Sitzung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func describe(_ error: StreamError) -> String {
        switch error {
        case .deviceNotFound: return "Brille nicht gefunden. Einschalten und Bügel öffnen."
        case .deviceNotConnected: return "Brille getrennt – Bluetooth prüfen."
        case .permissionDenied: return "Kamera-Freigabe fehlt – in der Meta-AI-App erlauben."
        case .hingesClosed: return "Bügel geschlossen – zum Weitermachen aufklappen."
        case .thermalHot: return "Brille zu warm – Stream pausiert."
        case .batteryLow: return "Akku der Brille niedrig – bitte laden."
        case .peakPowerLimit: return "Leistungsgrenze erreicht – kurz warten."
        case .timeout: return "Zeitüberschreitung – erneut versuchen."
        case .videoStreamingError, .audioStreamingError: return "Videostream unterbrochen – erneut verbinden."
        case .internalError: return "Interner SDK-Fehler – App neu starten."
        default: return "Fehler der Brille: \(error.localizedDescription)"
        }
    }
}

/// Drosselt die JPEG-Erzeugung (thread-sicher, läuft im Listener der Brille).
final class FrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var frameInterval: TimeInterval = 1.0
    private var jpegQuality: CGFloat = 0.85
    private var lastCapture: Date = .distantPast

    func update(frameInterval: TimeInterval, jpegQuality: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        self.frameInterval = frameInterval
        self.jpegQuality = jpegQuality
    }

    func jpegIfDue(_ image: UIImage) -> Data? {
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastCapture) >= frameInterval else {
            lock.unlock()
            return nil
        }
        lastCapture = now
        let quality = jpegQuality
        lock.unlock()
        return image.jpegData(compressionQuality: quality)
    }
}
