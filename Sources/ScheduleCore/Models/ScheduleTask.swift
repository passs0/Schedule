import Foundation

/// A single task, milestone, or summary group in a Schedule project.
public struct ScheduleTask: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    /// User-editable or auto-assigned task identifier (e.g., "1.1" or "DES-01").
    public var identifier: String
    public var title: String
    public var startDate: CalendarDay
    public var endDate: CalendarDay
    /// Working-day duration. Milestones have `durationDays == 0`.
    public var durationDays: Int
    public var isMilestone: Bool
    /// Completion percentage from 0 to 100.
    public var percentComplete: Double
    public var notes: String
    /// Parent group task ID, or `nil` for top-level tasks.
    public var parentID: UUID?
    public var isExpanded: Bool
    /// Dependencies where this task is the successor.
    public var dependencies: [TaskDependency]
    /// Optional user-pinned manual constraint: if true, task won't shift earlier than `startDate` unless driven by a dependency.
    public var isManuallyScheduled: Bool
    /// Optional assigned owner/region calendar ID. `nil` inherits the project's default calendar.
    public var calendarID: UUID?
    /// Optional Directly Responsible Individual (DRI) assigned to this task.
    public var dri: String?
    /// Optional fixed external deadline date. Unlike `endDate`, this does not shift automatically.
    public var deadline: CalendarDay?

    // Computed by `SchedulingEngine`:
    public var isCritical: Bool
    public var totalSlackDays: Int

    public init(
        id: UUID = UUID(),
        identifier: String = "",
        title: String,
        startDate: CalendarDay = .today,
        endDate: CalendarDay? = nil,
        durationDays: Int = 1,
        isMilestone: Bool = false,
        percentComplete: Double = 0,
        notes: String = "",
        parentID: UUID? = nil,
        isExpanded: Bool = true,
        dependencies: [TaskDependency] = [],
        isManuallyScheduled: Bool = false,
        calendarID: UUID? = nil,
        dri: String? = nil,
        deadline: CalendarDay? = nil,
        isCritical: Bool = false,
        totalSlackDays: Int = 0,
        calendar: WorkingCalendar = .standard
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        let clampedDuration = isMilestone ? 0 : max(1, durationDays)
        self.durationDays = clampedDuration
        self.isMilestone = isMilestone
        let snappedStart = calendar.snapToWorkingDay(startDate, forward: true)
        self.startDate = snappedStart
        if let endDate {
            self.endDate = isMilestone ? snappedStart : max(snappedStart, endDate)
        } else {
            self.endDate = isMilestone ? snappedStart : calendar.endDate(startingOn: snappedStart, durationDays: clampedDuration)
        }
        self.percentComplete = min(100, max(0, percentComplete))
        self.notes = notes
        self.parentID = parentID
        self.isExpanded = isExpanded
        self.dependencies = dependencies
        self.isManuallyScheduled = isManuallyScheduled
        self.calendarID = calendarID
        self.dri = dri
        self.deadline = deadline
        self.isCritical = isCritical
        self.totalSlackDays = totalSlackDays
    }
}
