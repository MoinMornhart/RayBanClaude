import Foundation

// MARK: - Gateway-Modus (REST)

struct ChatRequest: Encodable {
    let text: String
    let images: [String] // Base64-JPEGs
    let conversation_id: String?
}

struct ChatResponse: Decodable {
    let text: String
    let tool_calls: [ToolCallResult]
    let conversation_id: String
}

struct ToolCallResult: Decodable {
    let name: String
    let result: AnyCodable
}

struct HealthResponse: Decodable {
    let status: String
    let mode: String?
}

/// Hülle zum Dekodieren beliebiger JSON-Werte
struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
}

// MARK: - Channel-Modus (WebSocket)

struct Attachment: Identifiable, Equatable {
    let name: String
    let path: String
    var id: String { path }

    var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains((path as NSString).pathExtension.lowercased())
    }
}

/// Freigabe-Anfrage von Claude Code (Permission-Relay)
struct PermissionRequest: Identifiable, Equatable {
    let id: String
    let toolName: String
    let description: String
    let inputPreview: String
}

// MARK: - Transkript

struct TranscriptMessage: Identifiable, Equatable {
    /// Server-ID bei Claude-Antworten (für edit_message), sonst eine lokale UUID
    let id: String
    let role: Role
    var text: String
    let timestamp: Date
    let toolCalls: [String]
    let attachments: [Attachment]
    var delivered: Bool

    enum Role {
        case user
        case assistant
        case system
    }

    init(id: String = UUID().uuidString, role: Role, text: String, toolCalls: [String] = [],
         attachments: [Attachment] = [], delivered: Bool = true) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = Date()
        self.toolCalls = toolCalls
        self.attachments = attachments
        self.delivered = delivered
    }
}
