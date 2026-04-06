import CoreImage
import CoreVideo
import Foundation
import UIKit
import Vision

enum CaptureAnalysisError: Error {
    case missingCGImage
    case unableToRasterizePreview
}

enum CapturePersonSegmentationQuality {
    case fast
    case balanced
    case accurate

    @available(iOS 15.0, *)
    var visionQualityLevel: VNGeneratePersonSegmentationRequest.QualityLevel {
        switch self {
        case .fast:
            return .fast
        case .balanced:
            return .balanced
        case .accurate:
            return .accurate
        }
    }
}

struct CaptureAnalysisOptions {
    let maxDimension: Int?
    let personSegmentationQuality: CapturePersonSegmentationQuality
    let includeForegroundSaliency: Bool

    nonisolated(unsafe) static let collectionExport = Self(
        maxDimension: nil,
        personSegmentationQuality: .balanced,
        includeForegroundSaliency: true
    )

    nonisolated(unsafe) static let renderPreview = Self(
        maxDimension: 512,
        personSegmentationQuality: .fast,
        includeForegroundSaliency: false
    )
}

struct CaptureAnalysisResult: Sendable {
    let width: Int
    let height: Int
    let faceMask: [Float]
    let personMask: [Float]
    let highlightMask: [Float]
    let shadowMask: [Float]
    let foregroundSubjectMask: [Float]

    var npzEntries: [NPZArrayEntry] {
        [
            NPZArrayEntry(name: "face.npy", shape: [height, width], values: faceMask),
            NPZArrayEntry(name: "person.npy", shape: [height, width], values: personMask),
            NPZArrayEntry(name: "highlight.npy", shape: [height, width], values: highlightMask),
            NPZArrayEntry(name: "shadow.npy", shape: [height, width], values: shadowMask),
            NPZArrayEntry(
                name: "foreground_subject.npy",
                shape: [height, width],
                values: foregroundSubjectMask
            )
        ]
    }
}

struct CaptureAnalyzer {
    nonisolated init() {}

    nonisolated func analyze(
        previewImage: UIImage,
        options: CaptureAnalysisOptions = .collectionExport
    ) throws -> CaptureAnalysisResult {
        guard let sourceCGImage = previewImage.cgImage else {
            throw CaptureAnalysisError.missingCGImage
        }

        let cgImage = try makeAnalysisImage(from: sourceCGImage, maxDimension: options.maxDimension)
        let raster = try rasterize(cgImage)
        let faceMask = detectFaceMask(in: cgImage, width: raster.width, height: raster.height)
        let personMask = detectPersonMask(
            in: cgImage,
            width: raster.width,
            height: raster.height,
            quality: options.personSegmentationQuality
        )
        let foregroundMask = detectForegroundMask(
            in: cgImage,
            width: raster.width,
            height: raster.height,
            personMask: personMask,
            faceMask: faceMask,
            includeSaliency: options.includeForegroundSaliency
        )
        let luma = makeLumaValues(from: raster.rgba)
        let highlightMask = makeHighlightMask(from: luma)
        let shadowMask = makeShadowMask(from: luma)

        return CaptureAnalysisResult(
            width: raster.width,
            height: raster.height,
            faceMask: faceMask,
            personMask: personMask,
            highlightMask: highlightMask,
            shadowMask: shadowMask,
            foregroundSubjectMask: foregroundMask
        )
    }

    private nonisolated func makeAnalysisImage(from cgImage: CGImage, maxDimension: Int?) throws -> CGImage {
        guard let maxDimension, maxDimension > 0 else {
            return cgImage
        }

        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        let longestEdge = max(sourceWidth, sourceHeight)
        guard longestEdge > maxDimension else {
            return cgImage
        }

        let scale = CGFloat(maxDimension) / CGFloat(longestEdge)
        let targetWidth = max(1, Int((CGFloat(sourceWidth) * scale).rounded()))
        let targetHeight = max(1, Int((CGFloat(sourceHeight) * scale).rounded()))
        let bytesPerRow = targetWidth * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw CaptureAnalysisError.unableToRasterizePreview
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let resized = context.makeImage() else {
            throw CaptureAnalysisError.unableToRasterizePreview
        }

        return resized
    }

    private nonisolated func rasterize(_ cgImage: CGImage) throws -> RasterImage {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw CaptureAnalysisError.unableToRasterizePreview
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RasterImage(width: width, height: height, rgba: rgba)
    }

    private nonisolated func detectFaceMask(in cgImage: CGImage, width: Int, height: Int) -> [Float] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return [Float](repeating: 0, count: width * height)
        }

        let observations = request.results ?? []
        guard !observations.isEmpty else {
            return [Float](repeating: 0, count: width * height)
        }

        var mask = [Float](repeating: 0, count: width * height)
        for observation in observations {
            let rect = observation.boundingBox
            let minX = max(0, Int(floor(rect.minX * CGFloat(width))))
            let maxX = min(width, Int(ceil(rect.maxX * CGFloat(width))))
            let minY = max(0, Int(floor((1.0 - rect.maxY) * CGFloat(height))))
            let maxY = min(height, Int(ceil((1.0 - rect.minY) * CGFloat(height))))

            guard minX < maxX, minY < maxY else { continue }
            for y in minY..<maxY {
                let rowOffset = y * width
                for x in minX..<maxX {
                    mask[rowOffset + x] = 1.0
                }
            }
        }
        return mask
    }

    private nonisolated func detectPersonMask(
        in cgImage: CGImage,
        width: Int,
        height: Int,
        quality: CapturePersonSegmentationQuality
    ) -> [Float] {
        guard #available(iOS 15.0, *) else {
            return [Float](repeating: 0, count: width * height)
        }

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality.visionQualityLevel
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNPixelBufferObservation else {
                return [Float](repeating: 0, count: width * height)
            }
            return resizePixelBufferMask(observation.pixelBuffer, targetWidth: width, targetHeight: height)
        } catch {
            return [Float](repeating: 0, count: width * height)
        }
    }

    private nonisolated func detectForegroundMask(
        in cgImage: CGImage,
        width: Int,
        height: Int,
        personMask: [Float],
        faceMask: [Float],
        includeSaliency: Bool
    ) -> [Float] {
        let fallback = mergeMasks(personMask, faceMask)
        guard includeSaliency else {
            return fallback
        }

        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNSaliencyImageObservation else {
                return fallback
            }
            let saliency = resizePixelBufferMask(
                observation.pixelBuffer,
                targetWidth: width,
                targetHeight: height
            )
            return mergeMasks(saliency, fallback)
        } catch {
            return fallback
        }
    }

    private nonisolated func resizePixelBufferMask(
        _ pixelBuffer: CVPixelBuffer,
        targetWidth: Int,
        targetHeight: Int
    ) -> [Float] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return [Float](repeating: 0, count: targetWidth * targetHeight)
        }

        var output = [Float](repeating: 0, count: targetWidth * targetHeight)
        let scaleX = sourceWidth > 1 ? Float(sourceWidth - 1) / Float(max(targetWidth - 1, 1)) : 0
        let scaleY = sourceHeight > 1 ? Float(sourceHeight - 1) / Float(max(targetHeight - 1, 1)) : 0

        for y in 0..<targetHeight {
            let sy = Float(y) * scaleY
            let y0 = Int(floor(sy))
            let y1 = min(y0 + 1, sourceHeight - 1)
            let wy = sy - Float(y0)

            for x in 0..<targetWidth {
                let sx = Float(x) * scaleX
                let x0 = Int(floor(sx))
                let x1 = min(x0 + 1, sourceWidth - 1)
                let wx = sx - Float(x0)

                let top = lerp(
                    sampleScalar(pixelBuffer, x: x0, y: y0),
                    sampleScalar(pixelBuffer, x: x1, y: y0),
                    t: wx
                )
                let bottom = lerp(
                    sampleScalar(pixelBuffer, x: x0, y: y1),
                    sampleScalar(pixelBuffer, x: x1, y: y1),
                    t: wx
                )
                output[y * targetWidth + x] = clamp(lerp(top, bottom, t: wy))
            }
        }

        return output
    }

    private nonisolated func sampleScalar(_ pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> Float {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isPlanar = CVPixelBufferIsPlanar(pixelBuffer)
        let plane = isPlanar ? 0 : -1

        let width = plane >= 0 ? CVPixelBufferGetWidthOfPlane(pixelBuffer, plane) : CVPixelBufferGetWidth(pixelBuffer)
        let height = plane >= 0 ? CVPixelBufferGetHeightOfPlane(pixelBuffer, plane) : CVPixelBufferGetHeight(pixelBuffer)
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }

        let bytesPerRow = plane >= 0 ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane) : CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = plane >= 0
            ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane)
            : CVPixelBufferGetBaseAddress(pixelBuffer)

        guard let baseAddress else { return 0 }

        switch format {
        case kCVPixelFormatType_OneComponent8:
            let row = baseAddress.advanced(by: y * bytesPerRow)
            let value = row.load(fromByteOffset: x, as: UInt8.self)
            return Float(value) / 255.0

        case kCVPixelFormatType_OneComponent16Half:
            let row = baseAddress.advanced(by: y * bytesPerRow)
            let bitPattern = row.load(fromByteOffset: x * MemoryLayout<UInt16>.stride, as: UInt16.self)
            return clamp(Float(Float16(bitPattern: bitPattern)))

        case kCVPixelFormatType_OneComponent32Float:
            let row = baseAddress.advanced(by: y * bytesPerRow)
            return clamp(row.load(fromByteOffset: x * MemoryLayout<Float>.stride, as: Float.self))

        case kCVPixelFormatType_32BGRA:
            let row = baseAddress.advanced(by: y * bytesPerRow)
            let offset = x * 4
            let b = Float(row.load(fromByteOffset: offset, as: UInt8.self)) / 255.0
            let g = Float(row.load(fromByteOffset: offset + 1, as: UInt8.self)) / 255.0
            let r = Float(row.load(fromByteOffset: offset + 2, as: UInt8.self)) / 255.0
            return 0.2126 * r + 0.7152 * g + 0.0722 * b

        default:
            return 0
        }
    }

    private nonisolated func makeLumaValues(from rgba: [UInt8]) -> [Float] {
        stride(from: 0, to: rgba.count, by: 4).map { offset in
            let r = Float(rgba[offset]) / 255.0
            let g = Float(rgba[offset + 1]) / 255.0
            let b = Float(rgba[offset + 2]) / 255.0
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
    }

    private nonisolated func makeHighlightMask(from luma: [Float]) -> [Float] {
        let threshold = percentile(values: luma, q: 0.86)
        return luma.map { value in
            smoothstep(edge0: threshold - 0.08, edge1: threshold + 0.02, x: value)
        }
    }

    private nonisolated func makeShadowMask(from luma: [Float]) -> [Float] {
        let threshold = percentile(values: luma, q: 0.22)
        return luma.map { value in
            1.0 - smoothstep(edge0: threshold - 0.02, edge1: threshold + 0.08, x: value)
        }
    }

    private nonisolated func mergeMasks(_ lhs: [Float], _ rhs: [Float]) -> [Float] {
        guard lhs.count == rhs.count else { return lhs }
        return zip(lhs, rhs).map { max($0, $1) }
    }

    private nonisolated func percentile(values: [Float], q: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(
            sorted.count - 1,
            max(0, Int((Float(sorted.count - 1) * q).rounded()))
        )
        return sorted[index]
    }

    private nonisolated func clamp(_ value: Float, low: Float = 0, high: Float = 1) -> Float {
        min(max(value, low), high)
    }

    private nonisolated func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = clamp((x - edge0) / max(edge1 - edge0, 1e-6))
        return t * t * (3 - 2 * t)
    }

    private nonisolated func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }
}

private struct RasterImage {
    let width: Int
    let height: Int
    let rgba: [UInt8]
}
