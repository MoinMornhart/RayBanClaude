import Foundation
import Security

/// Speichert Geheimnisse (Channel-Token, ElevenLabs-Key) im iOS-Schlüsselbund
/// statt im Klartext in den UserDefaults.
enum KeychainStore {
    private static let service = "com.raybanclaude.secrets"

    enum Key: String {
        case channelToken
        case elevenLabsAPIKey
        case anthropicAPIKey
    }

    static func get(_ key: Key) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func set(_ value: String, for key: Key) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // Nur auf diesem Gerät, nach dem ersten Entsperren verfügbar (auch im Hintergrund)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Speichern fehlgeschlagen (\(key.rawValue)): \(status)")
        }
    }
}
