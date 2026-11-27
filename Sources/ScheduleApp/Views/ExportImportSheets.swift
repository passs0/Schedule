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
enum ExportMenuPresenter {
    private final class MenuTarget: NSObject {
        let onSelect: (ExportFormat) -> Void
        init(onSelect: @escaping (ExportFormat) -> Void) {
            self.onSelect = onSelect
        }
        @objc func handleSelect(_ sender: NSMenuItem) {
            guard let format = sender.representedObject as? ExportFormat else { return }
            onSelect(format)
        }
    }

    // Retained while the modal menu is tracking
    private static var activeTarget: MenuTarget?

    static func show(onSelect: @escaping (ExportFormat) -> Void) {
        let target = MenuTarget(onSelect: onSelect)
        activeTarget = target

        let menu = NSMenu(title: "Export")
        for format in ExportFormat.allCases {
            let item = NSMenuItem(
                title: NSLocalizedString(format.rawValue, comment: ""),
                action: #selector(MenuTarget.handleSelect(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = format
            item.image = NSImage(systemSymbolName: format.systemImage, accessibilityDescription: nil)
            menu.addItem(item)
        }

        if let event = NSApp.currentEvent,
           let window = event.window,
           let themeFrame = window.contentView?.superview,
           let hitView = themeFrame.hitTest(event.locationInWindow) {
            let y = hitView.isFlipped ? hitView.bounds.maxY + 4 : -4
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: hitView)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }

        activeTarget = nil
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
        panel.message = "Import Microsoft Project (.mpp, .xml), Excel (.xlsx), CSV (.csv/.tsv), or Schedule (.schedule) files."

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
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 380, height: 220)
    }
}
