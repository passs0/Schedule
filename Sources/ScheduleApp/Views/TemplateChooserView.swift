import SwiftUI
import ScheduleCore

/// Native macOS Welcome window scene content (compact, fixed-size via `.windowResizability(.contentSize)`).
struct WelcomeWindowView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var showingTemplateChooser = false
    @State private var pendingTemplate: ProjectTemplate?
    @State private var importErrorMessage: String?

    var body: some View {
        WelcomeView(
            recentProjects: store.recentProjects,
            onOpenProject: { id in
                store.selectProject(id)
                openWorkspace()
            },
            onOpenFile: {
                guard let result = FileDialogs.importProject() else { return }
                switch result {
                case .success(let doc):
                    store.importProject(doc)
                    openWorkspace()
                case .failure(let error):
                    let nsErr = error as NSError
                    importErrorMessage = [error.localizedDescription, nsErr.localizedRecoverySuggestion]
                        .compactMap { $0 }
                        .joined(separator: "\n\n")
                }
            },
            onNewDocument: {
                showingTemplateChooser = true
            }
        )
        .frame(width: 560, height: 480)
        .sheet(isPresented: $showingTemplateChooser, onDismiss: {
            if let template = pendingTemplate {
                pendingTemplate = nil
                _ = store.createNewProject(template: template)
                openWorkspace()
            }
        }) {
            TemplateChooserView(
                onSelectTemplate: { template in
                    pendingTemplate = template
                    showingTemplateChooser = false
                },
                onCancel: {
                    pendingTemplate = nil
                    showingTemplateChooser = false
                }
            )
            .frame(width: 720, height: 460)
        }
        .alert(
            "Import Notice",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private func openWorkspace() {
        openWindow(id: "workspace")
        dismissWindow(id: "welcome")
    }
}

/// Pages-style initial screen shown when no project is open:
/// lets the user open an existing/recent file or click "New Document…" to pick a template.
struct WelcomeView: View {
    let recentProjects: [ProjectDocument]
    let onOpenProject: (UUID) -> Void
    let onOpenFile: () -> Void
    let onNewDocument: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)

                    Text("Schedule")
                        .font(.title2.weight(.semibold))

                    Text("Open an existing project, import a task list, or create a new schedule.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !recentProjects.isEmpty {
                    let visibleRecent = Array(recentProjects.prefix(4))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Projects")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        List(visibleRecent) { project in
                            Button {
                                onOpenProject(project.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar.day.timeline.leading")
                                        .font(.callout)
                                        .foregroundStyle(ScheduleTheme.accent)
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .font(.callout.weight(.medium))
                                        Text("\(project.tasks.count) items")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(project.modifiedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .listStyle(.bordered(alternatesRowBackgrounds: false))
                        .frame(height: CGFloat(visibleRecent.count) * 44 + 8)
                    }
                    .frame(maxWidth: 430)
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Button {
                    onOpenFile()
                } label: {
                    Label("Open File…", systemImage: "folder")
                        .frame(minWidth: 136)
                }
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    onNewDocument()
                } label: {
                    Label("New Document…", systemImage: "plus")
                        .frame(minWidth: 148)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Pages-style "Choose a Template" sheet (no sidebar, clean card grid + Cancel / Create).
struct TemplateChooserView: View {
    let onSelectTemplate: (ProjectTemplate) -> Void
    let onCancel: () -> Void

    @State private var selectedTemplate: ProjectTemplate = .blank

    private let columns = [
        GridItem(.adaptive(minimum: 205, maximum: 240), spacing: 14)
    ]

    private static let summaryByTemplate: [ProjectTemplate: String] = {
        var map: [ProjectTemplate: String] = [:]
        for template in ProjectTemplate.allCases where template != .blank {
            let doc = template.makeDocument(referenceDate: CalendarDay(year: 2026, month: 1, day: 5))
            let phases = doc.tasks.filter { $0.parentID == nil }.count
            map[template] = "\(phases) phases · \(doc.tasks.count) items"
        }
        return map
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a Template")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ProjectTemplate.allCases) { template in
                        templateCard(template)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    onSelectTemplate(selectedTemplate)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func templateCard(_ template: ProjectTemplate) -> some View {
        let isSelected = selectedTemplate == template

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: template.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : ScheduleTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected ? ScheduleTheme.accent : ScheduleTheme.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                Spacer()

                Text(template.badge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? ScheduleTheme.accent : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (isSelected ? ScheduleTheme.accent : Color.secondary).opacity(0.12),
                        in: Capsule()
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let summary = Self.summaryByTemplate[template] {
                Text(summary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(minHeight: 138, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? ScheduleTheme.accent : Color(nsColor: .separatorColor).opacity(0.55),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(count: 2) {
            selectedTemplate = template
            onSelectTemplate(template)
        }
        .onTapGesture(count: 1) {
            selectedTemplate = template
        }
    }
}
