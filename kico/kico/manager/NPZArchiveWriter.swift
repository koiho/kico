import Foundation

struct NPZArrayEntry: Sendable {
    let name: String
    let shape: [Int]
    let values: [Float]
}

enum NPZArchiveWriter {
    static func write(entries: [NPZArrayEntry], to url: URL) throws {
        let preparedEntries = try entries.map { entry in
            let fileNameData = Data(entry.name.utf8)
            let payload = try makeNPYData(shape: entry.shape, values: entry.values)
            return PreparedEntry(
                fileNameData: fileNameData,
                payload: payload,
                crc: crc32(payload)
            )
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let handle = try FileHandle(forWritingTo: url)
        var currentOffset: UInt32 = 0
        var centralDirectory = Data()

        do {
            for (index, entry) in entries.enumerated() {
                let prepared = preparedEntries[index]
                let localOffset = currentOffset
                let localHeader = makeLocalFileHeader(
                    crc: prepared.crc,
                    payloadSize: prepared.payload.count,
                    fileNameSize: prepared.fileNameData.count
                )
                try handle.write(contentsOf: localHeader)
                try handle.write(contentsOf: prepared.fileNameData)
                try handle.write(contentsOf: prepared.payload)

                currentOffset += UInt32(localHeader.count + prepared.fileNameData.count + prepared.payload.count)

                centralDirectory.append(
                    makeCentralDirectoryEntry(
                        crc: prepared.crc,
                        payloadSize: prepared.payload.count,
                        fileNameSize: prepared.fileNameData.count,
                        localOffset: localOffset
                    )
                )
                centralDirectory.append(prepared.fileNameData)
            }

            let centralDirectoryOffset = currentOffset
            try handle.write(contentsOf: centralDirectory)

            var endOfCentralDirectory = Data()
            endOfCentralDirectory.appendLE(UInt32(0x06054b50))
            endOfCentralDirectory.appendLE(UInt16(0))
            endOfCentralDirectory.appendLE(UInt16(0))
            endOfCentralDirectory.appendLE(UInt16(entries.count))
            endOfCentralDirectory.appendLE(UInt16(entries.count))
            endOfCentralDirectory.appendLE(UInt32(centralDirectory.count))
            endOfCentralDirectory.appendLE(centralDirectoryOffset)
            endOfCentralDirectory.appendLE(UInt16(0))
            try handle.write(contentsOf: endOfCentralDirectory)
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private static func makeLocalFileHeader(
        crc: UInt32,
        payloadSize: Int,
        fileNameSize: Int
    ) -> Data {
        var header = Data()
        header.appendLE(UInt32(0x04034b50))
        header.appendLE(UInt16(20))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(crc)
        header.appendLE(UInt32(payloadSize))
        header.appendLE(UInt32(payloadSize))
        header.appendLE(UInt16(fileNameSize))
        header.appendLE(UInt16(0))
        return header
    }

    private static func makeCentralDirectoryEntry(
        crc: UInt32,
        payloadSize: Int,
        fileNameSize: Int,
        localOffset: UInt32
    ) -> Data {
        var entry = Data()
        entry.appendLE(UInt32(0x02014b50))
        entry.appendLE(UInt16(20))
        entry.appendLE(UInt16(20))
        entry.appendLE(UInt16(0))
        entry.appendLE(UInt16(0))
        entry.appendLE(UInt16(0))
        entry.appendLE(UInt16(0))
        entry.appendLE(crc)
        entry.appendLE(UInt32(payloadSize))
        entry.appendLE(UInt32(payloadSize))
        entry.appendLE(UInt16(fileNameSize))
        entry.appendLE(UInt16(0))
        entry.appendLE(UInt16(0))
        entry.appendLE(UInt16(0))
        entry.appendLE(UInt16(0))
        entry.appendLE(UInt32(0))
        entry.appendLE(localOffset)
        return entry
    }

    private static func makeNPYData(shape: [Int], values: [Float]) throws -> Data {
        let expectedCount = shape.reduce(1, *)
        precondition(expectedCount == values.count, "NPY shape does not match value count")

        var header = "{'descr': '<f4', 'fortran_order': False, 'shape': \(shapeDescription(shape)), }"
        let preambleCount = 10
        while (preambleCount + header.utf8.count + 1) % 16 != 0 {
            header.append(" ")
        }
        header.append("\n")

        var data = Data()
        data.append(contentsOf: [0x93])
        data.append("NUMPY".data(using: .ascii)!)
        data.append(contentsOf: [0x01, 0x00])
        data.appendLE(UInt16(header.utf8.count))
        data.append(header.data(using: .ascii)!)

        for value in values {
            data.appendLE(value.bitPattern)
        }

        return data
    }

    private static func shapeDescription(_ shape: [Int]) -> String {
        switch shape.count {
        case 0:
            return "()"
        case 1:
            return "(\(shape[0]),)"
        default:
            return "(\(shape.map(String.init).joined(separator: ", ")),)"
        }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crc32Table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crc32Table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            if value & 1 == 1 {
                value = 0xEDB8_8320 ^ (value >> 1)
            } else {
                value >>= 1
            }
        }
        return value
    }
}

private struct PreparedEntry {
    let fileNameData: Data
    let payload: Data
    let crc: UInt32
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}
