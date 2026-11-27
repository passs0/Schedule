import Foundation

/// Strategy and diagnostics for Microsoft Project `.mpp` binary interoperability.
public enum MPPCompatibility {
    /// OLE2 Compound Document magic header (`D0 CF 11 E0 A1 B1 1A E1`).
    private static let ole2Signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

    public static func isBinaryMPP(url: URL) -> Bool {
        if url.pathExtension.lowercased() == "mpp" {
            return true
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 8)) ?? Data()
        return Array(header) == ole2Signature
    }

    public static func importFile(at url: URL) throws -> ProjectDocument {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent
        if ext == "mpp" || isBinaryMPP(url: url) {
            return try MPPBinaryParser.parse(data: data, fallbackName: baseName)
        }
        if ext == "schedule" || ext == "json" {
            return try ProjectDocument.decodeJSON(from: data)
        }
        if ext == "xlsx" {
            return try SpreadsheetImporter.importXLSX(from: data, projectName: baseName)
        }
        if ext == "csv" || ext == "tsv" || ext == "txt" {
            return try SpreadsheetImporter.importDelimited(from: data, delimiter: ext == "tsv" ? "\t" : nil, projectName: baseName)
        }
        return try MSPXMLInterop.importXML(from: data, fallbackName: baseName)
    }
}
