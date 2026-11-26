import Foundation

/// An immutable snapshot of a project's tasks at a point in time, used for version history and side-by-side comparison.
public struct ProjectVersion: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var notes: String
    public var tasks: [ScheduleTask]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        notes: String = "",
        tasks: [ScheduleTask]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.notes = notes
        self.tasks = tasks
    }
}
