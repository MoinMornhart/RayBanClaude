import Foundation

/// Entscheidet, ob eine Frage ein Kamerabild braucht – wie bei Meta AI wird nur dann ein Foto gemacht.
///
/// „Was ist das?“, „Lies mal vor“, „Was steht auf dem Schild?“, „Mach ein Foto“ → Foto.
/// „Stell einen Timer“, „Wie wird das Wetter?“ → kein Foto. Fragt Claude trotzdem nach einem Bild,
/// löst es selbst eins aus (Werkzeug request_photo/take_photo). Im Zweifel lieber kein Foto.
enum VisionIntent {
    /// Ganze Wörter, die ein Bild meinen („sieh mal“, „lies vor“) – nicht „sieht“ wie in „Wie sieht das Wetter aus?“
    private static let visualWords: Set<String> = [
        "sieh", "siehst", "seht", "lies", "liest", "bild", "bilder", "qr", "look", "see", "read",
    ]

    /// Wortanfänge, die fast immer ein Bild meinen („schau“ passt auch auf „schaust“)
    private static let visualStems = [
        "schau", "guck", "anschau", "anguck", "betracht", "lese", "vorles", "entziffer", "erkenn",
        "identifizier", "beschreib", "foto", "fotografier", "kamera", "knips",
        "schild", "etikett", "typenschild", "aufkleber", "zettel", "speisekarte", "menükarte", "verpackung",
        "display", "bildschirm", "barcode", "strichcode", "photo", "picture",
    ]

    /// Hinweiswörter („das hier“, „vor mir“) – zusammen mit einem Fragewort ein Bildwunsch
    private static let deicticPhrases = [
        "das hier", "dies hier", "der hier", "die hier", "das da", "dieses ding", "dieses teil",
        "vor mir", "in meiner hand", "hier vorne", "was ich sehe", "was ich gerade sehe",
    ]

    /// Kurze Fragen, die ohne Bild keinen Sinn ergeben
    private static let shortVisualQuestions = [
        "was ist das", "wer ist das", "was ist dies", "was sind das", "wie heißt das", "was kostet das",
        "wie viel kostet das", "welche farbe", "welches modell", "was für ein", "was für eine",
        "wie alt ist das", "ist das echt", "kann man das essen", "what is this", "what's this",
    ]

    static func needsImage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let words = lowered.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        if words.contains(where: { word in visualWords.contains(word) || visualStems.contains { word.hasPrefix($0) } }) {
            return true
        }
        if deicticPhrases.contains(where: { lowered.contains($0) }) { return true }
        return shortVisualQuestions.contains { phrase in
            guard let range = lowered.range(of: phrase) else { return false }
            // „Was ist das?“ am Satzende – nicht „Was ist das Wetter morgen?“
            let rest = lowered[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return rest.isEmpty || rest.split(separator: " ").count <= 2 || phrase.hasPrefix("welch") || phrase.hasPrefix("was für")
        }
    }
}
