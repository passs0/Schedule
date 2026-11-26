import Foundation

public enum NumbersExportError: LocalizedError, Sendable {
    case numbersNotInstalled
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .numbersNotInstalled:
            return "Apple Numbers is not installed on this Mac. You can export as a formula-driven Excel (.xlsx) workbook instead, which opens natively in Numbers."
        case .conversionFailed(let message):
            return "Could not convert to a Numbers document: \(message)"
        }
    }
}

/// Exports a project to a native `.numbers` package using Apple Numbers automation when installed.
/// Apple does not provide a public standalone SDK for writing the proprietary IWA `.numbers` format directly.
public enum NumbersExporter {
    public static var isNumbersInstalled: Bool {
        let paths = [
            "/Applications/Numbers.app",
            "/System/Applications/Numbers.app"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    public static func export(document: ProjectDocument, to destinationURL: URL) throws {
        guard isNumbersInstalled else {
            throw NumbersExportError.numbersNotInstalled
        }

        let tempXLSX = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        defer { try? FileManager.default.removeItem(at: tempXLSX) }

        try XLSXExporter.export(document: document, to: tempXLSX)

        let script = """
        tell application "Numbers"
            set docRef to open POSIX file "\(escapeAppleScript(tempXLSX.path))"
            save docRef in POSIX file "\(escapeAppleScript(destinationURL.path))"
            close docRef saving no
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "Unknown AppleScript error"
            throw NumbersExportError.conversionFailed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func escapeAppleScript(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
