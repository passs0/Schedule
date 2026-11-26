import Foundation

/*
 Pure-Swift Microsoft Project (.mpp) binary parser for MPP14+ (Project 2010 and later).

 Binary layout, field offsets, timestamp decoding, Var2Data string extraction,
 and TBkndCons predecessor parsing are ported from `msp-export` by Andrew Bergsma
 (https://github.com/andrewbergsma/msp-export), licensed under the MIT License:

   MIT License
   Copyright (c) 2026 abergsma
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:
   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.
 */

public enum MPPBinaryError: LocalizedError, Sendable {
    case unsupportedOrCorruptMPP(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedOrCorruptMPP(let detail):
            return "Could not parse binary .mpp file: \(detail)"
        }
    }
}

/// Parses binary Microsoft Project (`.mpp`, MPP14+) files natively in pure Swift
/// using `OLE2Reader`, without requiring Java or external dependencies.
public enum MPPBinaryParser {
    private static let mppEpoch = CalendarDay(year: 1983, month: 12, day: 31)
    private static let mppDateDivisor: Double = 65536.0
    private static let fixedMetaMagic: UInt32 = 0xFADFADBA
    private static let varMetaTaskName: UInt16 = 0x000E

    private struct TaskOffsets {
        let id: Int?
        let uniqueID: Int?
        let outlineLevel: Int?
        let duration: Int?
        let start: Int?
        let finish: Int?
        let summaryFlag: Int?
    }

    private static let offsets202 = TaskOffsets(
        id: 48, uniqueID: 52, outlineLevel: 18, duration: 132, start: 144, finish: 148, summaryFlag: 188
    )
    private static let offsets193 = TaskOffsets(
        id: 48, uniqueID: 52, outlineLevel: 18, duration: 132, start: 144, finish: 148, summaryFlag: 179
    )
    private static let offsets172 = TaskOffsets(
        id: 4, uniqueID: 0, outlineLevel: 146, duration: 84, start: 100, finish: 104, summaryFlag: 144
    )

    private static func offsets(for recordSize: Int) -> TaskOffsets {
        if recordSize == 172 { return offsets172 }
        if recordSize == 193 { return offsets193 }
        return offsets202
    }

    public static func parse(data: Data, fallbackName: String = "Imported Project") throws -> ProjectDocument {
        let ole = try OLE2Reader(data: data)

        let storages = ["   114", "   112", "   19", "   18"]
        guard let mainStorage = storages.first(where: { ole.exists([$0]) }) else {
            throw MPPBinaryError.unsupportedOrCorruptMPP("No supported MPP14+ storage found (older MPP8/9 or encrypted files are not supported).")
        }

        guard let fixedData = ole.readStream([mainStorage, "TBkndTask", "FixedData"]), !fixedData.isEmpty else {
            throw MPPBinaryError.unsupportedOrCorruptMPP("Missing TBkndTask/FixedData stream.")
        }
        let fixedMeta = ole.readStream([mainStorage, "TBkndTask", "FixedMeta"]) ?? Data()
        let var2Data = ole.readStream([mainStorage, "TBkndTask", "Var2Data"]) ?? Data()
        let varMeta = ole.readStream([mainStorage, "TBkndTask", "VarMeta"]) ?? Data()

        let varMetaStrings = parseVar2DataStrings(var2Data: var2Data, varMeta: varMeta)
        let fallbackNames = extractTaskNames(from: var2Data)

        var recordCount = 0
        var recordSize = 0
        if fixedMeta.count >= 12, fixedMeta.u32(at: 0) == fixedMetaMagic {
            recordCount = Int(fixedMeta.u32(at: 8))
            if recordCount > 0 {
                recordSize = fixedData.count / recordCount
            }
        }
        if recordCount == 0, !fallbackNames.isEmpty {
            for testSize in [172, 193, 202, 200, 204, 196, 208] {
                let testCount = fixedData.count / testSize
                if testCount >= fallbackNames.count && testCount <= fallbackNames.count + 5 {
                    recordSize = testSize
                    recordCount = testCount
                    break
                }
            }
            if recordCount == 0 {
                recordSize = max(1, fixedData.count / (fallbackNames.count + 1))
                recordCount = fixedData.count / recordSize
            }
        }

        guard recordCount > 0, recordSize > 0 else {
            throw MPPBinaryError.unsupportedOrCorruptMPP("No task records could be decoded.")
        }

        let off = offsets(for: recordSize)
        let cal = WorkingCalendar.standard

        struct RawTask {
            var id: Int
            var uniqueID: Int
            var title: String
            var outlineLevel: Int
            var start: CalendarDay
            var finish: CalendarDay?
            var durationDays: Int
            var isMilestone: Bool
            var isSummary: Bool
        }

        var rawTasks: [RawTask] = []
        var nameIndex = 0

        for i in 0..<recordCount {
            let base = i * recordSize
            guard base + recordSize <= fixedData.count else { break }
            let rec = fixedData.subdata(in: base..<(base + recordSize))

            // Skip null / deleted marker (-65536 / 0xFFFF0000)
            if rec.i32(at: 0) == -65536 { continue }

            var taskID = off.id.map { Int(rec.i32(at: $0)) } ?? i
            var uniqueID = off.uniqueID.map { Int(rec.i32(at: $0)) } ?? i
            if taskID <= 0 { taskID = i }
            if uniqueID <= 0 { uniqueID = i }

            var name = varMetaStrings[uniqueID]?[varMetaTaskName] ?? ""
            if name.isEmpty && nameIndex < fallbackNames.count {
                name = fallbackNames[nameIndex]
                nameIndex += 1
            } else if !name.isEmpty {
                nameIndex += 1
            }
            guard !name.isEmpty else { continue }

            var outlineLevel = 1
            if let olOff = off.outlineLevel, olOff + 2 <= recordSize {
                let rawOL = Int(rec.i16(at: olOff))
                if rawOL >= 0 && rawOL <= 50 {
                    outlineLevel = max(1, rawOL)
                }
            }

            let start = off.start.flatMap { sOff -> CalendarDay? in
                guard sOff + 4 <= recordSize else { return nil }
                return readTimestamp(rec, offset: sOff)
            } ?? .today

            let finish = off.finish.flatMap { fOff -> CalendarDay? in
                guard fOff + 4 <= recordSize else { return nil }
                return readTimestamp(rec, offset: fOff)
            }

            var durationDays = 1
            var isMilestone = false
            if let dOff = off.duration, dOff + 4 <= recordSize {
                let durRaw = rec.u32(at: dOff)
                if durRaw == 0 {
                    isMilestone = true
                    durationDays = 0
                } else if durRaw < 100_000_000 {
                    let minutes = Double(durRaw) / 10.0
                    durationDays = max(1, Int(round(minutes / 480.0)))
                }
            } else if let finish, finish >= start {
                durationDays = cal.workingDuration(from: start, to: finish)
            }

            var isSummary = false
            if let sOff = off.summaryFlag, sOff < recordSize {
                isSummary = rec[sOff] == 1
            }

            rawTasks.append(RawTask(
                id: taskID,
                uniqueID: uniqueID,
                title: name,
                outlineLevel: outlineLevel,
                start: start,
                finish: finish,
                durationDays: durationDays,
                isMilestone: isMilestone,
                isSummary: isSummary
            ))
        }

        guard !rawTasks.isEmpty else {
            throw MPPBinaryError.unsupportedOrCorruptMPP("No tasks with names were found in this .mpp file.")
        }

        // Reconstruct outline hierarchy
        var uuidByTaskID: [Int: UUID] = [:]
        var uuidByUniqueID: [Int: UUID] = [:]
        var scheduleTasks: [ScheduleTask] = []
        var stack: [(level: Int, id: UUID)] = []

        for (idx, raw) in rawTasks.enumerated() {
            let uuid = UUID()
            uuidByTaskID[raw.id] = uuid
            uuidByUniqueID[raw.uniqueID] = uuid

            while let last = stack.last, last.level >= raw.outlineLevel {
                stack.removeLast()
            }
            let parentID = stack.last?.id

            let task = ScheduleTask(
                id: uuid,
                identifier: "\(idx + 1)",
                title: raw.title,
                startDate: raw.start,
                endDate: raw.isMilestone ? raw.start : raw.finish,
                durationDays: raw.durationDays,
                isMilestone: raw.isMilestone,
                parentID: parentID,
                isManuallyScheduled: true,
                calendar: cal
            )
            scheduleTasks.append(task)
            stack.append((level: raw.outlineLevel, id: uuid))
        }

        // Parse predecessors from TBkndCons/FixedData (20-byte records)
        if let consData = ole.readStream([mainStorage, "TBkndCons", "FixedData"]), consData.count >= 20 {
            let indexByUUID = Dictionary(uniqueKeysWithValues: scheduleTasks.enumerated().map { ($0.element.id, $0.offset) })
            let linkCount = consData.count / 20
            for i in 0..<linkCount {
                let rec = consData.subdata(in: (i * 20)..<((i + 1) * 20))
                let predID = Int(rec.i32(at: 4))
                let succID = Int(rec.i32(at: 8))
                let typeCode = Int(rec.i32(at: 12))
                let lagRaw = Int(rec.i32(at: 16))
                guard predID > 0, succID > 0 else { continue }

                guard let predUUID = uuidByTaskID[predID] ?? uuidByUniqueID[predID],
                      let succUUID = uuidByTaskID[succID] ?? uuidByUniqueID[succID],
                      let succIdx = indexByUUID[succUUID],
                      predUUID != succUUID else { continue }

                let depType = DependencyType(mspTypeCode: typeCode) ?? .finishToStart
                let lagDays: Int
                if lagRaw != 458_752 && lagRaw > 0 {
                    lagDays = Int(round(Double(lagRaw) / 4800.0))
                } else {
                    lagDays = 0
                }

                if !SchedulingEngine.wouldCreateCycle(tasks: scheduleTasks, predecessorID: predUUID, successorID: succUUID) {
                    scheduleTasks[succIdx].dependencies.append(
                        TaskDependency(predecessorID: predUUID, type: depType, lagDays: lagDays)
                    )
                    scheduleTasks[succIdx].isManuallyScheduled = false
                }
            }
        }

        let projectStart = scheduleTasks.map(\.startDate).min() ?? .today
        let recalculated = SchedulingEngine.recalculateAll(tasks: scheduleTasks, projectStart: projectStart, calendar: cal)

        var doc = ProjectDocument(
            name: fallbackName,
            projectStartDate: projectStart,
            workingCalendar: cal,
            tasks: recalculated
        )
        doc.versions = [
            ProjectVersion(name: "Imported Baseline", notes: "Imported from Microsoft Project (.mpp)", tasks: recalculated)
        ]
        return doc
    }

    // MARK: - Binary Decoding Helpers

    private static func readTimestamp(_ data: Data, offset: Int) -> CalendarDay? {
        guard offset + 4 <= data.count else { return nil }
        let value = data.u32(at: offset)
        guard value >= 300_000_000 && value <= 1_500_000_000 else { return nil }
        let days = Int(floor(Double(value) / mppDateDivisor))
        return mppEpoch.addingCalendarDays(days)
    }

    private static func parseVar2DataStrings(var2Data: Data, varMeta: Data) -> [Int: [UInt16: String]] {
        var result: [Int: [UInt16: String]] = [:]
        guard varMeta.count >= 24, varMeta.u32(at: 0) == fixedMetaMagic else { return result }
        let itemCount = Int(varMeta.u32(at: 8))
        var offset = 24
        for _ in 0..<itemCount {
            guard offset + 12 <= varMeta.count else { break }
            let fieldInfo = varMeta.u32(at: offset)
            let recordID = Int(varMeta.u32(at: offset + 4))
            let dataOffset = Int(varMeta.u32(at: offset + 8))
            let fieldType = UInt16(fieldInfo & 0xFFFF)

            if dataOffset + 4 < var2Data.count {
                let strLen = Int(var2Data.u32(at: dataOffset))
                if strLen > 0 && strLen < 1000 && dataOffset + 4 + strLen <= var2Data.count {
                    let sub = var2Data.subdata(in: (dataOffset + 4)..<(dataOffset + 4 + strLen))
                    if let text = String(data: sub, encoding: .utf16LittleEndian)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines)),
                       !text.isEmpty {
                        result[recordID, default: [:]][fieldType] = text
                    }
                }
            }
            offset += 12
        }
        return result
    }

    private static func extractTaskNames(from var2Data: Data) -> [String] {
        var names: [String] = []
        var offset = 0
        while offset + 4 < var2Data.count {
            let length = Int(var2Data.u32(at: offset))
            if length >= 6 && length <= 500 && length % 2 == 0 && offset + 4 + length <= var2Data.count {
                let sub = var2Data.subdata(in: (offset + 4)..<(offset + 4 + length))
                if let raw = String(data: sub, encoding: .utf16LittleEndian) {
                    let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
                    if text.count >= 2, let first = text.unicodeScalars.first,
                       first.isASCII && CharacterSet.alphanumerics.contains(first) {
                        names.append(text)
                        offset += 4 + length
                        continue
                    }
                }
            }
            offset += 1
        }
        return names
    }
}

private extension Data {
    func u32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func i32(at offset: Int) -> Int32 {
        Int32(bitPattern: u32(at: offset))
    }

    func i16(at offset: Int) -> Int16 {
        guard offset + 2 <= count else { return 0 }
        let u = UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
        return Int16(bitPattern: u)
    }
}
