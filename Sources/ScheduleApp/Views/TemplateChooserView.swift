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
        .frame(width: store.recentProjects.isEmpty ? 580 : 680, height: store.recentProjects.isEmpty ? 380 : 400)
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

/// Apple-style welcome screen:
/// centered single-column (580x380, matching Player) when empty,
/// or Xcode-style two-column layout (680x400) with a right-hand Recent Projects list.
struct WelcomeView: View {
    let recentProjects: [ProjectDocument]
    let onOpenProject: (UUID) -> Void
    let onOpenFile: () -> Void
    let onNewDocument: () -> Void

    @State private var hoveredProjectID: UUID?

    var body: some View {
        if recentProjects.isEmpty {
            heroColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        } else {
            HStack(spacing: 0) {
                heroColumn
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                recentColumn
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var heroColumn: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)

            VStack(spacing: 4) {
                Text("Schedule")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Open a project, import a task list, or create a new schedule")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onNewDocument) {
                    Label("New Document…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button(action: onOpenFile) {
                    Label("Open File…", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
    }

    private var recentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Projects")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(recentProjects.prefix(12)) { project in
                        Button {
                            onOpenProject(project.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.day.timeline.leading")
                                    .font(.callout)
                                    .foregroundStyle(ScheduleTheme.accent)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text("\(project.tasks.count) items")
                                        Text("·")
                                        Text(project.modifiedAt, format: .dateTime.month(.abbreviated).day())
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 4)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                hoveredProjectID == project.id
                                    ? Color.primary.opacity(0.08)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredProjectID = hovering ? project.id : (hoveredProjectID == project.id ? nil : hoveredProjectID)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
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
