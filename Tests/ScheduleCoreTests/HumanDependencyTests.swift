import XCTest
@testable import ScheduleCore

final class HumanDependencyTests: XCTestCase {

    func testPlainEnglishPhrasing() {
        let predID = UUID()
        let fsLag = TaskDependency(predecessorID: predID, type: .finishToStart, lagDays: 3)
        let desc = HumanDependency.describe(fsLag, predecessorName: "Manufacturing", successorName: "Packaging")
        XCTAssertEqual(desc, "Packaging starts 3 days after \"Manufacturing\" is completed")
        XCTAssertFalse(desc.contains("FS"))

        let ss = TaskDependency(predecessorID: predID, type: .startToStart, lagDays: 0)
        let ssDesc = HumanDependency.describe(ss, predecessorName: "Design")
        XCTAssertEqual(ssDesc, "This task begins at the same time as \"Design\"")

        let tech = HumanDependency.technicalSummary(for: fsLag)
        XCTAssertEqual(tech, "FS +3d")
    }
}
