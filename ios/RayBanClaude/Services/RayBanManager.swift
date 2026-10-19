import Foundation
import Combine
import UIKit
import MWDATCore
import MWDATCamera

/// Kamera der Ray-Ban Meta (Gen 1 und Gen 2) über das Meta Wearables DAT SDK 1.x.
///
/// Wie bei Meta AI filmt die Brille NICHT dauernd: Sie ist nur „bereit“. Erst wenn ein Foto
/// gebraucht wird, startet die Kamera kurz (Sitzung → Kamera → Stream → Foto) und geht nach
/// einer kurzen Nachlaufzeit wieder aus. Das schont Akku und Privatsphäre – und die Meta-AI-App
/// kann die Brille dazwischen selbst nutzen.
///
/// Ablauf laut SDK: Registrierung → Kamera-Freigabe → DeviceSession starten →
/// auf `.started` warten → Kamera hinzufügen → Audio (HFP) einrichten → Stream starten.
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

    // MARK: SDK-Objekte

    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private let streamTokens = ListenerTokenBag()
    private let deviceTokens = ListenerTokenBag()
    private var registrationTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var deviceMonitorTask: Task<Void, Never>?
    private nonisolated let gate = FrameGate()
    private var photoWaiter: CheckedContinuation<Data?, Never>?
    /// Brille ist als Bildquelle gewählt und bereit (Kamera startet nur bei Bedarf)
    private var isArmed = false
    private var idleStopTask: Task<Void, Never>?
    /// Audio (HFP) wurde schon einmal eingerichtet und hatte Zeit, sich zu setzen
    private var audioSettled = false

    /// Nur für Fotos: `hvc1` liefert laut Meta auch bei gesperrtem iPhone (Hintergrund) – `raw` nur im Vordergrund.
    /// Mittlere Auflösung schont Bluetooth und Akku; die Fotos selbst kommen trotzdem in 1440×1080.
    private let streamConfig = StreamConfiguration(videoCodec: .hvc1, resolution: .medium, frameRate: 15)
    /// Meta: zwischen zwei Sitzungen mindestens 2 s Pause, sonst kann die Brille hängen bleiben
    private let sessionGap: TimeInterval = 2
    private var lastTeardown: Date = .distantPast
    private let sessionStartTimeout: UInt64 = 20_000_000_000 // 20 s
    private let hfpSettleDelay: UInt64 = 2_000_000_000       // 2 s laut Meta-Doku
    private let photoTimeout: UInt64 = 12_000_000_000         // 12 s
    /// So lange bleibt die Kamera nach einem Foto an (für schnelle Rückfragen), dann geht sie aus
    private let cameraKeepAlive: UInt64 = 15_000_000_000      // 15 s
    /// Maximal so lange auf einen laufenden Stream warten
    private let streamReadyTimeout: TimeInterval = 15
    /// Belichtung nach dem Kamerastart kurz einpendeln lassen
    private let exposureSettleDelay: UInt64 = 400_000_000      // 0,4 s
    private let pollInterval: UInt64 = 100_000_000             // 0,1 s

    private var wearables: any WearablesInterface { Wearables.shared }

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

    /// Brille als Bildquelle wählen: prüft Registrierung und Kamera-Freigabe – filmt aber noch nicht.
    func start() throws {
        isArmed = true
        guard startTask == nil, deviceSession == nil else { return } // läuft schon / startet gerade
        Task { [weak self] in
            guard let self, await self.ensureAccess(), self.isArmed, self.deviceSession == nil else { return }
            self.connectionStatus = .standby
        }
    }

    func stop() {
        isArmed = false
        idleStopTask?.cancel()
        idleStopTask = nil
        startTask?.cancel()
        startTask = nil
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
            prepareCapture()
            idleStopTask?.cancel() // während des Starts nicht abschalten
            guard await waitForStreaming() else {
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

    private func waitForStreaming() async -> Bool {
        let deadline = Date().addingTimeInterval(streamReadyTimeout)
        while Date() < deadline {
            if isRunning { return true }
            if case .error = connectionStatus, startTask == nil { return false }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return isRunning
    }

    /// Nach der Nachlaufzeit ohne weiteres Foto: Kamera und Sitzung wieder freigeben
    private func scheduleIdleStop() {
        idleStopTask?.cancel()
        idleStopTask = Task { [weak self, cameraKeepAlive] in
            try? await Task.sleep(nanoseconds: cameraKeepAlive)
            guard !Task.isCancelled, let self, self.isArmed else { return }
            self.startTask?.cancel()
            self.startTask = nil
            self.teardown(status: .standby)
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

    private func startStreaming() async {
        connectionStatus = .connecting

        // 1. Registrierung und Kamera-Freigabe
        guard await ensureAccess(), !Task.isCancelled else { return }
        let sinceLast = Date().timeIntervalSince(lastTeardown)
        if sinceLast < sessionGap {
            try? await Task.sleep(nanoseconds: UInt64((sessionGap - sinceLast) * 1_000_000_000))
        }
        guard !Task.isCancelled else { return }

        // 2. Geräte-Sitzung
        let session: DeviceSession
        do {
            session = try wearables.createSession(deviceSelector: AutoDeviceSelector(wearables: wearables))
        } catch {
            connectionStatus = .error(describe(error))
            return
        }
        deviceSession = session
        let states = session.stateStream() // vor start() abonnieren – Publisher wiederholen nichts
        do {
            try session.start()
        } catch {
            teardown(status: .error(describe(error)))
            await handleUpdateRequirement(error)
            return
        }
        guard await waitUntilStarted(states) else {
            teardown(status: .error("Brille antwortet nicht. Eingeschaltet, Bügel offen, in Bluetooth-Reichweite?"))
            return
        }
        observeDevice(session.device)

        // 3. Kamera + Stream
        let cam: Camera
        do {
            guard let created = try session.addCamera(config: streamConfig) else {
                teardown(status: .error("Kamera der Brille nicht verfügbar"))
                return
            }
            cam = created
        } catch {
            teardown(status: .error(describe(error)))
            return
        }
        camera = cam
        subscribe(to: cam.stream)

        // 4. Audio über die Brille (HFP) VOR dem Streamstart einrichten und beim ersten Mal kurz setzen lassen
        try? AudioSessionManager.shared.configureForVoiceChat()
        if !audioSettled {
            try? await Task.sleep(nanoseconds: hfpSettleDelay)
            audioSettled = true
        }
        guard !Task.isCancelled, camera != nil else { return }
        cam.stream.start()
    }

    private func waitUntilStarted(_ states: AsyncStream<DeviceSessionState>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await state in states {
                    if state == .started { return true }
                    if state == .stopped { return false }
                }
                return false
            }
            group.addTask { [sessionStartTimeout] in
                try? await Task.sleep(nanoseconds: sessionStartTimeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func subscribe(to stream: MWDATCamera.Stream) {
        stream.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in self?.handle(state: state) }
        }.store(in: streamTokens)

        stream.videoFramePublisher.listen { [weak self, gate] frame in
            // Umwandlung abseits des Main-Threads, nur das Ergebnis geht an die UI
            guard let image = frame.makeUIImage() else { return }
            let jpeg = gate.jpegIfDue(image)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.latestImage = image
                self.frameCount += 1
                if let jpeg { self.latestFrame = jpeg }
            }
        }.store(in: streamTokens)

        stream.photoDataPublisher.listen { [weak self] photo in
            let data = photo.data
            Task { @MainActor [weak self] in self?.resolvePhoto(data) }
        }.store(in: streamTokens)

        stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in self?.handle(error: error) }
        }.store(in: streamTokens)
    }

    private func handle(state: StreamState) {
        switch state {
        case .streaming:
            isRunning = true
            connectionStatus = .connected
        case .paused:
            // Einmal auf das Touchpad getippt → Stream pausiert; nicht neu starten
            connectionStatus = .error("Pausiert – zum Fortsetzen auf das Touchpad der Brille tippen")
        case .waitingForDevice, .starting, .stopping:
            connectionStatus = .connecting
        case .stopped:
            isRunning = false
            if isArmed {
                // Von außen beendet (z. B. Bügel zu) → sauber abbauen, das nächste Foto startet neu
                teardown(status: connectionStatus.isReady || connectionStatus == .connecting ? .standby : connectionStatus)
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
        // Nach einem Stream-Fehler Kamera abbauen (Teardown immer von oben nach unten)
        teardown(status: .error(message))
    }

    /// Kamera und Sitzung sofort freigeben (z. B. bevor iOS die App anhält), bleibt aber bereit
    func releaseCamera() {
        idleStopTask?.cancel()
        idleStopTask = nil
        startTask?.cancel()
        startTask = nil
        guard deviceSession != nil else { return }
        teardown(status: isArmed ? .standby : .disconnected)
    }

    private func teardown(status: FrameSourceStatus) {
        if deviceSession != nil { lastTeardown = Date() }
        resolvePhoto(nil)
        streamTokens.clear()
        camera?.stop()
        camera = nil
        deviceSession?.stop()
        deviceSession = nil
        isRunning = false
        latestFrame = nil
        latestImage = nil
        connectionStatus = status
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
        batteryLevel = state.batteryLevel
        hasActiveDevice = state.linkState == .connected
        switch state.hingeState {
        case .open: hingesOpen = true
        case .closed: hingesOpen = false
        default: hingesOpen = nil
        }
        // Kein automatischer Neustart mehr: die Kamera startet beim nächsten Foto ohnehin neu
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
