import Foundation
import Network

/// Verbindung zum PC:
/// - Channel-Modus: WebSocket zur Claude-Code-Sitzung (alle MCP-Tools und Skills, kostenlos mit Abo)
/// - Gateway-Modus: REST zum eigenständigen Gateway-Server (Anthropic-API-Key)
///
/// Der PC kann zwei Adressen haben: die im Heim-WLAN und – für unterwegs – seine Tailscale-Adresse.
/// Die App probiert sie der Reihe nach (ohne WLAN nur Tailscale) und bleibt bei der, die antwortet.
@MainActor
final class ClaudeBridge: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: ConnectionState = .disconnected
    /// Verbunden über die Unterwegs-Adresse (Tailscale) statt übers Heim-WLAN
    @Published private(set) var isRemote = false
    var isConnected: Bool { state == .connected }

    // MARK: Rückmeldungen an das ViewModel

    struct Reply {
        let id: String
        let text: String
        let audioPath: String?
        let replyTo: String?
        let attachments: [Attachment]
    }

    var onReply: ((Reply) -> Void)?
    var onEdit: ((_ id: String, _ text: String) -> Void)?
    var onAck: ((String) -> Void)?
    var onCaptureRequest: ((_ id: String, _ reason: String?) -> Void)?
    var onPermissionRequest: ((PermissionRequest) -> Void)?
    var onPermissionResolved: ((String) -> Void)?
    var onPhoneAction: ((PhoneAction) -> Void)?
    /// Claude hat sich (am PC) etwas gemerkt oder vergessen: op = "add" | "remove"
    var onMemory: ((_ op: String, _ items: [String]) -> Void)?
    var onServerError: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    private var config: ClaudeConfig
    private var urlSession: URLSession?
    private var webSocket: URLSessionWebSocketTask?
    private var conversationId: String?
    private var reconnectAttempts = 0
    private var reconnectWork: DispatchWorkItem?
    private var isManualDisconnect = false
    /// Gesetzt bei 401/429 – dann nicht endlos neu verbinden, Meldung stehen lassen
    private var authFailure: String?
    private var pingTimer: Timer?
    private let maxReconnectAttempts = 8

    /// Adresse, mit der gerade verbunden wird bzw. ist
    private var activeHost = ""
    /// Noch nicht probierte Adressen der laufenden Runde
    private var hostQueue: [String] = []
    /// Hat das iPhone gerade WLAN (oder Kabel)? Ohne WLAN ist der PC zu Hause nur über Tailscale erreichbar.
    private var onLocalNetwork = true
    private var networkReachable = true
    private let pathMonitor = NWPathMonitor()

    init(config: ClaudeConfig) {
        self.config = config
        super.init()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let local = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                || path.availableInterfaces.contains { $0.type == .wifi || $0.type == .wiredEthernet }
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in self?.networkChanged(local: local, reachable: reachable) }
        }
        pathMonitor.start(queue: .main)
    }

    /// Einstellungen mit der gerade genutzten Adresse
    private var activeConfig: ClaudeConfig { config.using(host: activeHost) }

    /// Reihenfolge der Adressen: zu Hause erst WLAN, dann Tailscale; mit mobilen Daten nur Tailscale.
    private var candidateHosts: [String] {
        let lan = config.gatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = config.remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.hasRemoteHost else { return [lan] }
        return onLocalNetwork ? [lan, remote] : [remote]
    }

    /// Netz gewechselt (WLAN ↔ mobile Daten, Tailscale an): eine aufgegebene Verbindung neu versuchen.
    private func networkChanged(local: Bool, reachable: Bool) {
        let changed = local != onLocalNetwork || reachable != networkReachable
        onLocalNetwork = local
        networkReachable = reachable
        guard changed, reachable, !isManualDisconnect, authFailure == nil, config.connectionMode.usesPC else { return }
        // WLAN weg, aber noch über die Heim-Adresse verbunden → die Verbindung ist tot: gleich über Tailscale
        if state == .connected, !isRemote, !local, config.hasRemoteHost, config.connectionMode == .channel {
            closeSocket()
            hostQueue.removeAll()
            state = .connecting
            openWebSocket()
            return
        }
        guard case .failed = state else { return }
        reconnectAttempts = 0
        reconnectWork?.cancel()
        reconnectWork = nil
        hostQueue.removeAll()
        Task { await connect() }
    }

    func updateConfig(_ config: ClaudeConfig) {
        let needsReconnect = config.gatewayHost != self.config.gatewayHost
            || config.remoteHost != self.config.remoteHost
            || config.gatewayPort != self.config.gatewayPort
            || config.channelToken != self.config.channelToken
            || config.connectionMode != self.config.connectionMode
        self.config = config
        if needsReconnect && state != .disconnected { disconnect() }
    }

    // MARK: - Verbinden

    func connect() async {
        isManualDisconnect = false
        reconnectAttempts = 0
        hostQueue.removeAll()
        switch config.connectionMode {
        case .channel: openWebSocket()
        case .gateway: await connectGateway()
        case .direct: state = .disconnected // ohne PC – keine Verbindung nötig
        }
    }

    func disconnect() {
        isManualDisconnect = true
        reconnectWork?.cancel()
        reconnectWork = nil
        closeSocket()
        hostQueue.removeAll()
        isRemote = false
        state = .disconnected
        onDisconnected?()
    }

    private func openWebSocket() {
        // Neue Runde: alle Adressen in der aktuellen Reihenfolge
        if hostQueue.isEmpty { hostQueue = candidateHosts }
        activeHost = hostQueue.removeFirst()
        guard let wsURL = activeConfig.wsURL else {
            state = .failed("PC-Adresse fehlt – QR-Code im Dashboard scannen")
            return
        }
        guard !config.channelToken.isEmpty else {
            state = .failed("Token fehlt – QR-Code im Dashboard scannen")
            return
        }
        closeSocket()
        authFailure = nil
        state = .connecting
        // Alte Session freigeben – früher blieben bei jedem Reconnect Sessions samt Delegate hängen
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        urlSession = session
        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(config.channelToken)", forHTTPHeaderField: "Authorization")
        // Kurz halten: ist der PC unter dieser Adresse nicht da, kommt gleich die nächste dran
        request.timeoutInterval = 6
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        webSocket = task
        task.resume()
        receive(on: task)
    }

    private func closeSocket() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    private func connectGateway() async {
        state = .connecting
        var lastError: Error = BridgeError.notConfigured
        for host in candidateHosts {
            activeHost = host
            do {
                try await checkAuthorized()
                isRemote = host != config.gatewayHost
                state = .connected
                onConnected?()
                return
            } catch {
                lastError = error
            }
        }
        isRemote = false
        state = .failed(lastError.localizedDescription)
    }

    // MARK: - Empfangen

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, task === self.webSocket else { return } // veraltete Verbindung ignorieren
                switch result {
                case .success(.string(let text)):
                    self.handle(text)
                    self.receive(on: task)
                case .success(.data(let data)):
                    self.handle(String(decoding: data, as: UTF8.self))
                    self.receive(on: task)
                case .success:
                    self.receive(on: task)
                case .failure(let error):
                    print("[Verbindung] Empfang beendet: \(error.localizedDescription)")
                    self.connectionLost()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "status":
            if json["status"] as? String == "connected" {
                isRemote = activeHost != config.gatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
                hostQueue.removeAll()
                state = .connected
                reconnectAttempts = 0
                startPingTimer()
                onConnected?()
            }
        case "ack":
            if let id = json["id"] as? String { onAck?(id) }
        case "reply":
            let files = (json["files"] as? [[String: Any]] ?? []).compactMap { f -> Attachment? in
                guard let name = f["name"] as? String, let url = f["url"] as? String else { return nil }
                return Attachment(name: name, path: url)
            }
            onReply?(Reply(
                id: json["id"] as? String ?? UUID().uuidString,
                text: json["text"] as? String ?? "",
                audioPath: json["audio_url"] as? String,
                replyTo: json["reply_to"] as? String,
                attachments: files
            ))
        case "edit":
            if let id = json["id"] as? String, let newText = json["text"] as? String { onEdit?(id, newText) }
        case "capture_request":
            if let id = json["id"] as? String { onCaptureRequest?(id, json["reason"] as? String) }
        case "permission_request":
            if let id = json["request_id"] as? String {
                onPermissionRequest?(PermissionRequest(
                    id: id,
                    toolName: json["tool_name"] as? String ?? "Tool",
                    description: json["description"] as? String ?? "",
                    inputPreview: json["input_preview"] as? String ?? ""
                ))
            }
        case "permission_resolved":
            if let id = json["request_id"] as? String { onPermissionResolved?(id) }
        case "phone_action":
            guard let id = json["id"] as? String,
                  let kind = (json["action"] as? String).flatMap(PhoneAction.Kind.init(rawValue:)) else { return }
            onPhoneAction?(PhoneAction(
                id: id, kind: kind,
                durationSeconds: json["duration_seconds"] as? Int,
                time: json["time"] as? String,
                date: json["date"] as? String,
                label: json["label"] as? String,
                contact: json["contact"] as? String,
                number: json["number"] as? String,
                text: json["text"] as? String,
                destination: json["destination"] as? String
            ))
        case "memory":
            guard let op = json["op"] as? String, let items = json["items"] as? [String] else { return }
            onMemory?(op, items)
        case "error":
            onServerError?(json["message"] as? String ?? "Unbekannter Serverfehler")
        default:
            break
        }
    }

    // MARK: - Wiederverbinden

    private func connectionLost() {
        let wasConnecting = state == .connecting
        closeSocket()
        if let authFailure {
            state = .failed(authFailure)
            return
        }
        guard state != .disconnected else { return }
        // PC unter dieser Adresse nicht erreichbar → sofort die nächste (z. B. Tailscale) probieren
        if wasConnecting, !hostQueue.isEmpty, !isManualDisconnect {
            openWebSocket()
            return
        }
        hostQueue.removeAll()
        isRemote = false
        state = .failed(wasConnecting ? unreachableMessage : "Verbindung zum PC verloren")
        onDisconnected?()
        scheduleReconnect()
    }

    private var unreachableMessage: String {
        if config.hasRemoteHost { return "PC nicht erreichbar – läuft er, und ist Tailscale auf dem iPhone an?" }
        return onLocalNetwork
            ? "PC nicht erreichbar – läuft Claude Code mit dem Channel?"
            : "Unterwegs ohne Tailscale ist der PC nicht erreichbar – siehe Einstellungen"
    }

    /// Exponentielles Backoff; früher wurde der Zähler bei jedem Versuch zurückgesetzt
    /// und zwei Wege lösten parallel Reconnects aus.
    private func scheduleReconnect() {
        guard !isManualDisconnect, authFailure == nil, config.connectionMode == .channel, reconnectWork == nil else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            state = .failed(unreachableMessage) // Netzwechsel startet einen neuen Versuch
            return
        }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0)
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reconnectWork = nil
                guard !self.isManualDisconnect, self.authFailure == nil else { return }
                self.openWebSocket()
            }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let socket = self?.webSocket else { return }
                socket.sendPing { error in
                    guard let error else { return }
                    print("[Verbindung] Ping fehlgeschlagen: \(error.localizedDescription)")
                    // Tote Verbindung (z. B. Tunnel weg) nicht stehen lassen
                    Task { @MainActor [weak self] in
                        guard let self, socket === self.webSocket else { return }
                        self.connectionLost()
                    }
                }
            }
        }
    }

    // MARK: - Senden (Channel)

    struct Outgoing {
        let id: String
        let text: String
        let source: FrameSourceType
        let mode: VisionMode
        var image: Data?
        var inReplyTo: String?
    }

    /// Sendet über den WebSocket; große Bilder per HTTP-Upload (spart Base64-Aufblähung).
    func send(_ message: Outgoing) async throws {
        guard state == .connected else { throw BridgeError.notConnected }
        if let image = message.image, image.count > 100_000 {
            do {
                try await upload(message, image: image)
                return
            } catch {
                print("[Verbindung] Upload fehlgeschlagen, sende per WebSocket: \(error.localizedDescription)")
            }
        }
        var payload: [String: Any] = [
            "type": "message",
            "id": message.id,
            "text": message.text,
            "source": message.source.wireName,
            "mode": message.mode.name,
            "mode_prompt": message.mode.systemPrompt,
        ]
        if let image = message.image { payload["image"] = image.base64EncodedString() }
        if let reply = message.inReplyTo { payload["in_reply_to"] = reply }
        try await sendJSON(payload)
    }

    /// Ergebnis einer Handy-Aktion an Claude zurückmelden
    func sendActionResult(id: String, result: ActionResult) async throws {
        try await sendJSON(["type": "action_result", "id": id, "ok": result.ok, "message": result.message])
    }

    func sendPermission(requestId: String, allow: Bool) async throws {
        try await sendJSON(["type": "permission", "request_id": requestId, "behavior": allow ? "allow" : "deny"])
    }

    /// Merkliste an den PC – Claude bekommt sie mit der nächsten Nachricht (nur im Arbeitsspeicher des PCs)
    func sendMemory(_ items: [String], enabled: Bool) async throws {
        guard state == .connected, config.connectionMode == .channel else { return }
        try await sendJSON(["type": "memory_sync", "items": enabled ? items : [], "enabled": enabled])
    }

    private func sendJSON(_ payload: [String: Any]) async throws {
        guard let socket = webSocket else { throw BridgeError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func upload(_ message: Outgoing, image: Data) async throws {
        guard let url = activeConfig.uploadURL else { throw BridgeError.notConfigured }
        var request = authorizedRequest(url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let boundary = "RayBanClaude-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields: [(String, String)] = [
            ("id", message.id), ("text", message.text), ("source", message.source.wireName),
            ("mode", message.mode.name), ("mode_prompt", message.mode.systemPrompt),
        ]
        if let reply = message.inReplyTo { fields.append(("in_reply_to", reply)) }

        var body = Data()
        for (key, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Der Server antwortet mit 202 (früher wurde nur 204 akzeptiert)
        guard (200...299).contains(status) else { throw BridgeError.http(status) }
    }

    // MARK: - Gateway-Modus (REST)

    func chatREST(text: String, images: [Data]) async throws -> ChatResponse {
        guard let url = activeConfig.chatURL else { throw BridgeError.notConfigured }
        var request = authorizedRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            text: text, images: images.map { $0.base64EncodedString() }, conversation_id: conversationId
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw BridgeError.http(status) }
        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        conversationId = chat.conversation_id
        return chat
    }

    func resetConversation() {
        conversationId = nil
    }

    // MARK: - Hilfen

    /// Anfrage mit Token – für den Channel als Bearer, für das Gateway zusätzlich als X-Gateway-Key.
    func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.channelToken)", forHTTPHeaderField: "Authorization")
        request.setValue(config.channelToken, forHTTPHeaderField: "X-Gateway-Key")
        return request
    }

    func fileRequest(_ path: String) -> URLRequest? {
        activeConfig.fileURL(path).map(authorizedRequest)
    }

    /// Prüft Erreichbarkeit UND Token (der öffentliche /health-Endpunkt allein reicht dafür nicht).
    func checkAuthorized() async throws {
        guard let url = activeConfig.authCheckURL else { throw BridgeError.notConfigured }
        var request = authorizedRequest(url)
        request.timeoutInterval = 8
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw BridgeError.http(status) }
    }
}

// MARK: - WebSocket-Delegate

extension ClaudeBridge: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor [weak self] in
            guard let self, webSocketTask === self.webSocket else { return }
            self.connectionLost()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let response = task.response as? HTTPURLResponse, response.statusCode == 401 || response.statusCode == 429 else { return }
        let status = response.statusCode
        Task { @MainActor [weak self] in
            guard let self else { return }
            let message = BridgeError.http(status).localizedDescription
            self.authFailure = message // falsches Token: nicht endlos neu versuchen
            self.reconnectWork?.cancel()
            self.reconnectWork = nil
            self.state = .failed(message)
        }
    }
}

enum BridgeError: LocalizedError {
    case notConnected
    case notConfigured
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Nicht mit dem PC verbunden"
        case .notConfigured: return "PC-Adresse fehlt – QR-Code im Dashboard scannen"
        case .http(401): return "Token falsch – QR-Code im Dashboard neu scannen"
        case .http(429): return "Zu viele Fehlversuche – 15 Minuten warten"
        case .http(503): return "Claude ist gerade überlastet – gleich nochmal versuchen"
        case .http(let code): return "PC antwortet mit Fehler \(code)"
        }
    }
}
