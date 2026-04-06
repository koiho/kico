import UIKit
import AVFoundation

enum FlashMode: String, CaseIterable {
    case off = "bolt.slash.fill"
    case on = "bolt.fill"

    var systemName: String {
        return rawValue
    }
}

struct CameraState {
    var selectedZoomFactor: CGFloat = 1.0
    var supportedZoomFactors: [CGFloat] = [1.0]
    var isUltraWide: Bool = false
    var displayZoomFactor: CGFloat = 1.0
    var lastPhotoThumbnail: UIImage? = nil
    var photoCount: Int = 0
    var photos: [PhotoItem] = []

    var isRawSupported = false
    var rawStatusMessage: String = "RAW: checking..."
    var rawProcessingPlan: RawProcessingPlan = .identity
    var isSessionReady = false
    var isCapturing = false
    var isSwitchingCamera = false

    var exposureEV: Float = 0
    var exposureMinEV: Float = 0
    var exposureMaxEV: Float = 0

    var focusPointInPreview: CGPoint?
    var flashMode: FlashMode = .off
}
