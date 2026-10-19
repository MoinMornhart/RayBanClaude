import Foundation
import AVFoundation

/// Erkennt das Weckwort („Hey Claude“ oder „Claudi“) im Text der Spracherkennung
/// und liefert den Rest des Satzes als Befehl.
///
/// „Claude“ allein reicht bewusst nicht – sonst würde jedes Gespräch *über* Claude auslösen.
/// Die Liste enthält typische Verhörer der deutschen Spracherkennung („Hey Cloud“, „Klaudi“).
enum WakeWord {
    struct Match: Equatable {
        /// Ab hier beginnt der eigentliche Befehl im Originaltext
        let commandStart: String.Index
    }

    /// Wortfolgen (bereits normalisiert: klein, ohne Akzente)
    static let phrases: [[String]] = [
        ["hey", "claude"], ["hey", "cloud"], ["hey", "claud"], ["hey", "klaud"], ["hey", "clod"], ["hey", "klod"],
        ["hey", "claudi"], ["hey", "klaudi"],
        ["hi", "claude"], ["hallo", "claude"], ["ok", "claude"], ["okay", "claude"], ["he", "claude"], ["hei", "claude"],
        ["claudi"], ["klaudi"], ["claudie"], ["klaudie"], ["clodi"], ["glaudi"],
    ]

    /// Hilft der Spracherkennung, diese Wörter richtig zu schreiben
    static let contextualStrings = ["Hey Claude", "Claude", "Claudi"]

    /// Anzeige in der App
    static let displayName = "„Hey Claude“ oder „Claudi“"

    static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE")).lowercased()
    }

    /// Frühestes Weckwort im Text, oder nil
    static func match(in text: String) -> Match? {
        var words: [(word: String, range: Range<String.Index>)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { substring, range, _, _ in
            if let substring { words.append((normalize(substring), range)) }
        }
        for start in words.indices {
            for phrase in phrases where start + phrase.count <= words.count {
                let candidate = words[start..<(start + phrase.count)].map(\.word)
                if candidate == phrase {
                    return Match(commandStart: words[start + phrase.count - 1].range.upperBound)
                }
            }
        }
        return nil
    }

    /// Befehl nach dem Weckwort, ohne führende Satzzeichen („Hey Claude, was siehst du?“ → „was siehst du?“)
    static func command(in text: String) -> String? {
        guard let match = match(in: text) else { return nil }
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return String(text[match.commandStart...]).trimmingCharacters(in: trimSet)
    }
}

/// Kurzer Zwei-Ton-Gong als Rückmeldung „Ich höre zu“ – wird im Speicher erzeugt
/// und läuft über die aktive Audio-Route (also auch über die Brille).
@MainActor
final class Chime {
    static let shared = Chime()
    private var player: AVAudioPlayer?
    private let wav = Chime.makeWAV()

    func play() {
        do {
            let player = try AVAudioPlayer(data: wav)
            player.volume = 0.7
            player.play()
            self.player = player
        } catch {
            print("[Gong] Wiedergabe fehlgeschlagen: \(error)")
        }
    }

    /// 16-Bit-Mono-WAV mit zwei kurzen Sinustönen (G5, D6) und weichen Flanken
    private static func makeWAV() -> Data {
        let sampleRate = 44_100.0
        let tones: [(frequency: Double, seconds: Double)] = [(784, 0.09), (1175, 0.13)]
        var samples: [Int16] = []
        for tone in tones {
            let count = Int(sampleRate * tone.seconds)
            let fade = Int(sampleRate * 0.012)
            for i in 0..<count {
                let envelope = min(1.0, Double(min(i, count - i)) / Double(fade))
                let value = sin(2 * .pi * tone.frequency * Double(i) / sampleRate) * envelope * 0.45
                samples.append(Int16(value * Double(Int16.max)))
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        samples.forEach { append($0) }
        return data
    }
}
