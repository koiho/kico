import Foundation
import Combine
import AVFoundation
import UIKit

@MainActor
class CameraViewModel: ObservableObject {
    @Published var state = CameraState()
    @Published var toastErrorMessage: String?
    let camera = MultiCamCameraManager()
    private let exportStore = NeutralRenderExportStore()
    private let photoLibraryStore = PhotoLibraryStore()
    private let renderService = OnnxPhotoRenderService()
    private let renderPreparationQueue = DispatchQueue(
        label: "kico.render-preparation",
        qos: .userInitiated
    )
    private var lastRawCapture: RawCaptureResult?

    init() {
        let exposureRange = camera.exposureCompensationRange()
        state.exposureMinEV = exposureRange.lowerBound
        state.exposureMaxEV = exposureRange.upperBound
        state.exposureEV = max(exposureRange.lowerBound, min(0, exposureRange.upperBound))

        state.isRawSupported = camera.isRawCaptureSupported
        state.rawStatusMessage = camera.isRawCaptureSupported ? "RAW: available" : "RAW: unavailable"
        state.supportedZoomFactors = camera.supportedZoomFactors
        state.selectedZoomFactor = nearestZoomFactor(to: camera.zoomFactor, in: state.supportedZoomFactors)

        // Use zoomState for atomic updates
        state.isUltraWide = camera.zoomState.isUltraWide
        state.displayZoomFactor = camera.zoomState.displayZoomFactor

        camera.$supportedZoomFactors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] factors in
                guard let self else { return }
                self.state.supportedZoomFactors = factors
                self.state.selectedZoomFactor = self.nearestZoomFactor(to: self.state.selectedZoomFactor, in: factors)
            }
            .store(in: &cancellables)

        // Subscribe to zoomState for atomic updates of all zoom-related properties
        camera.$zoomState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] zoomState in
                guard let self else { return }
                self.state.selectedZoomFactor = zoomState.zoomFactor
                self.state.isUltraWide = zoomState.isUltraWide
                self.state.displayZoomFactor = zoomState.displayZoomFactor
            }
            .store(in: &cancellables)

        camera.$isRawCaptureSupported
            .receive(on: DispatchQueue.main)
            .sink { [weak self] supported in
                self?.state.isRawSupported = supported
                self?.state.rawStatusMessage = supported ? "RAW: available" : "RAW: unavailable"
            }
            .store(in: &cancellables)

        camera.$isSessionReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                self?.state.isSessionReady = ready
            }
            .store(in: &cancellables)

        camera.$exposureBiasRange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in
                guard let self else { return }
                self.state.exposureMinEV = range.lowerBound
                self.state.exposureMaxEV = range.upperBound
                self.state.exposureEV = max(range.lowerBound, min(self.state.exposureEV, range.upperBound))
            }
            .store(in: &cancellables)

        // Initialize flash mode state
        if camera.isFlashAvailable() {
            let currentFlashMode = camera.getCurrentFlashMode()
            state.flashMode = currentFlashMode == .on ? .on : .off
        }

        Task { [weak self] in
            await self?.loadStoredPhotos()
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private func nearestZoomFactor(to target: CGFloat, in factors: [CGFloat]) -> CGFloat {
        guard let first = factors.first else { return 1.0 }
        return factors.min(by: { abs($0 - target) < abs($1 - target) }) ?? first
    }

    private func emitError(_ message: String) {
        toastErrorMessage = message
    }

    func selectZoom(_ factor: CGFloat) {
        Task {
            await camera.applyZoomFactor(factor)
        }
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        camera.attachPreviewLayer(layer)
    }

    func capturePhoto(referenceImage: UIImage?) {
        guard state.isSessionReady else {
            return
        }

        guard !state.isCapturing else {
            return
        }

        state.isCapturing = true
        guard state.isRawSupported else {
            state.rawStatusMessage = "RAW: unavailable"
            emitError("当前设备不支持 RAW 拍摄")
            state.isCapturing = false
            return
        }

        if CaptureWorkflowConfiguration.mode == .renderTest,
           CaptureWorkflowConfiguration.renderRequiresReferenceImage,
           referenceImage == nil {
            state.rawStatusMessage = "RAW: waiting for reference"
            emitError("请先导入并选择一张参考图")
            state.isCapturing = false
            return
        }

        state.rawStatusMessage = "RAW: processing..."
        let retainRawPhotoData = CaptureWorkflowConfiguration.mode == .dataCollection
        let renderPayloadMaxDimension = CaptureWorkflowConfiguration.mode == .renderTest
            ? CaptureWorkflowConfiguration.renderPayloadMaxDimension
            : nil
        let previewMaxDimension = CaptureWorkflowConfiguration.mode == .renderTest
            ? CaptureWorkflowConfiguration.renderCapturePreviewMaxDimension
            : nil
        camera.captureRawPhoto(
            plan: state.rawProcessingPlan,
            includeRenderPayload: true,
            retainRawPhotoData: retainRawPhotoData,
            previewMaxDimension: previewMaxDimension,
            renderPayloadMaxDimension: renderPayloadMaxDimension
        ) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success(let raw):
                switch CaptureWorkflowConfiguration.mode {
                case .renderTest:
                    self.lastRawCapture = nil
                    self.state.rawStatusMessage = referenceImage == nil
                        ? "RAW: inferencing with self reference..."
                        : "RAW: inferencing..."
                    self.renderCapturedPhoto(raw, referenceImage: referenceImage)

                case .dataCollection:
                    self.lastRawCapture = raw
                    self.state.rawStatusMessage = "RAW: collecting..."
                    self.collectRawCapture(raw)
                }
            case .failure(_):
                self.emitError("RAW 拍摄失败，请稍后重试")
                self.state.rawStatusMessage = "RAW failed"
                self.state.isCapturing = false
            }
        }
    }

    func collectLastCapture() {
        guard let lastRawCapture else {
            emitError("当前没有可采集的 RAW 数据")
            return
        }

        collectRawCapture(lastRawCapture)
    }

    private func collectRawCapture(_ rawCapture: RawCaptureResult) {
        Task {
            do {
                let record = try await exportStore.collect(
                    rawCapture: rawCapture,
                    previewMaxDimension: CaptureWorkflowConfiguration.collectionPreviewMaxDimension,
                    analysisOptions: CaptureWorkflowConfiguration.collectionAnalysisOptions
                )
                await MainActor.run {
                    self.state.isCapturing = false
                    self.lastRawCapture = nil
                    self.state.rawStatusMessage = "RAW: collected \(record.stem)"
                }
                if CaptureWorkflowConfiguration.collectionSavesPreviewToGallery {
                    self.enqueuePhotoSave(
                        rawCapture.previewImage,
                        successStatusMessage: "RAW: collected \(record.stem)"
                    )
                }
            } catch {
                await MainActor.run {
                    self.state.rawStatusMessage = "RAW: collect failed"
                    self.emitError("neutral 数据采集失败，请检查存储空间")
                    self.state.isCapturing = false
                    self.lastRawCapture = nil
                }
            }
        }
    }

    private func renderCapturedPhoto(_ raw: RawCaptureResult, referenceImage: UIImage?) {
        state.rawStatusMessage = "RAW: preparing masks..."
        let analysisOptions = CaptureWorkflowConfiguration.renderAnalysisOptions
        let previewImageMaxDimension = CaptureWorkflowConfiguration.renderPreviewImageMaxDimension
        let referenceImageMaxDimension = CaptureWorkflowConfiguration.renderReferenceImageMaxDimension
        let renderRuntimeOptions = FfiRenderRuntimeOptions(
            maskWorkingMaxDimension: CaptureWorkflowConfiguration.renderMaskWorkingMaxDimension.map(UInt32.init),
            bloomBaseMaxDimension: CaptureWorkflowConfiguration.renderBloomBaseMaxDimension.map(UInt32.init)
        )
        let requiresReferenceImage = CaptureWorkflowConfiguration.renderRequiresReferenceImage
        let savePreviewFallbackOnRenderFailure = CaptureWorkflowConfiguration.savePreviewFallbackOnRenderFailure
        let previewFallbackImage = raw.previewImage

        renderPreparationQueue.async { [weak self] in
            guard let self else { return }

            do {
                let job = try autoreleasepool {
                    try OnnxPhotoRenderJobBuilder.prepare(
                        referenceImage: referenceImage,
                        rawCapture: raw,
                        analysisOptions: analysisOptions,
                        previewImageMaxDimension: previewImageMaxDimension,
                        referenceImageMaxDimension: referenceImageMaxDimension,
                        renderRuntimeOptions: renderRuntimeOptions,
                        requiresReferenceImage: requiresReferenceImage
                    )
                }

                Task { [weak self] in
                    guard let self else { return }

                    await MainActor.run {
                        self.state.rawStatusMessage = job.usedSelfReference
                            ? "RAW: inferencing with self reference..."
                            : "RAW: inferencing..."
                    }

                    do {
                        InferenceDebugConsole.logRenderStart(usedSelfReference: job.usedSelfReference)
                        let response = try await self.renderService.render(request: job.request)
                        InferenceDebugConsole.log(response: response, usedSelfReference: job.usedSelfReference)
                        let renderedImage = try autoreleasepool {
                            try OnnxPhotoRenderJobBuilder.makeDisplayImage(from: response.finalImage)
                        }
                        await MainActor.run {
                            self.state.isCapturing = false
                            self.lastRawCapture = nil
                            self.state.rawStatusMessage = "RAW: saving..."
                            self.enqueuePhotoSave(
                                renderedImage,
                                successStatusMessage: job.usedSelfReference
                                    ? "RAW: rendered (self reference)"
                                    : "RAW: rendered"
                            )
                        }
                    } catch {
                        InferenceDebugConsole.logRenderFailure(error)
                        await MainActor.run {
                            self.state.rawStatusMessage = "RAW: render failed"
                            self.emitError("真实模型推理渲染失败：\(error.localizedDescription)")
                            self.state.isCapturing = false
                            self.lastRawCapture = nil
                        }
                        if savePreviewFallbackOnRenderFailure {
                            await MainActor.run {
                                self.enqueuePhotoSave(previewFallbackImage, successStatusMessage: "RAW: render failed")
                            }
                        }
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.state.rawStatusMessage = "RAW: render prep failed"
                    self.emitError("推理输入准备失败：\(error.localizedDescription)")
                    self.state.isCapturing = false
                    self.lastRawCapture = nil
                }
            }
        }
    }

    private func enqueuePhotoSave(_ image: UIImage, successStatusMessage: String) {
        Task(priority: .utility) { [weak self] in
            guard let self else { return }

            do {
                let savedPhoto = try await self.photoLibraryStore.savePhoto(image)
                await MainActor.run {
                    self.applySavedPhoto(savedPhoto)
                    self.state.rawStatusMessage = successStatusMessage
                }
            } catch {
                await MainActor.run {
                    self.state.rawStatusMessage = "RAW: save failed"
                    self.emitError("保存照片失败，请检查存储空间")
                }
            }
        }
    }

    private func loadStoredPhotos() async {
        do {
            let photos = try await photoLibraryStore.loadPhotos()
            let latestThumbnail = photos.first.flatMap { StoredPhotoImageLoader.image(at: $0.thumbnailURL) }
            await MainActor.run {
                self.state.photos = photos
                self.state.photoCount = photos.count
                self.state.lastPhotoThumbnail = latestThumbnail
            }
        } catch {
            await MainActor.run {
                self.emitError("读取本地照片失败")
            }
        }
    }

    private func applySavedPhoto(_ savedPhoto: SavedPhotoArtifact) {
        state.lastPhotoThumbnail = UIImage(data: savedPhoto.thumbnailData)
        state.photos.insert(savedPhoto.item, at: 0)
        state.photoCount = state.photos.count
    }

    func setExposureEV(_ value: Float) {
        let clamped = max(state.exposureMinEV, min(state.exposureMaxEV, value))
        state.exposureEV = clamped
        camera.setExposureCompensation(clamped)
    }

    func updateRawProcessingPlan(_ plan: RawProcessingPlan) {
        state.rawProcessingPlan = plan
    }

    func focus(indicatorPoint: CGPoint, devicePoint: CGPoint) {
        state.focusPointInPreview = indicatorPoint
        camera.focusAndExpose(at: devicePoint)
    }

    func flipCamera() {
        let preserveFlashMode = state.flashMode
        state.isSwitchingCamera = true

        camera.flipCamera {
            let exposureRange = self.camera.exposureCompensationRange()
            self.state.exposureMinEV = exposureRange.lowerBound
            self.state.exposureMaxEV = exposureRange.upperBound
            self.state.exposureEV = 0
            self.camera.setExposureCompensation(0)
            self.state.flashMode = preserveFlashMode
            self.camera.setFlashMode(preserveFlashMode == .on ? .on : .off)
            self.state.isSwitchingCamera = false
        }
    }

    func toggleFlash() {
        guard camera.isFlashAvailable() else { return }

        switch state.flashMode {
        case .off:
            state.flashMode = .on
            camera.setFlashMode(.on)
        case .on:
            state.flashMode = .off
            camera.setFlashMode(.off)
        }
    }
}
