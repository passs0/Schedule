import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ScheduleCore

struct VersionComparisonView: View {
    @Bindable var viewModel: ProjectViewModel
    @State private var leftSourceID: String = "snapshot:0"
    @State private var rightSourceID: String = "current"
    @State private var externalLeftDoc: ProjectDocument?
    @State private var externalRightDoc: ProjectDocument?
    @State private var syncScrolling: Bool = true
    @State private var leftScrollPosition = ScrollPosition(point: .zero)
    @State private var rightScrollPosition = ScrollPosition(point: .zero)
    @State private var isSyncingScroll: Bool = false

    private let rowHeight: CGFloat = 34
    private let dayWidth: CGFloat = 18

    private var availableSources: [(id: String, label: String, tasks: [ScheduleTask])] {
        var list: [(String, String, [ScheduleTask])] = [
            ("current", "Current Schedule", viewModel.document.tasks)
        ]
        for (idx, v) in viewModel.document.versions.enumerated() {
            list.append(("snapshot:\(idx)", v.name, v.tasks))
        }
        if let extL = externalLeftDoc {
            list.append(("external:left", "File: \(extL.name)", extL.tasks))
        }
        if let extR = externalRightDoc {
            list.append(("external:right", "File: \(extR.name)", extR.tasks))
        }
        return list
    }

    private func tasks(for sourceID: String) -> [ScheduleTask] {
        availableSources.first { $0.id == sourceID }?.tasks ?? viewModel.document.tasks
    }

    var body: some View {
        let leftTasks = tasks(for: leftSourceID)
        let rightTasks = tasks(for: rightSourceID)
        let comparison = ProjectDiffEngine.compare(baseline: leftTasks, revised: rightTasks)

        let allTasks = leftTasks + rightTasks
        let timelineStart = (allTasks.map(\.startDate).min() ?? viewModel.document.projectStartDate).addingCalendarDays(-3)
        let timelineEnd = (allTasks.map(\.endDate).max() ?? viewModel.document.projectStartDate.addingCalendarDays(20)).addingCalendarDays(7)
        let totalDays = max(25, timelineStart.calendarDays(until: timelineEnd) + 1)

        VStack(spacing: 0) {
            comparisonToolbar(comparison: comparison)
            Divider()

            HSplitView {
                comparisonPane(
                    title: "Baseline",
                    sourceID: $leftSourceID,
                    isLeft: true,
                    rows: comparison.rows,
                    timelineStart: timelineStart,
                    totalDays: totalDays,
                    scrollPosition: $leftScrollPosition,
                    onOffsetChanged: { pt in
                        guard syncScrolling, !isSyncingScroll else { return }
                        isSyncingScroll = true
                        rightScrollPosition.scrollTo(point: pt)
                        DispatchQueue.main.async { isSyncingScroll = false }
                    }
                )

                comparisonPane(
                    title: "Comparison",
                    sourceID: $rightSourceID,
                    isLeft: false,
                    rows: comparison.rows,
                    timelineStart: timelineStart,
                    totalDays: totalDays,
                    scrollPosition: $rightScrollPosition,
                    onOffsetChanged: { pt in
                        guard syncScrolling, !isSyncingScroll else { return }
                        isSyncingScroll = true
                        leftScrollPosition.scrollTo(point: pt)
                        DispatchQueue.main.async { isSyncingScroll = false }
                    }
                )
            }
        }
        .onAppear {
            if viewModel.document.versions.isEmpty {
                leftSourceID = "current"
            } else {
                leftSourceID = "snapshot:0"
            }
            rightSourceID = "current"
        }
    }

    private func comparisonToolbar(comparison: ProjectComparisonResult) -> some View {
        HStack(spacing: 14) {
            Label("Version Comparison", systemImage: "rectangle.split.2x1")
                .font(.headline)

            HStack(spacing: 8) {
                diffBadge(count: comparison.addedCount, label: "Added", color: .green)
                diffBadge(count: comparison.deletedCount, label: "Removed", color: .red)
                diffBadge(count: comparison.modifiedCount, label: "Modified", color: .orange)

                if let delta = comparison.finishDateDeltaDays {
                    Text(delta == 0 ? "Finish: Unchanged" : (delta > 0 ? "Finish: +\(delta)d later" : "Finish: \(delta)d earlier"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(delta > 0 ? .red : (delta < 0 ? .green : .secondary))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }

            Spacer()

            Toggle("Sync Scroll", isOn: $syncScrolling)
                .toggleStyle(.checkbox)
                .font(.callout)

            Button("Done") {
                viewModel.isComparingVersions = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func diffBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count) \(label)")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }

    private func comparisonPane(
        title: String,
        sourceID: Binding<String>,
        isLeft: Bool,
        rows: [TaskDiffRow],
        timelineStart: CalendarDay,
        totalDays: Int,
        scrollPosition: Binding<ScrollPosition>,
        onOffsetChanged: @escaping (CGPoint) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("", selection: sourceID) {
                    ForEach(availableSources, id: \.id) { src in
                        Text(src.label).tag(src.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)

                Button("Open File…") {
                    openExternalFile(isLeft: isLeft)
                }
                .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView([.vertical, .horizontal]) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        let task = isLeft ? row.leftTask : row.rightTask
                        comparisonRow(row: row, task: task, isLeft: isLeft, timelineStart: timelineStart, totalDays: totalDays)
                            .frame(height: rowHeight)
                    }
                }
            }
            .scrollPosition(scrollPosition)
            .onScrollGeometryChange(for: CGPoint.self) { geo in
                geo.contentOffset
            } action: { _, newOffset in
                onOffsetChanged(newOffset)
            }
        }
    }

    @ViewBuilder
    private func comparisonRow(
        row: TaskDiffRow,
        task: ScheduleTask?,
        isLeft: Bool,
        timelineStart: CalendarDay,
        totalDays: Int
    ) -> some View {
        let rowTint: Color = {
            switch row.kind {
            case .added: return isLeft ? Color.clear : Color.green.opacity(0.08)
            case .deleted: return isLeft ? Color.red.opacity(0.08) : Color.clear
            case .modified: return Color.orange.opacity(0.08)
            case .unchanged: return Color.clear
            }
        }()

        HStack(spacing: 0) {
            // Task info
            HStack(spacing: 6) {
                statusSymbol(for: row.kind, isLeft: isLeft)
                    .frame(width: 16)

                if let task {
                    Text(task.title)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !isLeft, case .modified(let changes) = row.kind, let first = changes.first {
                        Text(first.summaryLabel)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                    }
                    Text(task.isMilestone ? "Milestone" : "\(task.durationDays)d")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .frame(width: 240)
            .padding(.horizontal, 8)

            Divider()

            // Mini Gantt Bar
            ZStack(alignment: .leading) {
                Color.clear.frame(width: CGFloat(totalDays) * dayWidth, height: rowHeight)
                if let task {
                    let offsetDays = timelineStart.calendarDays(until: task.startDate)
                    let spanDays = max(1, task.startDate.calendarDays(until: task.endDate) + 1)
                    let x = CGFloat(offsetDays) * dayWidth
                    let w = task.isMilestone ? 12 : max(10, CGFloat(spanDays) * dayWidth)
                    let barColor: Color = {
                        switch row.kind {
                        case .added: return .green
                        case .deleted: return .red
                        case .modified: return .orange
                        case .unchanged: return ScheduleTheme.accent
                        }
                    }()

                    if task.isMilestone {
                        Image(systemName: "diamond.fill")
                            .font(.caption2)
                            .foregroundStyle(barColor)
                            .offset(x: x)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor.opacity(0.75))
                            .frame(width: w, height: 14)
                            .offset(x: x)
                    }
                }
            }
        }
        .background(rowTint)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    @ViewBuilder
    private func statusSymbol(for kind: TaskDiffKind, isLeft: Bool) -> some View {
        switch kind {
        case .added:
            if !isLeft {
                Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.caption)
            }
        case .deleted:
            if isLeft {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red).font(.caption)
            }
        case .modified:
            Image(systemName: "pencil.circle.fill").foregroundStyle(.orange).font(.caption)
        case .unchanged:
            EmptyView()
        }
    }

    private func openExternalFile(isLeft: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "schedule") ?? .json, .json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url),
           let doc = try? ProjectDocument.decodeJSON(from: data) {
            if isLeft {
                externalLeftDoc = doc
                leftSourceID = "external:left"
            } else {
                externalRightDoc = doc
                rightSourceID = "external:right"
            }
        }
    }
}
