import AVFoundation
import UIKit

enum NineCameraPosition: String, CaseIterable {
    case back
    case front

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back: return .back
        case .front: return .front
        }
    }

    var alternate: NineCameraPosition {
        switch self {
        case .back: return .front
        case .front: return .back
        }
    }
}

@MainActor
final class CameraManager: NSObject, ObservableObject {
    private static let preferredCameraPositionKey = "nine.preferredCameraPosition"

    @Published private(set) var authorizationDenied = false
    @Published private(set) var isReady = false
    @Published var exposureBias: Float = 0
    @Published private(set) var manualLensPosition: Float = 0.5
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var isHoldFocusLocked = false
    @Published private(set) var isManualFocusActive = false
    @Published private(set) var cameraPosition: NineCameraPosition
    @Published private(set) var canSwitchCamera = false

    var isPreviewMirrored: Bool {
        cameraPosition == .front
    }

    // AVFoundation session work is serialized on sessionQueue, outside UI isolation.
    nonisolated(unsafe) let session = AVCaptureSession()

    nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.nine.camera.session", qos: .userInitiated)
    nonisolated(unsafe) private var device: AVCaptureDevice?
    nonisolated(unsafe) private var currentInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var isConfigured = false
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var focusAcquisitionTask: Task<Void, Never>?
    private var focusRestoreTask: Task<Void, Never>?
    private var focusLockToken: UUID?

    override init() {
        let storedPosition = UserDefaults.standard.string(forKey: Self.preferredCameraPositionKey)
            .flatMap(NineCameraPosition.init(rawValue:))
        cameraPosition = storedPosition ?? .back
        super.init()
    }

    func start() async {
        guard await authorizeCamera() else {
            authorizationDenied = true
            return
        }

        do {
            try await configureIfNeeded()
            sessionQueue.async { [weak self] in
                guard let self, !self.session.isRunning else { return }
                self.session.startRunning()
            }
            isReady = true
        } catch {
            authorizationDenied = true
        }
    }

    func stop() {
        cancelHoldFocusLock()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        isReady = false
    }

    func capturePhoto() async throws -> UIImage {
        guard isReady, continuation == nil else { throw CameraError.notReady }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            settings.flashMode = .off
            if let connection = output.connection(with: .video),
               connection.isVideoMirroringSupported {
                // Keep front-camera captures mirrored because the front preview is mirrored.
                // This preserves the user's composition across preview, captured frames,
                // blend preview, contact sheet, and exported images.
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = cameraPosition == .front
            }
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func switchCamera() {
        print("[Nine] Camera switch requested · current: \(cameraPosition.rawValue)")
        guard !isHoldFocusLocked, continuation == nil else { return }
        let nextPosition = cameraPosition.alternate
        guard camera(for: nextPosition) != nil else {
            print("[Nine] Camera switch unavailable · missing: \(nextPosition.rawValue)")
            return
        }

        isReady = false
        cancelHoldFocusLock()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureInput(position: nextPosition)
                Task { @MainActor in
                    self.cameraPosition = nextPosition
                    self.persistPreferredCameraPosition(nextPosition)
                    self.resetPublishedCameraControls()
                    self.isReady = true
                    print("[Nine] Camera switched · current: \(nextPosition.rawValue)")
                }
            } catch {
                Task { @MainActor in
                    self.isReady = true
                    print("[Nine] Camera switch failed · \(error.localizedDescription)")
                }
            }
        }
    }

    func setExposureBias(_ value: Float) {
        guard let device else { return }
        let bias = min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(bias)
            device.unlockForConfiguration()
            exposureBias = bias
        } catch { }
    }

    func focus(at normalizedPoint: CGPoint) {
        guard let device else { return }
        cancelHoldFocusLock()
        let point = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
            isManualFocusActive = false
        } catch { }
    }

    func setManualFocus(_ position: Float) {
        guard let device, device.isLockingFocusWithCustomLensPositionSupported else { return }
        guard !isHoldFocusLocked else { return }
        cancelHoldFocusLock()
        let clamped = min(max(position, 0), 1)
        do {
            try device.lockForConfiguration()
            device.setFocusModeLocked(lensPosition: clamped)
            device.unlockForConfiguration()
            manualLensPosition = clamped
            isManualFocusActive = true
        } catch { }
    }

    @discardableResult
    func beginHoldFocusLock(at normalizedPoint: CGPoint) -> Bool {
        guard let device else { return false }
        cancelHoldFocusLock()

        let point = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )
        let token = UUID()
        focusLockToken = token
        isHoldFocusLocked = true

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            device.unlockForConfiguration()
        } catch {
            cancelHoldFocusLock()
            return false
        }

        focusAcquisitionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.lockCurrentFocus(for: token)
        }
        return true
    }

    func endHoldFocusLock() {
        guard isHoldFocusLocked, let token = focusLockToken else { return }
        restoreContinuousAutofocus(for: token)
    }

    func resetFocusLockAfterCapture() {
        endHoldFocusLock()
    }

    func setZoomFactor(_ value: CGFloat) {
        guard let device else { return }
        let maximum = min(device.maxAvailableVideoZoomFactor, 3)
        let zoom = min(max(value, 1), maximum)
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.ramp(toVideoZoomFactor: zoom, withRate: 12)
            device.unlockForConfiguration()
            zoomFactor = zoom
        } catch { }
    }

    private func authorizeCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureIfNeeded() async throws {
        guard !isConfigured else { return }
        let selectedPosition = camera(for: cameraPosition) != nil ? cameraPosition : .back

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }
                do {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    defer { self.session.commitConfiguration() }

                    guard self.camera(for: selectedPosition) != nil,
                          self.session.canAddOutput(self.output) else {
                        throw CameraError.configurationFailed
                    }

                    self.session.addOutput(self.output)
                    try self.configureInput(position: selectedPosition, commitsSessionConfiguration: false)
                    self.output.maxPhotoQualityPrioritization = .speed
                    self.isConfigured = true
                    let canSwitch = NineCameraPosition.allCases.allSatisfy { self.camera(for: $0) != nil }
                    Task { @MainActor in
                        self.canSwitchCamera = canSwitch
                        self.cameraPosition = selectedPosition
                        self.resetPublishedCameraControls()
                        continuation.resume(returning: ())
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated func camera(for position: NineCameraPosition) -> AVCaptureDevice? {
        switch position {
        case .back:
            return preferredBackCamera()
        case .front:
            return preferredFrontCamera()
        }
    }

    private nonisolated func preferredBackCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private nonisolated func preferredFrontCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTrueDepthCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .front
        )
        return discovery.devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }

    private nonisolated func configureInput(
        position: NineCameraPosition,
        commitsSessionConfiguration: Bool = true
    ) throws {
        guard let camera = camera(for: position),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            throw CameraError.configurationFailed
        }

        if commitsSessionConfiguration {
            session.beginConfiguration()
        }
        defer {
            if commitsSessionConfiguration {
                session.commitConfiguration()
            }
        }

        let previousInput = currentInput
        if let currentInput {
            session.removeInput(currentInput)
        }

        guard session.canAddInput(input) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            throw CameraError.configurationFailed
        }

        if position == .back {
            configureAutomaticCloseFocusIfSupported(on: camera)
        }

        session.addInput(input)
        currentInput = input
        device = camera

        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private nonisolated func configureAutomaticCloseFocusIfSupported(on camera: AVCaptureDevice) {
        guard camera.isVirtualDevice,
              camera.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported else {
            return
        }

        do {
            try camera.lockForConfiguration()
            camera.fallbackPrimaryConstituentDevices = camera.supportedFallbackPrimaryConstituentDevices
            camera.setPrimaryConstituentDeviceSwitchingBehavior(
                .auto,
                restrictedSwitchingBehaviorConditions: []
            )
            camera.unlockForConfiguration()
        } catch { }
    }

    private func lockCurrentFocus(for token: UUID) {
        guard focusLockToken == token,
              isHoldFocusLocked,
              let device,
              device.isLockingFocusWithCustomLensPositionSupported else { return }

        do {
            let currentPosition = device.lensPosition
            try device.lockForConfiguration()
            device.setFocusModeLocked(lensPosition: currentPosition)
            device.unlockForConfiguration()
            manualLensPosition = currentPosition
            isManualFocusActive = true
        } catch { }
    }

    private func restoreContinuousAutofocus(for token: UUID) {
        guard focusLockToken == token, let device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch { }
        cancelHoldFocusLock()
        isManualFocusActive = false
    }

    private func cancelHoldFocusLock() {
        focusAcquisitionTask?.cancel()
        focusRestoreTask?.cancel()
        focusAcquisitionTask = nil
        focusRestoreTask = nil
        focusLockToken = nil
        isHoldFocusLocked = false
    }

    private func persistPreferredCameraPosition(_ position: NineCameraPosition) {
        UserDefaults.standard.set(position.rawValue, forKey: Self.preferredCameraPositionKey)
    }

    private func resetPublishedCameraControls() {
        exposureBias = 0
        manualLensPosition = device?.lensPosition ?? 0.5
        zoomFactor = device?.videoZoomFactor ?? 1
        isManualFocusActive = false
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                continuation?.resume(throwing: error)
                continuation = nil
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data),
                  let squareImage = image.centerSquareCropped() else {
                continuation?.resume(throwing: CameraError.captureFailed)
                continuation = nil
                return
            }
            continuation?.resume(returning: squareImage)
            continuation = nil
        }
    }
}

private extension UIImage {
    func centerSquareCropped() -> UIImage? {
        let side = min(size.width, size.height)
        guard side > 0 else { return nil }

        let destination = CGRect(x: 0, y: 0, width: side, height: side)
        let source = CGRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: destination.size, format: format).image { _ in
            draw(
                in: CGRect(
                    x: -source.minX,
                    y: -source.minY,
                    width: size.width,
                    height: size.height
                )
            )
        }
    }
}

enum CameraError: LocalizedError {
    case notReady
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .notReady: return "The camera is not ready for an exposure."
        case .configurationFailed: return "The camera could not be configured."
        case .captureFailed: return "The exposure could not be recorded."
        }
    }
}
