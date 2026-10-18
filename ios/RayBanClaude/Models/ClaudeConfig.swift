import Foundation

/// Verbindungsart zum PC.
enum ConnectionMode: String, Codable, CaseIterable, Identifiable {
    /// Claude Code + Channel – kostenlos mit dem Claude-Abo, alle MCP-Tools und Skills
    case channel
    /// Eigenständiger Gateway-Server mit Anthropic-API-Key (kostet pro Nutzung)
    case gateway

    var id: String { rawValue }

    var label: String {
        switch self {
        case .channel: return "Claude Code (kostenlos)"
        case .gateway: return "Gateway (API-Key)"
        }
    }
}

struct ClaudeConfig: Codable, Equatable {
    var gatewayHost: String = ""
    var gatewayPort: Int = ClaudeConfig.defaultPort
    var connectionMode: ConnectionMode = .channel
    var videoFrameInterval: TimeInterval = 1.0
    var videoJPEGQuality: Double = 0.85
    var speechPauseThreshold: TimeInterval = 1.5
    var elevenLabsVoiceId: String = "XB0fDUnXU5powFXDhCwa" // Charlotte (mehrsprachig)
    /// Sprache für Spracherkennung und Stimme, z. B. "de-DE"
    var speechLanguage: String = ClaudeConfig.defaultLanguage
    /// Nach Claudes Antwort automatisch wieder zuhören (freihändig mit der Brille)
    var autoListen: Bool = true

    // Geheimnisse liegen im Schlüsselbund, nicht in den UserDefaults
    var channelToken: String = ""
    var elevenLabsAPIKey: String = ""

    static let defaultPort = 18790
    static let supportedLanguages: [(code: String, name: String)] = [
        ("de-DE", "Deutsch"), ("de-AT", "Deutsch (Österreich)"), ("de-CH", "Deutsch (Schweiz)"),
        ("en-US", "Englisch (US)"), ("en-GB", "Englisch (UK)"), ("fr-FR", "Französisch"),
        ("es-ES", "Spanisch"), ("it-IT", "Italienisch"), ("tr-TR", "Türkisch"), ("pl-PL", "Polnisch"),
    ]

    static var defaultLanguage: String {
        let preferred = Locale.preferredLanguages.first ?? "de-DE"
        return supportedLanguages.first { preferred.hasPrefix($0.code) }?.code
            ?? supportedLanguages.first { preferred.hasPrefix(String($0.code.prefix(2))) }?.code
            ?? "de-DE"
    }

    private enum CodingKeys: String, CodingKey {
        case gatewayHost, gatewayPort, connectionMode, videoFrameInterval, videoJPEGQuality
        case speechPauseThreshold, elevenLabsVoiceId, speechLanguage, autoListen
    }

    var isConfigured: Bool { baseURL != nil && !channelToken.isEmpty }

    // MARK: - URLs (nie per Force-Unwrap – ungültige Eingaben dürfen nicht abstürzen)

    private func url(scheme: String, path: String) -> URL? {
        let host = gatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65535).contains(gatewayPort) else { return nil }
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.port = gatewayPort
        comps.path = path
        return comps.url
    }

    var baseURL: URL? { url(scheme: "http", path: "") }
    var wsURL: URL? { url(scheme: "ws", path: "/ws") }
    var chatURL: URL? { url(scheme: "http", path: "/chat") }
    var healthURL: URL? { url(scheme: "http", path: "/health") }
    var uploadURL: URL? { url(scheme: "http", path: "/upload") }
    /// Endpunkt, der ein gültiges Token verlangt – zum Testen der Kopplung
    var authCheckURL: URL? {
        url(scheme: "http", path: connectionMode == .channel ? "/api/status" : "/health/details")
    }

    func fileURL(_ path: String) -> URL? {
        guard path.hasPrefix("/files/") else { return nil }
        return url(scheme: "http", path: path)
    }

    // MARK: - Speichern / Laden

    private static let storageKey = "RayBanClaudeConfig"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        KeychainStore.set(channelToken, for: .channelToken)
        KeychainStore.set(elevenLabsAPIKey, for: .elevenLabsAPIKey)
    }

    static func load() -> ClaudeConfig {
        var config = UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(ClaudeConfig.self, from: $0) } ?? ClaudeConfig()
        config.channelToken = KeychainStore.get(.channelToken)
        config.elevenLabsAPIKey = KeychainStore.get(.elevenLabsAPIKey)
        return config
    }
}

extension ClaudeConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ClaudeConfig()
        gatewayHost = try c.decodeIfPresent(String.self, forKey: .gatewayHost) ?? defaults.gatewayHost
        gatewayPort = try c.decodeIfPresent(Int.self, forKey: .gatewayPort) ?? defaults.gatewayPort
        connectionMode = try c.decodeIfPresent(ConnectionMode.self, forKey: .connectionMode) ?? defaults.connectionMode
        videoFrameInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .videoFrameInterval) ?? defaults.videoFrameInterval
        videoJPEGQuality = try c.decodeIfPresent(Double.self, forKey: .videoJPEGQuality) ?? defaults.videoJPEGQuality
        speechPauseThreshold = try c.decodeIfPresent(TimeInterval.self, forKey: .speechPauseThreshold) ?? defaults.speechPauseThreshold
        elevenLabsVoiceId = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceId) ?? defaults.elevenLabsVoiceId
        speechLanguage = try c.decodeIfPresent(String.self, forKey: .speechLanguage) ?? defaults.speechLanguage
        autoListen = try c.decodeIfPresent(Bool.self, forKey: .autoListen) ?? defaults.autoListen
    }
}
