import XCTest
@testable import ScheduleCore

final class SchedulingEngineTests: XCTestCase {

    func testFinishToStartWithLagSkipsWeekends() {
        let cal = WorkingCalendar.standard
        let monday = CalendarDay(year: 2026, month: 11, day: 2)
        let mfgID = UUID()
        let pkgID = UUID()

        let mfg = ScheduleTask(id: mfgID, identifier: "1", title: "Manufacturing", startDate: monday, durationDays: 5, calendar: cal)
        let pkg = ScheduleTask(
            id: pkgID,
            identifier: "2",
            title: "Packaging",
            startDate: monday,
            durationDays: 2,
            dependencies: [TaskDependency(predecessorID: mfgID, type: .finishToStart, lagDays: 3)],
            calendar: cal
        )

        let result = SchedulingEngine.recalculateAll(tasks: [mfg, pkg], projectStart: monday, calendar: cal)
        XCTAssertEqual(result[0].startDate, CalendarDay(year: 2026, month: 11, day: 2))
        XCTAssertEqual(result[0].endDate, CalendarDay(year: 2026, month: 11, day: 6))
        XCTAssertEqual(result[1].startDate, CalendarDay(year: 2026, month: 11, day: 12))
        XCTAssertEqual(result[1].endDate, CalendarDay(year: 2026, month: 11, day: 13))
    }

    func testStartToStartAndFinishToFinish() {
        let cal = WorkingCalendar.standard
        let monday = CalendarDay(year: 2026, month: 11, day: 2)
        let aID = UUID()
        let bID = UUID()
        let cID = UUID()

        let a = ScheduleTask(id: aID, title: "A", startDate: monday, durationDays: 5, calendar: cal)
        let b = ScheduleTask(
            id: bID,
            title: "B",
            startDate: monday,
            durationDays: 3,
            dependencies: [TaskDependency(predecessorID: aID, type: .startToStart, lagDays: 2)],
            calendar: cal
        )
        let c = ScheduleTask(
            id: cID,
            title: "C",
            startDate: monday,
            durationDays: 2,
            dependencies: [TaskDependency(predecessorID: aID, type: .finishToFinish, lagDays: 0)],
            calendar: cal
        )

        let result = SchedulingEngine.recalculateAll(tasks: [a, b, c], projectStart: monday, calendar: cal)
        XCTAssertEqual(result[1].startDate, CalendarDay(year: 2026, month: 11, day: 4))
        XCTAssertEqual(result[2].startDate, CalendarDay(year: 2026, month: 11, day: 5))
        XCTAssertEqual(result[2].endDate, CalendarDay(year: 2026, month: 11, day: 6))
    }

    func testCycleDetection() {
        let aID = UUID()
        let bID = UUID()
        let cID = UUID()

        let a = ScheduleTask(id: aID, title: "A")
        let b = ScheduleTask(id: bID, title: "B", dependencies: [TaskDependency(predecessorID: aID)])
        let c = ScheduleTask(id: cID, title: "C", dependencies: [TaskDependency(predecessorID: bID)])
        let tasks = [a, b, c]

        XCTAssertTrue(SchedulingEngine.wouldCreateCycle(tasks: tasks, predecessorID: cID, successorID: aID))
        XCTAssertFalse(SchedulingEngine.wouldCreateCycle(tasks: tasks, predecessorID: aID, successorID: cID))
    }

    func testSummaryGroupRollupAndCriticalPath() {
        let cal = WorkingCalendar.standard
        let monday = CalendarDay(year: 2026, month: 11, day: 2)
        let groupID = UUID()
        let t1ID = UUID()
        let t2ID = UUID()
        let sideID = UUID()

        let group = ScheduleTask(id: groupID, title: "Phase 1")
        let t1 = ScheduleTask(id: t1ID, title: "Long Task 1", startDate: monday, durationDays: 4, percentComplete: 100, parentID: groupID, calendar: cal)
        let t2 = ScheduleTask(
            id: t2ID,
            title: "Long Task 2",
            startDate: monday,
            durationDays: 2,
            percentComplete: 0,
            parentID: groupID,
            dependencies: [TaskDependency(predecessorID: t1ID)],
            calendar: cal
        )
        let side = ScheduleTask(id: sideID, title: "Short Parallel", startDate: monday, durationDays: 2, percentComplete: 50, calendar: cal)

        let result = SchedulingEngine.recalculateAll(tasks: [group, t1, t2, side], projectStart: monday, calendar: cal)
        XCTAssertEqual(result[0].durationDays, 6)
        XCTAssertEqual(result[0].percentComplete, 400.0 / 6.0, accuracy: 0.01)
        XCTAssertTrue(result[1].isCritical)
        XCTAssertTrue(result[2].isCritical)
        XCTAssertFalse(result[3].isCritical)
        XCTAssertGreaterThan(result[3].totalSlackDays, 0)
    }
}
