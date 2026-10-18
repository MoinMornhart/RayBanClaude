import Foundation
import Combine

enum FrameSourceType: String, CaseIterable, Identifiable {
    case iPhone = "iPhone-Kamera"
    case rayBan = "Ray-Ban Meta"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .iPhone: return "iPhone"
        case .rayBan: return "Brille"
        }
    }

    var icon: String {
        switch self {
        case .iPhone: return "camera.fill"
        case .rayBan: return "eyeglasses"
        }
    }

    /// Wert für das Feld `source` beim Server
    var wireName: String {
        switch self {
        case .iPhone: return "iphone"
        case .rayBan: return "rayban"
        }
    }
}

@MainActor
protocol FrameSource: AnyObject {
    var latestFrame: Data? { get }
    var isRunning: Bool { get }
    var sourceType: FrameSourceType { get }
    var connectionStatus: FrameSourceStatus { get }
    func start() throws
    func stop()
    func consumeFrame() -> Data?
    /// Ein frisches, möglichst scharfes Foto (für das Tool request_photo)
    func capturePhoto() async -> Data?
}

enum FrameSourceStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: return "Getrennt"
        case .connecting: return "Verbinde …"
        case .connected: return "Verbunden"
        case .error(let msg): return msg
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
