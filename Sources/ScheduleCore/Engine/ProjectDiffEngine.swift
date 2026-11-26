import Foundation

/// Field-level difference detected between two versions of the same task.
public enum TaskFieldChange: Equatable, Hashable, Sendable {
    case title(old: String, new: String)
    case startDate(old: CalendarDay, new: CalendarDay)
    case endDate(old: CalendarDay, new: CalendarDay)
    case duration(old: Int, new: Int)
    case progress(old: Double, new: Double)
    case dependenciesChanged
    case milestoneChanged(old: Bool, new: Bool)
    case hierarchyChanged

    public var summaryLabel: String {
        switch self {
        case .title:
            return "Renamed"
        case .startDate(let old, let new):
            let delta = old.calendarDays(until: new)
            return delta >= 0 ? "Start +\(delta)d" : "Start \(delta)d"
        case .endDate(let old, let new):
            let delta = old.calendarDays(until: new)
            return delta >= 0 ? "End +\(delta)d" : "End \(delta)d"
        case .duration(let old, let new):
            let delta = new - old
            return delta >= 0 ? "Duration +\(delta)d" : "Duration \(delta)d"
        case .progress(let old, let new):
            return String(format: "Progress %.0f%% → %.0f%%", old, new)
        case .dependenciesChanged:
            return "Dependencies changed"
        case .milestoneChanged(_, let new):
            return new ? "Converted to Milestone" : "Converted to Task"
        case .hierarchyChanged:
            return "Moved in hierarchy"
        }
    }
}

public enum TaskDiffKind: Equatable, Hashable, Sendable {
    case unchanged
    case added
    case deleted
    case modified([TaskFieldChange])
}

public struct TaskDiffRow: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var leftTask: ScheduleTask?
    public var rightTask: ScheduleTask?
    public var kind: TaskDiffKind

    public var displayTitle: String {
        rightTask?.title ?? leftTask?.title ?? ""
    }

    public var displayIdentifier: String {
        rightTask?.identifier ?? leftTask?.identifier ?? ""
    }
}

public struct ProjectComparisonResult: Equatable, Sendable {
    public var rows: [TaskDiffRow]
    public var addedCount: Int
    public var deletedCount: Int
    public var modifiedCount: Int
    public var leftFinishDate: CalendarDay?
    public var rightFinishDate: CalendarDay?

    public var finishDateDeltaDays: Int? {
        guard let left = leftFinishDate, let right = rightFinishDate else { return nil }
        return left.calendarDays(until: right)
    }
}

/// Compares two project task lists and produces a structured diff for side-by-side comparison.
public enum ProjectDiffEngine {
    public static func compare(
        baseline: [ScheduleTask],
        revised: [ScheduleTask]
    ) -> ProjectComparisonResult {
        let leftMap = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })

        var rows: [TaskDiffRow] = []
        var seenIDs = Set<UUID>()
        var addedCount = 0
        var deletedCount = 0
        var modifiedCount = 0

        // Preserve revised order first, inserting deleted baseline tasks near their original neighbors.
        for rightTask in revised {
            seenIDs.insert(rightTask.id)
            if let leftTask = leftMap[rightTask.id] {
                let changes = diffFields(left: leftTask, right: rightTask)
                if changes.isEmpty {
                    rows.append(TaskDiffRow(id: rightTask.id, leftTask: leftTask, rightTask: rightTask, kind: .unchanged))
                } else {
                    modifiedCount += 1
                    rows.append(TaskDiffRow(id: rightTask.id, leftTask: leftTask, rightTask: rightTask, kind: .modified(changes)))
                }
            } else {
                addedCount += 1
                rows.append(TaskDiffRow(id: rightTask.id, leftTask: nil, rightTask: rightTask, kind: .added))
            }
        }

        // Append tasks that were deleted from baseline.
        for (index, leftTask) in baseline.enumerated() where !seenIDs.contains(leftTask.id) {
            deletedCount += 1
            let row = TaskDiffRow(id: leftTask.id, leftTask: leftTask, rightTask: nil, kind: .deleted)
            let insertAt = min(index, rows.count)
            rows.insert(row, at: insertAt)
        }

        return ProjectComparisonResult(
            rows: rows,
            addedCount: addedCount,
            deletedCount: deletedCount,
            modifiedCount: modifiedCount,
            leftFinishDate: baseline.map(\.endDate).max(),
            rightFinishDate: revised.map(\.endDate).max()
        )
    }

    private static func diffFields(left: ScheduleTask, right: ScheduleTask) -> [TaskFieldChange] {
        var changes: [TaskFieldChange] = []
        if left.title != right.title {
            changes.append(.title(old: left.title, new: right.title))
        }
        if left.startDate != right.startDate {
            changes.append(.startDate(old: left.startDate, new: right.startDate))
        }
        if left.endDate != right.endDate {
            changes.append(.endDate(old: left.endDate, new: right.endDate))
        }
        if left.durationDays != right.durationDays {
            changes.append(.duration(old: left.durationDays, new: right.durationDays))
        }
        if abs(left.percentComplete - right.percentComplete) > 0.01 {
            changes.append(.progress(old: left.percentComplete, new: right.percentComplete))
        }
        if normalizedDeps(left.dependencies) != normalizedDeps(right.dependencies) {
            changes.append(.dependenciesChanged)
        }
        if left.isMilestone != right.isMilestone {
            changes.append(.milestoneChanged(old: left.isMilestone, new: right.isMilestone))
        }
        if left.parentID != right.parentID {
            changes.append(.hierarchyChanged)
        }
        return changes
    }

    private static func normalizedDeps(_ deps: [TaskDependency]) -> [String] {
        deps.map { "\($0.predecessorID.uuidString):\($0.type.rawValue):\($0.lagDays)" }.sorted()
    }
}
