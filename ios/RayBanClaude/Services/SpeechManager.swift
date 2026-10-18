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

@MainActor
final class SpeechManager: NSObject, ObservableObject {
    @Published private(set) var transcribedText: String = ""
    @Published private(set) var isListening: Bool = false
    @Published private(set) var isSpeaking: Bool = false

    /// Erkannter Satz nach einer Sprechpause
    var onSpeechPause: ((String) -> Void)?
    /// Sprachausgabe natürlich beendet (nicht bei Abbruch)
    var onSpeechFinished: (() -> Void)?
    /// Zuhören wurde vom System beendet (Fehler, Zeitlimit)
    var onListeningStopped: ((String?) -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var languageCode: String = ClaudeConfig.defaultLanguage

    private var elevenLabsClient: ElevenLabsTTSClient?
    private var elevenLabsVoiceId: String = ElevenLabsVoice.allVoices[0].id
    private let appleSynthesizer = AVSpeechSynthesizer()

    private var silenceTimer: Timer?
    private var pauseThreshold: TimeInterval = 1.5
    private var pauseHandled = false

    override init() {
        super.init()
        appleSynthesizer.delegate = self
        setLanguage(languageCode)
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

    func startListening() throws {
        if isSpeaking { stopSpeaking() }
        stopListening()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable(languageCode)
        }
        try AudioSessionManager.shared.configureForVoiceChat()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true // Datenschutz: Sprache verlässt das iPhone nicht
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        // Tatsächliches Format der aktiven Route (iPhone 48 kHz, Brille/HFP 8–16 kHz)
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw SpeechError.inputNotReady
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        pauseHandled = false
        transcribedText = ""
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                if let text {
                    self.transcribedText = text
                    self.resetSilenceTimer()
                    if isFinal { self.handlePause() }
                }
                if failed && !self.pauseHandled {
                    self.stopListening()
                    self.onListeningStopped?(self.transcribedText.isEmpty ? nil : self.transcribedText)
                }
            }
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: pauseThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.handlePause() }
        }
    }

    /// Pause oder Endergebnis – wird pro Äußerung nur EINMAL weitergegeben (früher teils doppelt).
    private func handlePause() {
        guard !pauseHandled else { return }
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pauseHandled = true
        stopListening()
        transcribedText = ""
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
