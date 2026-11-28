import Foundation

/// Exports a `ProjectDocument` as a formula-driven Microsoft Excel (.xlsx) workbook
/// that is also directly compatible with Apple Numbers.
public enum XLSXExporter {

    public static func exportData(for document: ProjectDocument) throws -> Data {
        var zip = ZipWriter()
        try zip.addFile(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8))
        try zip.addFile(path: "_rels/.rels", data: Data(rootRelsXML.utf8))
        try zip.addFile(path: "xl/workbook.xml", data: Data(workbookXML.utf8))
        try zip.addFile(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRelsXML.utf8))
        try zip.addFile(path: "xl/styles.xml", data: Data(stylesXML.utf8))
        try zip.addFile(path: "xl/worksheets/sheet1.xml", data: Data(buildScheduleSheet(document: document).utf8))
        try zip.addFile(path: "xl/worksheets/sheet2.xml", data: Data(buildDependenciesSheet(document: document).utf8))
        return zip.finalize()
    }

    public static func export(document: ProjectDocument, to url: URL) throws {
        let data = try exportData(for: document)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Sheet 1: Schedule

    private static func buildScheduleSheet(document: ProjectDocument) -> String {
        let tasks = document.tasks
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // Map task ID -> 1-based Excel row index (tasks start at row 5)
        let startRow = 5
        var rowByID: [UUID: Int] = [:]
        for (idx, task) in tasks.enumerated() {
            rowByID[task.id] = startRow + idx
        }

        // Identify summary groups and their contiguous/subtree child rows
        var childrenByParent: [UUID: [UUID]] = [:]
        for task in tasks {
            if let pid = task.parentID, taskMap[pid] != nil {
                childrenByParent[pid, default: []].append(task.id)
            }
        }

        // Compute hierarchy depth for visual indentation
        func depth(of task: ScheduleTask) -> Int {
            var d = 0
            var cur = task.parentID
            while let pid = cur, let p = taskMap[pid], d < 20 {
                d += 1
                cur = p.parentID
            }
            return d
        }

        let lastRow = max(startRow, startRow + tasks.count - 1)
        let leafRows = tasks.enumerated().compactMap { idx, t in
            (childrenByParent[t.id]?.isEmpty ?? true) ? (startRow + idx) : nil
        }

        var rowsXML = ""

        // Row 1: Title
        rowsXML += """
        <row r="1" ht="26" customHeight="1">
          <c r="A1" t="inlineStr" s="1"><is><t>\(xmlEscape(document.name))</t></is></c>
        </row>
        """

        // Row 2: Project Summary Formulas
        let startRange = "D\(startRow):D\(lastRow)"
        let endRange = "E\(startRow):E\(lastRow)"
        let leafDurRefs = leafRows.map { "F\($0)" }
        let leafProgRefs = leafRows.map { "F\($0)*G\($0)" }
        let progressFormula: String
        if leafRows.isEmpty {
            progressFormula = "0"
        } else {
            let num = leafProgRefs.joined(separator: "+")
            let den = leafDurRefs.joined(separator: "+")
            progressFormula = "(\(num))/MAX(1,\(den))"
        }

        rowsXML += """
        <row r="2" ht="20" customHeight="1">
          <c r="A2" t="inlineStr" s="2"><is><t>Project Start</t></is></c>
          <c r="B2" s="4"><f>MIN(\(startRange))</f></c>
          <c r="C2" t="inlineStr" s="2"><is><t>Project Finish</t></is></c>
          <c r="D2" s="4"><f>MAX(\(endRange))</f></c>
          <c r="E2" t="inlineStr" s="2"><is><t>Working Days</t></is></c>
          <c r="F2" s="5"><f>NETWORKDAYS(B2,D2)</f></c>
          <c r="G2" s="6"><f>\(xmlEscape(progressFormula))</f></c>
          <c r="H2" t="inlineStr" s="2"><is><t>Overall Progress</t></is></c>
        </row>
        """

        // Row 4: Table Headers
        let headers = [
            ("A", "ID"),
            ("B", "Task Name"),
            ("C", "Type"),
            ("D", "Start Date"),
            ("E", "End Date"),
            ("F", "Duration (Days)"),
            ("G", "% Complete"),
            ("H", "Dependencies"),
            ("I", "Critical Path"),
            ("J", "Notes")
        ]
        rowsXML += "<row r=\"4\" ht=\"22\" customHeight=\"1\">"
        for (col, title) in headers {
            rowsXML += "<c r=\"\(col)4\" t=\"inlineStr\" s=\"3\"><is><t>\(xmlEscape(title))</t></is></c>"
        }
        rowsXML += "</row>"

        // Task Rows
        for (idx, task) in tasks.enumerated() {
            let r = startRow + idx
            let isGroup = !(childrenByParent[task.id]?.isEmpty ?? true)
            let d = depth(of: task)
            let indentPrefix = String(repeating: "  ", count: d)
            let textStyle = isGroup ? 7 : 0
            let dateStyle = isGroup ? 8 : 4
            let numStyle = isGroup ? 9 : 5
            let pctStyle = isGroup ? 10 : 6

            let typeLabel = isGroup ? "Group" : (task.isMilestone ? "Milestone" : "Task")
            let depDescription = task.dependencies.map { dep in
                let predName = taskMap[dep.predecessorID]?.title ?? "Unknown"
                return HumanDependency.describe(dep, predecessorName: predName, successorName: nil)
            }.joined(separator: "; ")

            let startCell: String
            let endCell: String
            let durationCell: String
            let progressCell: String

            if isGroup, let childIDs = childrenByParent[task.id], !childIDs.isEmpty {
                let childRows = childIDs.compactMap { rowByID[$0] }.sorted()
                let minRow = childRows.first ?? r
                let maxRow = childRows.last ?? r
                startCell = "<c r=\"D\(r)\" s=\"\(dateStyle)\"><f>MIN(D\(minRow):D\(maxRow))</f></c>"
                endCell = "<c r=\"E\(r)\" s=\"\(dateStyle)\"><f>MAX(E\(minRow):E\(maxRow))</f></c>"
                durationCell = "<c r=\"F\(r)\" s=\"\(numStyle)\"><f>NETWORKDAYS(D\(r),E\(r))</f></c>"
                progressCell = "<c r=\"G\(r)\" s=\"\(pctStyle)\"><f>SUMPRODUCT(F\(minRow):F\(maxRow),G\(minRow):G\(maxRow))/MAX(1,SUM(F\(minRow):F\(maxRow)))</f></c>"
            } else {
                if let startFormula = buildStartFormula(for: task, taskMap: taskMap, rowByID: rowByID) {
                    startCell = "<c r=\"D\(r)\" s=\"\(dateStyle)\"><f>\(xmlEscape(startFormula))</f><v>\(excelSerial(task.startDate))</v></c>"
                } else {
                    startCell = "<c r=\"D\(r)\" s=\"\(dateStyle)\"><v>\(excelSerial(task.startDate))</v></c>"
                }
                endCell = "<c r=\"E\(r)\" s=\"\(dateStyle)\"><f>IF(F\(r)=0,D\(r),WORKDAY(D\(r),F\(r)-1))</f><v>\(excelSerial(task.endDate))</v></c>"
                durationCell = "<c r=\"F\(r)\" s=\"\(numStyle)\"><v>\(task.durationDays)</v></c>"
                let pctValue = String(format: "%.4f", task.percentComplete / 100.0)
                progressCell = "<c r=\"G\(r)\" s=\"\(pctStyle)\"><v>\(pctValue)</v></c>"
            }

            let critLabel = task.isCritical ? "Critical" : ""

            rowsXML += """
            <row r="\(r)">
              <c r="A\(r)" t="inlineStr" s="\(textStyle)"><is><t>\(xmlEscape(task.identifier))</t></is></c>
              <c r="B\(r)" t="inlineStr" s="\(textStyle)"><is><t>\(xmlEscape(indentPrefix + task.title))</t></is></c>
              <c r="C\(r)" t="inlineStr" s="\(textStyle)"><is><t>\(typeLabel)</t></is></c>
              \(startCell)
              \(endCell)
              \(durationCell)
              \(progressCell)
              <c r="H\(r)" t="inlineStr" s="\(textStyle)"><is><t>\(xmlEscape(depDescription))</t></is></c>
              <c r="I\(r)" t="inlineStr" s="\(textStyle)"><is><t>\(critLabel)</t></is></c>
              <c r="J\(r)" t="inlineStr" s="\(textStyle)"><is><t>\(xmlEscape(task.notes))</t></is></c>
            </row>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetViews>
            <sheetView tabSelected="1" workbookViewId="0">
              <pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/>
            </sheetView>
          </sheetViews>
          <cols>
            <col min="1" max="1" width="10" customWidth="1"/>
            <col min="2" max="2" width="34" customWidth="1"/>
            <col min="3" max="3" width="12" customWidth="1"/>
            <col min="4" max="4" width="14" customWidth="1"/>
            <col min="5" max="5" width="14" customWidth="1"/>
            <col min="6" max="6" width="16" customWidth="1"/>
            <col min="7" max="7" width="13" customWidth="1"/>
            <col min="8" max="8" width="44" customWidth="1"/>
            <col min="9" max="9" width="13" customWidth="1"/>
            <col min="10" max="10" width="32" customWidth="1"/>
          </cols>
          <sheetData>
            \(rowsXML)
          </sheetData>
        </worksheet>
        """
    }

    private static func buildStartFormula(
        for task: ScheduleTask,
        taskMap: [UUID: ScheduleTask],
        rowByID: [UUID: Int]
    ) -> String? {
        guard !task.dependencies.isEmpty, !task.isManuallyScheduled else { return nil }
        var terms: [String] = []
        for dep in task.dependencies {
            guard let pred = taskMap[dep.predecessorID],
                  let predRow = rowByID[dep.predecessorID] else { continue }
            switch dep.type {
            case .finishToStart:
                let offset = pred.isMilestone ? dep.lagDays : (1 + dep.lagDays)
                terms.append("WORKDAY(E\(predRow),\(offset))")
            case .startToStart:
                terms.append("WORKDAY(D\(predRow),\(dep.lagDays))")
            case .finishToFinish:
                let durOffset = task.isMilestone ? 0 : -(task.durationDays - 1)
                terms.append("WORKDAY(WORKDAY(E\(predRow),\(dep.lagDays)),\(durOffset))")
            case .startToFinish:
                let durOffset = task.isMilestone ? 0 : -(task.durationDays - 1)
                terms.append("WORKDAY(WORKDAY(D\(predRow),\(dep.lagDays)),\(durOffset))")
            }
        }
        guard !terms.isEmpty else { return nil }
        return terms.count == 1 ? terms[0] : "MAX(\(terms.joined(separator: ",")))"
    }

    // MARK: - Sheet 2: Dependencies

    private static func buildDependenciesSheet(document: ProjectDocument) -> String {
        let taskMap = Dictionary(uniqueKeysWithValues: document.tasks.map { ($0.id, $0) })
        var rowsXML = """
        <row r="1" ht="22" customHeight="1">
          <c r="A1" t="inlineStr" s="3"><is><t>Task</t></is></c>
          <c r="B1" t="inlineStr" s="3"><is><t>Depends On</t></is></c>
          <c r="C1" t="inlineStr" s="3"><is><t>Plain-English Description</t></is></c>
          <c r="D1" t="inlineStr" s="3"><is><t>Type</t></is></c>
          <c r="E1" t="inlineStr" s="3"><is><t>Lag / Lead (Days)</t></is></c>
        </row>
        """

        var r = 2
        for task in document.tasks {
            for dep in task.dependencies {
                let predName = taskMap[dep.predecessorID]?.title ?? "Unknown"
                let desc = HumanDependency.describe(dep, predecessorName: predName, successorName: task.title)
                rowsXML += """
                <row r="\(r)">
                  <c r="A\(r)" t="inlineStr"><is><t>\(xmlEscape(task.title))</t></is></c>
                  <c r="B\(r)" t="inlineStr"><is><t>\(xmlEscape(predName))</t></is></c>
                  <c r="C\(r)" t="inlineStr"><is><t>\(xmlEscape(desc))</t></is></c>
                  <c r="D\(r)" t="inlineStr"><is><t>\(dep.type.rawValue)</t></is></c>
                  <c r="E\(r)" s="5"><v>\(dep.lagDays)</v></c>
                </row>
                """
                r += 1
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <cols>
            <col min="1" max="1" width="28" customWidth="1"/>
            <col min="2" max="2" width="28" customWidth="1"/>
            <col min="3" max="3" width="52" customWidth="1"/>
            <col min="4" max="4" width="10" customWidth="1"/>
            <col min="5" max="5" width="18" customWidth="1"/>
          </cols>
          <sheetData>
            \(rowsXML)
          </sheetData>
        </worksheet>
        """
    }

    // MARK: - Helpers & Static OOXML Parts

    public static func excelSerial(_ day: CalendarDay) -> Int {
        let epoch = CalendarDay(year: 1899, month: 12, day: 30)
        return epoch.calendarDays(until: day)
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="Schedule" sheetId="1" r:id="rId1"/>
        <sheet name="Dependencies" sheetId="2" r:id="rId2"/>
      </sheets>
    </workbook>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <numFmts count="1">
        <numFmt numFmtId="164" formatCode="yyyy-mm-dd"/>
      </numFmts>
      <fonts count="4">
        <font><sz val="11"/><name val="SF Pro Text"/></font>
        <font><b/><sz val="16"/><name val="SF Pro Display"/></font>
        <font><b/><sz val="11"/><color rgb="FF1D1D1F"/><name val="SF Pro Text"/></font>
        <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="SF Pro Text"/></font>
      </fonts>
      <fills count="4">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF2C5282"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFF2F4F7"/></patternFill></fill>
      </fills>
      <borders count="2">
        <border><left/><right/><top/><bottom/><diagonal/></border>
        <border><bottom style="thin"><color rgb="FFD1D5DB"/></bottom></border>
      </borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="11">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="1"/>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0"/>
        <xf numFmtId="0" fontId="2" fillId="0" borderId="0"/>
        <xf numFmtId="0" fontId="3" fillId="2" borderId="0" applyFont="1" applyFill="1"/>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="1" applyNumberFormat="1"/>
        <xf numFmtId="1" fontId="0" fillId="0" borderId="1" applyNumberFormat="1"/>
        <xf numFmtId="9" fontId="0" fillId="0" borderId="1" applyNumberFormat="1"/>
        <xf numFmtId="0" fontId="2" fillId="3" borderId="1" applyFont="1" applyFill="1"/>
        <xf numFmtId="164" fontId="2" fillId="3" borderId="1" applyFont="1" applyFill="1" applyNumberFormat="1"/>
        <xf numFmtId="1" fontId="2" fillId="3" borderId="1" applyFont="1" applyFill="1" applyNumberFormat="1"/>
        <xf numFmtId="9" fontId="2" fillId="3" borderId="1" applyFont="1" applyFill="1" applyNumberFormat="1"/>
      </cellXfs>
    </styleSheet>
    """
}
