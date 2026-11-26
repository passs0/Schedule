import XCTest
@testable import ScheduleCore

final class ProjectDiffTests: XCTestCase {

    func testDetectsAddedDeletedAndModifiedTasks() {
        let monday = CalendarDay(year: 2026, month: 11, day: 2)
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let baseline = [
            ScheduleTask(id: id1, identifier: "1", title: "Design", startDate: monday, durationDays: 3),
            ScheduleTask(id: id2, identifier: "2", title: "Legacy Step", startDate: monday, durationDays: 2)
        ]

        let revised = [
            ScheduleTask(id: id1, identifier: "1", title: "Design", startDate: monday, durationDays: 5),
            ScheduleTask(id: id3, identifier: "2", title: "New QA", startDate: monday, durationDays: 2)
        ]

        let result = ProjectDiffEngine.compare(baseline: baseline, revised: revised)
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.deletedCount, 1)
        XCTAssertEqual(result.modifiedCount, 1)
        XCTAssertEqual(result.finishDateDeltaDays, 2)
    }
}
