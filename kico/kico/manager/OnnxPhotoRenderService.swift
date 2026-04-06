import CoreImage
import Foundation
import UIKit

enum OnnxPhotoRenderServiceError: Error {
    case missingRenderPayload
    case missingReferenceImage
    case modelAssetNotFound(String)
    case invalidReferenceImage
    case invalidFinalImageBuffer
    case unsupportedFinalImageFormat(FfiRenderBufferFormat)
}

extension OnnxPhotoRenderServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingRenderPayload:
            return "缺少 RAW 渲染载荷"
        case .missingReferenceImage:
            return "未选择参考图"
        case .modelAssetNotFound(let path):
            return "未找到模型资源：\(path)"
        case .invalidReferenceImage:
            return "参考图无法解码"
        case .invalidFinalImageBuffer:
            return "渲染输出图像无效"
        case .unsupportedFinalImageFormat(let format):
            return "不支持的渲染输出格式：\(format)"
        }
    }
}

struct PreparedPhotoRenderJob: Sendable {
    let request: FfiOnnxRenderRequest
    let usedSelfReference: Bool
}

enum OnnxPhotoRenderJobBuilder {
    nonisolated(unsafe) private static let displayColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB)!
    nonisolated(unsafe) private static let displayDecodeContext = CIContext(
        options: [.workingColorSpace: displayColorSpace]
    )

    nonisolated static func prepare(
        referenceImage: UIImage?,
        rawCapture: RawCaptureResult,
        analysisOptions: CaptureAnalysisOptions = .collectionExport,
        previewImageMaxDimension: Int? = nil,
        referenceImageMaxDimension: Int? = nil,
        renderRuntimeOptions: FfiRenderRuntimeOptions,
        requiresReferenceImage: Bool = false
    ) throws -> PreparedPhotoRenderJob {
        guard let renderPayload = rawCapture.renderPayload else {
            throw OnnxPhotoRenderServiceError.missingRenderPayload
        }

        if requiresReferenceImage, referenceImage == nil {
            throw OnnxPhotoRenderServiceError.missingReferenceImage
        }

        let normalizedPreview = normalizeOrientation(of: rawCapture.previewImage)
        let effectivePreviewImage = downscaleIfNeeded(
            normalizedPreview,
            maxDimension: previewImageMaxDimension
        )
        let normalizedReferenceImage = referenceImage.map(normalizeOrientation)
        let effectiveReferenceImage = downscaleIfNeeded(
            normalizedReferenceImage ?? effectivePreviewImage,
            maxDimension: referenceImageMaxDimension
        )
        let usedSelfReference = referenceImage == nil

        let analysis = try CaptureAnalyzer().analyze(
            previewImage: effectivePreviewImage,
            options: analysisOptions
        )
        let request = FfiOnnxRenderRequest(
            referenceImage: try makeRGBA8Buffer(from: effectiveReferenceImage),
            neutralPreviewImage: try makeRGBA8Buffer(from: effectivePreviewImage),
            neutralImage: makeRGBA16Buffer(from: renderPayload),
            faceMask: makeMaskBuffer(values: analysis.faceMask, width: analysis.width, height: analysis.height),
            personMask: makeMaskBuffer(values: analysis.personMask, width: analysis.width, height: analysis.height),
            highlightMask: makeMaskBuffer(values: analysis.highlightMask, width: analysis.width, height: analysis.height),
            shadowMask: makeMaskBuffer(values: analysis.shadowMask, width: analysis.width, height: analysis.height),
            foregroundSubjectMask: makeMaskBuffer(
                values: analysis.foregroundSubjectMask,
                width: analysis.width,
                height: analysis.height
            ),
            renderRuntimeOptions: renderRuntimeOptions
        )

        return PreparedPhotoRenderJob(request: request, usedSelfReference: usedSelfReference)
    }

    nonisolated static func makeDisplayImage(from buffer: FfiRenderBuffer) throws -> UIImage {
        if buffer.format == .rgba16Float {
            return try makeToneMappedDisplayImage(from: buffer)
        }
        guard buffer.format == .rgba8Unorm else {
            throw OnnxPhotoRenderServiceError.unsupportedFinalImageFormat(buffer.format)
        }

        let size = CGSize(width: Int(buffer.width), height: Int(buffer.height))
        let extent = CGRect(origin: .zero, size: size)

        let ciImage = CIImage(
            bitmapData: buffer.data,
            bytesPerRow: Int(buffer.bytesPerRow),
            size: size,
            format: .RGBA8,
            colorSpace: displayColorSpace
        )
        guard let cgImage = displayDecodeContext.createCGImage(
            ciImage,
            from: extent,
            format: .RGBA8,
            colorSpace: displayColorSpace
        ) else {
            throw OnnxPhotoRenderServiceError.invalidFinalImageBuffer
        }

        return UIImage(cgImage: cgImage)
    }

    // Apply the display transfer function explicitly before quantizing the
    // renderer's linear RGBA16F output into an 8-bit delivery image.
    private nonisolated static func makeToneMappedDisplayImage(from buffer: FfiRenderBuffer) throws -> UIImage {
        let width = Int(buffer.width)
        let height = Int(buffer.height)
        let bytesPerRow = Int(buffer.bytesPerRow)
        let outputBytesPerRow = width * 4
        let colorSpace = displayColorSpace
        var output = Data(count: height * outputBytesPerRow)

        let rendered = output.withUnsafeMutableBytes { destinationBuffer -> Bool in
            guard let destination = destinationBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }

            return buffer.data.withUnsafeBytes { sourceBuffer in
                guard let source = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return false
                }

                for y in 0..<height {
                    let sourceRow = y * bytesPerRow
                    let destinationRow = y * outputBytesPerRow

                    for x in 0..<width {
                        let sourceOffset = sourceRow + (x * 8)
                        let destinationOffset = destinationRow + (x * 4)

                        let r = decodeFloat16(source, at: sourceOffset)
                        let g = decodeFloat16(source, at: sourceOffset + 2)
                        let b = decodeFloat16(source, at: sourceOffset + 4)
                        let a = decodeFloat16(source, at: sourceOffset + 6)

                        destination[destinationOffset] = displayEncodedU8(r)
                        destination[destinationOffset + 1] = displayEncodedU8(g)
                        destination[destinationOffset + 2] = displayEncodedU8(b)
                        destination[destinationOffset + 3] = UInt8(clamping: Int((clamp01(a) * 255).rounded()))
                    }
                }

                return true
            }
        }

        guard rendered else {
            throw OnnxPhotoRenderServiceError.invalidFinalImageBuffer
        }

        guard let provider = CGDataProvider(data: output as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outputBytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    .union(.byteOrder32Big),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw OnnxPhotoRenderServiceError.invalidFinalImageBuffer
        }

        return UIImage(cgImage: cgImage)
    }

    private nonisolated static func makeRGBA8Buffer(from image: UIImage) throws -> FfiRenderBuffer {
        guard let cgImage = image.cgImage else {
            throw OnnxPhotoRenderServiceError.invalidReferenceImage
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var data = Data(count: height * bytesPerRow)
        let colorSpace = displayColorSpace

        let rendered = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard rendered else {
            throw OnnxPhotoRenderServiceError.invalidReferenceImage
        }

        return FfiRenderBuffer(
            width: UInt32(width),
            height: UInt32(height),
            bytesPerRow: UInt32(bytesPerRow),
            format: .rgba8Unorm,
            data: data
        )
    }

    private nonisolated static func makeRGBA16Buffer(from payload: RawRenderPayload) -> FfiRenderBuffer {
        FfiRenderBuffer(
            width: UInt32(payload.width),
            height: UInt32(payload.height),
            bytesPerRow: UInt32(payload.bytesPerRow),
            format: .rgba16Float,
            data: payload.pixelData
        )
    }

    private nonisolated static func makeMaskBuffer(values: [Float], width: Int, height: Int) -> FfiRenderBuffer {
        let data = Data(values.map { UInt8(clamping: Int(($0.clamped(to: 0...1)) * 255.0)) })
        return FfiRenderBuffer(
            width: UInt32(width),
            height: UInt32(height),
            bytesPerRow: UInt32(width),
            format: .r8Unorm,
            data: data
        )
    }

    private nonisolated static func downscaleIfNeeded(_ image: UIImage, maxDimension: Int?) -> UIImage {
        guard let maxDimension, maxDimension > 0 else {
            return image
        }

        let imageWidth = image.size.width
        let imageHeight = image.size.height
        let longestEdge = max(imageWidth, imageHeight)
        guard longestEdge > CGFloat(maxDimension) else {
            return image
        }

        let scale = CGFloat(maxDimension) / longestEdge
        let targetSize = CGSize(
            width: max(1, (imageWidth * scale).rounded()),
            height: max(1, (imageHeight * scale).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private nonisolated static func normalizeOrientation(of image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private nonisolated static func u8(_ value: Float) -> UInt8 {
        UInt8(clamping: Int((clamp01(value) * 255).rounded()))
    }

    private nonisolated static func displayEncodedU8(_ linearValue: Float) -> UInt8 {
        u8(encodeDisplayTransfer(clamp01(linearValue)))
    }

    private nonisolated static func encodeDisplayTransfer(_ linearValue: Float) -> Float {
        if linearValue <= 0.003_130_8 {
            return linearValue * 12.92
        }
        return (1.055 * pow(linearValue, 1 / 2.4)) - 0.055
    }

    private nonisolated static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    private nonisolated static func decodeFloat16(_ bytes: UnsafePointer<UInt8>, at offset: Int) -> Float {
        let bits = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        return Float(Float16(bitPattern: bits))
    }
}

actor OnnxPhotoRenderService {
    private var pipeline: OnnxRenderPipeline?

    func render(request: FfiOnnxRenderRequest) throws -> FfiOnnxRenderResponse {
        let pipeline = try resolvePipeline()
        return try pipeline.render(request: request)
    }

    private func resolvePipeline() throws -> OnnxRenderPipeline {
        if let pipeline {
            return pipeline
        }

        let modelURL = try resolveModelURL(
            resourceName: "style_param_net",
            extensionName: "onnx"
        )
        let metadataURL = try resolveModelURL(
            resourceName: "style_param_net",
            extensionName: "json"
        )
        let pipeline = try OnnxRenderPipeline(
            modelPath: modelURL.path,
            metadataPath: metadataURL.path
        )
        self.pipeline = pipeline
        return pipeline
    }

    private func resolveModelURL(resourceName: String, extensionName: String) throws -> URL {
        if let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: extensionName,
            subdirectory: "resource/model"
        ) {
            return url
        }

        if let url = Bundle.main.url(forResource: resourceName, withExtension: extensionName) {
            return url
        }

        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("resource/model/\(resourceName).\(extensionName)"),
            Bundle.main.bundleURL.appendingPathComponent("resource/model/\(resourceName).\(extensionName)")
        ]

        for candidate in candidates.compactMap({ $0 }) where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        throw OnnxPhotoRenderServiceError.modelAssetNotFound("\(resourceName).\(extensionName)")
    }
}

private struct InferenceDebugModelMetadata: Decodable {
    let parameterNames: [String]
    let gateNames: [String]

    private enum CodingKeys: String, CodingKey {
        case parameterNames = "parameter_names"
        case gateNames = "gate_names"
    }
}

enum InferenceDebugConsole {
    nonisolated(unsafe) private static let cachedMetadata: InferenceDebugModelMetadata? = loadMetadata()

    nonisolated static func logRenderStart(usedSelfReference: Bool) {
        NSLog("[InferenceDebug] render start usedSelfReference=%@", usedSelfReference ? "true" : "false")
    }

    nonisolated static func log(response: FfiOnnxRenderResponse, usedSelfReference: Bool) {
        let parameterNames = names(
            from: cachedMetadata?.parameterNames,
            fallbackPrefix: "param",
            count: response.normalizedParams.count
        )
        let gateNames = names(
            from: cachedMetadata?.gateNames,
            fallbackPrefix: "gate",
            count: response.gateValues.count
        )

        let parameterMap = Dictionary(uniqueKeysWithValues: zip(parameterNames, response.normalizedParams.map(Double.init)))
        let gateMap = Dictionary(uniqueKeysWithValues: zip(gateNames, response.gateValues.map(Double.init)))

        let payload: [String: Any] = [
            "used_self_reference": usedSelfReference,
            "final_image": [
                "width": Int(response.finalImage.width),
                "height": Int(response.finalImage.height),
                "format": String(describing: response.finalImage.format)
            ],
            "summary": [
                "parameter_count": response.normalizedParams.count,
                "parameter_min": response.normalizedParams.min().map(Double.init) as Any,
                "parameter_max": response.normalizedParams.max().map(Double.init) as Any,
                "gate_count": response.gateValues.count,
                "gate_min": response.gateValues.min().map(Double.init) as Any,
                "gate_max": response.gateValues.max().map(Double.init) as Any
            ],
            "gate_values": gateMap,
            "normalized_params": parameterMap
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            NSLog("[InferenceDebug] failed to encode payload")
            return
        }

        NSLog("[InferenceDebug] begin")
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            NSLog("[InferenceDebug] %@", String(line))
        }
        NSLog("[InferenceDebug] end")
    }

    nonisolated static func logRenderFailure(_ error: Error) {
        NSLog("[InferenceDebug] render failure %@", error.localizedDescription)
    }

    private nonisolated static func names(
        from source: [String]?,
        fallbackPrefix: String,
        count: Int
    ) -> [String] {
        guard let source, source.count == count else {
            return (0..<count).map { "\(fallbackPrefix)_\($0)" }
        }
        return source
    }

    private nonisolated static func loadMetadata() -> InferenceDebugModelMetadata? {
        guard let url = Bundle.main.url(
            forResource: "style_param_net",
            withExtension: "json",
            subdirectory: "resource/model"
        ) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(InferenceDebugModelMetadata.self, from: data)
    }
}

private extension Float {
    nonisolated func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
