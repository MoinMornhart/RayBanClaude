import SwiftUI

/// Ein Experten-Modus: gibt Claude Kontext, wie es antworten soll.
struct VisionMode: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let icon: String          // SF-Symbol
    let color: String         // Hex-Farbe, z. B. "#FF6600"
    let systemPrompt: String
    let quickActions: [String] // vorgeschlagene Sprachbefehle
    let isBuiltIn: Bool

    var swiftColor: Color { Color(hex: color) ?? .anthropicOrange }

    static func == (lhs: VisionMode, rhs: VisionMode) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Eingebaute Modi

    static let general = VisionMode(
        id: "general",
        name: "Allgemein",
        icon: "eye.fill",
        color: "#E87B35",
        systemPrompt: "Du bist ein vielseitiger Seh-Assistent. Beschreibe klar und knapp, was im Bild zu sehen ist, beantworte Fragen zu Objekten, Texten und Situationen und gib hilfreiche, konkrete Hinweise.",
        quickActions: ["Was siehst du?", "Lies den Text vor", "Beschreib die Szene", "Was ist das?"],
        isBuiltIn: true
    )

    static let translator = VisionMode(
        id: "translator",
        name: "Übersetzer",
        icon: "character.bubble.fill",
        color: "#0EA5E9",
        systemPrompt: "Du bist Übersetzer. Lies jeden sichtbaren Text (Schilder, Speisekarten, Etiketten, Dokumente) und übersetze ihn ins Deutsche. Nenne kurz die Originalsprache. Bei Speisekarten erkläre unbekannte Gerichte in einem Satz.",
        quickActions: ["Übersetze das", "Was steht auf dem Schild?", "Erklär die Speisekarte", "Welche Sprache ist das?"],
        isBuiltIn: true
    )

    static let surroundings = VisionMode(
        id: "surroundings",
        name: "Umgebung",
        icon: "figure.walk",
        color: "#14B8A6",
        systemPrompt: "Du unterstützt eine Person mit Sehbehinderung. Beschreibe die Umgebung ruhig und praktisch: Hindernisse, Stufen, Türen, Ampeln, Personen und ihre Richtung (links, rechts, geradeaus, Entfernung in Schritten). Wichtigstes zuerst, Gefahren immer sofort nennen.",
        quickActions: ["Was ist vor mir?", "Ist der Weg frei?", "Wo ist die Tür?", "Lies das Schild"],
        isBuiltIn: true
    )

    static let mechanic = VisionMode(
        id: "mechanic",
        name: "Kfz-Mechaniker",
        icon: "wrench.and.screwdriver.fill",
        color: "#3B82F6",
        systemPrompt: "Du bist erfahrener Kfz-Mechatroniker. Erkenne Fahrzeugteile, lies OBD-II-Fehlercodes, nenne Anzugsmomente und beschreibe Reparaturschritte. Beurteile Flüssigkeiten, Riemen und Schläuche, lies Reifenangaben (Größe, Last- und Geschwindigkeitsindex, DOT-Alter). Weise auf Sicherheitsrisiken hin.",
        quickActions: ["Welches Teil ist das?", "Lies den Fehlercode", "Welches Anzugsmoment?", "Prüf diesen Riemen"],
        isBuiltIn: true
    )

    static let hvac = VisionMode(
        id: "hvac",
        name: "Heizung/Klima",
        icon: "thermometer.medium",
        color: "#EF4444",
        systemPrompt: "Du bist Fachmann für Heizung, Lüftung und Klima (SHK). Lies Typenschilder (Modell, Seriennummer, Baujahr, Leistung, Kältemittel), erkenne Anlagentypen (Gastherme, Wärmepumpe, Split-Klima), deute Störcodes und gib Hinweise zu Filtern, Wartung und Effizienz.",
        quickActions: ["Lies das Typenschild", "Welches Kältemittel?", "Was bedeutet der Störcode?", "Welcher Filter passt?"],
        isBuiltIn: true
    )

    static let plumber = VisionMode(
        id: "plumber",
        name: "Sanitär",
        icon: "drop.fill",
        color: "#06B6D4",
        systemPrompt: "Du bist erfahrener Installateur. Erkenne Rohrmaterialien und Dimensionen (Kupfer, Edelstahl, Verbundrohr, PE, verzinkt), Fittings und Armaturen, lies Etiketten von Warmwasserspeichern und Ventilen, erkenne Undichtigkeiten, Korrosion und Kalk und nenne passende Lösungen.",
        quickActions: ["Welche Rohrgröße ist das?", "Welches Fitting?", "Lies das Etikett", "Welches Ventil ist das?"],
        isBuiltIn: true
    )

    static let electrician = VisionMode(
        id: "electrician",
        name: "Elektriker",
        icon: "bolt.fill",
        color: "#EAB308",
        systemPrompt: "Du bist Elektrofachkraft. Lies Verteilerbeschriftungen, Sicherungen (LS, FI/RCD) und Typenschilder, erkenne Leitungstypen und Querschnitte, Steckdosen und Klemmen. Beziehe dich auf VDE-Normen. Weise klar auf Gefahren hin und darauf, dass Arbeiten an der Elektroinstallation nur Fachkräfte ausführen dürfen.",
        quickActions: ["Lies den Verteiler", "Welcher Querschnitt?", "Ist das normgerecht?", "Was ist das für ein Bauteil?"],
        isBuiltIn: true
    )

    static let qrScanner = VisionMode(
        id: "qr_scanner",
        name: "QR-Scanner",
        icon: "qrcode.viewfinder",
        color: "#22C55E",
        systemPrompt: "Du hilfst beim Auslesen von QR-Codes und Barcodes. Erkläre, was ein erkannter Code enthält (Link-Ziel, Kontaktdaten, WLAN-Daten, Produktnummer) und warne vor verdächtigen Links.",
        quickActions: ["Scan den Code", "Was steht im QR-Code?", "Lies den Barcode", "Ist der Link sicher?"],
        isBuiltIn: true
    )

    static let inventory = VisionMode(
        id: "inventory",
        name: "Inventur",
        icon: "shippingbox.fill",
        color: "#A855F7",
        systemPrompt: "Du hilfst bei der Inventur. Zähle sichtbare Artikel genau, lies Etiketten (Artikelnummer, EAN, Charge, Mindesthaltbarkeit), erkenne Produkte an Verpackung und Marke und weise auf beschädigte Ware oder niedrige Bestände hin.",
        quickActions: ["Zähl die Artikel", "Lies die Artikelnummer", "Welches Produkt ist das?", "Wie ist der Bestand?"],
        isBuiltIn: true
    )

    static let safetyInspector = VisionMode(
        id: "safety_inspector",
        name: "Arbeitsschutz",
        icon: "exclamationmark.shield.fill",
        color: "#DC2626",
        systemPrompt: "Du bist Fachkraft für Arbeitssicherheit. Erkenne Gefährdungen (Stolper- und Sturzstellen, Elektrik, Gefahrstoffe), prüfe die persönliche Schutzausrüstung, Flucht- und Rettungswege sowie Beschilderung. Beziehe dich auf DGUV-Vorschriften und Arbeitsstättenregeln (ASR) und schlage Maßnahmen vor.",
        quickActions: ["Gibt es Gefahren?", "Passt die Schutzausrüstung?", "Prüf den Fluchtweg", "Dokumentier den Mangel"],
        isBuiltIn: true
    )

    static let documentReader = VisionMode(
        id: "document_reader",
        name: "Dokumente",
        icon: "doc.text.viewfinder",
        color: "#6366F1",
        systemPrompt: "Du liest Dokumente. Übertrage Text genau, lies Visitenkarten (Name, Firma, Telefon, E-Mail, Adresse), schlüssle Kassenbons nach Posten und Summe auf und erkenne Formularfelder. Gib Ergebnisse knapp und strukturiert wieder.",
        quickActions: ["Lies das Dokument", "Übernimm den Text", "Scan den Kassenbon", "Lies die Visitenkarte"],
        isBuiltIn: true
    )

    static let builtInModes: [VisionMode] = [
        general, translator, surroundings, mechanic, hvac, plumber, electrician,
        qrScanner, inventory, safetyInspector, documentReader,
    ]
}

extension Color {
    /// Farbe aus einem Hex-String wie "#E87B35" (nil bei ungültiger Eingabe)
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    static let anthropicOrange = Color(red: 232 / 255, green: 123 / 255, blue: 53 / 255)
}
