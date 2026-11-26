import XCTest
@testable import ScheduleCore

final class InteropTests: XCTestCase {

    func testXLSXExportContainsFormulas() throws {
        let project = ProjectDocument.sampleProject(referenceDate: CalendarDay(year: 2026, month: 11, day: 2))
        let data = try XLSXExporter.exportData(for: project)

        XCTAssertEqual(data.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]))

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_schedule_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try data.write(to: tempURL)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-p", tempURL.path, "xl/worksheets/sheet1.xml"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)

        let xml = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("<f>MIN("))
        XCTAssertTrue(xml.contains("<f>MAX("))
        XCTAssertTrue(xml.contains("WORKDAY("))
        XCTAssertTrue(xml.contains("NETWORKDAYS("))
        XCTAssertTrue(xml.contains("SUMPRODUCT("))
    }

    func testMSPXMLRoundTrip() throws {
        let project = ProjectDocument.sampleProject(referenceDate: CalendarDay(year: 2026, month: 11, day: 2))
        let xmlData = MSPXMLInterop.exportXML(for: project)
        let imported = try MSPXMLInterop.importXML(from: xmlData)

        XCTAssertEqual(imported.name, project.name)
        XCTAssertEqual(imported.tasks.count, project.tasks.count)

        let importedMilestones = imported.tasks.filter(\.isMilestone)
        XCTAssertEqual(importedMilestones.count, 2)

        let subtasks = imported.tasks.filter { $0.parentID != nil }
        XCTAssertEqual(subtasks.count, 7)

        let pkg = imported.tasks.first { $0.title.contains("Packaging") }
        XCTAssertEqual(pkg?.dependencies.first?.lagDays, 3)
        XCTAssertEqual(pkg?.dependencies.first?.type, .finishToStart)
    }

    func testMPPDetection() {
        let url = URL(fileURLWithPath: "/tmp/example.mpp")
        XCTAssertTrue(MPPCompatibility.isBinaryMPP(url: url))
    }
}
