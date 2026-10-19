import Foundation
@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import UIKit

// MARK: - Erkannter QR-/Barcode

struct DetectedCode: Equatable {
    let type: String
    let value: String
    let timestamp: Date

    static func == (lhs: DetectedCode, rhs: DetectedCode) -> Bool {
        lhs.type == rhs.type && lhs.value == rhs.value
    }

    /// Lesbarer Name des Codetyps
    var typeLabel: String {
        type.replacingOccurrences(of: "org.iso.", with: "")
            .replacingOccurrences(of: "org.gs1.", with: "")
            .uppercased()
    }
}

// MARK: - iPhone-Kamera

@MainActor
final class CameraManager: NSObject, ObservableObject, FrameSource {
    @Published private(set) var latestFrame: Data?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var connectionStatus: FrameSourceStatus = .disconnected
    @Published private(set) var frameCount: Int = 0
    @Published var lastDetectedCode: DetectedCode?

    let sourceType: FrameSourceType = .iPhone
    nonisolated let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    /// Alle Session-Änderungen laufen auf dieser Queue (Apple-Empfehlung, blockiert nicht die UI)
    private nonisolated let sessionQueue = DispatchQueue(label: "camera.session")
    private nonisolated let processor = FrameProcessor()
    private var isConfigured = false

    private var lastCodeValue: String?
    private var lastCodeTime: Date = .distantPast
    private let codeDebounceInterval: TimeInterval = 3.0

    private let supportedCodeTypes: [AVMetadataObject.ObjectType] = [
        .qr, .ean13, .ean8, .code128, .code39, .upce, .pdf417, .aztec, .dataMatrix,
    ]

    func configure(frameInterval: TimeInterval = 1.0, jpegQuality: CGFloat = 0.85) {
        processor.update(frameInterval: frameInterval, jpegQuality: jpegQuality)
    }

    func start() throws {
        if !isConfigured {
            try configureSession()
            isConfigured = true
        }
        connectionStatus = .connecting
        sessionQueue.async { [captureSession] in
            if !captureSession.isRunning { captureSession.startRunning() }
            let running = captureSession.isRunning
            Task { @MainActor [weak self] in
                self?.isRunning = running
                self?.connectionStatus = running ? .connected : .error("Kamera konnte nicht starten")
            }
        }
    }

    /// Stoppt immer – auch wenn der Start noch läuft (früher wurde ein laufender Start übersehen).
    func stop() {
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
        isRunning = false
        connectionStatus = .disconnected
    }

    func consumeFrame() -> Data? {
        latestFrame
    }

    func capturePhoto() async -> Data? {
        guard isRunning else { return latestFrame }
        return await processor.nextFrame(quality: 0.92) ?? latestFrame
    }

    /// iPhone-Kamera läuft als Sucher ohnehin, solange die App offen ist
    func prepareCapture() {}

    // MARK: - Einrichtung

    private func configureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .hd1920x1080

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            throw CameraError.noCameraAvailable
        }
        captureSession.addInput(input)

        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
            if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
            camera.unlockForConfiguration()
        } catch {
            print("[Kamera] Gerät nicht konfigurierbar: \(error)")
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        processor.onFrame = { [weak self] jpeg in
            Task { @MainActor [weak self] in
                self?.latestFrame = jpeg
                self?.frameCount += 1
            }
        }
        videoOutput.setSampleBufferDelegate(processor, queue: processor.queue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        // Hochformat: ohne diese Drehung kamen die Bilder bei Claude um 90° gedreht an
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = supportedCodeTypes.filter {
                metadataOutput.availableMetadataObjectTypes.contains($0)
            }
        }
    }

    fileprivate func handle(code value: String, type: String) {
        let now = Date()
        if value == lastCodeValue && now.timeIntervalSince(lastCodeTime) < codeDebounceInterval { return }
        lastCodeValue = value
        lastCodeTime = now
        lastDetectedCode = DetectedCode(type: type, value: value, timestamp: now)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - QR-/Barcode-Erkennung

extension CameraManager: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = code.stringValue else { return }
        let type = code.type.rawValue
        MainActor.assumeIsolated {
            handle(code: value, type: type)
        }
    }
}

// MARK: - Bildverarbeitung (läuft auf eigener Queue, nicht auf dem Main-Thread)

/// Wandelt Kamerabilder gedrosselt in JPEG um. Ein CIContext wird wiederverwendet
/// (früher wurde pro Bild ein neuer erzeugt – teuer).
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "camera.frames")
    var onFrame: ((Data) -> Void)?

    private let context = CIContext()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let lock = NSLock()
    private var frameInterval: TimeInterval = 1.0
    private var jpegQuality: CGFloat = 0.85
    private var lastCapture: Date = .distantPast
    private var waiter: (quality: CGFloat, continuation: CheckedContinuation<Data?, Never>)?

    func update(frameInterval: TimeInterval, jpegQuality: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        self.frameInterval = frameInterval
        self.jpegQuality = jpegQuality
    }

    /// Liefert das nächste Kamerabild in hoher Qualität (max. 2 s warten).
    func nextFrame(quality: CGFloat) async -> Data? {
        await withCheckedContinuation { continuation in
            lock.lock()
            waiter?.continuation.resume(returning: nil)
            waiter = (quality, continuation)
            lock.unlock()
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.finishWaiter(with: nil)
            }
        }
    }

    private func finishWaiter(with data: Data?) {
        lock.lock()
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.continuation.resume(returning: data)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let now = Date()
        let pendingQuality = waiter?.quality
        let due = now.timeIntervalSince(lastCapture) >= frameInterval
        let quality = pendingQuality ?? jpegQuality
        if due || pendingQuality != nil { lastCapture = now }
        lock.unlock()
        guard due || pendingQuality != nil, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let image = CIImage(cvPixelBuffer: buffer)
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        guard let jpeg = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options) else { return }
        if pendingQuality != nil { finishWaiter(with: jpeg) }
        onFrame?(jpeg)
    }
}

enum CameraError: LocalizedError {
    case noCameraAvailable

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: return "Keine Kamera verfügbar"
        }
    }
}
