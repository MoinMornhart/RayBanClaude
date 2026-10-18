import Foundation
import Combine
import UIKit
import MWDATCore
import MWDATCamera

/// Kamera der Ray-Ban Meta (Gen 1 und Gen 2) über das Meta Wearables DAT SDK 1.x.
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
    /// Brille soll laufen (für automatischen Neustart nach Bügel-Öffnen)
    private var wantsStreaming = false

    /// Gen 2: 720p bei 15 fps liefert über Bluetooth sauberere Einzelbilder als 30 fps
    private let streamConfig = StreamConfiguration(videoCodec: .raw, resolution: .high, frameRate: 15)
    private let sessionStartTimeout: UInt64 = 20_000_000_000 // 20 s
    private let hfpSettleDelay: UInt64 = 2_000_000_000       // 2 s laut Meta-Doku
    private let photoTimeout: UInt64 = 12_000_000_000         // 12 s

    private var wearables: any WearablesInterface { Wearables.shared }

    func configure(frameInterval: TimeInterval = 1.0, jpegQuality: CGFloat = 0.85) {
        gate.update(frameInterval: frameInterval, jpegQuality: jpegQuality)
    }

    // MARK: - Registrierung (einmalig, über die Meta-AI-App)

    func startMonitoringRegistration() {
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
        guard !isRegistered else { return }
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

    func start() throws {
        wantsStreaming = true
        guard startTask == nil, deviceSession == nil else { return } // läuft schon / startet gerade
        startTask = Task { [weak self] in
            await self?.startStreaming()
            self?.startTask = nil
        }
    }

    func stop() {
        wantsStreaming = false
        startTask?.cancel()
        startTask = nil
        teardown(status: .disconnected)
    }

    func consumeFrame() -> Data? {
        latestFrame
    }

    /// Foto direkt auf der Brille auslösen (schärfer als ein Videobild).
    func capturePhoto() async -> Data? {
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

    private func startStreaming() async {
        connectionStatus = .connecting

        guard wearables.registrationState == .registered else {
            connectionStatus = .error("Brille erst verbinden: Einstellungen → „Brille über Meta AI verbinden“")
            await register()
            return
        }

        // 1. Kamera-Freigabe (öffnet ggf. die Meta-AI-App)
        do {
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                guard try await wearables.requestPermission(.camera) == .granted else {
                    connectionStatus = .error("Kamera-Freigabe abgelehnt – in der Meta-AI-App erlauben")
                    return
                }
            }
        } catch {
            connectionStatus = .error("Kamera-Freigabe nicht möglich: \(error.localizedDescription)")
            return
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

        // 4. Audio über die Brille (HFP) VOR dem Streamstart einrichten und kurz setzen lassen
        try? AudioSessionManager.shared.configureForVoiceChat()
        try? await Task.sleep(nanoseconds: hfpSettleDelay)
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
            if connectionStatus == .connecting || connectionStatus == .connected {
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

    private func teardown(status: FrameSourceStatus) {
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
        let wasClosed = hingesOpen == false
        switch state.hingeState {
        case .open: hingesOpen = true
        case .closed: hingesOpen = false
        default: hingesOpen = nil
        }
        // Bügel wieder geöffnet → Sitzung ist beendet und muss neu aufgebaut werden
        if wasClosed, hingesOpen == true, wantsStreaming, deviceSession == nil {
            try? start()
        }
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
