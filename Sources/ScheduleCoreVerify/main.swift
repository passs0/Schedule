import Foundation
import ScheduleCore

func check(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

let cal = WorkingCalendar.standard
let monday = CalendarDay(year: 2026, month: 11, day: 2)

// 1. Finish-to-Start with 3-day lag skipping weekends
do {
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
    check(result[0].startDate == CalendarDay(year: 2026, month: 11, day: 2), "Mfg start")
    check(result[0].endDate == CalendarDay(year: 2026, month: 11, day: 6), "Mfg end")
    check(result[1].startDate == CalendarDay(year: 2026, month: 11, day: 12), "Pkg start with 3d lag")
    check(result[1].endDate == CalendarDay(year: 2026, month: 11, day: 13), "Pkg end")
}

// 2. Start-to-Start & Finish-to-Finish
do {
    let aID = UUID()
    let bID = UUID()
    let cID = UUID()
    let a = ScheduleTask(id: aID, title: "A", startDate: monday, durationDays: 5, calendar: cal)
    let b = ScheduleTask(id: bID, title: "B", startDate: monday, durationDays: 3, dependencies: [TaskDependency(predecessorID: aID, type: .startToStart, lagDays: 2)], calendar: cal)
    let c = ScheduleTask(id: cID, title: "C", startDate: monday, durationDays: 2, dependencies: [TaskDependency(predecessorID: aID, type: .finishToFinish, lagDays: 0)], calendar: cal)
    let result = SchedulingEngine.recalculateAll(tasks: [a, b, c], projectStart: monday, calendar: cal)
    check(result[1].startDate == CalendarDay(year: 2026, month: 11, day: 4), "SS +2d start")
    check(result[2].startDate == CalendarDay(year: 2026, month: 11, day: 5), "FF start")
    check(result[2].endDate == CalendarDay(year: 2026, month: 11, day: 6), "FF end")
}

// 3. Cycle detection
do {
    let aID = UUID()
    let bID = UUID()
    let cID = UUID()
    let tasks = [
        ScheduleTask(id: aID, title: "A"),
        ScheduleTask(id: bID, title: "B", dependencies: [TaskDependency(predecessorID: aID)]),
        ScheduleTask(id: cID, title: "C", dependencies: [TaskDependency(predecessorID: bID)])
    ]
    check(SchedulingEngine.wouldCreateCycle(tasks: tasks, predecessorID: cID, successorID: aID), "Detects cycle")
    check(!SchedulingEngine.wouldCreateCycle(tasks: tasks, predecessorID: aID, successorID: cID), "Allows valid edge")
}

// 4. Summary group roll-up & critical path
do {
    let groupID = UUID()
    let t1ID = UUID()
    let t2ID = UUID()
    let sideID = UUID()
    let group = ScheduleTask(id: groupID, title: "Phase 1")
    let t1 = ScheduleTask(id: t1ID, title: "Long 1", startDate: monday, durationDays: 4, percentComplete: 100, parentID: groupID, calendar: cal)
    let t2 = ScheduleTask(id: t2ID, title: "Long 2", startDate: monday, durationDays: 2, percentComplete: 0, parentID: groupID, dependencies: [TaskDependency(predecessorID: t1ID)], calendar: cal)
    let side = ScheduleTask(id: sideID, title: "Side", startDate: monday, durationDays: 2, percentComplete: 50, calendar: cal)
    let result = SchedulingEngine.recalculateAll(tasks: [group, t1, t2, side], projectStart: monday, calendar: cal)
    check(result[0].durationDays == 6, "Group duration rollup")
    check(abs(result[0].percentComplete - (400.0 / 6.0)) < 0.01, "Group weighted progress")
    check(result[1].isCritical && result[2].isCritical, "Critical path tasks")
    check(!result[3].isCritical && result[3].totalSlackDays > 0, "Non-critical slack")
}

// 5. Human-readable dependencies
do {
    let predID = UUID()
    let fsLag = TaskDependency(predecessorID: predID, type: .finishToStart, lagDays: 3)
    let desc = HumanDependency.describe(fsLag, predecessorName: "Manufacturing", successorName: "Packaging")
    check(desc == "Packaging starts 3 days after \"Manufacturing\" is completed", "Plain-English FS+lag")
    check(!desc.contains("FS"), "No FS abbreviation in plain English")
    check(HumanDependency.technicalSummary(for: fsLag) == "FS +3d", "Technical summary")
}

// 6. XLSX export with formulas
do {
    let project = ProjectDocument.sampleProject(referenceDate: monday)
    let data = try XLSXExporter.exportData(for: project)
    check(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]), "Valid ZIP header")

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("verify_\(UUID().uuidString).xlsx")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try data.write(to: tempURL)

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    proc.arguments = ["-p", tempURL.path, "xl/worksheets/sheet1.xml"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    try proc.run()
    proc.waitUntilExit()
    check(proc.terminationStatus == 0, "unzip sheet1.xml")

    let xml = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    check(xml.contains("<f>MIN(") && xml.contains("<f>MAX("), "XLSX summary formulas")
    check(xml.contains("WORKDAY(") && xml.contains("NETWORKDAYS(") && xml.contains("SUMPRODUCT("), "XLSX scheduling formulas")
}

// 7. Microsoft Project XML round-trip
do {
    let project = ProjectDocument.sampleProject(referenceDate: monday)
    let xmlData = MSPXMLInterop.exportXML(for: project)
    let imported = try MSPXMLInterop.importXML(from: xmlData)
    check(imported.name == project.name, "MSP XML name")
    check(imported.tasks.count == project.tasks.count, "MSP XML task count")
    check(imported.tasks.filter(\.isMilestone).count == 2, "MSP XML milestones")
    check(imported.tasks.filter { $0.parentID != nil }.count == 7, "MSP XML hierarchy")
    let pkg = imported.tasks.first { $0.title.contains("Packaging") }
    check(pkg?.dependencies.first?.lagDays == 3 && pkg?.dependencies.first?.type == .finishToStart, "MSP XML dependency lag")
}

// 8. Project Diff Engine
do {
    let id1 = UUID(), id2 = UUID(), id3 = UUID()
    let baseline = [
        ScheduleTask(id: id1, identifier: "1", title: "Design", startDate: monday, durationDays: 3),
        ScheduleTask(id: id2, identifier: "2", title: "Legacy", startDate: monday, durationDays: 2)
    ]
    let revised = [
        ScheduleTask(id: id1, identifier: "1", title: "Design", startDate: monday, durationDays: 5),
        ScheduleTask(id: id3, identifier: "2", title: "New QA", startDate: monday, durationDays: 2)
    ]
    let diff = ProjectDiffEngine.compare(baseline: baseline, revised: revised)
    check(diff.addedCount == 1 && diff.deletedCount == 1 && diff.modifiedCount == 1, "Diff counts")
    check(diff.finishDateDeltaDays == 2, "Diff finish delta")
}

print("All 8 ScheduleCore verification suites passed.")
