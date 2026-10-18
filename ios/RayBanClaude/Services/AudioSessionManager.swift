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

    /// Bevorzugt das Mikrofon der Brille (HFP), falls verbunden.
    func routeToBluetoothMicIfAvailable() {
        let session = AVAudioSession.sharedInstance()
        guard let inputs = session.availableInputs else { return }

        if session.currentRoute.inputs.contains(where: { $0.portType == .bluetoothHFP }) {
            return // schon auf der Brille – nicht unnötig umschalten
        }
        let preferred = inputs.first { $0.portType == .bluetoothHFP }
            ?? inputs.first { $0.portType == .bluetoothLE }
            ?? inputs.first { $0.portName.localizedCaseInsensitiveContains("ray-ban") || $0.portName.localizedCaseInsensitiveContains("meta") }

        guard let input = preferred else {
            print("[Audio] Kein Bluetooth-Mikrofon gefunden – nutze iPhone-Mikrofon")
            return
        }
        do {
            try session.setPreferredInput(input)
            print("[Audio] Mikrofon: \(input.portName)")
        } catch {
            print("[Audio] Umschalten auf \(input.portName) fehlgeschlagen: \(error)")
        }
    }

    var isBluetoothInputActive: Bool {
        AVAudioSession.sharedInstance().currentRoute.inputs.contains { $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE }
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
        if reason == .newDeviceAvailable {
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
