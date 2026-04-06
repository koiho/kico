import Foundation
@preconcurrency import AVFoundation
import Combine
import ImageIO
import UIKit

// MARK: - Type Definitions

struct RawCaptureResult {
    let previewImage: UIImage
    let rawPhotoData: Data?
    let renderPayload: RawRenderPayload?
    let captureMetadata: RawCaptureMetadata
}

struct RawCaptureMetadata: Codable, Sendable {
    let capturedAt: Date
    let lensID: String
    let deviceModel: String
    let iso: Float?
    let shutterSeconds: Double?
    let aperture: Float?
    let focalLengthMm: Float?
    let exposureBiasEV: Float?
}

enum RawCaptureError: Error {
    case notSupported
    case unavailableRawFormat
    case missingRawData
    case processingFailed(Error)
}

struct CameraZoomState {
    let zoomFactor: CGFloat
    let isUltraWide: Bool
    let displayZoomFactor: CGFloat
}

private enum BackLensKind: CaseIterable {
    case ultraWide
    case wide
    case tele
}

private struct RawLensOption {
    let kind: BackLensKind
    let device: AVCaptureDevice
    let uiZoomFactor: CGFloat
}

// MARK: - Camera Manager With Physical-Lens RAW Capture

@MainActor
class MultiCamCameraManager: NSObject, ObservableObject {
    let session: AVCaptureSession

    // Active capture device. Back camera capture is always performed with a physical lens.
    // backZoomReferenceDevice is kept only for deriving user-facing focal labels like 0.5x/3x.
    internal var activeDevice: AVCaptureDevice?
    private var activeInput: AVCaptureDeviceInput?
    private var backZoomReferenceDevice: AVCaptureDevice?

    // Individual device references (only for querying capabilities, NOT for manual switching)
    private var ultraWideDevice: AVCaptureDevice?
    private var wideDevice: AVCaptureDevice?
    private var teleDevice: AVCaptureDevice?
    private var rawCapableBackLenses: [RawLensOption] = []

    // Photo output
    private var photoOutput = AVCapturePhotoOutput()
    private var rawPhotoCompletion: ((Result<RawCaptureResult, RawCaptureError>) -> Void)?
    private var isProcessingPhoto = false
    private var pendingRawProcessingPlan: RawProcessingPlan = .identity
    private var pendingIncludeRenderPayload = false
    private var pendingRetainRawPhotoData = true
    private var pendingPreviewMaxDimension: Int?
    private var pendingRenderPayloadMaxDimension: Int?
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var exposureBias: Float = 0
    private let rawProcessor = RawPhotoProcessor()
    private let rawProcessingQueue = DispatchQueue(label: "camera.raw.processing", qos: .userInitiated)
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?

    // Zoom state
    @Published var zoomFactor: CGFloat = 1.0
    @Published var supportedZoomFactors: [CGFloat] = [1.0]
    @Published var isUltraWide = false
    @Published var isRawCaptureSupported = false
    @Published var exposureBiasRange: ClosedRange<Float> = 0...0
    @Published var isSessionReady = false

    // Zoom state for atomic updates
    @Published var zoomState: CameraZoomState = CameraZoomState(zoomFactor: 1.0, isUltraWide: false, displayZoomFactor: 1.0)

    private var currentZoomFactor: CGFloat = 1.0

    private let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)

    var currentVideoDevice: AVCaptureDevice? {
        activeDevice
    }

    override init() {
        self.session = AVCaptureSession()
        super.init()
        Task { await setup() }
    }

    private func setup() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return }
        await setupCamera()
    }

    // MARK: - Camera Setup

    private func setupCamera() async {
        session.beginConfiguration()
        session.sessionPreset = .photo

        backZoomReferenceDevice = preferredBackZoomReferenceDevice()

        // Keep individual references for capability probing and physical-lens switching.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )

        let devices = discovery.devices
        for device in devices {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                ultraWideDevice = device
            case .builtInWideAngleCamera:
                wideDevice = device
            case .builtInTelephotoCamera:
                teleDevice = device
            default:
                break
            }
        }

        let selectedDevice = wideDevice ?? backZoomReferenceDevice
        guard let selectedDevice else {
            session.commitConfiguration()
            return
        }

        activeDevice = selectedDevice

        do {
            activeInput = try AVCaptureDeviceInput(device: selectedDevice)
        } catch {
            session.commitConfiguration()
            return
        }

        guard let input = activeInput else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            session.commitConfiguration()
            return
        }

        // Configure the active physical device
        configureContinuousAutoMode(for: activeDevice)

        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        // Initialize state
        refreshBackLensRawCapabilities()
        refreshRawCaptureSupport()
        updateExposureCompensationRange()
        rebuildRotationCoordinator()

        // Initialize with the physical wide camera at its native 1.0x.
        if let device = activeDevice {
            try? device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, 1.0)
            device.unlockForConfiguration()
        }
        currentZoomFactor = 1.0
        updateSupportedZoomFactors()
        updateZoomState()

        session.startRunning()

        try? await Task.sleep(nanoseconds: 100_000_000)
        refreshBackLensRawCapabilities()
        refreshRawCaptureSupport()
        fallbackToWideCameraForRAWIfNeeded()
        isSessionReady = true
    }

    // MARK: - State Management

    private func updateZoomState() {
        let zoom = currentZoomFactor
        let ultraWide = zoom < 1.0
        zoomState = CameraZoomState(zoomFactor: zoom, isUltraWide: ultraWide, displayZoomFactor: zoom)
        isUltraWide = ultraWide
    }

    private func updateExposureCompensationRange() {
        guard let device = activeDevice else {
            exposureBiasRange = 0...0
            return
        }
        exposureBiasRange = supportedExposureCompensationRange(for: device)
    }

    private func updateSupportedZoomFactors() {
        guard currentVideoDevice?.position == .back else {
            supportedZoomFactors = [1.0]
            return
        }
        var factors = rawCapableBackLenses.map(\.uiZoomFactor)
        if factors.isEmpty { factors = [1.0] }
        supportedZoomFactors = factors.sorted().reduce(into: [CGFloat]()) { result, f in
            if result.last.map({ abs($0 - f) > 0.05 }) ?? true { result.append(f) }
        }
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        rebuildRotationCoordinator()
    }

    private func rebuildRotationCoordinator() {
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil

        guard let device = activeDevice else {
            return
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )
        rotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            Task { @MainActor [weak self] in
                self?.applyPreviewRotationAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        }
        captureRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            Task { @MainActor [weak self] in
                self?.applyCaptureRotationAngle(coordinator.videoRotationAngleForHorizonLevelCapture)
            }
        }
    }

    private func applyPreviewRotationAngle(_ angle: CGFloat) {
        guard let previewConnection = previewLayer?.connection else {
            return
        }
        let normalizedAngle = Self.normalizedSupportedRotationAngle(angle)
        guard previewConnection.isVideoRotationAngleSupported(normalizedAngle) else {
            return
        }
        previewConnection.videoRotationAngle = normalizedAngle
    }

    private func applyCaptureRotationAngle(_ angle: CGFloat) {
        guard let photoConnection = photoOutput.connection(with: .video) else {
            return
        }
        let normalizedAngle = Self.normalizedSupportedRotationAngle(angle)
        guard photoConnection.isVideoRotationAngleSupported(normalizedAngle) else {
            return
        }
        photoConnection.videoRotationAngle = normalizedAngle
    }

    private static func normalizedSupportedRotationAngle(_ angle: CGFloat) -> CGFloat {
        let snapped = round(angle / 90.0) * 90.0
        let wrapped = snapped.truncatingRemainder(dividingBy: 360.0)
        if wrapped < 0 {
            return wrapped + 360.0
        }
        return wrapped
    }

    // MARK: - Configuration Helpers

    private func configureContinuousAutoMode(for device: AVCaptureDevice?) {
        guard let device else { return }

        try? device.lockForConfiguration()

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        device.setExposureTargetBias(exposureBias, completionHandler: nil)

        device.unlockForConfiguration()
    }

    // MARK: - Apply Zoom Factor (for button taps)

    func applyZoomFactor(_ factor: CGFloat) async {
        guard let rawLens = rawCapableBackLens(for: factor) else { return }
        switchToBackLens(rawLens)
    }

    // MARK: - Flash Control

    func isFlashAvailable() -> Bool {
        guard let device = activeDevice else { return false }
        return device.hasFlash
    }

    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        flashMode = mode
    }

    func getCurrentFlashMode() -> AVCaptureDevice.FlashMode {
        return flashMode
    }

    // MARK: - Exposure Control

    func exposureCompensationRange() -> ClosedRange<Float> {
        guard let device = activeDevice else {
            return exposureBiasRange
        }
        return supportedExposureCompensationRange(for: device)
    }

    func setExposureCompensation(_ value: Float) {
        guard let device = activeDevice else { return }
        let supportedRange = supportedExposureCompensationRange(for: device)
        let clamped = max(supportedRange.lowerBound, min(value, supportedRange.upperBound))
        exposureBias = clamped
        try? device.lockForConfiguration()
        device.setExposureTargetBias(clamped, completionHandler: nil)
        device.unlockForConfiguration()
    }

    private func supportedExposureCompensationRange(for device: AVCaptureDevice) -> ClosedRange<Float> {
        device.minExposureTargetBias...device.maxExposureTargetBias
    }

    // MARK: - Focus Control

    func focusAndExpose(at normalizedPoint: CGPoint) {
        guard let device = activeDevice else { return }

        let x = max(0, min(1, normalizedPoint.x))
        let y = max(0, min(1, normalizedPoint.y))
        let point = CGPoint(x: x, y: y)

        try? device.lockForConfiguration()

        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = point
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        }

        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            } else if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
        }

        device.unlockForConfiguration()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            self?.configureContinuousAutoMode(for: device)
        }
    }

    // MARK: - Camera Flip

    func flipCamera(completion: (() -> Void)? = nil) {
        let current = currentVideoDevice?.position ?? .back
        let newPosition: AVCaptureDevice.Position = current == .back ? .front : .back
        let session = self.session

        sessionQueue.async {
            let newDevice: AVCaptureDevice?
            let backReferenceDevice: AVCaptureDevice?
            if newPosition == .back {
                backReferenceDevice = [
                    AVCaptureDevice.DeviceType.builtInTripleCamera,
                    .builtInDualWideCamera,
                    .builtInDualCamera,
                    .builtInWideAngleCamera
                ].lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: .back) }.first
                newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? backReferenceDevice
            } else {
                backReferenceDevice = nil
                newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            }

            guard let newDevice, let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            var uw: AVCaptureDevice? = nil, wide: AVCaptureDevice? = nil, tele: AVCaptureDevice? = nil
            if newPosition == .back {
                for device in AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera], mediaType: .video, position: .back).devices {
                    switch device.deviceType {
                    case .builtInUltraWideCamera: uw = device
                    case .builtInWideAngleCamera: wide = device
                    case .builtInTelephotoCamera: tele = device
                    default: break
                    }
                }
            }

            // Configure device without going through self (avoids actor hop)
            try? newDevice.lockForConfiguration()
            if newDevice.isFocusModeSupported(.continuousAutoFocus) { newDevice.focusMode = .continuousAutoFocus }
            if newDevice.isSmoothAutoFocusSupported { newDevice.isSmoothAutoFocusEnabled = true }
            if newDevice.isExposureModeSupported(.continuousAutoExposure) { newDevice.exposureMode = .continuousAutoExposure }
            newDevice.unlockForConfiguration()

            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if session.canAddInput(newInput) { session.addInput(newInput) }
            session.commitConfiguration()

            try? newDevice.lockForConfiguration()
            newDevice.videoZoomFactor = max(newDevice.minAvailableVideoZoomFactor, 1.0)
            newDevice.unlockForConfiguration()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.activeDevice = newDevice
                self.activeInput = newInput
                self.backZoomReferenceDevice = backReferenceDevice
                self.ultraWideDevice = uw; self.wideDevice = wide; self.teleDevice = tele
                self.currentZoomFactor = 1.0
                self.zoomFactor = 1.0
                self.updateZoomState()
                self.refreshBackLensRawCapabilities()
                self.updateSupportedZoomFactors()
                self.updateExposureCompensationRange()
                self.refreshRawCaptureSupport()
                self.fallbackToWideCameraForRAWIfNeeded()
                self.rebuildRotationCoordinator()
                completion?()
            }
        }
    }

    func captureRawPhoto(plan: RawProcessingPlan = RawProcessingPlan(),
                         includeRenderPayload: Bool = false,
                         retainRawPhotoData: Bool = true,
                         previewMaxDimension: Int? = nil,
                         renderPayloadMaxDimension: Int? = nil,
                         completion: @escaping (Result<RawCaptureResult, RawCaptureError>) -> Void) {
        guard isSessionReady else {
            completion(.failure(.notSupported))
            return
        }

        guard !isProcessingPhoto else {
            completion(.failure(.notSupported))
            return
        }

        prepareForRawCaptureIfNeeded()
        refreshRawCaptureSupport()

        guard let rawType = preferredRawPhotoPixelFormatType() else {
            completion(.failure(.unavailableRawFormat))
            return
        }

        isProcessingPhoto = true
        pendingRawProcessingPlan = plan
        pendingIncludeRenderPayload = includeRenderPayload
        pendingRetainRawPhotoData = retainRawPhotoData
        pendingPreviewMaxDimension = previewMaxDimension
        pendingRenderPayloadMaxDimension = renderPayloadMaxDimension
        rawPhotoCompletion = { [weak self] result in
            completion(result)
            self?.pendingRawProcessingPlan = .identity
            self?.pendingIncludeRenderPayload = false
            self?.pendingRetainRawPhotoData = true
            self?.pendingPreviewMaxDimension = nil
            self?.pendingRenderPayloadMaxDimension = nil
            self?.isProcessingPhoto = false
        }

        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: nil)

        if let device = activeDevice, device.hasFlash {
            let currentFlashMode = getCurrentFlashMode()
            if photoOutput.supportedFlashModes.contains(currentFlashMode) {
                settings.flashMode = currentFlashMode
            }
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func refreshRawCaptureSupport() {
        if photoOutput.isAppleProRAWSupported {
            photoOutput.isAppleProRAWEnabled = true
        } else {
            photoOutput.isAppleProRAWEnabled = false
        }

        isRawCaptureSupported = preferredRawPhotoPixelFormatType() != nil
    }

    private func preferredRawPhotoPixelFormatType() -> OSType? {
        preferredRawPhotoPixelFormatType(from: photoOutput.availableRawPhotoPixelFormatTypes)
    }

    private func preferredRawPhotoPixelFormatType(from rawTypes: [OSType]) -> OSType? {
        if let proRAWType = rawTypes.first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) {
            return proRAWType
        }

        if let bayerType = rawTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) {
            return bayerType
        }

        return nil
    }

    private func refreshBackLensRawCapabilities() {
        guard currentVideoDevice?.position == .back else {
            rawCapableBackLenses = []
            return
        }

        rawCapableBackLenses = [
            (BackLensKind.ultraWide, ultraWideDevice),
            (BackLensKind.wide, wideDevice),
            (BackLensKind.tele, teleDevice)
        ]
        .compactMap { kind, device in
            guard let device, probeRawSupport(for: device) != nil else { return nil }
            return RawLensOption(
                kind: kind,
                device: device,
                uiZoomFactor: uiZoomFactor(for: device)
            )
        }
        .sorted { $0.uiZoomFactor < $1.uiZoomFactor }
    }

    private func probeRawSupport(for device: AVCaptureDevice) -> OSType? {
        let probeSession = AVCaptureSession()
        probeSession.beginConfiguration()
        probeSession.sessionPreset = .photo

        guard let input = try? AVCaptureDeviceInput(device: device),
              probeSession.canAddInput(input) else {
            probeSession.commitConfiguration()
            return nil
        }
        probeSession.addInput(input)

        let probeOutput = AVCapturePhotoOutput()
        guard probeSession.canAddOutput(probeOutput) else {
            probeSession.commitConfiguration()
            return nil
        }
        probeSession.addOutput(probeOutput)
        probeSession.commitConfiguration()

        if probeOutput.isAppleProRAWSupported {
            probeOutput.isAppleProRAWEnabled = true
        }

        guard let preferredType = preferredRawPhotoPixelFormatType(from: probeOutput.availableRawPhotoPixelFormatTypes) else {
            return nil
        }

        return preferredType
    }

    private func rawCapableBackLens(for factor: CGFloat) -> RawLensOption? {
        rawCapableBackLenses.first(where: { abs($0.uiZoomFactor - factor) < 0.05 })
    }

    private func switchToBackLens(_ lens: RawLensOption) {
        guard currentVideoDevice?.position == .back else { return }

        if activeDevice?.uniqueID == lens.device.uniqueID {
            currentZoomFactor = lens.uiZoomFactor
            zoomFactor = lens.uiZoomFactor

            try? lens.device.lockForConfiguration()
            lens.device.videoZoomFactor = 1.0
            lens.device.unlockForConfiguration()

            updateZoomState()
            refreshRawCaptureSupport()
            return
        }

        guard let newInput = try? AVCaptureDeviceInput(device: lens.device) else { return }

        session.beginConfiguration()
        let previousInput = activeInput
        if let previousInput {
            session.removeInput(previousInput)
        }

        guard session.canAddInput(newInput) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            session.commitConfiguration()
            return
        }

        session.addInput(newInput)
        session.commitConfiguration()

        configureContinuousAutoMode(for: lens.device)

        activeDevice = lens.device
        activeInput = newInput
        currentZoomFactor = lens.uiZoomFactor
        zoomFactor = lens.uiZoomFactor

        try? lens.device.lockForConfiguration()
        lens.device.videoZoomFactor = 1.0
        lens.device.unlockForConfiguration()

        updateZoomState()
        updateExposureCompensationRange()
        refreshRawCaptureSupport()
        updateSupportedZoomFactors()
        rebuildRotationCoordinator()
    }

    private func uiZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        guard let referenceDevice = backZoomReferenceDevice,
              referenceDevice.isVirtualDevice else {
            return fallbackUIZoomFactor(for: backLensKind(for: device) ?? .wide)
        }

        let constituents = referenceDevice.constituentDevices
        let switchPoints = referenceDevice.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let nativeZoomFactors = [CGFloat(1.0)] + switchPoints

        guard let wideIndex = constituents.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) else {
            return fallbackUIZoomFactor(for: backLensKind(for: device) ?? .wide)
        }

        let wideNativeZoom = nativeZoomFactors[min(wideIndex, nativeZoomFactors.count - 1)]
        guard let index = constituents.firstIndex(where: { $0.uniqueID == device.uniqueID }) else {
            return fallbackUIZoomFactor(for: backLensKind(for: device) ?? .wide)
        }

        let nativeZoom = nativeZoomFactors[min(index, nativeZoomFactors.count - 1)]
        return nativeZoom / max(wideNativeZoom, 0.01)
    }

    private func backLensKind(for device: AVCaptureDevice) -> BackLensKind? {
        switch device.deviceType {
        case .builtInUltraWideCamera:
            return .ultraWide
        case .builtInWideAngleCamera:
            return .wide
        case .builtInTelephotoCamera:
            return .tele
        default:
            return nil
        }
    }

    private func fallbackUIZoomFactor(for lens: BackLensKind) -> CGFloat {
        switch lens {
        case .ultraWide:
            return 0.5
        case .wide:
            return 1.0
        case .tele:
            return 2.0
        }
    }

    private func preferredBackZoomReferenceDevice() -> AVCaptureDevice? {
        [
            AVCaptureDevice.DeviceType.builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ].lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: .back) }.first
    }

    private func fallbackToWideCameraForRAWIfNeeded() {
        guard currentVideoDevice?.position == .back else { return }
        guard !isRawCaptureSupported else { return }
        guard let targetLens = rawCapableBackLens(for: 1.0) ?? rawCapableBackLenses.first else { return }
        switchToBackLens(targetLens)
    }

    private func prepareForRawCaptureIfNeeded() {
        guard let device = activeDevice else { return }
        guard abs(device.videoZoomFactor - 1.0) > 0.01 else { return }

        try? device.lockForConfiguration()
        device.videoZoomFactor = 1.0
        device.unlockForConfiguration()

        zoomFactor = currentZoomFactor
        updateZoomState()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension MultiCamCameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Task { @MainActor [weak self] in
                if let rawCompletion = self?.rawPhotoCompletion {
                    rawCompletion(.failure(.processingFailed(error)))
                    self?.rawPhotoCompletion = nil
                }
            }
            return
        }

        if photo.isRawPhoto {
            handleRawPhoto(photo)
        }
    }

    private nonisolated func handleRawPhoto(_ photo: AVCapturePhoto) {
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor [weak self] in
                self?.rawPhotoCompletion?(.failure(.missingRawData))
                self?.rawPhotoCompletion = nil
                self?.isProcessingPhoto = false
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            let rawProcessor = self.rawProcessor
            let plan = self.pendingRawProcessingPlan
            let includeRenderPayload = self.pendingIncludeRenderPayload
            let retainRawPhotoData = self.pendingRetainRawPhotoData
            let previewMaxDimension = self.pendingPreviewMaxDimension
            let renderPayloadMaxDimension = self.pendingRenderPayloadMaxDimension
            let rawProcessingQueue = self.rawProcessingQueue
            let captureMetadata = self.captureMetadata(from: photo)

            rawProcessingQueue.async {
                let processingResult = autoreleasepool {
                    Result {
                        try rawProcessor.process(
                            rawPhotoData: data,
                            plan: plan,
                            includeRenderPayload: includeRenderPayload,
                            previewMaxDimension: previewMaxDimension,
                            renderPayloadMaxDimension: renderPayloadMaxDimension
                        )
                    }
                }

                do {
                    let processed = try processingResult.get()
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let result = RawCaptureResult(
                            previewImage: processed.previewImage,
                            rawPhotoData: retainRawPhotoData ? data : nil,
                            renderPayload: processed.renderPayload,
                            captureMetadata: captureMetadata
                        )
                        self.rawPhotoCompletion?(.success(result))
                        self.rawPhotoCompletion = nil
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        self?.rawPhotoCompletion?(.failure(.processingFailed(error)))
                        self?.rawPhotoCompletion = nil
                        self?.isProcessingPhoto = false
                    }
                }
            }
        }
    }

    private func captureMetadata(from photo: AVCapturePhoto) -> RawCaptureMetadata {
        let exifKey = String(kCGImagePropertyExifDictionary)
        let isoKey = String(kCGImagePropertyExifISOSpeedRatings)
        let exposureTimeKey = String(kCGImagePropertyExifExposureTime)
        let apertureKey = String(kCGImagePropertyExifFNumber)
        let focalLengthKey = String(kCGImagePropertyExifFocalLength)
        let biasKey = String(kCGImagePropertyExifExposureBiasValue)

        let exif = photo.metadata[exifKey] as? [String: Any]
        let lensID = activeDevice?.deviceType.rawValue ?? "unknown_lens"
        let deviceModel = Self.machineIdentifier()

        let iso: Float?
        if let array = exif?[isoKey] as? [NSNumber], let first = array.first {
            iso = first.floatValue
        } else if let value = exif?[isoKey] as? NSNumber {
            iso = value.floatValue
        } else {
            iso = nil
        }

        let shutterSeconds = (exif?[exposureTimeKey] as? NSNumber)?.doubleValue
        let aperture = (exif?[apertureKey] as? NSNumber)?.floatValue
        let focalLengthMm = (exif?[focalLengthKey] as? NSNumber)?.floatValue
        let exposureBiasEV = (exif?[biasKey] as? NSNumber)?.floatValue

        return RawCaptureMetadata(
            capturedAt: Date(),
            lensID: lensID,
            deviceModel: deviceModel,
            iso: iso,
            shutterSeconds: shutterSeconds,
            aperture: aperture,
            focalLengthMm: focalLengthMm,
            exposureBiasEV: exposureBiasEV
        )
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}
