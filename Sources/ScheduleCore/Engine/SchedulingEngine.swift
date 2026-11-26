import Foundation

/// Pure-Swift, incremental Critical Path Method (CPM) scheduling engine.
/// Handles FS/SS/FF/SF dependencies, lag/lead, working days, milestones,
/// summary group rollups, and cycle detection.
public enum SchedulingEngine {

    /// Checks whether adding `predecessorID -> successorID` would introduce a cycle.
    public static func wouldCreateCycle(
        tasks: [ScheduleTask],
        predecessorID: UUID,
        successorID: UUID
    ) -> Bool {
        if predecessorID == successorID { return true }
        // A cycle is created if `predecessorID` is reachable from `successorID`
        // following existing predecessor -> successor edges, OR equivalently
        // if `successorID` is already an ancestor of `predecessorID`.
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var visited = Set<UUID>()
        var stack = [predecessorID]
        while let current = stack.popLast() {
            if current == successorID { return true }
            if visited.contains(current) { continue }
            visited.insert(current)
            if let task = taskByID[current] {
                for dep in task.dependencies {
                    stack.append(dep.predecessorID)
                }
            }
        }
        return false
    }

    /// Recalculates the entire project schedule, summary groups, WBS-free metrics, and critical path.
    public static func recalculateAll(
        tasks: [ScheduleTask],
        projectStart: CalendarDay,
        calendar: WorkingCalendar,
        namedCalendars: [NamedWorkingCalendar] = []
    ) -> [ScheduleTask] {
        let allIDs = Set(tasks.map(\.id))
        return recalculateIncremental(
            tasks: tasks,
            changedTaskIDs: allIDs,
            projectStart: projectStart,
            calendar: calendar,
            namedCalendars: namedCalendars
        )
    }

    /// Incrementally recalculates `changedTaskIDs` and their transitive downstream dependents,
    /// then rolls up summary groups and updates critical path metrics.
    public static func recalculateIncremental(
        tasks: [ScheduleTask],
        changedTaskIDs: Set<UUID>,
        projectStart: CalendarDay,
        calendar: WorkingCalendar,
        namedCalendars: [NamedWorkingCalendar] = []
    ) -> [ScheduleTask] {
        guard !tasks.isEmpty else { return [] }

        let calendarLookup = Dictionary(uniqueKeysWithValues: namedCalendars.map { ($0.id, $0.workingCalendar) })
        func effectiveCalendar(for task: ScheduleTask) -> WorkingCalendar {
            if let cid = task.calendarID, let custom = calendarLookup[cid] {
                return custom
            }
            return calendar
        }

        var taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let orderedIDs = tasks.map(\.id)

        // Build parent -> children map to identify summary groups.
        var childrenMap: [UUID: [UUID]] = [:]
        for task in tasks {
            if let parentID = task.parentID, taskMap[parentID] != nil {
                childrenMap[parentID, default: []].append(task.id)
            }
        }

        // Build predecessor -> successors adjacency list.
        var successorsMap: [UUID: [UUID]] = [:]
        for task in tasks {
            for dep in task.dependencies where taskMap[dep.predecessorID] != nil {
                successorsMap[dep.predecessorID, default: []].append(task.id)
            }
        }

        // Find transitive closure of affected tasks starting from `changedTaskIDs`.
        var affected = Set<UUID>()
        var queue = Array(changedTaskIDs)
        while let current = queue.popLast() {
            guard !affected.contains(current) else { continue }
            affected.insert(current)
            for succ in successorsMap[current] ?? [] {
                if !affected.contains(succ) {
                    queue.append(succ)
                }
            }
        }

        // Topological sort of leaf/non-group tasks (groups are rolled up bottom-up).
        let topoOrder = topologicalOrder(ids: orderedIDs, taskMap: taskMap)
        let snappedProjectStart = calendar.snapToWorkingDay(projectStart, forward: true)

        // Forward pass on affected non-summary tasks.
        for id in topoOrder {
            guard affected.contains(id), var task = taskMap[id] else { continue }
            // Skip summary groups during forward pass; they roll up from children.
            if let children = childrenMap[id], !children.isEmpty {
                continue
            }

            let taskCal = effectiveCalendar(for: task)
            let duration = task.isMilestone ? 0 : max(1, task.durationDays)
            task.durationDays = duration

            var constrainedStart: CalendarDay
            if task.isManuallyScheduled {
                constrainedStart = taskCal.snapToWorkingDay(task.startDate, forward: true)
            } else if task.dependencies.isEmpty {
                constrainedStart = max(snappedProjectStart, taskCal.snapToWorkingDay(task.startDate, forward: true))
            } else {
                constrainedStart = snappedProjectStart
            }

            for dep in task.dependencies {
                guard let pred = taskMap[dep.predecessorID] else { continue }
                let depStart = earliestStart(
                    for: task,
                    duration: duration,
                    dependingOn: pred,
                    dependency: dep,
                    calendar: taskCal
                )
                if depStart > constrainedStart {
                    constrainedStart = depStart
                }
            }

            constrainedStart = taskCal.snapToWorkingDay(constrainedStart, forward: true)
            task.startDate = constrainedStart
            task.endDate = task.isMilestone
                ? constrainedStart
                : taskCal.endDate(startingOn: constrainedStart, durationDays: duration)

            taskMap[id] = task
        }

        // Bottom-up roll-up for summary groups (deepest groups first).
        let groupDepths = computeDepths(orderedIDs: orderedIDs, taskMap: taskMap)
        let groupsByDepthDesc = orderedIDs
            .filter { !(childrenMap[$0]?.isEmpty ?? true) }
            .sorted { (groupDepths[$0] ?? 0) > (groupDepths[$1] ?? 0) }

        for groupID in groupsByDepthDesc {
            guard var group = taskMap[groupID],
                  let childIDs = childrenMap[groupID],
                  !childIDs.isEmpty else { continue }
            let children = childIDs.compactMap { taskMap[$0] }
            guard let minStart = children.map(\.startDate).min(),
                  let maxEnd = children.map(\.endDate).max() else { continue }

            group.isMilestone = false
            group.startDate = minStart
            group.endDate = maxEnd
            group.durationDays = calendar.workingDuration(from: minStart, to: maxEnd)

            let totalWeight = children.reduce(0.0) { $0 + Double(max(1, $1.durationDays)) }
            let weightedProgress = children.reduce(0.0) { $0 + ($1.percentComplete * Double(max(1, $1.durationDays))) }
            group.percentComplete = totalWeight > 0 ? (weightedProgress / totalWeight) : 0

            taskMap[groupID] = group
        }

        // Critical Path Method (backward pass) across leaf tasks.
        updateCriticalPath(
            orderedIDs: orderedIDs,
            topoOrder: topoOrder,
            childrenMap: childrenMap,
            groupsByDepthDesc: groupsByDepthDesc,
            taskMap: &taskMap,
            defaultCalendar: calendar,
            calendarLookup: calendarLookup
        )

        return orderedIDs.compactMap { taskMap[$0] }
    }

    // MARK: - Private Helpers

    private static func earliestStart(
        for successor: ScheduleTask,
        duration: Int,
        dependingOn predecessor: ScheduleTask,
        dependency: TaskDependency,
        calendar: WorkingCalendar
    ) -> CalendarDay {
        let lag = dependency.lagDays
        switch dependency.type {
        case .finishToStart:
            let baseOffset = predecessor.isMilestone ? lag : (1 + lag)
            let raw = calendar.addWorkingDays(baseOffset, to: predecessor.endDate)
            return calendar.snapToWorkingDay(raw, forward: true)

        case .startToStart:
            let raw = calendar.addWorkingDays(lag, to: predecessor.startDate)
            return calendar.snapToWorkingDay(raw, forward: true)

        case .finishToFinish:
            let targetEnd = calendar.snapToWorkingDay(calendar.addWorkingDays(lag, to: predecessor.endDate), forward: false)
            if successor.isMilestone {
                return targetEnd
            }
            return calendar.startDate(endingOn: targetEnd, durationDays: duration)

        case .startToFinish:
            let targetEnd = calendar.snapToWorkingDay(calendar.addWorkingDays(lag, to: predecessor.startDate), forward: false)
            if successor.isMilestone {
                return targetEnd
            }
            return calendar.startDate(endingOn: targetEnd, durationDays: duration)
        }
    }

    private static func topologicalOrder(
        ids: [UUID],
        taskMap: [UUID: ScheduleTask]
    ) -> [UUID] {
        var inDegree: [UUID: Int] = [:]
        var dependents: [UUID: [UUID]] = [:]

        for id in ids {
            inDegree[id] = 0
        }
        for id in ids {
            guard let task = taskMap[id] else { continue }
            for dep in task.dependencies where taskMap[dep.predecessorID] != nil {
                inDegree[id, default: 0] += 1
                dependents[dep.predecessorID, default: []].append(id)
            }
        }

        var queue = ids.filter { (inDegree[$0] ?? 0) == 0 }
        var result: [UUID] = []
        var visited = Set<UUID>()

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if visited.contains(current) { continue }
            visited.insert(current)
            result.append(current)

            for next in dependents[current] ?? [] {
                inDegree[next, default: 0] -= 1
                if (inDegree[next] ?? 0) <= 0 {
                    queue.append(next)
                }
            }
        }

        // Append any remaining tasks (in case of malformed external data with cycles).
        for id in ids where !visited.contains(id) {
            result.append(id)
        }
        return result
    }

    private static func computeDepths(
        orderedIDs: [UUID],
        taskMap: [UUID: ScheduleTask]
    ) -> [UUID: Int] {
        var depths: [UUID: Int] = [:]
        for id in orderedIDs {
            var depth = 0
            var current = taskMap[id]?.parentID
            var guardCount = 0
            while let pid = current, let parent = taskMap[pid], guardCount < 64 {
                depth += 1
                current = parent.parentID
                guardCount += 1
            }
            depths[id] = depth
        }
        return depths
    }

    private static func updateCriticalPath(
        orderedIDs: [UUID],
        topoOrder: [UUID],
        childrenMap: [UUID: [UUID]],
        groupsByDepthDesc: [UUID],
        taskMap: inout [UUID: ScheduleTask],
        defaultCalendar: WorkingCalendar,
        calendarLookup: [UUID: WorkingCalendar]
    ) {
        func effectiveCal(for task: ScheduleTask) -> WorkingCalendar {
            if let cid = task.calendarID, let custom = calendarLookup[cid] {
                return custom
            }
            return defaultCalendar
        }

        let leafIDs = orderedIDs.filter { childrenMap[$0]?.isEmpty ?? true }
        guard let projectEnd = leafIDs.compactMap({ taskMap[$0]?.endDate }).max() else { return }

        // Build successor edges for leaf tasks.
        var outgoing: [UUID: [(successorID: UUID, dep: TaskDependency)]] = [:]
        for id in orderedIDs {
            guard let task = taskMap[id] else { continue }
            for dep in task.dependencies where taskMap[dep.predecessorID] != nil {
                outgoing[dep.predecessorID, default: []].append((id, dep))
            }
        }

        var lateStart: [UUID: CalendarDay] = [:]
        var lateEnd: [UUID: CalendarDay] = [:]

        for id in topoOrder.reversed() {
            guard let task = taskMap[id] else { continue }
            if !(childrenMap[id]?.isEmpty ?? true) { continue }

            let taskCal = effectiveCal(for: task)
            let duration = task.isMilestone ? 0 : max(1, task.durationDays)
            let succs = outgoing[id] ?? []

            var lEnd = projectEnd
            if !succs.isEmpty {
                for (succID, dep) in succs {
                    guard taskMap[succID] != nil,
                          let sLS = lateStart[succID],
                          let sLE = lateEnd[succID] else { continue }

                    let candidateEnd: CalendarDay
                    switch dep.type {
                    case .finishToStart:
                        let offset = task.isMilestone ? -dep.lagDays : -(1 + dep.lagDays)
                        candidateEnd = taskCal.snapToWorkingDay(taskCal.addWorkingDays(offset, to: sLS), forward: false)
                    case .startToStart:
                        let candidateStart = taskCal.snapToWorkingDay(taskCal.addWorkingDays(-dep.lagDays, to: sLS), forward: false)
                        candidateEnd = task.isMilestone ? candidateStart : taskCal.endDate(startingOn: candidateStart, durationDays: duration)
                    case .finishToFinish:
                        candidateEnd = taskCal.snapToWorkingDay(taskCal.addWorkingDays(-dep.lagDays, to: sLE), forward: false)
                    case .startToFinish:
                        let candidateStart = taskCal.snapToWorkingDay(taskCal.addWorkingDays(-dep.lagDays, to: sLE), forward: false)
                        candidateEnd = task.isMilestone ? candidateStart : taskCal.endDate(startingOn: candidateStart, durationDays: duration)
                    }
                    if candidateEnd < lEnd {
                        lEnd = candidateEnd
                    }
                }
            }

            let lStart = task.isMilestone
                ? lEnd
                : taskCal.startDate(endingOn: lEnd, durationDays: duration)

            lateEnd[id] = lEnd
            lateStart[id] = lStart

            let slack: Int
            if lStart >= task.startDate {
                slack = taskCal.workingDuration(from: task.startDate, to: lStart) - 1
            } else {
                slack = -(taskCal.workingDuration(from: lStart, to: task.startDate) - 1)
            }

            var updated = task
            updated.totalSlackDays = slack
            updated.isCritical = slack <= 0
            taskMap[id] = updated
        }

        // Propagate criticality to summary groups.
        for groupID in groupsByDepthDesc {
            guard var group = taskMap[groupID],
                  let childIDs = childrenMap[groupID] else { continue }
            let children = childIDs.compactMap { taskMap[$0] }
            group.isCritical = children.contains { $0.isCritical }
            group.totalSlackDays = children.map(\.totalSlackDays).min() ?? 0
            taskMap[groupID] = group
        }
    }
}
