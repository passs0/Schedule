import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ScheduleCore

enum ExportFormat: String, CaseIterable, Identifiable {
    case ganttPDF = "Gantt Chart PDF (.pdf)"
    case ganttPNG = "Gantt Chart Image (.png)"
    case excel = "Microsoft Excel (.xlsx)"
    case numbers = "Apple Numbers (.numbers)"
    case mspXML = "Microsoft Project XML (.xml)"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .ganttPDF: return "Lossless vector graphic for Keynote & print"
        case .ganttPNG: return "High-DPI image for PowerPoint, Google Slides & web"
        case .excel: return "Formula-driven workbook (also opens in Numbers)"
        case .numbers: return "Native Apple Numbers document"
        case .mspXML: return "Compatible with Microsoft Project"
        }
    }

    var systemImage: String {
        switch self {
        case .ganttPDF: return "doc.richtext"
        case .ganttPNG: return "photo"
        case .excel: return "tablecells"
        case .numbers: return "chart.bar.doc.horizontal"
        case .mspXML: return "doc.text"
        }
    }
}

@MainActor
enum FileDialogs {
    static func saveScheduleDocument(_ document: ProjectDocument, existingURL: URL?) -> (url: URL?, error: String?) {
        let targetURL: URL
        if let existingURL {
            targetURL = existingURL
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = document.name
            panel.allowedContentTypes = [UTType(filenameExtension: "schedule") ?? .json]
            panel.title = "Save Schedule"
            guard panel.runModal() == .OK, let url = panel.url else {
                return (nil, nil)
            }
            targetURL = url
        }

        do {
            let data = try document.encodeJSON()
            try data.write(to: targetURL, options: .atomic)
            return (targetURL, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    static func saveScheduleDocumentAs(_ document: ProjectDocument) -> (url: URL?, error: String?) {
        saveScheduleDocument(document, existingURL: nil)
    }

    static func exportProject(_ viewModel: ProjectViewModel, format: ExportFormat) -> (success: Bool, message: String?) {
        let document = viewModel.document
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.name

        switch format {
        case .ganttPDF:
            panel.allowedContentTypes = [.pdf]
        case .ganttPNG:
            panel.allowedContentTypes = [.png]
        case .excel:
            panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .spreadsheet]
        case .numbers:
            if !NumbersExporter.isNumbersInstalled {
                return (false, NumbersExportError.numbersNotInstalled.localizedDescription)
            }
            panel.allowedContentTypes = [UTType(filenameExtension: "numbers") ?? .package]
        case .mspXML:
            panel.allowedContentTypes = [.xml]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return (false, nil)
        }

        do {
            switch format {
            case .ganttPDF:
                try GanttExporter.exportPDF(viewModel: viewModel, to: url)
            case .ganttPNG:
                try GanttExporter.exportPNG(viewModel: viewModel, to: url)
            case .excel:
                try XLSXExporter.export(document: document, to: url)
            case .numbers:
                try NumbersExporter.export(document: document, to: url)
            case .mspXML:
                try MSPXMLInterop.export(document: document, to: url)
            }
            return (true, "Exported to \(url.lastPathComponent)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    static func importProject() -> Result<ProjectDocument, Error>? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .xml,
            .json,
            .commaSeparatedText,
            .tabSeparatedText,
            .plainText,
            UTType(filenameExtension: "xlsx") ?? .spreadsheet,
            UTType(filenameExtension: "schedule") ?? .json,
            UTType(filenameExtension: "mpp") ?? .data
        ]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Import Excel (.xlsx), CSV (.csv/.tsv), Microsoft Project XML (.xml), or Schedule (.schedule) files."

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let doc = try MPPCompatibility.importFile(at: url)
            return .success(doc)
        } catch {
            return .failure(error)
        }
    }
}

struct SnapshotSheet: View {
    @Bindable var viewModel: ProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var notes: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Save Project Snapshot") {
                    TextField("Version Name", text: $name, prompt: Text("e.g., Revised Plan"))
                    TextField("Notes (Optional)", text: $notes, prompt: Text("Reason for this snapshot"))
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Snapshot") {
                    viewModel.saveSnapshot(name: name, notes: notes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 380, height: 220)
    }
}
