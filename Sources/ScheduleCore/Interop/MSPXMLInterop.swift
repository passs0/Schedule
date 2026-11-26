import Foundation

public enum MSPXMLInteropError: LocalizedError, Sendable {
    case invalidXML(String)
    case emptyProject

    public var errorDescription: String? {
        switch self {
        case .invalidXML(let detail):
            return "Could not parse Microsoft Project XML: \(detail)"
        case .emptyProject:
            return "The Microsoft Project XML file did not contain any tasks."
        }
    }
}

/// Imports and exports Microsoft Project XML (MSPDI `.xml`) files.
/// Preserves task hierarchy (OutlineLevel), dates, durations, milestones,
/// completion percentages, notes, and predecessor dependencies (FS/SS/FF/SF + lag).
public enum MSPXMLInterop {

    // MARK: - Export

    public static func exportXML(for document: ProjectDocument) -> Data {
        let tasks = document.tasks
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var uidByID: [UUID: Int] = [:]
        for (idx, task) in tasks.enumerated() {
            uidByID[task.id] = idx + 1
        }

        var childrenSet = Set<UUID>()
        for task in tasks {
            if let pid = task.parentID, taskMap[pid] != nil {
                childrenSet.insert(pid)
            }
        }

        func outlineLevel(for task: ScheduleTask) -> Int {
            var level = 1
            var cur = task.parentID
            while let pid = cur, let p = taskMap[pid], level < 32 {
                level += 1
                cur = p.parentID
            }
            return level
        }

        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Project xmlns="http://schemas.microsoft.com/project">
          <Name>\(xmlEscape(document.name))</Name>
          <Title>\(xmlEscape(document.name))</Title>
          <StartDate>\(document.projectStartDate.isoString)T08:00:00</StartDate>
          <CalendarUID>1</CalendarUID>
          <MinutesPerDay>480</MinutesPerDay>
          <MinutesPerWeek>2400</MinutesPerWeek>
          <DaysPerMonth>20</DaysPerMonth>
          <Tasks>
            <Task>
              <UID>0</UID>
              <ID>0</ID>
              <Name>\(xmlEscape(document.name))</Name>
              <OutlineLevel>0</OutlineLevel>
              <Summary>1</Summary>
            </Task>
        """

        for (idx, task) in tasks.enumerated() {
            let uid = idx + 1
            let level = outlineLevel(for: task)
            let isSummary = childrenSet.contains(task.id) ? 1 : 0
            let isMilestone = task.isMilestone ? 1 : 0
            let hours = task.isMilestone ? 0 : task.durationDays * 8
            let pct = Int(round(task.percentComplete))

            xml += """
                <Task>
                  <UID>\(uid)</UID>
                  <ID>\(uid)</ID>
                  <Name>\(xmlEscape(task.title))</Name>
                  <WBS>\(xmlEscape(task.identifier))</WBS>
                  <OutlineLevel>\(level)</OutlineLevel>
                  <Start>\(task.startDate.isoString)T08:00:00</Start>
                  <Finish>\(task.endDate.isoString)T17:00:00</Finish>
                  <Duration>PT\(hours)H0M0S</Duration>
                  <Milestone>\(isMilestone)</Milestone>
                  <Summary>\(isSummary)</Summary>
                  <PercentComplete>\(pct)</PercentComplete>
            """
            if !task.notes.isEmpty {
                xml += "      <Notes>\(xmlEscape(task.notes))</Notes>\n"
            }
            for dep in task.dependencies {
                if let predUID = uidByID[dep.predecessorID] {
                    // 1 working day (8h) = 480 minutes = 4800 tenths of a minute
                    let linkLag = dep.lagDays * 4800
                    xml += """
                          <PredecessorLink>
                            <PredecessorUID>\(predUID)</PredecessorUID>
                            <Type>\(dep.type.mspTypeCode)</Type>
                            <LinkLag>\(linkLag)</LinkLag>
                            <LagFormat>7</LagFormat>
                          </PredecessorLink>
                    """
                }
            }
            xml += "    </Task>\n"
        }

        xml += """
          </Tasks>
        </Project>
        """
        return Data(xml.utf8)
    }

    public static func export(document: ProjectDocument, to url: URL) throws {
        let data = exportXML(for: document)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Import

    public static func importXML(from data: Data, fallbackName: String = "Imported Project") throws -> ProjectDocument {
        let parserDelegate = MSPXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "Malformed XML"
            throw MSPXMLInteropError.invalidXML(reason)
        }

        let rawTasks = parserDelegate.tasks.filter { $0.uid != 0 }
        guard !rawTasks.isEmpty else {
            throw MSPXMLInteropError.emptyProject
        }

        var uuidByUID: [Int: UUID] = [:]
        for raw in rawTasks {
            uuidByUID[raw.uid] = UUID()
        }

        let cal = WorkingCalendar.standard
        var stackByLevel: [(level: Int, id: UUID)] = []
        var scheduleTasks: [ScheduleTask] = []

        for (index, raw) in rawTasks.enumerated() {
            guard let taskID = uuidByUID[raw.uid] else { continue }
            let level = max(1, raw.outlineLevel)
            while let last = stackByLevel.last, last.level >= level {
                stackByLevel.removeLast()
            }
            let parentID = stackByLevel.last?.id

            let start = parseDay(raw.start) ?? .today
            let end = parseDay(raw.finish)
            let isMilestone = raw.isMilestone
            let duration = isMilestone ? 0 : max(1, parseDurationDays(raw.duration) ?? (end.map { cal.workingDuration(from: start, to: $0) } ?? 1))

            let deps: [TaskDependency] = raw.predecessors.compactMap { link in
                guard let predID = uuidByUID[link.predecessorUID] else { return nil }
                let type = DependencyType(mspTypeCode: link.type) ?? .finishToStart
                let lagDays = Int(round(Double(link.linkLag) / 4800.0))
                return TaskDependency(predecessorID: predID, type: type, lagDays: lagDays)
            }

            let identifier = raw.wbs.isEmpty ? "\(index + 1)" : raw.wbs
            let task = ScheduleTask(
                id: taskID,
                identifier: identifier,
                title: raw.name.isEmpty ? "Untitled Task" : raw.name,
                startDate: start,
                endDate: end,
                durationDays: duration,
                isMilestone: isMilestone,
                percentComplete: raw.percentComplete,
                notes: raw.notes,
                parentID: parentID,
                dependencies: deps,
                calendar: cal
            )
            scheduleTasks.append(task)
            stackByLevel.append((level: level, id: taskID))
        }

        let projectStart = parseDay(parserDelegate.projectStart) ?? (scheduleTasks.map(\.startDate).min() ?? .today)
        let docName = parserDelegate.projectName.isEmpty ? fallbackName : parserDelegate.projectName

        let recalculated = SchedulingEngine.recalculateAll(
            tasks: scheduleTasks,
            projectStart: projectStart,
            calendar: cal
        )

        var doc = ProjectDocument(
            name: docName,
            projectStartDate: projectStart,
            workingCalendar: cal,
            tasks: recalculated
        )
        doc.versions = [
            ProjectVersion(name: "Imported Baseline", notes: "Imported from Microsoft Project XML", tasks: recalculated)
        ]
        return doc
    }

    // MARK: - Parsing Helpers

    private static func parseDay(_ iso: String) -> CalendarDay? {
        guard iso.count >= 10 else { return nil }
        let prefix = String(iso.prefix(10))
        let parts = prefix.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else { return nil }
        return CalendarDay(year: y, month: m, day: d)
    }

    private static func parseDurationDays(_ isoDuration: String) -> Int? {
        // Format: PT8H0M0S or PT40H0M0S
        guard isoDuration.hasPrefix("PT") else { return nil }
        var hours = 0
        if let hIndex = isoDuration.firstIndex(of: "H") {
            let numStr = isoDuration[isoDuration.index(isoDuration.startIndex, offsetBy: 2)..<hIndex]
            hours = Int(numStr) ?? 0
        }
        return max(1, Int(ceil(Double(hours) / 8.0)))
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private final class MSPXMLParserDelegate: NSObject, XMLParserDelegate {
    struct RawLink {
        var predecessorUID: Int = 0
        var type: Int = 1
        var linkLag: Int = 0
    }

    struct RawTask {
        var uid: Int = 0
        var name: String = ""
        var wbs: String = ""
        var outlineLevel: Int = 1
        var start: String = ""
        var finish: String = ""
        var duration: String = ""
        var isMilestone: Bool = false
        var percentComplete: Double = 0
        var notes: String = ""
        var predecessors: [RawLink] = []
    }

    var projectName: String = ""
    var projectStart: String = ""
    var tasks: [RawTask] = []

    private var inTasks = false
    private var currentTask: RawTask?
    private var currentLink: RawLink?
    private var currentElement: String = ""
    private var buffer: String = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        buffer = ""
        if elementName == "Tasks" {
            inTasks = true
        } else if inTasks && elementName == "Task" {
            currentTask = RawTask()
        } else if currentTask != nil && elementName == "PredecessorLink" {
            currentLink = RawLink()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if var link = currentLink {
            switch elementName {
            case "PredecessorUID": link.predecessorUID = Int(trimmed) ?? 0; currentLink = link
            case "Type": link.type = Int(trimmed) ?? 1; currentLink = link
            case "LinkLag": link.linkLag = Int(trimmed) ?? 0; currentLink = link
            case "PredecessorLink":
                currentTask?.predecessors.append(link)
                currentLink = nil
            default:
                currentLink = link
            }
            buffer = ""
            return
        }

        if var task = currentTask {
            switch elementName {
            case "UID": task.uid = Int(trimmed) ?? 0; currentTask = task
            case "Name": task.name = trimmed; currentTask = task
            case "WBS": task.wbs = trimmed; currentTask = task
            case "OutlineLevel": task.outlineLevel = Int(trimmed) ?? 1; currentTask = task
            case "Start": task.start = trimmed; currentTask = task
            case "Finish": task.finish = trimmed; currentTask = task
            case "Duration": task.duration = trimmed; currentTask = task
            case "Milestone": task.isMilestone = (trimmed == "1" || trimmed.lowercased() == "true"); currentTask = task
            case "PercentComplete": task.percentComplete = Double(trimmed) ?? 0; currentTask = task
            case "Notes": task.notes = trimmed; currentTask = task
            case "Task":
                tasks.append(task)
                currentTask = nil
            default:
                currentTask = task
            }
            buffer = ""
            return
        }

        if !inTasks {
            if elementName == "Title" || (elementName == "Name" && projectName.isEmpty) {
                projectName = trimmed
            } else if elementName == "StartDate" {
                projectStart = trimmed
            }
        } else if elementName == "Tasks" {
            inTasks = false
        }
        buffer = ""
    }
}
