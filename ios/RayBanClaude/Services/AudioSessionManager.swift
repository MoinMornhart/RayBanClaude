import Foundation
import AVFoundation

/// Verwaltet die Audio-Session für Sprechen und Zuhören.
///
/// Wichtig für Ray-Ban Meta Gen 2: Die Session wird nur EINMAL auf
/// `.playAndRecord` + Bluetooth-HFP konfiguriert und danach nicht mehr ständig
/// umgeschaltet – Meta rät davon ab, die AVAudioSession bei offener Brillen-Sitzung
/// neu zu konfigurieren (führt sonst zu „Device unavailable“).
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]

    private init() {
        setupNotifications()
    }

    /// Sprach-Chat mit Bluetooth-Mikrofon (Brille). Idempotent: ändert nichts, wenn schon passend.
    func configureForVoiceChat() throws {
        let session = AVAudioSession.sharedInstance()
        let alreadyConfigured = session.category == .playAndRecord
            && session.mode == .voiceChat
            && session.categoryOptions.isSuperset(of: options)
        if !alreadyConfigured {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        }
        try session.setActive(true)
        routeToBluetoothMicIfAvailable()
    }

    /// Reihenfolge für Mikrofon und Lautsprecher: Ray-Ban Meta → anderes Bluetooth-Headset → iPhone.
    /// Bei Bluetooth-Sprachverbindungen (HFP) folgt der Lautsprecher automatisch dem Mikrofon.
    func routeToBluetoothMicIfAvailable() {
        let session = AVAudioSession.sharedInstance()
        guard let inputs = session.availableInputs else { return }
        let current = session.currentRoute.inputs.first

        // 1. Die Brille hat immer Vorrang – auch vor Auto, AirPods & Co.
        if let glasses = inputs.first(where: Self.isMetaGlasses) {
            if current?.uid != glasses.uid { setPreferred(glasses, in: session) }
            return
        }
        // 2. Sonst ein anderes Bluetooth-Headset, falls schon eins aktiv ist bzw. verfügbar
        if let current, Self.isBluetooth(current) { return }
        if let headset = inputs.first(where: { $0.portType == .bluetoothHFP }) ?? inputs.first(where: { $0.portType == .bluetoothLE }) {
            setPreferred(headset, in: session)
            return
        }
        print("[Audio] Keine Brille und kein Bluetooth-Mikrofon – nutze das iPhone")
    }

    private func setPreferred(_ input: AVAudioSessionPortDescription, in session: AVAudioSession) {
        do {
            try session.setPreferredInput(input)
            print("[Audio] Mikrofon und Lautsprecher: \(input.portName)")
        } catch {
            print("[Audio] Umschalten auf \(input.portName) fehlgeschlagen: \(error)")
        }
    }

    private static func isBluetooth(_ port: AVAudioSessionPortDescription) -> Bool {
        port.portType == .bluetoothHFP || port.portType == .bluetoothLE
    }

    /// Ray-Ban Meta / Oakley Meta erkennt man am Namen des Bluetooth-Geräts
    static func isMetaGlasses(_ port: AVAudioSessionPortDescription) -> Bool {
        guard isBluetooth(port) else { return false }
        let name = port.portName.lowercased()
        return ["ray-ban", "rayban", "ray ban", "meta", "oakley"].contains { name.contains($0) }
    }

    var isBluetoothInputActive: Bool {
        AVAudioSession.sharedInstance().currentRoute.inputs.contains(where: Self.isBluetooth)
    }

    /// Für die Anzeige: Worüber laufen Mikrofon und Stimme gerade?
    var currentRouteLabel: String {
        let route = AVAudioSession.sharedInstance().currentRoute
        guard let input = route.inputs.first else { return "–" }
        if Self.isMetaGlasses(input) { return "Brille (\(input.portName))" }
        return Self.isBluetooth(input) ? input.portName : "iPhone"
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil
        )
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Brille (wieder) da oder Route von außen umgestellt → Brille zurückholen
        if reason == .newDeviceAvailable || reason == .override || reason == .routeConfigurationChange {
            routeToBluetoothMicIfAvailable()
        }
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            NotificationCenter.default.post(name: .audioInterruptionBegan, object: nil)
        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                try? configureForVoiceChat()
                NotificationCenter.default.post(name: .audioInterruptionEnded, object: nil)
            }
        @unknown default:
            break
        }
    }
}

extension Notification.Name {
    static let audioInterruptionBegan = Notification.Name("audioInterruptionBegan")
    static let audioInterruptionEnded = Notification.Name("audioInterruptionEnded")
}
