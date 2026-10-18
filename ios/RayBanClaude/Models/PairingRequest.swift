import Foundation

/// Kopplungsdaten aus dem QR-Code im PC-Dashboard:
/// `raybanclaude://pair?host=192.168.1.20&port=18790&token=…`
///
/// Wird vor dem Übernehmen immer bestätigt – ein fremder QR-Code könnte die App
/// sonst unbemerkt auf einen fremden Server umleiten (und Kamerabilder dorthin schicken).
struct PairingRequest: Identifiable, Equatable {
    let host: String
    let port: Int
    let token: String

    var id: String { "\(host):\(port)" }

    static let urlHost = "pair"

    init?(url: URL) {
        guard url.scheme?.lowercased() == "raybanclaude",
              url.host?.lowercased() == Self.urlHost,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard let host = value("host"), Self.isValidHost(host),
              let portText = value("port"), let port = Int(portText), (1024...65535).contains(port),
              let token = value("token"), Self.isValidToken(token) else {
            return nil
        }
        self.host = host
        self.port = port
        self.token = token
    }

    /// IPv4-Adresse oder einfacher Hostname (z. B. „mein-pc.local“)
    static func isValidHost(_ host: String) -> Bool {
        guard (1...253).contains(host.count) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return host.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
            && !host.hasPrefix(".") && !host.hasPrefix("-")
    }

    /// 16–128 Zeichen aus Buchstaben, Ziffern, _ und -
    static func isValidToken(_ token: String) -> Bool {
        guard (16...128).contains(token.count) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return token.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
    }
}
