import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

enum RawRenderPixelFormat: String, Sendable {
    case rgba16Half
}

struct RawRenderPayload: Sendable {
    let pixelData: Data
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixelFormat: RawRenderPixelFormat
    let colorSpaceName: String
}

struct RawProcessedFrame {
    let previewImage: UIImage
    let renderPayload: RawRenderPayload?
}

enum CoreImageBaseAdjustment: Sendable {
    case whiteBalance(temperature: Float, tint: Float)
    case exposure(ev: Float)
    case highlightShadow(highlight: Float, shadow: Float)
    case toneCurve(black: Float, shadow: Float, mid: Float, highlight: Float, white: Float)
    case vibrance(amount: Float)
    case noiseReduction(noiseLevel: Float, sharpness: Float)
    case detail(sharpness: Float)

    var stage: CoreImageBaseStage {
        switch self {
        case .whiteBalance:
            return .whiteBalance
        case .exposure:
            return .exposure
        case .highlightShadow:
            return .highlightShadow
        case .toneCurve:
            return .toneCurve
        case .vibrance:
            return .vibrance
        case .noiseReduction:
            return .noiseReduction
        case .detail:
            return .detail
        }
    }
}

enum CoreImageBaseStage: Int, Sendable {
    case whiteBalance
    case exposure
    case highlightShadow
    case toneCurve
    case vibrance
    case noiseReduction
    case detail
}

struct CoreImageBaseAdjustmentStep: Sendable {
    let adjustment: CoreImageBaseAdjustment
    let sort: Int

    init(_ adjustment: CoreImageBaseAdjustment, sort: Int = 0) {
        self.adjustment = adjustment
        self.sort = sort
    }

    var stage: CoreImageBaseStage {
        adjustment.stage
    }
}

struct RawProcessingPlan: Sendable {
    var coreImageBaseAdjustments: [CoreImageBaseAdjustmentStep] = []

    static let identity = RawProcessingPlan()
}

enum RawPhotoProcessingError: Error {
    case invalidRawData
    case rawFilterCreationFailed
    case outputImageMissing
    case previewImageCreationFailed
}

final class RawPhotoProcessor: @unchecked Sendable {
    private let ciContext: CIContext
    private let workingColorSpace =
        CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let previewColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB)!

    nonisolated init() {
        self.ciContext = CIContext(
            options: [
                .workingColorSpace: workingColorSpace,
                .workingFormat: CIFormat.RGBAh
            ]
        )
    }

    func process(rawPhotoData: Data,
                 plan: RawProcessingPlan = .identity,
                 includeRenderPayload: Bool = false) throws -> RawProcessedFrame {
        guard !rawPhotoData.isEmpty else {
            throw RawPhotoProcessingError.invalidRawData
        }

        guard let rawFilter = CIRAWFilter(imageData: rawPhotoData) else {
            throw RawPhotoProcessingError.rawFilterCreationFailed
        }

        // Neutralize the default presentation bias so downstream base adjustments
        // and LUT application start from a stable RAW baseline.
        neutralizeDefaultPresentationBias(of: rawFilter)

        // Note: isGamutMappingEnabled is not available on all iOS versions
        // rawFilter.isGamutMappingEnabled = false

        guard let outputImage = rawFilter.outputImage else {
            throw RawPhotoProcessingError.outputImageMissing
        }

        let baseAdjustedImage = applyBaseAdjustments(
            to: outputImage,
            adjustments: plan.coreImageBaseAdjustments
        )

        let width = Int(baseAdjustedImage.extent.width)
        let height = Int(baseAdjustedImage.extent.height)
        let renderPayload = includeRenderPayload
            ? try makeRenderPayload(from: baseAdjustedImage, width: width, height: height)
            : nil
        guard let previewCGImage = ciContext.createCGImage(
            baseAdjustedImage,
            from: baseAdjustedImage.extent,
            format: .RGBA8,
            colorSpace: previewColorSpace
        ) else {
            throw RawPhotoProcessingError.previewImageCreationFailed
        }

        return RawProcessedFrame(
            previewImage: UIImage(cgImage: previewCGImage),
            renderPayload: renderPayload
        )
    }

    private func makeRenderPayload(from image: CIImage,
                                   width: Int,
                                   height: Int) throws -> RawRenderPayload {
        let bytesPerPixel = MemoryLayout<UInt16>.stride * 4
        let bytesPerRow = width * bytesPerPixel
        let byteCount = bytesPerRow * height
        var pixelData = Data(count: byteCount)

        pixelData.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            ciContext.render(
                image,
                toBitmap: baseAddress,
                rowBytes: bytesPerRow,
                bounds: image.extent,
                format: .RGBAh,
                colorSpace: workingColorSpace
            )
        }

        return RawRenderPayload(
            pixelData: pixelData,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            pixelFormat: .rgba16Half,
            colorSpaceName: (workingColorSpace.name as String?) ?? "linearSRGB"
        )
    }

    private func neutralizeDefaultPresentationBias(of rawFilter: CIRAWFilter) {
        setRawFilterValue(
            0,
            propertyKey: "baselineExposure",
            selectorName: "setBaselineExposure:",
            legacyInputKey: CIRAWFilterOption.baselineExposure.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "shadowBias",
            selectorName: "setShadowBias:",
            legacyInputKey: "inputShadowBias",
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "boostAmount",
            selectorName: "setBoostAmount:",
            legacyInputKey: CIRAWFilterOption.boostAmount.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "localToneMapAmount",
            selectorName: "setLocalToneMapAmount:",
            legacyInputKey: CIRAWFilterOption.ciInputLocalToneMapAmountKey.rawValue,
            on: rawFilter
        )
        setRawFilterBoolValue(
            false,
            propertyKey: "highlightRecoveryEnabled",
            selectorName: "setHighlightRecoveryEnabled:",
            on: rawFilter
        )
        setRawFilterBoolValue(
            false,
            propertyKey: "lensCorrectionEnabled",
            selectorName: "setLensCorrectionEnabled:",
            legacyInputKey: CIRAWFilterOption.enableVendorLensCorrection.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "luminanceNoiseReductionAmount",
            selectorName: "setLuminanceNoiseReductionAmount:",
            legacyInputKey: CIRAWFilterOption.luminanceNoiseReductionAmount.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "colorNoiseReductionAmount",
            selectorName: "setColorNoiseReductionAmount:",
            legacyInputKey: CIRAWFilterOption.colorNoiseReductionAmount.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "sharpnessAmount",
            selectorName: "setSharpnessAmount:",
            legacyInputKey: CIRAWFilterOption.noiseReductionSharpnessAmount.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "contrastAmount",
            selectorName: "setContrastAmount:",
            legacyInputKey: CIRAWFilterOption.noiseReductionContrastAmount.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "detailAmount",
            selectorName: "setDetailAmount:",
            legacyInputKey: CIRAWFilterOption.noiseReductionDetailAmount.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "moireReductionAmount",
            selectorName: "setMoireReductionAmount:",
            legacyInputKey: CIRAWFilterOption.moireAmount.rawValue,
            on: rawFilter
        )
        setRawFilterValue(
            0,
            propertyKey: "noiseReductionAmount",
            selectorName: "setNoiseReductionAmount:",
            legacyInputKey: CIRAWFilterOption.noiseReductionAmount.rawValue,
            on: rawFilter
        )
        setRawFilterBoolValue(
            false,
            propertyKey: "enableSharpening",
            selectorName: "setEnableSharpening:",
            legacyInputKey: CIRAWFilterOption.enableSharpening.rawValue,
            on: rawFilter
        )
        setRawFilterBoolValue(
            false,
            propertyKey: "enableChromaticNoiseTracking",
            selectorName: "setEnableChromaticNoiseTracking:",
            legacyInputKey: CIRAWFilterOption.enableChromaticNoiseTracking.rawValue,
            on: rawFilter
        )
        setRawFilterBoolValue(
            false,
            propertyKey: "gamutMappingEnabled",
            selectorName: "setGamutMappingEnabled:",
            legacyInputKey: CIRAWFilterOption.disableGamutMap.rawValue,
            legacyValueTransform: { !$0 },
            on: rawFilter
        )
    }

    private func setRawFilterValue(_ value: Float,
                                   propertyKey: String,
                                   selectorName: String,
                                   legacyInputKey: String? = nil,
                                   on rawFilter: CIRAWFilter) {
        let number = NSNumber(value: value)
        let selector = NSSelectorFromString(selectorName)

        if rawFilter.responds(to: selector) {
            rawFilter.setValue(number, forKey: propertyKey)
            return
        }

        guard let legacyInputKey,
              rawFilter.inputKeys.contains(legacyInputKey) else {
            return
        }

        rawFilter.setValue(number, forKey: legacyInputKey)
    }

    private func setRawFilterBoolValue(_ value: Bool,
                                       propertyKey: String,
                                       selectorName: String,
                                       legacyInputKey: String? = nil,
                                       legacyValueTransform: ((Bool) -> Bool)? = nil,
                                       on rawFilter: CIRAWFilter) {
        let number = NSNumber(value: value)
        let selector = NSSelectorFromString(selectorName)

        if rawFilter.responds(to: selector) {
            rawFilter.setValue(number, forKey: propertyKey)
            return
        }

        guard let legacyInputKey,
              rawFilter.inputKeys.contains(legacyInputKey) else {
            return
        }

        let legacyValue = legacyValueTransform?(value) ?? value
        rawFilter.setValue(NSNumber(value: legacyValue), forKey: legacyInputKey)
    }

    private func applyBaseAdjustments(to image: CIImage,
                                      adjustments: [CoreImageBaseAdjustmentStep]) -> CIImage {
        var result = image

        let orderedAdjustments = adjustments.sorted {
            if $0.stage.rawValue == $1.stage.rawValue {
                return $0.sort < $1.sort
            }
            return $0.stage.rawValue < $1.stage.rawValue
        }

        for step in orderedAdjustments {
            switch step.adjustment {
            case .whiteBalance(let temperature, let tint):
                let neutral = CIVector(x: 6500, y: 0)
                let target = CIVector(
                    x: CGFloat(6500 + temperature),
                    y: CGFloat(tint)
                )
                result = result.applyingFilter(
                    "CITemperatureAndTint",
                    parameters: [
                        "inputNeutral": neutral,
                        "inputTargetNeutral": target
                    ]
                )
            case .exposure(let ev):
                result = result.applyingFilter(
                    "CIExposureAdjust",
                    parameters: [kCIInputEVKey: ev]
                )
            case .highlightShadow(let highlight, let shadow):
                result = result.applyingFilter(
                    "CIHighlightShadowAdjust",
                    parameters: [
                        "inputHighlightAmount": highlight,
                        "inputShadowAmount": shadow
                    ]
                )
            case .toneCurve(let black, let shadow, let mid, let highlight, let white):
                result = result.applyingFilter(
                    "CIToneCurve",
                    parameters: [
                        "inputPoint0": CIVector(x: 0, y: clampedUnit(black)),
                        "inputPoint1": CIVector(x: 0.25, y: clampedUnit(shadow)),
                        "inputPoint2": CIVector(x: 0.5, y: clampedUnit(mid)),
                        "inputPoint3": CIVector(x: 0.75, y: clampedUnit(highlight)),
                        "inputPoint4": CIVector(x: 1, y: clampedUnit(white))
                    ]
                )
            case .vibrance(let amount):
                result = result.applyingFilter(
                    "CIVibrance",
                    parameters: ["inputAmount": amount]
                )
            case .noiseReduction(let noiseLevel, let sharpness):
                result = result.applyingFilter(
                    "CINoiseReduction",
                    parameters: [
                        "inputNoiseLevel": noiseLevel,
                        "inputSharpness": sharpness
                    ]
                )
            case .detail(let sharpness):
                result = result.applyingFilter(
                    "CISharpenLuminance",
                    parameters: ["inputSharpness": sharpness]
                )
            }
        }

        return result
    }

    private func clampedUnit(_ value: Float) -> CGFloat {
        CGFloat(max(0, min(1, value)))
    }
}
