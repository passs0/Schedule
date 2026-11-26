import Foundation
import SwiftUI
import ScheduleCore

public struct VisibleTaskRow: Identifiable, Equatable {
    public var id: UUID { task.id }
    public let task: ScheduleTask
    public let depth: Int
    public let isGroup: Bool
    public let flatIndex: Int
}

public enum GanttTimeScale: String, CaseIterable, Identifiable {
    case days = "Days"
    case weeks = "Weeks"
    case months = "Months"
    case quarters = "Quarters"

    public var id: String { rawValue }

    public var defaultDayWidth: CGFloat {
        switch self {
        case .days: return 34
        case .weeks: return 18
        case .months: return 8
        case .quarters: return 4
        }
    }
}

public enum WorkspaceViewMode: String, CaseIterable, Identifiable {
    case listOnly = "List"
    case split = "Split"
    case ganttOnly = "Gantt"

    public var id: String { rawValue }
}

@MainActor
@Observable
public final class ScrollSyncState {
    public var offsetY: CGFloat = 0
    public init() {}
}

@MainActor
@Observable
public final class ProjectViewModel {
    public var document: ProjectDocument {
        didSet {
            rebuildVisibleRows()
        }
    }
    public private(set) var visibleRows: [VisibleTaskRow] = []
    public var selectedTaskID: UUID?
    public var viewMode: WorkspaceViewMode = .listOnly
    public var timeScale: GanttTimeScale = .days
    public var dayWidth: CGFloat = 34
    public var showCriticalPath: Bool = false
    public var isInspectorPresented: Bool = false
    public var isComparingVersions: Bool = false
    public var cycleWarningMessage: String?
    public var recentlyRescheduledIDs: Set<UUID> = []
    public var lastScheduleSummary: String?

    public weak var undoManager: UndoManager?
    private let onPersist: (ProjectDocument) -> Void

    public init(document: ProjectDocument, onPersist: @escaping (ProjectDocument) -> Void) {
        self.document = document
        self.onPersist = onPersist
        self.selectedTaskID = document.tasks.first?.id
        rebuildVisibleRows()
    }

    public var selectedTask: ScheduleTask? {
        guard let id = selectedTaskID else { return nil }
        return document.tasks.first { $0.id == id }
    }

    private func rebuildVisibleRows() {
        let tasks = document.tasks
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var childrenSet = Set<UUID>()
        for t in tasks {
            if let pid = t.parentID, taskMap[pid] != nil {
                childrenSet.insert(pid)
            }
        }

        func isAncestorCollapsed(_ task: ScheduleTask) -> Bool {
            var cur = task.parentID
            var guardCount = 0
            while let pid = cur, let parent = taskMap[pid], guardCount < 32 {
                if !parent.isExpanded { return true }
                cur = parent.parentID
                guardCount += 1
            }
            return false
        }

        func depth(of task: ScheduleTask) -> Int {
            var d = 0
            var cur = task.parentID
            var guardCount = 0
            while let pid = cur, let parent = taskMap[pid], guardCount < 32 {
                d += 1
                cur = parent.parentID
                guardCount += 1
            }
            return d
        }

        var rows: [VisibleTaskRow] = []
        rows.reserveCapacity(tasks.count)
        for (idx, task) in tasks.enumerated() {
            if isAncestorCollapsed(task) { continue }
            rows.append(VisibleTaskRow(
                task: task,
                depth: depth(of: task),
                isGroup: childrenSet.contains(task.id),
                flatIndex: idx
            ))
        }
        visibleRows = rows
    }

    public func selectTask(_ id: UUID?, openInspectorIfNeeded: Bool = false) {
        selectedTaskID = id
        if openInspectorIfNeeded && id != nil {
            isInspectorPresented = true
        }
    }

    // MARK: - Task Mutations with Undo/Redo

    private func applyMutation(actionName: String, changedIDs: Set<UUID>? = nil, _ mutate: (inout ProjectDocument) -> Void) {
        let previous = document
        var next = document
        mutate(&next)
        if let changed = changedIDs, !changed.isEmpty {
            next.tasks = SchedulingEngine.recalculateIncremental(
                tasks: next.tasks,
                changedTaskIDs: changed,
                projectStart: next.projectStartDate,
                calendar: next.workingCalendar,
                namedCalendars: next.calendars
            )
        } else {
            next.tasks = SchedulingEngine.recalculateAll(
                tasks: next.tasks,
                projectStart: next.projectStartDate,
                calendar: next.workingCalendar,
                namedCalendars: next.calendars
            )
        }
        next.modifiedAt = Date()
        commit(newDocument: next, previousDocument: previous, actionName: actionName)
    }

    private func commit(newDocument: ProjectDocument, previousDocument: ProjectDocument, actionName: String) {
        let oldDates = Dictionary(uniqueKeysWithValues: previousDocument.tasks.map { ($0.id, ($0.startDate, $0.endDate)) })
        let movedIDs = Set(newDocument.tasks.compactMap { task -> UUID? in
            guard let old = oldDates[task.id] else { return nil }
            return (old.0 != task.startDate || old.1 != task.endDate) ? task.id : nil
        })

        document = newDocument
        onPersist(newDocument)

        if !movedIDs.isEmpty {
            recentlyRescheduledIDs = movedIDs
            lastScheduleSummary = movedIDs.count == 1
                ? "1 task rescheduled"
                : "\(movedIDs.count) tasks rescheduled"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.2))
                guard let self else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    self.recentlyRescheduledIDs = []
                    self.lastScheduleSummary = nil
                }
            }
        }

        undoManager?.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                target.commit(newDocument: previousDocument, previousDocument: newDocument, actionName: actionName)
            }
        }
        undoManager?.setActionName(actionName)
    }

    public func addTask(after anchorID: UUID? = nil, isMilestone: Bool = false, asSubtask: Bool = false) {
        let newID = UUID()
        applyMutation(actionName: isMilestone ? "New Milestone" : "New Task", changedIDs: [newID]) { doc in
            let anchorIdx = anchorID.flatMap { id in doc.tasks.firstIndex(where: { $0.id == id }) }
            let anchorTask = anchorIdx.map { doc.tasks[$0] }

            let parentID: UUID?
            let startDate: CalendarDay
            if asSubtask, let anchorTask {
                parentID = anchorTask.id
                startDate = anchorTask.startDate
            } else {
                parentID = anchorTask?.parentID
                startDate = anchorTask?.startDate ?? doc.projectStartDate
            }

            let newTask = ScheduleTask(
                id: newID,
                identifier: "\(doc.tasks.count + 1)",
                title: isMilestone ? "New Milestone" : "New Task",
                startDate: startDate,
                durationDays: isMilestone ? 0 : 3,
                isMilestone: isMilestone,
                parentID: parentID,
                calendar: doc.workingCalendar
            )

            if let idx = anchorIdx {
                doc.tasks.insert(newTask, at: idx + 1)
            } else {
                doc.tasks.append(newTask)
            }
            doc.tasks = renumberIdentifiers(in: doc.tasks)
        }
        selectedTaskID = newID
    }

    public func deleteTask(_ id: UUID) {
        applyMutation(actionName: "Delete Task") { doc in
            guard let target = doc.tasks.first(where: { $0.id == id }) else { return }
            // Re-parent direct children to target's parent so subtasks aren't orphaned.
            for i in doc.tasks.indices {
                if doc.tasks[i].parentID == id {
                    doc.tasks[i].parentID = target.parentID
                }
                doc.tasks[i].dependencies.removeAll { $0.predecessorID == id }
            }
            doc.tasks.removeAll { $0.id == id }
            doc.tasks = renumberIdentifiers(in: doc.tasks)
        }
        if selectedTaskID == id {
            selectedTaskID = document.tasks.first?.id
        }
    }

    public func updateTask(_ id: UUID, actionName: String = "Edit Task", _ mutate: (inout ScheduleTask, WorkingCalendar) -> Void) {
        applyMutation(actionName: actionName, changedIDs: [id]) { doc in
            guard let idx = doc.tasks.firstIndex(where: { $0.id == id }) else { return }
            let cal = doc.calendars.first(where: { $0.id == doc.tasks[idx].calendarID })?.workingCalendar ?? doc.workingCalendar
            mutate(&doc.tasks[idx], cal)
        }
    }

    public func upsertCalendar(_ calendar: NamedWorkingCalendar) {
        applyMutation(actionName: "Update Calendar") { doc in
            if let idx = doc.calendars.firstIndex(where: { $0.id == calendar.id }) {
                doc.calendars[idx] = calendar
            } else {
                doc.calendars.append(calendar)
            }
        }
    }

    public func deleteCalendar(_ id: UUID) {
        applyMutation(actionName: "Delete Calendar") { doc in
            doc.calendars.removeAll { $0.id == id }
            for i in doc.tasks.indices where doc.tasks[i].calendarID == id {
                doc.tasks[i].calendarID = nil
            }
        }
    }

    public func toggleExpand(_ id: UUID) {
        guard let idx = document.tasks.firstIndex(where: { $0.id == id }) else { return }
        document.tasks[idx].isExpanded.toggle()
        onPersist(document)
    }

    public func indentTask(_ id: UUID) {
        applyMutation(actionName: "Indent Task") { doc in
            guard let idx = doc.tasks.firstIndex(where: { $0.id == id }), idx > 0 else { return }
            let currentParent = doc.tasks[idx].parentID
            // Find the nearest preceding sibling at the same parent level
            for prevIdx in stride(from: idx - 1, through: 0, by: -1) {
                if doc.tasks[prevIdx].parentID == currentParent {
                    doc.tasks[idx].parentID = doc.tasks[prevIdx].id
                    doc.tasks[prevIdx].isExpanded = true
                    break
                }
            }
            doc.tasks = renumberIdentifiers(in: doc.tasks)
        }
    }

    public func outdentTask(_ id: UUID) {
        applyMutation(actionName: "Outdent Task") { doc in
            guard let idx = doc.tasks.firstIndex(where: { $0.id == id }),
                  let parentID = doc.tasks[idx].parentID,
                  let parent = doc.tasks.first(where: { $0.id == parentID }) else { return }
            doc.tasks[idx].parentID = parent.parentID
            doc.tasks = renumberIdentifiers(in: doc.tasks)
        }
    }

    public func moveVisibleRows(from sourceOffsets: IndexSet, to destinationOffset: Int) {
        let visible = visibleRows
        guard let firstSource = sourceOffsets.first,
              firstSource < visible.count else { return }
        let movingID = visible[firstSource].id
        let destFlatIndex: Int
        if destinationOffset >= visible.count {
            destFlatIndex = document.tasks.count
        } else {
            destFlatIndex = visible[destinationOffset].flatIndex
        }

        applyMutation(actionName: "Reorder Tasks") { doc in
            guard doc.tasks.contains(where: { $0.id == movingID }) else { return }
            // Collect movingID and all of its descendants so groups move as a unit.
            var subtreeIDs: Set<UUID> = [movingID]
            var added = true
            while added {
                added = false
                for t in doc.tasks where !subtreeIDs.contains(t.id) {
                    if let pid = t.parentID, subtreeIDs.contains(pid) {
                        subtreeIDs.insert(t.id)
                        added = true
                    }
                }
            }
            if let destTaskID = destFlatIndex < doc.tasks.count ? doc.tasks[destFlatIndex].id : nil,
               subtreeIDs.contains(destTaskID) {
                return
            }

            let movingBlock = doc.tasks.filter { subtreeIDs.contains($0.id) }
            let targetAnchorID = destFlatIndex < doc.tasks.count ? doc.tasks[destFlatIndex].id : nil
            doc.tasks.removeAll { subtreeIDs.contains($0.id) }
            let insertIdx = targetAnchorID.flatMap { aid in doc.tasks.firstIndex(where: { $0.id == aid }) } ?? doc.tasks.count
            doc.tasks.insert(contentsOf: movingBlock, at: insertIdx)
            doc.tasks = renumberIdentifiers(in: doc.tasks)
        }
    }

    public func setProjectStartDate(_ newStart: CalendarDay) {
        applyMutation(actionName: "Change Project Start") { doc in
            doc.projectStartDate = doc.workingCalendar.snapToWorkingDay(newStart, forward: true)
        }
    }

    @discardableResult
    public func addDependency(to successorID: UUID, predecessorID: UUID, type: DependencyType, lagDays: Int) -> Bool {
        if SchedulingEngine.wouldCreateCycle(tasks: document.tasks, predecessorID: predecessorID, successorID: successorID) {
            cycleWarningMessage = "Cannot add this relationship because it would create a circular dependency loop."
            return false
        }
        cycleWarningMessage = nil
        applyMutation(actionName: "Add Dependency", changedIDs: [successorID]) { doc in
            guard let idx = doc.tasks.firstIndex(where: { $0.id == successorID }) else { return }
            doc.tasks[idx].dependencies.removeAll { $0.predecessorID == predecessorID }
            doc.tasks[idx].dependencies.append(TaskDependency(predecessorID: predecessorID, type: type, lagDays: lagDays))
        }
        return true
    }

    public func removeDependency(from taskID: UUID, dependencyID: UUID) {
        applyMutation(actionName: "Remove Dependency", changedIDs: [taskID]) { doc in
            guard let idx = doc.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            doc.tasks[idx].dependencies.removeAll { $0.id == dependencyID }
        }
    }

    public func previousLinkableTask(before taskID: UUID) -> ScheduleTask? {
        let rows = visibleRows
        guard let idx = rows.firstIndex(where: { $0.id == taskID }), idx > 0 else { return nil }
        for prev in stride(from: idx - 1, through: 0, by: -1) {
            if !rows[prev].isGroup {
                return rows[prev].task
            }
        }
        return nil
    }

    @discardableResult
    public func linkToPreviousTask(_ taskID: UUID) -> Bool {
        guard let prev = previousLinkableTask(before: taskID) else { return false }
        return addDependency(to: taskID, predecessorID: prev.id, type: .finishToStart, lagDays: 0)
    }

    public func saveSnapshot(name: String, notes: String = "") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionName = trimmed.isEmpty ? "Snapshot \(document.versions.count + 1)" : trimmed
        let snapshot = ProjectVersion(name: versionName, notes: notes, tasks: document.tasks)
        document.versions.append(snapshot)
        document.modifiedAt = Date()
        onPersist(document)
    }

    public func renameProject(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != document.name else { return }
        document.name = trimmed
        document.modifiedAt = Date()
        onPersist(document)
    }

    private func renumberIdentifiers(in tasks: [ScheduleTask]) -> [ScheduleTask] {
        var result = tasks
        var counters: [UUID?: Int] = [:]
        var idByUUID: [UUID: String] = [:]

        for i in result.indices {
            let pid = result[i].parentID
            let nextNum = (counters[pid] ?? 0) + 1
            counters[pid] = nextNum
            if let pid, let parentCode = idByUUID[pid] {
                let code = "\(parentCode).\(nextNum)"
                result[i].identifier = code
                idByUUID[result[i].id] = code
            } else {
                let code = "\(nextNum)"
                result[i].identifier = code
                idByUUID[result[i].id] = code
            }
        }
        return result
    }
}
