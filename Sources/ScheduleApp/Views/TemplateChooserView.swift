import SwiftUI
import ScheduleCore

/// Pages-style initial screen shown when no project is open:
/// lets the user open an existing/recent file or click "New Document…" to pick a template.
struct WelcomeView: View {
    let recentProjects: [ProjectDocument]
    let onOpenProject: (UUID) -> Void
    let onOpenFile: () -> Void
    let onNewDocument: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)

                    Text("Schedule")
                        .font(.largeTitle.weight(.semibold))

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
                            ForEach(recentProjects.prefix(5)) { project in
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
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if project.id != recentProjects.prefix(5).last?.id {
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
            .padding(32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TemplatePreviewData {
    struct Bar: Identifiable {
        let id = UUID()
        let startFrac: CGFloat
        let widthFrac: CGFloat
        let isGroup: Bool
        let isMilestone: Bool
    }

    let phaseCount: Int
    let taskCount: Int
    let bars: [Bar]

    static let cache: [ProjectTemplate: TemplatePreviewData] = {
        var result: [ProjectTemplate: TemplatePreviewData] = [:]
        for template in ProjectTemplate.allCases {
            let doc = template.makeDocument(referenceDate: CalendarDay(year: 2026, month: 1, day: 5))
            let tasks = doc.tasks
            let minDay = tasks.map(\.startDate).min() ?? doc.projectStartDate
            let maxDay = tasks.map(\.endDate).max() ?? doc.projectStartDate.addingCalendarDays(1)
            let span = max(1, minDay.calendarDays(until: maxDay) + 1)

            let phaseCount = tasks.filter { $0.parentID == nil }.count
            let bars: [Bar] = tasks.prefix(16).map { task in
                let offset = max(0, minDay.calendarDays(until: task.startDate))
                let dur = max(1, task.startDate.calendarDays(until: task.endDate) + 1)
                let startFrac = CGFloat(offset) / CGFloat(span)
                let widthFrac = task.isMilestone ? 0.02 : max(0.05, CGFloat(dur) / CGFloat(span))
                return Bar(
                    startFrac: startFrac,
                    widthFrac: min(1.0 - startFrac, widthFrac),
                    isGroup: task.parentID == nil && tasks.contains(where: { $0.parentID == task.id }),
                    isMilestone: task.isMilestone
                )
            }
            result[template] = TemplatePreviewData(
                phaseCount: phaseCount,
                taskCount: tasks.count,
                bars: bars
            )
        }
        return result
    }()
}

/// Pages-style "Choose a Template" sheet (no sidebar, visual preview card grid + Cancel / Create).
struct TemplateChooserView: View {
    let onSelectTemplate: (ProjectTemplate) -> Void
    let onCancel: () -> Void

    @State private var selectedTemplate: ProjectTemplate = .blank

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 250), spacing: 14)
    ]

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
        let preview = TemplatePreviewData.cache[template]

        return VStack(alignment: .leading, spacing: 10) {
            miniGanttPreview(template: template, preview: preview)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 6) {
                    Text(template.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let preview, template != .blank {
                    Text("\(preview.phaseCount) phases · \(preview.taskCount) items")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ScheduleTheme.accent)
                        .padding(.top, 2)
                } else {
                    Text(template.badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 190, alignment: .topLeading)
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

    @ViewBuilder
    private func miniGanttPreview(template: ProjectTemplate, preview: TemplatePreviewData?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))

            if template == .blank {
                VStack(spacing: 5) {
                    Image(systemName: "doc")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Empty Schedule")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if let preview {
                Canvas { context, size in
                    let padX: CGFloat = 10
                    let padY: CGFloat = 8
                    let usableW = max(1, size.width - padX * 2)
                    let usableH = max(1, size.height - padY * 2)
                    let count = max(1, preview.bars.count)
                    let rowH = usableH / CGFloat(count)

                    for (idx, bar) in preview.bars.enumerated() {
                        let y = padY + CGFloat(idx) * rowH
                        let x = padX + bar.startFrac * usableW

                        if bar.isMilestone {
                            let cy = y + rowH / 2
                            let r: CGFloat = min(3.2, rowH * 0.42)
                            var d = Path()
                            d.move(to: CGPoint(x: x, y: cy - r))
                            d.addLine(to: CGPoint(x: x + r, y: cy))
                            d.addLine(to: CGPoint(x: x, y: cy + r))
                            d.addLine(to: CGPoint(x: x - r, y: cy))
                            d.closeSubpath()
                            context.fill(d, with: .color(ScheduleTheme.accent))
                        } else if bar.isGroup {
                            let w = max(6, bar.widthFrac * usableW)
                            let h = max(2, rowH * 0.42)
                            let rect = CGRect(x: x, y: y + (rowH - h) / 2, width: w, height: h)
                            context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color.primary.opacity(0.45)))
                        } else {
                            let w = max(6, bar.widthFrac * usableW)
                            let h = max(2.5, rowH * 0.58)
                            let rect = CGRect(x: x, y: y + (rowH - h) / 2, width: w, height: h)
                            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(ScheduleTheme.accent.opacity(0.75)))
                        }
                    }
                }
            }
        }
        .frame(height: 86)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        )
    }
}
