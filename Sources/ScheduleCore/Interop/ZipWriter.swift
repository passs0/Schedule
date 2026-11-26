import Foundation
import zlib

/// Minimal, zero-dependency ZIP archive writer using system `zlib`.
/// Used to package OOXML (.xlsx) spreadsheets completely offline.
public struct ZipWriter {
    private struct Entry {
        let path: String
        let crc32: UInt32
        let compressedData: Data
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
        let compressionMethod: UInt16
    }

    private var entries: [Entry] = []
    private var buffer = Data()

    public init() {}

    public mutating func addFile(path: String, data: Data) throws {
        let pathData = Data(path.utf8)
        let uncompressedSize = UInt32(data.count)
        let crc = data.withUnsafeBytes { rawPtr -> UInt32 in
            guard let base = rawPtr.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return 0 }
            return UInt32(zlib.crc32(0, base, uInt(data.count)))
        }

        let (compressed, method) = try deflateRaw(data)
        let localOffset = UInt32(buffer.count)

        // Local file header (30 bytes + filename)
        buffer.appendUInt32LE(0x04034B50) // Signature
        buffer.appendUInt16LE(20)         // Version needed (2.0)
        buffer.appendUInt16LE(0x0800)     // UTF-8 filename flag
        buffer.appendUInt16LE(method)     // Compression method (8 = deflate, 0 = stored)
        buffer.appendUInt16LE(0)          // Mod time
        buffer.appendUInt16LE(0x5421)     // Mod date
        buffer.appendUInt32LE(crc)
        buffer.appendUInt32LE(UInt32(compressed.count))
        buffer.appendUInt32LE(uncompressedSize)
        buffer.appendUInt16LE(UInt16(pathData.count))
        buffer.appendUInt16LE(0)          // Extra field length
        buffer.append(pathData)
        buffer.append(compressed)

        entries.append(Entry(
            path: path,
            crc32: crc,
            compressedData: compressed,
            uncompressedSize: uncompressedSize,
            localHeaderOffset: localOffset,
            compressionMethod: method
        ))
    }

    public func finalize() -> Data {
        var out = buffer
        let centralDirOffset = UInt32(out.count)

        for entry in entries {
            let pathData = Data(entry.path.utf8)
            out.appendUInt32LE(0x02014B50) // Central directory header
            out.appendUInt16LE(20)         // Version made by
            out.appendUInt16LE(20)         // Version needed
            out.appendUInt16LE(0x0800)     // UTF-8 flag
            out.appendUInt16LE(entry.compressionMethod)
            out.appendUInt16LE(0)          // Mod time
            out.appendUInt16LE(0x5421)     // Mod date
            out.appendUInt32LE(entry.crc32)
            out.appendUInt32LE(UInt32(entry.compressedData.count))
            out.appendUInt32LE(entry.uncompressedSize)
            out.appendUInt16LE(UInt16(pathData.count))
            out.appendUInt16LE(0)          // Extra len
            out.appendUInt16LE(0)          // Comment len
            out.appendUInt16LE(0)          // Disk start
            out.appendUInt16LE(0)          // Internal attrs
            out.appendUInt32LE(0)          // External attrs
            out.appendUInt32LE(entry.localHeaderOffset)
            out.append(pathData)
        }

        let centralDirSize = UInt32(out.count) - centralDirOffset

        // End of central directory record
        out.appendUInt32LE(0x06054B50)
        out.appendUInt16LE(0)
        out.appendUInt16LE(0)
        out.appendUInt16LE(UInt16(entries.count))
        out.appendUInt16LE(UInt16(entries.count))
        out.appendUInt32LE(centralDirSize)
        out.appendUInt32LE(centralDirOffset)
        out.appendUInt16LE(0)

        return out
    }

    private func deflateRaw(_ data: Data) throws -> (Data, UInt16) {
        if data.isEmpty {
            return (Data(), 0)
        }
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS, // Raw deflate for ZIP
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            return (data, 0)
        }
        defer { deflateEnd(&stream) }

        var compressed = Data(count: max(64, data.count + 64))
        let resultCount = data.withUnsafeBytes { srcBytes -> Int? in
            guard let srcBase = srcBytes.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return nil }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBase)
            stream.avail_in = uInt(data.count)

            return compressed.withUnsafeMutableBytes { dstBytes -> Int? in
                guard let dstBase = dstBytes.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return nil }
                stream.next_out = dstBase
                stream.avail_out = uInt(dstBytes.count)
                let status = deflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END else { return nil }
                return Int(stream.total_out)
            }
        }

        if let count = resultCount, count < data.count {
            compressed.count = count
            return (compressed, 8)
        }
        return (data, 0)
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 2))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 4))
    }
}
