import Foundation

enum CaptureWorkflowMode: String {
    case renderTest
    case dataCollection
}

enum CaptureWorkflowConfiguration {
    // Change this value when you want to switch the camera workflow.
    static let mode: CaptureWorkflowMode = .dataCollection
    static let renderRequiresReferenceImage = true
    static let savePreviewFallbackOnRenderFailure = false

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

    // Render-test tuning. The Rust pipeline resizes masks and reference images
    // to model input size, so smaller prep inputs can greatly reduce latency.
    static let renderMaskMaxDimension: Int = 256
    static let renderReferenceImageMaxDimension: Int = 256
    static let renderUsesForegroundSaliency = false
    static let renderPersonSegmentationQuality: CapturePersonSegmentationQuality = .fast

    static let renderAnalysisOptions = CaptureAnalysisOptions(
        maxDimension: 256,
        personSegmentationQuality: .fast,
        includeForegroundSaliency: false
    )
}
