import SwiftUI
import UniformTypeIdentifiers
import ScheduleCore

struct TaskListView: View {
    @Bindable var viewModel: ProjectViewModel
    let scrollSync: ScrollSyncState
    let onAddDependency: (UUID) -> Void

    @State private var editingTaskID: UUID?
    @State private var editingTitle: String = ""
    @State private var draggingTaskID: UUID?
    @State private var searchText: String = ""
    @State private var activePopover: CellPopover?

    private enum CellPopover: Identifiable, Equatable {
        case start(UUID)
        case duration(UUID)
        case progress(UUID)
        case relationship(UUID)
        case calendar(UUID)

        var id: String {
            switch self {
            case .start(let id): return "start:\(id)"
            case .duration(let id): return "dur:\(id)"
            case .progress(let id): return "prog:\(id)"
            case .relationship(let id): return "rel:\(id)"
            case .calendar(let id): return "cal:\(id)"
            }
        }
    }

    private var filteredRows: [VisibleTaskRow] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return viewModel.visibleRows }
        return viewModel.visibleRows.filter {
            $0.task.title.localizedCaseInsensitiveContains(q) ||
            $0.task.identifier.localizedCaseInsensitiveContains(q)
        }
    }

    static let topBarHeight: CGFloat = 38
    static let headerHeight: CGFloat = 28
    static let rowHeight: CGFloat = 36

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMMd")
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            listSummaryBar
            Divider()
            headerBar
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRows) { row in
                        taskRow(row)
                            .transition(.opacity)
                            .onDrag {
                                draggingTaskID = row.id
                                return NSItemProvider(object: row.id.uuidString as NSString)
                            }
                            .onDrop(of: [.plainText], delegate: TaskReorderDropDelegate(
                                targetID: row.id,
                                draggingID: $draggingTaskID,
                                viewModel: viewModel
                            ))
                    }
                }
                .background(ScrollSyncAnchor(pane: .list, state: scrollSync))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .popover(item: $activePopover) { pop in
            popoverContent(for: pop)
        }
    }

    private var listSummaryBar: some View {
        HStack(spacing: 10) {
            Text("Tasks")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Filter tasks…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .frame(width: 150)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            Spacer()
            if let summary = viewModel.lastScheduleSummary {
                Label(summary, systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ScheduleTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ScheduleTheme.accent.opacity(0.14), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            Text("\(filteredRows.count) shown")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.topBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var showExtendedColumns: Bool {
        viewModel.viewMode == .listOnly
    }

    private var headerBar: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 48, alignment: .leading)
                .padding(.leading, 12)
            Divider().frame(height: 14)
            Text("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            if showExtendedColumns {
                Divider().frame(height: 14)
                Text("Relationship")
                    .frame(width: 240, alignment: .leading)
                    .padding(.horizontal, 10)
                Divider().frame(height: 14)
                Text("Calendar")
                    .frame(width: 118, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            Divider().frame(height: 14)
            Text("Start")
                .frame(width: 72, alignment: .leading)
                .padding(.horizontal, 8)
            if showExtendedColumns {
                Divider().frame(height: 14)
                Text("End")
                    .frame(width: 72, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            Divider().frame(height: 14)
            Text("Duration")
                .frame(width: 68, alignment: .trailing)
                .padding(.horizontal, 8)
            Divider().frame(height: 14)
            Text("%")
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(height: Self.headerHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func taskRow(_ row: VisibleTaskRow) -> some View {
        let task = row.task
        let isSelected = viewModel.selectedTaskID == task.id

        HStack(spacing: 0) {
            Text(task.identifier)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                .frame(width: 48, alignment: .leading)
                .padding(.leading, 12)

            // Title & Hierarchy
            HStack(spacing: 6) {
                if row.depth > 0 {
                    Spacer().frame(width: CGFloat(row.depth) * 16)
                }

                if row.isGroup {
                    Button {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            viewModel.toggleExpand(task.id)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                            .rotationEffect(.degrees(task.isExpanded ? 90 : 0))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if task.isMilestone {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : ScheduleTheme.accent)
                        .frame(width: 16)
                } else {
                    Spacer().frame(width: 16)
                }

                if editingTaskID == task.id {
                    TextField("Task Name", text: $editingTitle, onCommit: {
                        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.updateTask(task.id, actionName: "Rename Task") { t, _ in
                                t.title = trimmed
                            }
                        }
                        editingTaskID = nil
                    })
                    .textFieldStyle(.plain)
                    .font(row.isGroup || task.isMilestone ? .callout.weight(.semibold) : .callout)
                } else {
                    Text(task.title)
                        .font(row.isGroup || task.isMilestone ? .callout.weight(.semibold) : .callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                if !task.dependencies.isEmpty {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                        .help(dependencyTooltip(for: task))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)

            if showExtendedColumns {
                relationshipCell(for: task, isGroup: row.isGroup, isSelected: isSelected)
                    .frame(width: 240, alignment: .leading)
                    .padding(.horizontal, 10)

                calendarCell(for: task, isGroup: row.isGroup, isSelected: isSelected)
                    .frame(width: 118, alignment: .leading)
                    .padding(.horizontal, 8)
            }

            let wasJustRescheduled = viewModel.recentlyRescheduledIDs.contains(task.id)
            Text(Self.shortDateFormatter.string(from: task.startDate.toDate()))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : (wasJustRescheduled ? ScheduleTheme.accent : Color.secondary))
                .fontWeight(wasJustRescheduled ? .semibold : .regular)
                .frame(width: 72, alignment: .leading)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectTask(task.id)
                    if !row.isGroup { activePopover = .start(task.id) }
                }

            if showExtendedColumns {
                Text(Self.shortDateFormatter.string(from: task.endDate.toDate()))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                    .frame(width: 72, alignment: .leading)
                    .padding(.horizontal, 8)
            }

            Group {
                if task.isMilestone {
                    Text("Milestone")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Color.white.opacity(0.22) : ScheduleTheme.accent.opacity(0.14),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? Color.white : ScheduleTheme.accent)
                } else {
                    Text("\(task.durationDays)d")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                }
            }
            .frame(width: 68, alignment: .trailing)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectTask(task.id)
                if !row.isGroup && !task.isMilestone { activePopover = .duration(task.id) }
            }

            Text("\(Int(round(task.percentComplete)))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    isSelected
                        ? Color.white.opacity(0.9)
                        : (task.percentComplete >= 100 ? ScheduleTheme.accent : Color.secondary)
                )
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectTask(task.id)
                    if !row.isGroup { activePopover = .progress(task.id) }
                }
        }
        .frame(height: Self.rowHeight)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(rowBackground(isSelected: isSelected, isGroup: row.isGroup, isMilestone: task.isMilestone))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingTaskID = task.id
            editingTitle = task.title
        }
        .onTapGesture(count: 1) {
            viewModel.selectTask(task.id)
        }
        .contextMenu {
            Button("New Task Below") {
                viewModel.addTask(after: task.id, isMilestone: false, asSubtask: false)
            }
            Button("New Subtask") {
                viewModel.addTask(after: task.id, isMilestone: false, asSubtask: true)
            }
            Button("New Milestone Below") {
                viewModel.addTask(after: task.id, isMilestone: true, asSubtask: false)
            }
            Divider()
            if !row.isGroup, let prev = viewModel.previousLinkableTask(before: task.id) {
                Button("Start After \"\(prev.title)\"") {
                    viewModel.linkToPreviousTask(task.id)
                }
            }
            Button("Add Custom Relationship…") {
                viewModel.selectTask(task.id)
                onAddDependency(task.id)
            }
            Button("Inspect Task") {
                viewModel.selectTask(task.id, openInspectorIfNeeded: true)
            }
            Divider()
            Button("Indent") {
                viewModel.indentTask(task.id)
            }
            Button("Outdent") {
                viewModel.outdentTask(task.id)
            }
            Divider()
            Button("Delete Task", role: .destructive) {
                viewModel.deleteTask(task.id)
            }
        }
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool, isGroup: Bool, isMilestone: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .selectedContentBackgroundColor))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        } else if isGroup {
            Color(nsColor: .controlBackgroundColor).opacity(0.65)
        } else if isMilestone {
            ScheduleTheme.accent.opacity(0.06)
        } else {
            Color.clear
        }
    }

    private func dependencyTooltip(for task: ScheduleTask) -> String {
        let taskMap = Dictionary(uniqueKeysWithValues: viewModel.document.tasks.map { ($0.id, $0) })
        return task.dependencies.map { dep in
            let predName = taskMap[dep.predecessorID]?.title ?? "Unknown"
            return HumanDependency.describe(dep, predecessorName: predName)
        }.joined(separator: "\n")
    }

    @ViewBuilder
    private func relationshipCell(for task: ScheduleTask, isGroup: Bool, isSelected: Bool) -> some View {
        if isGroup {
            Text("—")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.4))
        } else {
            let taskMap = Dictionary(uniqueKeysWithValues: viewModel.document.tasks.map { ($0.id, $0) })
            Group {
                if task.dependencies.isEmpty {
                    Text("Add link…")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary.opacity(0.55))
                } else {
                    HStack(spacing: 4) {
                        ForEach(task.dependencies.prefix(2)) { dep in
                            let predName = taskMap[dep.predecessorID]?.title ?? "Unknown"
                            let compact = HumanDependency.compactLabel(dep, predecessorName: predName)
                            Text(compact)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    isSelected ? Color.white.opacity(0.22) : ScheduleTheme.accent.opacity(0.13),
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? Color.white : ScheduleTheme.accent)
                        }
                        if task.dependencies.count > 2 {
                            Text("+\(task.dependencies.count - 2)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                        }
                    }
                    .help(dependencyTooltip(for: task))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectTask(task.id)
                activePopover = .relationship(task.id)
            }
        }
    }

    @ViewBuilder
    private func popoverContent(for pop: CellPopover) -> some View {
        switch pop {
        case .start(let id):
            if let task = viewModel.document.tasks.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker(
                        "Start Date",
                        selection: Binding(
                            get: { task.startDate.toDate() },
                            set: { date in
                                viewModel.updateTask(task.id, actionName: "Change Start Date") { t, cal in
                                    let day = cal.snapToWorkingDay(CalendarDay(date: date, calendar: .current), forward: true)
                                    t.startDate = day
                                    t.endDate = t.isMilestone ? day : cal.endDate(startingOn: day, durationDays: t.durationDays)
                                    t.isManuallyScheduled = true
                                }
                            }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    if task.isManuallyScheduled && !task.dependencies.isEmpty {
                        Button("Follow Dependencies (Auto)") {
                            viewModel.updateTask(task.id, actionName: "Auto-Schedule Task") { t, _ in
                                t.isManuallyScheduled = false
                            }
                            activePopover = nil
                        }
                        .controlSize(.small)
                    }
                }
                .padding(10)
            }
        case .duration(let id):
            if let task = viewModel.document.tasks.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper(
                        value: Binding(
                            get: { task.durationDays },
                            set: { dur in
                                viewModel.updateTask(task.id, actionName: "Change Duration") { t, cal in
                                    t.durationDays = max(1, dur)
                                    t.endDate = cal.endDate(startingOn: t.startDate, durationDays: t.durationDays)
                                }
                            }
                        ),
                        in: 1...365
                    ) {
                        Text("\(task.durationDays) working \(task.durationDays == 1 ? "day" : "days")")
                            .font(.callout.weight(.medium))
                    }
                    HStack(spacing: 6) {
                        ForEach([1, 2, 3, 5, 10], id: \.self) { preset in
                            Button("\(preset)d") {
                                viewModel.updateTask(task.id, actionName: "Change Duration") { t, cal in
                                    t.durationDays = preset
                                    t.endDate = cal.endDate(startingOn: t.startDate, durationDays: preset)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(12)
            }
        case .progress(let id):
            if let task = viewModel.document.tasks.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Progress")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("\(Int(round(task.percentComplete)))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { task.percentComplete },
                            set: { pct in
                                viewModel.updateTask(task.id, actionName: "Update Progress") { t, _ in
                                    t.percentComplete = pct
                                }
                            }
                        ),
                        in: 0...100,
                        step: 5
                    )
                    HStack(spacing: 6) {
                        ForEach([0, 25, 50, 75, 100], id: \.self) { pct in
                            Button("\(pct)%") {
                                viewModel.updateTask(task.id, actionName: "Update Progress") { t, _ in
                                    t.percentComplete = Double(pct)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(12)
                .frame(width: 230)
            }
        case .relationship(let id):
            if let task = viewModel.document.tasks.first(where: { $0.id == id }) {
                let taskMap = Dictionary(uniqueKeysWithValues: viewModel.document.tasks.map { ($0.id, $0) })
                VStack(alignment: .leading, spacing: 10) {
                    Text("Relationships")
                        .font(.callout.weight(.semibold))

                    if task.dependencies.isEmpty {
                        Text("This task is not linked to any other task yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(task.dependencies) { dep in
                            let predName = taskMap[dep.predecessorID]?.title ?? "Unknown"
                            HStack(spacing: 8) {
                                Text(HumanDependency.describe(dep, predecessorName: predName))
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button {
                                    viewModel.removeDependency(from: task.id, dependencyID: dep.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove")
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        if let prev = viewModel.previousLinkableTask(before: task.id),
                           !task.dependencies.contains(where: { $0.predecessorID == prev.id }) {
                            Button("After \"\(prev.title)\"") {
                                viewModel.linkToPreviousTask(task.id)
                            }
                            .controlSize(.small)
                        }

                        Menu("Starts after…") {
                            ForEach(viewModel.document.tasks.filter { $0.id != task.id }) { candidate in
                                Button("\(candidate.identifier)  \(candidate.title)") {
                                    viewModel.addDependency(
                                        to: task.id,
                                        predecessorID: candidate.id,
                                        type: .finishToStart,
                                        lagDays: 0
                                    )
                                }
                            }
                        }
                        .controlSize(.small)

                        Spacer()

                        Button("Custom…") {
                            activePopover = nil
                            onAddDependency(task.id)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .frame(width: 340)
            }
        case .calendar(let id):
            if let task = viewModel.document.tasks.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Assign Calendar")
                        .font(.callout.weight(.semibold))
                        .padding(.bottom, 2)
                    Button {
                        viewModel.updateTask(task.id, actionName: "Assign Calendar") { t, _ in t.calendarID = nil }
                        activePopover = nil
                    } label: {
                        HStack {
                            Text("Default (Mon–Fri)")
                            Spacer()
                            if task.calendarID == nil { Image(systemName: "checkmark").foregroundStyle(ScheduleTheme.accent) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                    ForEach(viewModel.document.calendars) { cal in
                        Button {
                            viewModel.updateTask(task.id, actionName: "Assign Calendar") { t, _ in t.calendarID = cal.id }
                            activePopover = nil
                        } label: {
                            HStack {
                                Text(cal.owner.isEmpty ? cal.name : "\(cal.name) (\(cal.owner))")
                                Spacer()
                                if task.calendarID == cal.id { Image(systemName: "checkmark").foregroundStyle(ScheduleTheme.accent) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(width: 260)
            }
        }
    }

    @ViewBuilder
    private func calendarCell(for task: ScheduleTask, isGroup: Bool, isSelected: Bool) -> some View {
        if isGroup {
            Text("—")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.4))
        } else {
            let calName = viewModel.document.calendars.first(where: { $0.id == task.calendarID })?.owner
                .nilIfEmpty ?? viewModel.document.calendars.first(where: { $0.id == task.calendarID })?.name
                ?? "Default"
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text(calName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectTask(task.id)
                activePopover = .calendar(task.id)
            }
        }
    }
}

struct VerticalScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TaskReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    let viewModel: ProjectViewModel

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        let rows = viewModel.visibleRows
        guard let fromIdx = rows.firstIndex(where: { $0.id == draggingID }),
              let toIdx = rows.firstIndex(where: { $0.id == targetID }) else { return }
        let dest = toIdx > fromIdx ? toIdx + 1 : toIdx
        viewModel.moveVisibleRows(from: IndexSet(integer: fromIdx), to: dest)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
