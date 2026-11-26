import SwiftUI
import ScheduleCore

struct GanttChartView: View {
    @Bindable var viewModel: ProjectViewModel
    let scrollSync: ScrollSyncState

    @State private var dragState: BarDragState?
    @State private var linkDrag: LinkDragState?
    @State private var hoveredTaskID: UUID?
    @State private var viewportHeight: CGFloat = 600

    private static let weekMonthDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df
    }()

    private static let monthYearFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return df
    }()

    private struct LinkDragState {
        let sourceTaskID: UUID
        let startPoint: CGPoint
        var currentPoint: CGPoint
    }

    private struct BarDragState {
        let taskID: UUID
        let mode: Mode
        var dayDelta: Int = 0

        enum Mode {
            case move
            case resizeDuration
        }
    }

    private var dayWidth: CGFloat { viewModel.dayWidth }
    private let rowHeight: CGFloat = TaskListView.rowHeight
    private let headerHeight: CGFloat = TaskListView.headerHeight

    private var timelineBounds: (start: CalendarDay, totalDays: Int) {
        let tasks = viewModel.document.tasks
        let minDay = (tasks.map(\.startDate).min() ?? viewModel.document.projectStartDate).addingCalendarDays(-5)
        let maxDay = (tasks.map(\.endDate).max() ?? viewModel.document.projectStartDate.addingCalendarDays(20)).addingCalendarDays(21)
        let total = max(35, minDay.calendarDays(until: maxDay) + 1)
        return (minDay, total)
    }

    var body: some View {
        let bounds = timelineBounds
        let totalWidth = CGFloat(bounds.totalDays) * dayWidth
        let rows = viewModel.visibleRows
        let totalHeight = max(viewportHeight - headerHeight - 1, CGFloat(rows.count) * rowHeight)

        VStack(spacing: 0) {
            ganttControlsBar
            Divider()
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    timelineHeader(start: bounds.start, totalDays: bounds.totalDays)
                        .frame(width: totalWidth, height: headerHeight)
                    Divider()

                    ScrollView(.vertical) {
                        ZStack(alignment: .topLeading) {
                            ganttCanvas(
                                rows: rows,
                                start: bounds.start,
                                totalDays: bounds.totalDays,
                                width: totalWidth,
                                height: totalHeight
                            )
                            .frame(width: totalWidth, height: totalHeight)

                            interactiveOverlay(rows: rows, timelineStart: bounds.start)
                                .frame(width: totalWidth, height: totalHeight)
                        }
                        .background(ScrollSyncAnchor(pane: .gantt, state: scrollSync))
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.size.height
            } action: { _, newHeight in
                if abs(viewportHeight - newHeight) > 0.5 {
                    viewportHeight = newHeight
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Controls Bar

    private var ganttControlsBar: some View {
        HStack(spacing: 16) {
            Picker("Scale", selection: $viewModel.timeScale) {
                ForEach(GanttTimeScale.allCases) { scale in
                    Text(scale.rawValue).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
            .onChange(of: viewModel.timeScale) { _, newScale in
                viewModel.dayWidth = newScale.defaultDayWidth
            }

            Toggle("Critical Path", isOn: $viewModel.showCriticalPath)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.callout)

            Spacer()

            HStack(spacing: 4) {
                Button {
                    viewModel.dayWidth = max(3, viewModel.dayWidth * 0.8)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom Out")

                Button {
                    viewModel.dayWidth = min(64, viewModel.dayWidth * 1.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom In")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: TaskListView.topBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Timeline Header

    private func timelineHeader(start: CalendarDay, totalDays: Int) -> some View {
        Canvas { context, size in
            let cal = Calendar.gregorianUTC
            let today = CalendarDay.today

            for offset in 0..<totalDays {
                let day = start.addingCalendarDays(offset)
                let x = CGFloat(offset) * dayWidth
                let date = day.toDate(calendar: cal)
                let weekday = day.weekday

                // Weekend header tint
                if !viewModel.document.workingCalendar.isWorkingDay(day) {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(Color.secondary.opacity(0.06))
                    )
                }

                // Today highlight
                if day == today {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(Color.red.opacity(0.12))
                    )
                }

                let showLabel: Bool
                let labelText: String
                switch viewModel.timeScale {
                case .days:
                    showLabel = true
                    if day.day == 1 {
                        labelText = Self.weekMonthDayFormatter.string(from: date)
                    } else {
                        labelText = "\(day.day)"
                    }
                case .weeks:
                    showLabel = (weekday == 2) // Mondays
                    labelText = Self.weekMonthDayFormatter.string(from: date)
                case .months:
                    showLabel = (day.day == 1)
                    labelText = Self.monthYearFormatter.string(from: date)
                case .quarters:
                    showLabel = (day.day == 1 && (day.month == 1 || day.month == 4 || day.month == 7 || day.month == 10))
                    let q = ((day.month - 1) / 3) + 1
                    labelText = "Q\(q) \(day.year)"
                }

                if showLabel {
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 0))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(tick, with: .color(Color.secondary.opacity(0.22)), lineWidth: 0.5)

                    let text = Text(labelText)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(day == today ? .red : .secondary)
                    context.draw(text, at: CGPoint(x: x + 4, y: size.height / 2), anchor: .leading)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Gantt Canvas (Grid, Today, Connectors, Bars)

    private func ganttCanvas(
        rows: [VisibleTaskRow],
        start: CalendarDay,
        totalDays: Int,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        Canvas { context, size in
            let cal = viewModel.document.workingCalendar
            let today = CalendarDay.today

            // 1. Vertical grid lines & weekend shading
            for offset in 0..<totalDays {
                let day = start.addingCalendarDays(offset)
                let x = CGFloat(offset) * dayWidth
                if !cal.isWorkingDay(day) {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(Color.secondary.opacity(0.045))
                    )
                }
                if viewModel.timeScale == .days || day.weekday == 2 || day.day == 1 {
                    var gridLine = Path()
                    gridLine.move(to: CGPoint(x: x, y: 0))
                    gridLine.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(gridLine, with: .color(Color.secondary.opacity(0.10)), lineWidth: 0.5)
                }
            }

            // 2. Horizontal row dividers & selection highlight
            var rowIndexByID: [UUID: Int] = [:]
            for (idx, row) in rows.enumerated() {
                rowIndexByID[row.id] = idx
                let y = CGFloat(idx) * rowHeight
                if viewModel.selectedTaskID == row.id {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)),
                        with: .color(ScheduleTheme.accent.opacity(0.09))
                    )
                } else if row.isGroup {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)),
                        with: .color(Color.secondary.opacity(0.035))
                    )
                }
                var hLine = Path()
                hLine.move(to: CGPoint(x: 0, y: y + rowHeight))
                hLine.addLine(to: CGPoint(x: size.width, y: y + rowHeight))
                context.stroke(hLine, with: .color(Color.secondary.opacity(0.12)), lineWidth: 0.5)
            }

            // 3. Today vertical hairline
            let todayOffset = start.calendarDays(until: today)
            if todayOffset >= 0 && todayOffset < totalDays {
                let todayX = (CGFloat(todayOffset) + 0.5) * dayWidth
                var todayLine = Path()
                todayLine.move(to: CGPoint(x: todayX, y: 0))
                todayLine.addLine(to: CGPoint(x: todayX, y: size.height))
                context.stroke(todayLine, with: .color(Color.red.opacity(0.7)), lineWidth: 1.2)
            }

            // 4. Dependency connectors
            for (succIdx, row) in rows.enumerated() {
                let succ = row.task
                for dep in succ.dependencies {
                    guard let predIdx = rowIndexByID[dep.predecessorID] else { continue }
                    let pred = rows[predIdx].task

                    let predRect = barRect(for: pred, rowIndex: predIdx, timelineStart: start)
                    let succRect = barRect(for: succ, rowIndex: succIdx, timelineStart: start)

                    let startPt: CGPoint
                    switch dep.type {
                    case .finishToStart, .finishToFinish:
                        startPt = CGPoint(x: predRect.maxX, y: predRect.midY)
                    case .startToStart, .startToFinish:
                        startPt = CGPoint(x: predRect.minX, y: predRect.midY)
                    }

                    let endPt: CGPoint
                    switch dep.type {
                    case .finishToStart, .startToStart:
                        endPt = CGPoint(x: succRect.minX, y: succRect.midY)
                    case .finishToFinish, .startToFinish:
                        endPt = CGPoint(x: succRect.maxX, y: succRect.midY)
                    }

                    drawConnector(context: &context, from: startPt, to: endPt)
                }
            }

            // 5. Task bars & milestones
            for (idx, row) in rows.enumerated() {
                let task = row.task
                let rect = barRect(for: task, rowIndex: idx, timelineStart: start)
                let isCritical = viewModel.showCriticalPath && task.isCritical
                let isSelected = viewModel.selectedTaskID == task.id

                if task.isMilestone {
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    // Subtle dashed gate line across the milestone row
                    var gateLine = Path()
                    gateLine.move(to: CGPoint(x: center.x, y: CGFloat(idx) * rowHeight))
                    gateLine.addLine(to: CGPoint(x: center.x, y: CGFloat(idx + 1) * rowHeight))
                    context.stroke(
                        gateLine,
                        with: .color((isCritical ? Color.red : ScheduleTheme.accent).opacity(0.35)),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )

                    let r: CGFloat = 8.5
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: center.x, y: center.y - r))
                    diamond.addLine(to: CGPoint(x: center.x + r, y: center.y))
                    diamond.addLine(to: CGPoint(x: center.x, y: center.y + r))
                    diamond.addLine(to: CGPoint(x: center.x - r, y: center.y))
                    diamond.closeSubpath()

                    let fill: Color = isCritical ? .red : ScheduleTheme.accent
                    context.fill(diamond, with: .color(fill))
                    context.stroke(diamond, with: .color(isSelected ? Color.primary : Color.white.opacity(0.8)), lineWidth: isSelected ? 2.0 : 1.0)

                    let label = Text(task.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isCritical ? .red : ScheduleTheme.accent)
                    context.draw(label, at: CGPoint(x: center.x + r + 8, y: center.y), anchor: .leading)
                } else if row.isGroup {
                    // Summary group bracket bar
                    let barRect = CGRect(x: rect.minX, y: rect.minY + 4, width: rect.width, height: 6)
                    let path = Path(roundedRect: barRect, cornerRadius: 3)
                    context.fill(path, with: .color(Color.primary.opacity(0.65)))

                    let label = Text("\(task.identifier)  \(task.title)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    context.draw(label, at: CGPoint(x: rect.maxX + 8, y: rect.midY), anchor: .leading)
                } else {
                    let barShape = Path(roundedRect: rect, cornerRadius: 5)
                    let baseColor: Color = isCritical ? Color.red.opacity(0.85) : ScheduleTheme.accent.opacity(0.85)
                    context.fill(barShape, with: .color(baseColor.opacity(0.28)))

                    if task.percentComplete > 0 {
                        let fillWidth = rect.width * CGFloat(min(100, max(0, task.percentComplete)) / 100.0)
                        let progressRect = CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
                        context.drawLayer { layer in
                            layer.clip(to: barShape)
                            layer.fill(Path(progressRect), with: .color(baseColor))
                        }
                    }

                    context.stroke(
                        barShape,
                        with: .color(isSelected ? Color.primary : baseColor),
                        lineWidth: isSelected ? 1.5 : 0.75
                    )

                    let label = Text("\(task.identifier)  \(task.title)")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                    context.draw(label, at: CGPoint(x: rect.maxX + 8, y: rect.midY), anchor: .leading)
                }
            }
        }
    }

    private func barRect(for task: ScheduleTask, rowIndex: Int, timelineStart: CalendarDay) -> CGRect {
        var effectiveStart = task.startDate
        var effectiveDuration = task.durationDays
        if let drag = dragState, drag.taskID == task.id {
            switch drag.mode {
            case .move:
                effectiveStart = task.startDate.addingCalendarDays(drag.dayDelta)
            case .resizeDuration:
                effectiveDuration = max(1, task.durationDays + drag.dayDelta)
            }
        }

        let startOffset = timelineStart.calendarDays(until: effectiveStart)
        let spanDays: Int
        if task.isMilestone {
            spanDays = 1
        } else if let drag = dragState, drag.taskID == task.id, drag.mode == .resizeDuration {
            let end = viewModel.document.workingCalendar.endDate(startingOn: effectiveStart, durationDays: effectiveDuration)
            spanDays = max(1, effectiveStart.calendarDays(until: end) + 1)
        } else {
            let end = dragState?.taskID == task.id
                ? effectiveStart.addingCalendarDays(task.startDate.calendarDays(until: task.endDate))
                : task.endDate
            spanDays = max(1, effectiveStart.calendarDays(until: end) + 1)
        }

        let x = CGFloat(startOffset) * dayWidth
        let width = task.isMilestone ? dayWidth : max(dayWidth * 0.75, CGFloat(spanDays) * dayWidth)
        let y = CGFloat(rowIndex) * rowHeight + 8
        return CGRect(x: x, y: y, width: width, height: rowHeight - 16)
    }

    private func drawConnector(context: inout GraphicsContext, from start: CGPoint, to end: CGPoint) {
        let elbowX = start.x + 8
        var path = Path()
        path.move(to: start)
        if end.x >= elbowX + 6 {
            let midX = (start.x + end.x) / 2
            path.addLine(to: CGPoint(x: midX, y: start.y))
            path.addLine(to: CGPoint(x: midX, y: end.y))
            path.addLine(to: end)
        } else {
            let midY = (start.y + end.y) / 2
            path.addLine(to: CGPoint(x: elbowX, y: start.y))
            path.addLine(to: CGPoint(x: elbowX, y: midY))
            path.addLine(to: CGPoint(x: end.x - 10, y: midY))
            path.addLine(to: CGPoint(x: end.x - 10, y: end.y))
            path.addLine(to: end)
        }
        context.stroke(path, with: .color(Color.secondary.opacity(0.55)), lineWidth: 1.1)

        // Small arrowhead
        var arrow = Path()
        arrow.move(to: end)
        arrow.addLine(to: CGPoint(x: end.x - 5, y: end.y - 3))
        arrow.addLine(to: CGPoint(x: end.x - 5, y: end.y + 3))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(Color.secondary.opacity(0.65)))
    }

    // MARK: - Interactive Gesture Overlay

    private func interactiveOverlay(rows: [VisibleTaskRow], timelineStart: CalendarDay) -> some View {
        let activeHandleRow: (index: Int, row: VisibleTaskRow, rect: CGRect)? = {
            let targetID = linkDrag?.sourceTaskID ?? hoveredTaskID ?? viewModel.selectedTaskID
            guard let targetID,
                  let idx = rows.firstIndex(where: { $0.id == targetID }),
                  !rows[idx].isGroup else { return nil }
            let row = rows[idx]
            return (idx, row, barRect(for: row.task, rowIndex: idx, timelineStart: timelineStart))
        }()

        return ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            let idx = Int(floor(value.location.y / rowHeight))
                            if idx >= 0 && idx < rows.count {
                                viewModel.selectTask(rows[idx].id)
                            }
                        }
                )
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            let rowIdx = Int(floor(value.startLocation.y / rowHeight))
                            guard rowIdx >= 0 && rowIdx < rows.count else { return }
                            let row = rows[rowIdx]
                            guard !row.isGroup else { return }

                            if let existing = dragState, existing.taskID == row.id {
                                let deltaDays = Int(round(value.translation.width / dayWidth))
                                dragState = BarDragState(taskID: row.id, mode: existing.mode, dayDelta: deltaDays)
                            } else {
                                let rect = barRect(for: row.task, rowIndex: rowIdx, timelineStart: timelineStart)
                                guard value.startLocation.x >= rect.minX - 6 && value.startLocation.x <= rect.maxX + 6 else { return }
                                let deltaDays = Int(round(value.translation.width / dayWidth))
                                let isResize = !row.task.isMilestone && value.startLocation.x > max(rect.minX + 12, rect.maxX - 10)
                                dragState = BarDragState(
                                    taskID: row.id,
                                    mode: isResize ? .resizeDuration : .move,
                                    dayDelta: deltaDays
                                )
                            }
                        }
                        .onEnded { value in
                            guard let currentDrag = dragState else { return }
                            dragState = nil
                            let deltaDays = Int(round(value.translation.width / dayWidth))
                            guard deltaDays != 0 else { return }

                            switch currentDrag.mode {
                            case .move:
                                viewModel.updateTask(currentDrag.taskID, actionName: "Reschedule Task") { task, cal in
                                    let shifted = cal.snapToWorkingDay(task.startDate.addingCalendarDays(deltaDays), forward: deltaDays >= 0)
                                    task.startDate = shifted
                                    task.endDate = task.isMilestone ? shifted : cal.endDate(startingOn: shifted, durationDays: task.durationDays)
                                    task.isManuallyScheduled = true
                                }
                            case .resizeDuration:
                                viewModel.updateTask(currentDrag.taskID, actionName: "Resize Duration") { task, cal in
                                    let newDur = max(1, task.durationDays + deltaDays)
                                    task.durationDays = newDur
                                    task.endDate = cal.endDate(startingOn: task.startDate, durationDays: newDur)
                                }
                            }
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let idx = Int(floor(location.y / rowHeight))
                        let nextID = (idx >= 0 && idx < rows.count) ? rows[idx].id : nil
                        if hoveredTaskID != nextID {
                            hoveredTaskID = nextID
                        }
                    case .ended:
                        if hoveredTaskID != nil {
                            hoveredTaskID = nil
                        }
                    }
                }

            // Direct bar-to-bar link handle (only 1 view for the active/hovered task)
            if let active = activeHandleRow {
                let handleX = active.rect.maxX + 8
                let handleY = active.rect.midY
                Circle()
                    .fill(ScheduleTheme.accent)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .offset(x: handleX - 10, y: handleY - 10)
                    .help("Drag to another task to link")
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named("GanttOverlay"))
                            .onChanged { value in
                                linkDrag = LinkDragState(
                                    sourceTaskID: active.row.id,
                                    startPoint: CGPoint(x: active.rect.maxX, y: active.rect.midY),
                                    currentPoint: value.location
                                )
                            }
                            .onEnded { value in
                                let targetRowIndex = Int(floor(value.location.y / rowHeight))
                                if targetRowIndex >= 0 && targetRowIndex < rows.count {
                                    let targetRow = rows[targetRowIndex]
                                    if !targetRow.isGroup && targetRow.id != active.row.id {
                                        viewModel.addDependency(
                                            to: targetRow.id,
                                            predecessorID: active.row.id,
                                            type: .finishToStart,
                                            lagDays: 0
                                        )
                                    }
                                }
                                linkDrag = nil
                            }
                    )
            }

            // Live preview connector line while dragging from a link handle
            if let linkDrag {
                Path { path in
                    path.move(to: linkDrag.startPoint)
                    path.addLine(to: linkDrag.currentPoint)
                }
                .stroke(ScheduleTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "GanttOverlay")
    }
}
