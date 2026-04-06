import Foundation

enum CaptureWorkflowMode: String {
    case renderTest
    case dataCollection
}

enum RenderRuntimePreset {
    case safe
    case balanced
    case quality
}

enum CaptureWorkflowConfiguration {
    // Change this value when you want to switch the camera workflow.
    static let mode: CaptureWorkflowMode = .renderTest
    static let renderRequiresReferenceImage = true
    static let savePreviewFallbackOnRenderFailure = false
    static let renderRuntimePreset: RenderRuntimePreset = .balanced

    // Data-collection tuning. The exported preview is only used as model input
    // and is resized again during training, so keeping it below full sensor
    // resolution greatly reduces encode/write pressure without affecting usage.
    static let collectionPreviewMaxDimension: Int = 1536
    static let collectionSavesPreviewToGallery = false
    static let collectionAnalysisOptions = CaptureAnalysisOptions(
        maxDimension: 512,
        personSegmentationQuality: .fast,
        includeForegroundSaliency: false
    )

    // Render-test tuning. `balanced` is the default tradeoff for keeping the
    // look stable while avoiding the worst memory spikes on device.
    static var renderMaskMaxDimension: Int {
        switch renderRuntimePreset {
        case .safe, .balanced:
            return 256
        case .quality:
            return 384
        }
    }

    static var renderPreviewImageMaxDimension: Int {
        switch renderRuntimePreset {
        case .safe, .balanced:
            return 256
        case .quality:
            return 384
        }
    }

    static var renderCapturePreviewMaxDimension: Int {
        switch renderRuntimePreset {
        case .safe:
            return 1280
        case .balanced:
            return 1536
        case .quality:
            return 2048
        }
    }

    static var renderReferenceImageMaxDimension: Int {
        switch renderRuntimePreset {
        case .safe, .balanced:
            return 256
        case .quality:
            return 384
        }
    }

    static var renderPayloadMaxDimension: Int {
        switch renderRuntimePreset {
        case .safe:
            return 1536
        case .balanced:
            return 1792
        case .quality:
            return 2560
        }
    }

    static var renderUsesForegroundSaliency: Bool {
        switch renderRuntimePreset {
        case .quality:
            return true
        case .safe, .balanced:
            return false
        }
    }

    static var renderPersonSegmentationQuality: CapturePersonSegmentationQuality {
        switch renderRuntimePreset {
        case .quality:
            return .balanced
        case .safe, .balanced:
            return .fast
        }
    }

    static var renderAnalysisOptions: CaptureAnalysisOptions {
        CaptureAnalysisOptions(
            maxDimension: renderMaskMaxDimension,
            personSegmentationQuality: renderPersonSegmentationQuality,
            includeForegroundSaliency: renderUsesForegroundSaliency
        )
    }

    static var renderMaskWorkingMaxDimension: Int? {
        switch renderRuntimePreset {
        case .safe:
            return 1024
        case .balanced:
            return 1536
        case .quality:
            return nil
        }
    }

    static var renderBloomBaseMaxDimension: Int? {
        switch renderRuntimePreset {
        case .safe:
            return 1024
        case .balanced:
            return 1536
        case .quality:
            return nil
        }
    }
}
