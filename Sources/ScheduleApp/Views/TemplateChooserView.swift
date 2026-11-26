import SwiftUI
import ScheduleCore

/// Pages-style initial screen shown when no project is open:
/// lets the user open an existing/recent file or click "New Document…" to pick a template.
struct WelcomeView: View {
    let recentProjects: [ProjectDocument]
    let onOpenProject: (UUID) -> Void
    let onOpenFile: () -> Void
    let onNewDocument: () -> Void

    @State private var hoveredProjectID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)

                    Text("Welcome to Schedule")
                        .font(.title.weight(.semibold))

                    Text("Open an existing project, import a task list, or create a new schedule.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Projects")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            let visibleRecent = Array(recentProjects.prefix(5))
                            ForEach(visibleRecent) { project in
                                Button {
                                    onOpenProject(project.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "calendar.day.timeline.leading")
                                            .font(.callout)
                                            .foregroundStyle(ScheduleTheme.accent)
                                            .frame(width: 22)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(project.name)
                                                .font(.callout.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text("\(project.tasks.count) items")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text(project.modifiedAt, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        hoveredProjectID == project.id
                                            ? Color.primary.opacity(0.05)
                                            : Color.clear
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    hoveredProjectID = hovering ? project.id : (hoveredProjectID == project.id ? nil : hoveredProjectID)
                                }

                                if project.id != visibleRecent.last?.id {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: 420)
                }

                HStack(spacing: 12) {
                    Button {
                        onOpenFile()
                    } label: {
                        Label("Open File…", systemImage: "folder")
                            .frame(minWidth: 130)
                    }
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)

                    Button {
                        onNewDocument()
                    } label: {
                        Label("New Document…", systemImage: "plus")
                            .frame(minWidth: 145)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)

            Spacer()
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
                    .font(.system(size: 17, weight: .semibold))
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
