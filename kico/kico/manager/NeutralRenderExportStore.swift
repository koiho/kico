import Foundation
import UIKit

struct NeutralRenderExportRecord: Sendable {
    let stem: String
    let directoryURL: URL
    let previewURL: URL
    let payloadURL: URL
    let payloadMetadataURL: URL
    let maskBundleURL: URL
}

enum NeutralRenderExportError: Error {
    case missingRenderPayload
    case previewEncodingFailed
    case payloadMetadataEncodingFailed
}

actor NeutralRenderExportStore {
    private let fileManager = FileManager.default
    private let exportDirectoryName = "NeutralExports"
    private let analyzer = CaptureAnalyzer()

    func collect(
        rawCapture: RawCaptureResult,
        previewMaxDimension: Int?,
        analysisOptions: CaptureAnalysisOptions
    ) throws -> NeutralRenderExportRecord {
        try export(
            rawCapture: rawCapture,
            previewMaxDimension: previewMaxDimension,
            analysisOptions: analysisOptions
        )
    }

    func export(
        rawCapture: RawCaptureResult,
        previewMaxDimension: Int?,
        analysisOptions: CaptureAnalysisOptions
    ) throws -> NeutralRenderExportRecord {
        guard let payload = rawCapture.renderPayload else {
            throw NeutralRenderExportError.missingRenderPayload
        }

        let directoryURL = try ensureExportDirectory()
        let stem = makeStem(for: rawCapture.captureMetadata)
        let captureDirectoryURL = directoryURL.appendingPathComponent(stem, isDirectory: true)

        if !fileManager.fileExists(atPath: captureDirectoryURL.path) {
            try fileManager.createDirectory(at: captureDirectoryURL, withIntermediateDirectories: true)
        }

        let previewURL = captureDirectoryURL.appendingPathComponent("neutral_preview.png", isDirectory: false)
        let payloadURL = captureDirectoryURL.appendingPathComponent("neutral_linear.rgba16f.bin", isDirectory: false)
        let payloadMetadataURL = captureDirectoryURL.appendingPathComponent(
            "neutral_linear.rgba16f.json",
            isDirectory: false
        )
        let maskBundleURL = captureDirectoryURL.appendingPathComponent("mask_bundle.npz", isDirectory: false)
        let normalizedPreview = normalizeOrientation(of: rawCapture.previewImage)
        let exportPreview = resizeForExport(normalizedPreview, maxDimension: previewMaxDimension)

        guard let previewData = exportPreview.pngData() else {
            throw NeutralRenderExportError.previewEncodingFailed
        }
        let payloadMetadata: [String: Any] = [
            "width": payload.width,
            "height": payload.height,
            "bytesPerRow": payload.bytesPerRow,
            "pixelFormat": payload.pixelFormat.rawValue,
            "colorSpaceName": payload.colorSpaceName,
        ]
        guard JSONSerialization.isValidJSONObject(payloadMetadata),
              let payloadMetadataData = try? JSONSerialization.data(
                withJSONObject: payloadMetadata,
                options: [.prettyPrinted, .sortedKeys]
              ) else {
            throw NeutralRenderExportError.payloadMetadataEncodingFailed
        }
        try writeData(previewData, to: previewURL)
        try writeData(payload.pixelData, to: payloadURL)
        try writeData(payloadMetadataData, to: payloadMetadataURL)

        let analysis = try analyzer.analyze(previewImage: exportPreview, options: analysisOptions)
        try NPZArchiveWriter.write(entries: analysis.npzEntries, to: maskBundleURL)

        return NeutralRenderExportRecord(
            stem: stem,
            directoryURL: captureDirectoryURL,
            previewURL: previewURL,
            payloadURL: payloadURL,
            payloadMetadataURL: payloadMetadataURL,
            maskBundleURL: maskBundleURL
        )
    }

    private func ensureExportDirectory() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directoryURL = documentsURL.appendingPathComponent(exportDirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private func writeData(_ data: Data, to url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func normalizeOrientation(of image: UIImage) -> UIImage {
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

    private func resizeForExport(_ image: UIImage, maxDimension: Int?) -> UIImage {
        guard let maxDimension, maxDimension > 0 else {
            return image
        }

        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > CGFloat(maxDimension) else {
            return image
        }

        let scale = CGFloat(maxDimension) / longestEdge
        let targetSize = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func makeStem(for captureMetadata: RawCaptureMetadata) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"

        let lens = sanitizedComponent(captureMetadata.lensID)
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        return "\(formatter.string(from: captureMetadata.capturedAt))_\(lens)_\(suffix)"
    }

    private func sanitizedComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let result = String(scalars)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "capture" : result
    }
}
