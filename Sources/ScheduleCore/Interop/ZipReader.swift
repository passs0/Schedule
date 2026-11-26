import Foundation
import zlib

/// Minimal, zero-dependency ZIP archive reader using system `zlib`.
/// Used to read OOXML (`.xlsx`) entries completely offline.
public enum ZipReader {
    public enum ZipError: LocalizedError, Sendable {
        case invalidArchive
        case decompressionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidArchive:
                return "The file is not a valid ZIP/.xlsx archive."
            case .decompressionFailed(let name):
                return "Could not decompress entry \"\(name)\" from archive."
            }
        }
    }

    public static func readEntries(from data: Data) throws -> [String: Data] {
        // Locate End of Central Directory (0x06054b50) scanning backwards from the end.
        let minOffset = max(0, data.count - 65_557)
        var eocdOffset: Int?
        if data.count >= 22 {
            var i = data.count - 22
            while i >= minOffset {
                if data.readUInt32LE(at: i) == 0x06054B50 {
                    eocdOffset = i
                    break
                }
                i -= 1
            }
        }
        guard let eocd = eocdOffset else { throw ZipError.invalidArchive }

        let totalEntries = Int(data.readUInt16LE(at: eocd + 10))
        let centralDirOffset = Int(data.readUInt32LE(at: eocd + 16))
        guard centralDirOffset >= 0, centralDirOffset < data.count else { throw ZipError.invalidArchive }

        var entries: [String: Data] = [:]
        var cursor = centralDirOffset

        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count, data.readUInt32LE(at: cursor) == 0x02014B50 else {
                break
            }
            let method = data.readUInt16LE(at: cursor + 10)
            let compressedSize = Int(data.readUInt32LE(at: cursor + 20))
            let uncompressedSize = Int(data.readUInt32LE(at: cursor + 24))
            let nameLen = Int(data.readUInt16LE(at: cursor + 28))
            let extraLen = Int(data.readUInt16LE(at: cursor + 30))
            let commentLen = Int(data.readUInt16LE(at: cursor + 32))
            let localHeaderOffset = Int(data.readUInt32LE(at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLen <= data.count else { break }
            let name = String(data: data.subdata(in: nameStart..<(nameStart + nameLen)), encoding: .utf8) ?? ""
            cursor = nameStart + nameLen + extraLen + commentLen

            guard localHeaderOffset + 30 <= data.count,
                  data.readUInt32LE(at: localHeaderOffset) == 0x04034B50 else { continue }
            let localNameLen = Int(data.readUInt16LE(at: localHeaderOffset + 26))
            let localExtraLen = Int(data.readUInt16LE(at: localHeaderOffset + 28))
            let payloadStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            guard payloadStart + compressedSize <= data.count else { continue }
            let payload = data.subdata(in: payloadStart..<(payloadStart + compressedSize))

            if method == 0 {
                entries[name] = payload
            } else if method == 8 {
                let inflated = try inflateRaw(payload, expectedSize: max(uncompressedSize, payload.count * 4))
                entries[name] = inflated
            }
        }
        return entries
    }

    private static func inflateRaw(_ data: Data, expectedSize: Int) throws -> Data {
        if data.isEmpty { return Data() }
        var stream = z_stream()
        let status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ZipError.decompressionFailed("init") }
        defer { inflateEnd(&stream) }

        var output = Data(count: max(1024, expectedSize))
        let result: Data? = data.withUnsafeBytes { srcBytes in
            guard let srcBase = srcBytes.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return nil }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBase)
            stream.avail_in = uInt(data.count)

            while true {
                let written = Int(stream.total_out)
                if written >= output.count {
                    output.count += max(4096, output.count)
                }
                let availOut = output.count - written
                let stepStatus: Int32 = output.withUnsafeMutableBytes { dstBytes in
                    guard let dstBase = dstBytes.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return Z_MEM_ERROR }
                    stream.next_out = dstBase.advanced(by: written)
                    stream.avail_out = uInt(availOut)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                if stepStatus == Z_STREAM_END {
                    output.count = Int(stream.total_out)
                    return output
                }
                if stepStatus != Z_OK {
                    return nil
                }
            }
        }
        guard let inflated = result else { throw ZipError.decompressionFailed("stream") }
        return inflated
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1])
        return b0 | (b1 << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
