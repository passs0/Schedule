import Foundation

public enum SpreadsheetImportError: LocalizedError, Sendable {
    case noWorksheetFound
    case noTasksFound

    public var errorDescription: String? {
        switch self {
        case .noWorksheetFound:
            return "Could not find a worksheet in the Excel file."
        case .noTasksFound:
            return "No tasks were found in the spreadsheet."
        }
    }
}

/// Imports task lists from Excel (`.xlsx`), CSV (`.csv`), and TSV (`.tsv`) files,
/// preserving hierarchy when WBS IDs, outline levels, or indentation are present.
public enum SpreadsheetImporter {

    public static func importXLSX(from data: Data, projectName: String = "Imported Spreadsheet") throws -> ProjectDocument {
        let entries = try ZipReader.readEntries(from: data)
        let sharedStrings: [String]
        if let ssData = entries["xl/sharedStrings.xml"] {
            sharedStrings = SharedStringsParser.parse(ssData)
        } else {
            sharedStrings = []
        }

        let sheetKey = entries.keys
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()
            .first
        guard let sheetKey, let sheetData = entries[sheetKey] else {
            throw SpreadsheetImportError.noWorksheetFound
        }

        let rows = SheetRowsParser.parse(sheetData, sharedStrings: sharedStrings)
        return try buildProject(from: rows, projectName: projectName)
    }

    public static func importDelimited(from data: Data, delimiter: Character? = nil, projectName: String = "Imported Spreadsheet") throws -> ProjectDocument {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .macOSRoman)
            ?? ""
        let sep = delimiter ?? detectDelimiter(in: text)
        let rows = parseCSV(text, delimiter: sep)
        return try buildProject(from: rows, projectName: projectName)
    }

    // MARK: - Smart Table & Hierarchy Reconstruction

    static func buildProject(from rawRows: [[String]], projectName: String) throws -> ProjectDocument {
        let nonEmptyRows = rawRows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard !nonEmptyRows.isEmpty else {
            throw SpreadsheetImportError.noTasksFound
        }

        let mapping = detectHeader(in: nonEmptyRows)
        let dataRows = mapping.headerRowIndex.map { Array(nonEmptyRows.dropFirst($0 + 1)) } ?? nonEmptyRows

        let cal = WorkingCalendar.standard
        let epoch = CalendarDay(year: 1899, month: 12, day: 30)
        var tasks: [ScheduleTask] = []

        // Hierarchy tracking
        var idToUUID: [String: UUID] = [:]
        var stackByLevel: [(level: Int, id: UUID)] = []

        for (idx, row) in dataRows.enumerated() {
            func cell(_ col: Int?) -> String {
                guard let col, col >= 0, col < row.count else { return "" }
                return row[col]
            }

            let rawTitle = cell(mapping.titleCol)
            let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle.isEmpty { continue }

            let rawID = cell(mapping.idCol).trimmingCharacters(in: .whitespacesAndNewlines)
            let identifier = rawID.isEmpty ? "\(tasks.count + 1)" : rawID

            // Determine hierarchy level / parentID
            var parentID: UUID?
            var level = 1

            if let explicitLevel = Int(cell(mapping.levelCol).trimmingCharacters(in: .whitespacesAndNewlines)), explicitLevel >= 1 {
                level = explicitLevel
            } else if !rawID.isEmpty, rawID.contains(".") {
                let parts = rawID.split(separator: ".")
                level = parts.count
                let parentCode = parts.dropLast().joined(separator: ".")
                parentID = idToUUID[parentCode]
            } else {
                let leadingSpaces = rawTitle.prefix(while: { $0 == " " || $0 == "\t" }).count
                level = 1 + (leadingSpaces / 2)
            }

            while let last = stackByLevel.last, last.level >= level {
                stackByLevel.removeLast()
            }
            if parentID == nil {
                parentID = stackByLevel.last?.id
            }

            let typeStr = cell(mapping.typeCol).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let parsedDur = parseDuration(cell(mapping.durCol))
            let isMilestone = typeStr.contains("milestone") || parsedDur == 0

            let start = parseDate(cell(mapping.startCol), epoch: epoch) ?? .today
            let end = parseDate(cell(mapping.endCol), epoch: epoch)
            let duration: Int
            if isMilestone {
                duration = 0
            } else if let d = parsedDur, d > 0 {
                duration = d
            } else if let end, end >= start {
                duration = cal.workingDuration(from: start, to: end)
            } else {
                duration = 3
            }

            let progress = parsePercent(cell(mapping.pctCol))
            let notes = cell(mapping.notesCol).trimmingCharacters(in: .whitespacesAndNewlines)

            let taskID = UUID()
            let task = ScheduleTask(
                id: taskID,
                identifier: identifier,
                title: trimmedTitle,
                startDate: start,
                endDate: isMilestone ? start : end,
                durationDays: duration,
                isMilestone: isMilestone,
                percentComplete: progress,
                notes: notes,
                parentID: parentID,
                isManuallyScheduled: parseDate(cell(mapping.startCol), epoch: epoch) != nil,
                calendar: cal
            )
            tasks.append(task)
            idToUUID[identifier] = taskID
            stackByLevel.append((level: level, id: taskID))

            // Optional predecessor ID linking if a Predecessor/Depends On column is present
            if let depsCol = mapping.depsCol {
                let depStr = cell(depsCol).trimmingCharacters(in: .whitespacesAndNewlines)
                if !depStr.isEmpty {
                    let tokens = depStr.split(whereSeparator: { $0 == "," || $0 == ";" })
                    var deps: [TaskDependency] = []
                    for tok in tokens {
                        let key = tok.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let predID = idToUUID[key], predID != taskID {
                            deps.append(TaskDependency(predecessorID: predID, type: .finishToStart, lagDays: 0))
                        }
                    }
                    if !deps.isEmpty {
                        tasks[tasks.count - 1].dependencies = deps
                        tasks[tasks.count - 1].isManuallyScheduled = false
                    }
                }
            }

            _ = idx
        }

        guard !tasks.isEmpty else {
            throw SpreadsheetImportError.noTasksFound
        }

        let projectStart = tasks.map(\.startDate).min() ?? .today
        let recalculated = SchedulingEngine.recalculateAll(tasks: tasks, projectStart: projectStart, calendar: cal)

        var doc = ProjectDocument(
            name: projectName,
            projectStartDate: projectStart,
            workingCalendar: cal,
            tasks: recalculated
        )
        doc.versions = [
            ProjectVersion(name: "Imported Baseline", notes: "Imported from spreadsheet", tasks: recalculated)
        ]
        return doc
    }

    // MARK: - Header & Value Parsing

    private struct ColumnMapping {
        var headerRowIndex: Int?
        var idCol: Int?
        var titleCol: Int = 0
        var typeCol: Int?
        var startCol: Int?
        var endCol: Int?
        var durCol: Int?
        var pctCol: Int?
        var levelCol: Int?
        var notesCol: Int?
        var depsCol: Int?
    }

    private static func detectHeader(in rows: [[String]]) -> ColumnMapping {
        let limit = min(10, rows.count)
        for r in 0..<limit {
            let lowered = rows[r].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            if let titleIdx = lowered.firstIndex(where: {
                $0 == "task" || $0 == "task name" || $0 == "name" || $0 == "title" || $0 == "activity" || $0 == "deliverable"
            }) {
                var map = ColumnMapping(headerRowIndex: r, titleCol: titleIdx)
                for (c, h) in lowered.enumerated() where c != titleIdx {
                    if h == "id" || h == "#" || h == "wbs" || h == "task id" {
                        map.idCol = c
                    } else if h == "type" || h == "kind" {
                        map.typeCol = c
                    } else if h.contains("start") {
                        map.startCol = c
                    } else if h.contains("end") || h.contains("finish") || h.contains("due") {
                        map.endCol = c
                    } else if h.contains("duration") || h == "days" || h == "dur" {
                        map.durCol = c
                    } else if h.contains("%") || h.contains("complete") || h.contains("progress") {
                        map.pctCol = c
                    } else if h == "level" || h.contains("outline") || h.contains("indent") {
                        map.levelCol = c
                    } else if h.contains("note") || h.contains("desc") || h.contains("comment") {
                        map.notesCol = c
                    } else if h.contains("predecessor") || h.contains("depends") {
                        map.depsCol = c
                    }
                }
                return map
            }
        }

        // No header row: if column 0 looks like WBS IDs ("1", "1.1") and column 1 has text, use col 1 as title.
        if let first = rows.first, first.count >= 2 {
            let c0 = first[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if c0.allSatisfy({ $0.isNumber || $0 == "." }) && !c0.isEmpty {
                return ColumnMapping(headerRowIndex: nil, idCol: 0, titleCol: 1)
            }
        }
        return ColumnMapping(headerRowIndex: nil, titleCol: 0)
    }

    private static func parseDate(_ raw: String, epoch: CalendarDay) -> CalendarDay? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }

        // Excel serial date (e.g. 46350 or 46350.5)
        if let serial = Double(s), serial > 20_000 && serial < 100_000 {
            return epoch.addingCalendarDays(Int(floor(serial)))
        }

        // ISO yyyy-MM-dd
        if s.count >= 10 {
            let parts = String(s.prefix(10)).split(separator: "-")
            if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
                return CalendarDay(year: y, month: m, day: d)
            }
        }

        let formats = ["MM/dd/yyyy", "M/d/yyyy", "yyyy/MM/dd", "MMM d, yyyy", "d MMM yyyy"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            df.dateFormat = fmt
            if let date = df.date(from: s) {
                return CalendarDay(date: date, calendar: .current)
            }
        }
        return nil
    }

    private static func parseDuration(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }
        let digits = s.prefix(while: { $0.isNumber || $0 == "." })
        if let val = Double(digits) {
            return Int(round(val))
        }
        return nil
    }

    private static func parsePercent(_ raw: String) -> Double {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return 0 }
        let hasPct = s.contains("%")
        let numStr = s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let val = Double(numStr) else { return 0 }
        if !hasPct && val > 0 && val <= 1.0 {
            return min(100, max(0, val * 100.0))
        }
        return min(100, max(0, val))
    }

    // MARK: - CSV / TSV Parser

    private static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first ?? ""
        let tabs = firstLine.filter { $0 == "\t" }.count
        let commas = firstLine.filter { $0 == "," }.count
        return tabs > commas ? "\t" : ","
    }

    private static func parseCSV(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == delimiter {
                    currentRow.append(field)
                    field = ""
                } else if ch == "\r" {
                    if i + 1 < chars.count && chars[i + 1] == "\n" {
                        i += 1
                    }
                    currentRow.append(field)
                    rows.append(currentRow)
                    currentRow = []
                    field = ""
                } else if ch == "\n" {
                    currentRow.append(field)
                    rows.append(currentRow)
                    currentRow = []
                    field = ""
                } else {
                    field.append(ch)
                }
            }
            i += 1
        }
        if !field.isEmpty || !currentRow.isEmpty {
            currentRow.append(field)
            rows.append(currentRow)
        }
        return rows
    }
}

// MARK: - OOXML Parsers

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var inSI = false
    private var inT = false
    private var current = ""

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" {
            inSI = true
            current = ""
        } else if inSI && elementName == "t" {
            inT = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" {
            inT = false
        } else if elementName == "si" {
            strings.append(current)
            inSI = false
        }
    }
}

private final class SheetRowsParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [[String]] = []
    private var currentRow: [Int: String] = [:]
    private var currentCellType: String = ""
    private var currentColIndex: Int = 0
    private var inValue = false
    private var inInlineText = false
    private var buffer = ""

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = SheetRowsParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" {
            currentRow = [:]
        } else if elementName == "c" {
            currentCellType = attributeDict["t"] ?? ""
            currentColIndex = columnIndex(from: attributeDict["r"] ?? "")
            buffer = ""
        } else if elementName == "v" {
            inValue = true
            buffer = ""
        } else if elementName == "t" {
            inInlineText = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue || inInlineText {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" {
            inValue = false
            if currentCellType == "s", let idx = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines)), idx < sharedStrings.count {
                currentRow[currentColIndex] = sharedStrings[idx]
            } else {
                currentRow[currentColIndex] = buffer
            }
        } else if elementName == "t" {
            inInlineText = false
            currentRow[currentColIndex] = buffer
        } else if elementName == "row" {
            let maxCol = currentRow.keys.max() ?? -1
            if maxCol >= 0 {
                var arr = Array(repeating: "", count: maxCol + 1)
                for (c, val) in currentRow {
                    arr[c] = val
                }
                rows.append(arr)
            }
        }
    }

    private func columnIndex(from ref: String) -> Int {
        var result = 0
        for ch in ref.uppercased() where ch >= "A" && ch <= "Z" {
            result = result * 26 + Int(ch.asciiValue! - Character("A").asciiValue! + 1)
        }
        return max(0, result - 1)
    }
}
