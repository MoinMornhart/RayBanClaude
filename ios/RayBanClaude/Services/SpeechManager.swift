import Foundation
import Speech
import AVFoundation

// MARK: - ElevenLabs-Stimmen (optional, kostenpflichtig)

struct ElevenLabsVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String

    /// Alle Stimmen sprechen mit dem Modell eleven_flash_v2_5 auch Deutsch.
    static let allVoices: [ElevenLabsVoice] = [
        ElevenLabsVoice(id: "XB0fDUnXU5powFXDhCwa", name: "Charlotte", description: "Warm, weiblich"),
        ElevenLabsVoice(id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", description: "Ruhig, weiblich"),
        ElevenLabsVoice(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", description: "Sanft, weiblich"),
        ElevenLabsVoice(id: "MF3mGyEYCl7XYWbV9V6O", name: "Elli", description: "Jung, weiblich"),
        ElevenLabsVoice(id: "29vD33N1CtxCmqQRPOHJ", name: "Drew", description: "Ausgewogen, männlich"),
        ElevenLabsVoice(id: "2EiwWnXFnvU5JabPnv8n", name: "Clyde", description: "Tief, männlich"),
        ElevenLabsVoice(id: "TxGEqnHWrfWFTfGW9XjX", name: "Josh", description: "Jung, männlich"),
        ElevenLabsVoice(id: "pNInz6obpgDQGcFmaJgB", name: "Adam", description: "Klar, männlich"),
    ]

    static func voice(for id: String) -> ElevenLabsVoice {
        allVoices.first { $0.id == id } ?? allVoices[0]
    }
}

/// Direkter ElevenLabs-Aufruf vom iPhone (nur Gateway-Modus; im Channel-Modus erzeugt der PC das Audio)
struct ElevenLabsTTSClient {
    let apiKey: String

    func synthesize(text: String, voiceId: String) async throws -> Data {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/stream") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": String(text.prefix(2500)),
            "model_id": "eleven_flash_v2_5",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // Fehlertext des Anbieters nur ins Log, nicht in die UI
            print("[Sprache] ElevenLabs-Fehler: \(String(data: data, encoding: .utf8) ?? "-")")
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - MP3-Wiedergabe

@MainActor
final class AudioDataPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioDataPlayer()
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?

    /// Spielt in der bestehenden Voice-Chat-Session ab – kein Umschalten auf `.playback`
    /// (das hat bei der Brille die Bluetooth-Route zerlegt).
    func play(data: Data, completion: @escaping () -> Void) {
        stop()
        do {
            try AudioSessionManager.shared.configureForVoiceChat()
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            self.player = player
            self.completion = completion
            if !player.play() { finish() }
        } catch {
            print("[Audio] Wiedergabe fehlgeschlagen: \(error)")
            completion()
        }
    }

    /// Bricht ab, ohne die Fertig-Rückmeldung auszulösen (sonst startete das Zuhören doppelt).
    func stop() {
        completion = nil
        player?.stop()
        player = nil
    }

    private func finish() {
        let done = completion
        completion = nil
        player = nil
        done?()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finish() }
    }
}

// MARK: - Spracheingabe und -ausgabe

/// Zuhör-Modus: Bereitschaft (wartet auf „Hey Claude“/„Claudi“) oder Befehl (nimmt den Satz auf).
enum ListenMode: Equatable {
    case standby
    case command
}

@MainActor
final class SpeechManager: NSObject, ObservableObject {
    @Published private(set) var transcribedText: String = ""
    @Published private(set) var listenMode: ListenMode?
    @Published private(set) var isSpeaking: Bool = false

    var isListening: Bool { listenMode != nil }

    /// Erkannter Befehl nach einer Sprechpause
    var onSpeechPause: ((String) -> Void)?
    /// Weckwort erkannt – jetzt wird der Befehl aufgenommen
    var onWakeWord: (() -> Void)?
    /// Sprachausgabe natürlich beendet (nicht bei Abbruch)
    var onSpeechFinished: (() -> Void)?
    /// Befehls-Zuhören endete ohne Befehl (Fehler, Zeitlimit, nichts gesagt)
    var onListeningStopped: ((String?) -> Void)?

    /// Weckwort aktiv? Dann wird nach jedem Befehl wieder in Bereitschaft gewechselt.
    var wakeWordEnabled = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Die Aufnahme läuft durch (auch bei gesperrtem iPhone) – nur die Erkennung wechselt.
    /// Früher wurde sie nach jedem Satz gestoppt; im Hintergrund darf iOS sie dann nicht neu starten.
    private let audioEngine = AVAudioEngine()
    private let sink = RecognitionSink()
    private var tapInstalled = false
    private var languageCode: String = ClaudeConfig.defaultLanguage

    private var elevenLabsClient: ElevenLabsTTSClient?
    private var elevenLabsVoiceId: String = ElevenLabsVoice.allVoices[0].id
    private let appleSynthesizer = AVSpeechSynthesizer()

    private var silenceTimer: Timer?
    private var noSpeechTimer: Timer?
    private var standbyRefreshTimer: Timer?
    private var pauseThreshold: TimeInterval = 1.5
    private var pauseHandled = false
    /// Befehl kam über das Weckwort → nur der Teil danach zählt
    private var viaWakeWord = false
    /// Jede Erkennungs-Sitzung bekommt eine Nummer – Rückmeldungen alter Sitzungen werden ignoriert
    private var generation = 0
    private var standbyRetries = 0

    /// Bereitschaft regelmäßig neu starten (Apple begrenzt eine Erkennung auf etwa eine Minute)
    private let standbyRefreshInterval: TimeInterval = 50
    /// Nach dem Weckwort so lange auf den Befehl warten
    private let wakeCommandTimeout: TimeInterval = 7

    override init() {
        super.init()
        appleSynthesizer.delegate = self
        setLanguage(languageCode)
        // Brille verbunden/getrennt, Anruf o. Ä.: Das Eingangsformat ändert sich, die Aufnahme muss neu aufgesetzt werden
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.engineConfigurationChanged() }
        }
    }

    // MARK: Einstellungen

    /// Sprache für Erkennung und Stimme (früher fest auf Englisch – Deutsch wurde nicht verstanden).
    func setLanguage(_ code: String) {
        languageCode = code
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: code))
    }

    func configureElevenLabs(apiKey: String, voiceId: String) {
        elevenLabsClient = apiKey.isEmpty ? nil : ElevenLabsTTSClient(apiKey: apiKey)
        elevenLabsVoiceId = voiceId
    }

    func setPauseThreshold(_ threshold: TimeInterval) {
        pauseThreshold = threshold
    }

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech == .authorized && mic
    }

    // MARK: Zuhören (Apple-Spracherkennung, wenn möglich auf dem Gerät)

    /// Wartet auf das Weckwort. Ohne Weckwort-Einstellung wird nur gestoppt.
    func enterStandby() {
        guard wakeWordEnabled, !isSpeaking else {
            stopListening()
            return
        }
        do {
            try startListening(mode: .standby)
        } catch {
            scheduleStandbyRestart()
        }
    }

    /// - Parameter noSpeechTimeout: Kommt in dieser Zeit kein Wort, endet das Zuhören (z. B. nach einer Antwort).
    func startListening(mode: ListenMode = .command, noSpeechTimeout: TimeInterval? = nil) throws {
        if isSpeaking { stopSpeaking() }
        stopListening()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable(languageCode)
        }
        try ensureEngineRunning()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = WakeWord.contextualStrings
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true // Datenschutz: Sprache verlässt das iPhone nicht
        }
        recognitionRequest = request
        sink.set(request)

        generation += 1
        let session = generation
        pauseHandled = false
        viaWakeWord = false
        transcribedText = ""
        listenMode = mode

        if mode == .standby {
            standbyRefreshTimer = Timer.scheduledTimer(withTimeInterval: standbyRefreshInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == session, self.listenMode == .standby else { return }
                    self.enterStandby()
                }
            }
        } else if let noSpeechTimeout {
            startNoSpeechTimer(noSpeechTimeout, session: session)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == session, self.listenMode != nil else { return }
                if let text { self.handleTranscript(text, isFinal: isFinal) }
                if failed && !self.pauseHandled { self.handleRecognitionEnd() }
            }
        }
    }

    func stopListening() {
        generation += 1 // laufende Rückmeldungen verwerfen
        silenceTimer?.invalidate()
        silenceTimer = nil
        noSpeechTimer?.invalidate()
        noSpeechTimer = nil
        standbyRefreshTimer?.invalidate()
        standbyRefreshTimer = nil
        sink.set(nil) // Aufnahme läuft weiter, geht aber an keine Erkennung mehr
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        listenMode = nil
        transcribedText = ""
    }

    // MARK: Aufnahme (läuft durch, solange zugehört wird)

    /// Aufnahme starten, falls sie noch nicht läuft – mit dem Format der aktiven Route
    /// (iPhone 48 kHz, Brille/HFP 8–16 kHz).
    private func ensureEngineRunning() throws {
        try AudioSessionManager.shared.configureForVoiceChat()
        if !tapInstalled {
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw SpeechError.inputNotReady
            }
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [sink] buffer, _ in
                sink.append(buffer)
            }
            tapInstalled = true
        }
        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }
    }

    /// Mikrofon ganz freigeben (kein Weckwort, App getrennt) – dann verschwindet auch der orange Punkt
    func releaseMicrophone() {
        stopListening()
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// Route oder Format hat sich geändert – Aufnahme neu aufsetzen und dort weitermachen, wo wir waren
    private func engineConfigurationChanged() {
        let mode = listenMode
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning { audioEngine.stop() }
        switch mode {
        case .standby: enterStandby()
        case .command: handleRecognitionEnd()
        case nil: break
        }
    }

    private func handleTranscript(_ text: String, isFinal: Bool) {
        switch listenMode {
        case .standby:
            standbyRetries = 0
            // In Bereitschaft wird nichts angezeigt – nur auf das Weckwort geachtet
            guard let command = WakeWord.command(in: text) else { return }
            listenMode = .command
            viaWakeWord = true
            standbyRefreshTimer?.invalidate()
            standbyRefreshTimer = nil
            Chime.shared.play()
            onWakeWord?()
            transcribedText = command
            if command.isEmpty {
                startNoSpeechTimer(wakeCommandTimeout, session: generation)
            } else {
                resetSilenceTimer()
            }
        case .command:
            noSpeechTimer?.invalidate()
            noSpeechTimer = nil
            transcribedText = viaWakeWord ? (WakeWord.command(in: text) ?? text) : text
            guard !transcribedText.isEmpty else { return }
            resetSilenceTimer()
            if isFinal { handlePause() }
        case nil:
            break
        }
    }

    /// Erkennung beendet (Fehler, Stille, Zeitlimit von Apple)
    private func handleRecognitionEnd() {
        if listenMode == .standby {
            scheduleStandbyRestart()
            return
        }
        let heard = transcribedText
        stopListening()
        onListeningStopped?(heard.isEmpty ? nil : heard)
    }

    /// Neustart der Bereitschaft mit wachsender Pause, falls die Erkennung wiederholt scheitert
    private func scheduleStandbyRestart() {
        stopListening()
        standbyRetries += 1
        let delay = min(0.3 * Double(standbyRetries), 5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.listenMode == nil, !self.isSpeaking, self.wakeWordEnabled else { return }
            self.enterStandby()
        }
    }

    private func startNoSpeechTimer(_ timeout: TimeInterval, session: Int) {
        noSpeechTimer?.invalidate()
        noSpeechTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == session, self.transcribedText.isEmpty else { return }
                self.stopListening()
                self.onListeningStopped?(nil)
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        let session = generation
        silenceTimer = Timer.scheduledTimer(withTimeInterval: pauseThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == session else { return }
                self.handlePause()
            }
        }
    }

    /// Pause oder Endergebnis – wird pro Äußerung nur EINMAL weitergegeben (früher teils doppelt).
    private func handlePause() {
        guard !pauseHandled, listenMode == .command else { return }
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pauseHandled = true
        stopListening()
        onSpeechPause?(text)
    }

    // MARK: Sprechen

    /// Lokale Sprachausgabe: ElevenLabs (falls Key) sonst kostenlose iPhone-Stimme.
    func speak(_ text: String) {
        stopSpeaking()
        isSpeaking = true
        if let client = elevenLabsClient {
            Task {
                do {
                    let audio = try await client.synthesize(text: text, voiceId: elevenLabsVoiceId)
                    guard isSpeaking else { return }
                    AudioDataPlayer.shared.play(data: audio) { [weak self] in self?.finishSpeaking() }
                } catch {
                    guard isSpeaking else { return }
                    speakWithApple(text)
                }
            }
        } else {
            speakWithApple(text)
        }
    }

    /// Vom PC erzeugtes Audio abspielen (Channel-Modus, mit Token-Header).
    func playRemoteAudio(request: URLRequest, fallbackText: String) {
        stopSpeaking()
        isSpeaking = true
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                guard isSpeaking else { return }
                AudioDataPlayer.shared.play(data: data) { [weak self] in self?.finishSpeaking() }
            } catch {
                print("[Sprache] Audio vom PC nicht abspielbar (\(error.localizedDescription)) – iPhone-Stimme")
                guard isSpeaking else { return }
                speakWithApple(fallbackText)
            }
        }
    }

    func stopSpeaking() {
        AudioDataPlayer.shared.stop()
        if appleSynthesizer.isSpeaking { appleSynthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    private func finishSpeaking() {
        guard isSpeaking else { return }
        isSpeaking = false
        onSpeechFinished?()
    }

    private func speakWithApple(_ text: String) {
        try? AudioSessionManager.shared.configureForVoiceChat()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        appleSynthesizer.speak(utterance)
    }

    /// Beste installierte Stimme der Sprache (Premium > Erweitert > Standard)
    private static func bestVoice(for code: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == code }
        return voices.first { $0.quality == .premium }
            ?? voices.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: code)
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
    }
}

/// Reicht die Audio-Puffer der durchlaufenden Aufnahme an die gerade aktive Erkennung weiter.
/// Wird vom Audio-Thread aufgerufen – daher mit Sperre statt Main-Actor.
final class RecognitionSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}

enum SpeechError: LocalizedError {
    case recognizerUnavailable(String)
    case inputNotReady

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable(let code):
            return "Spracherkennung für \(code) nicht verfügbar – Sprache in den Einstellungen prüfen"
        case .inputNotReady:
            return "Mikrofon noch nicht bereit – bitte nochmal tippen"
        }
    }
}
