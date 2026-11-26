import Foundation

/// The root local-first document model for a Schedule project.
public struct ProjectDocument: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var projectStartDate: CalendarDay
    public var workingCalendar: WorkingCalendar
    public var calendars: [NamedWorkingCalendar]
    public var tasks: [ScheduleTask]
    public var versions: [ProjectVersion]
    public var isFavorite: Bool
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Untitled Project",
        projectStartDate: CalendarDay = .today,
        workingCalendar: WorkingCalendar = .standard,
        calendars: [NamedWorkingCalendar] = NamedWorkingCalendar.defaultPresets(),
        tasks: [ScheduleTask] = [],
        versions: [ProjectVersion] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectStartDate = workingCalendar.snapToWorkingDay(projectStartDate, forward: true)
        self.workingCalendar = workingCalendar
        self.calendars = calendars
        self.tasks = tasks
        self.versions = versions
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        projectStartDate = try c.decode(CalendarDay.self, forKey: .projectStartDate)
        workingCalendar = try c.decode(WorkingCalendar.self, forKey: .workingCalendar)
        calendars = try c.decodeIfPresent([NamedWorkingCalendar].self, forKey: .calendars) ?? NamedWorkingCalendar.defaultPresets()
        tasks = try c.decode([ScheduleTask].self, forKey: .tasks)
        versions = try c.decode([ProjectVersion].self, forKey: .versions)
        isFavorite = try c.decode(Bool.self, forKey: .isFavorite)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    public func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decodeJSON(from data: Data) throws -> ProjectDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectDocument.self, from: data)
    }
}

public extension ProjectDocument {
    /// Creates a realistic sample project demonstrating hierarchy, milestones, and plain-English dependencies.
    static func sampleProject(referenceDate: CalendarDay = .today) -> ProjectDocument {
        let cal = WorkingCalendar.standard
        let start = cal.snapToWorkingDay(referenceDate, forward: true)

        let groupDesignID = UUID()
        let taskResearchID = UUID()
        let taskPrototypeID = UUID()
        let milestoneDesignID = UUID()

        let groupBuildID = UUID()
        let taskMfgID = UUID()
        let taskPkgID = UUID()
        let taskQAID = UUID()
        let milestoneLaunchID = UUID()

        let tasks: [ScheduleTask] = [
            ScheduleTask(
                id: groupDesignID,
                identifier: "1",
                title: "Design & Prototyping",
                startDate: start,
                durationDays: 1,
                percentComplete: 75,
                notes: "Initial discovery, industrial design, and sign-off.",
                calendar: cal
            ),
            ScheduleTask(
                id: taskResearchID,
                identifier: "1.1",
                title: "User Research & Requirements",
                startDate: start,
                durationDays: 4,
                percentComplete: 100,
                parentID: groupDesignID,
                calendar: cal
            ),
            ScheduleTask(
                id: taskPrototypeID,
                identifier: "1.2",
                title: "Interactive Prototype",
                startDate: start,
                durationDays: 5,
                percentComplete: 60,
                parentID: groupDesignID,
                dependencies: [
                    TaskDependency(predecessorID: taskResearchID, type: .finishToStart, lagDays: 0)
                ],
                calendar: cal
            ),
            ScheduleTask(
                id: milestoneDesignID,
                identifier: "1.3",
                title: "Design Sign-Off",
                startDate: start,
                durationDays: 0,
                isMilestone: true,
                percentComplete: 0,
                parentID: groupDesignID,
                dependencies: [
                    TaskDependency(predecessorID: taskPrototypeID, type: .finishToStart, lagDays: 0)
                ],
                calendar: cal
            ),
            ScheduleTask(
                id: groupBuildID,
                identifier: "2",
                title: "Production & Launch",
                startDate: start,
                durationDays: 1,
                percentComplete: 0,
                notes: "Manufacturing, packaging, QA, and public release.",
                calendar: cal
            ),
            ScheduleTask(
                id: taskMfgID,
                identifier: "2.1",
                title: "Manufacturing",
                startDate: start,
                durationDays: 8,
                percentComplete: 0,
                parentID: groupBuildID,
                dependencies: [
                    TaskDependency(predecessorID: milestoneDesignID, type: .finishToStart, lagDays: 0)
                ],
                calendar: cal
            ),
            ScheduleTask(
                id: taskPkgID,
                identifier: "2.2",
                title: "Packaging & Fulfillment Prep",
                startDate: start,
                durationDays: 4,
                percentComplete: 0,
                parentID: groupBuildID,
                dependencies: [
                    TaskDependency(predecessorID: taskMfgID, type: .finishToStart, lagDays: 3)
                ],
                calendar: cal
            ),
            ScheduleTask(
                id: taskQAID,
                identifier: "2.3",
                title: "Final Quality Assurance",
                startDate: start,
                durationDays: 3,
                percentComplete: 0,
                parentID: groupBuildID,
                dependencies: [
                    TaskDependency(predecessorID: taskMfgID, type: .startToStart, lagDays: 4)
                ],
                calendar: cal
            ),
            ScheduleTask(
                id: milestoneLaunchID,
                identifier: "2.4",
                title: "Product Launch",
                startDate: start,
                durationDays: 0,
                isMilestone: true,
                percentComplete: 0,
                parentID: groupBuildID,
                dependencies: [
                    TaskDependency(predecessorID: taskPkgID, type: .finishToStart, lagDays: 0),
                    TaskDependency(predecessorID: taskQAID, type: .finishToStart, lagDays: 0)
                ],
                calendar: cal
            )
        ]

        var doc = ProjectDocument(
            name: "Product Launch",
            projectStartDate: start,
            workingCalendar: cal,
            tasks: tasks,
            isFavorite: true
        )
        doc.tasks = SchedulingEngine.recalculateAll(tasks: doc.tasks, projectStart: doc.projectStartDate, calendar: cal)
        doc.versions = [
            ProjectVersion(name: "Original Plan", notes: "Initial baseline schedule", tasks: doc.tasks)
        ]
        return doc
    }
}
