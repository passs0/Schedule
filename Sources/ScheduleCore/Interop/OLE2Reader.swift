import Foundation

/// Pure-Swift Microsoft OLE2 Compound File Binary Format (CFBF) reader.
/// Supports FAT, DIFAT, MiniFAT/MiniStream (< 4096 bytes), and directory tree traversal.
public struct OLE2Reader: Sendable {
    public enum OLE2Error: LocalizedError, Sendable {
        case invalidHeader
        case streamNotFound([String])

        public var errorDescription: String? {
            switch self {
            case .invalidHeader:
                return "Not a valid OLE2 Compound Document."
            case .streamNotFound(let path):
                return "Could not find OLE2 stream at path: \(path.joined(separator: "/"))"
            }
        }
    }

    private struct DirectoryEntry: Sendable {
        let name: String
        let objectType: UInt8 // 1 = storage, 2 = stream, 5 = root
        let leftSiblingID: UInt32
        let rightSiblingID: UInt32
        let childID: UInt32
        let startSector: UInt32
        let streamSize: UInt64
    }

    private static let endOfChain: UInt32 = 0xFFFFFFFE
    private static let freeSector: UInt32 = 0xFFFFFFFF
    private static let noStream: UInt32 = 0xFFFFFFFF

    private let data: Data
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniStreamCutoff: Int
    private let fat: [UInt32]
    private let miniFAT: [UInt32]
    private let miniStreamData: Data
    private let entries: [DirectoryEntry]

    public static func isOLE2(_ data: Data) -> Bool {
        let sig: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        return data.count >= 512 && Array(data.prefix(8)) == sig
    }

    public init(data: Data) throws {
        guard Self.isOLE2(data) else { throw OLE2Error.invalidHeader }
        self.data = data

        let sectorShift = Int(data.u16LE(at: 30))
        let miniSectorShift = Int(data.u16LE(at: 32))
        self.sectorSize = 1 << sectorShift
        self.miniSectorSize = 1 << miniSectorShift
        self.miniStreamCutoff = Int(data.u32LE(at: 56))

        let firstDirSector = data.u32LE(at: 48)
        let firstMiniFATSector = data.u32LE(at: 60)
        let numMiniFATSectors = Int(data.u32LE(at: 64))
        let firstDIFATSector = data.u32LE(at: 68)
        let numDIFATSectors = Int(data.u32LE(at: 72))

        // 1. Collect FAT sector indices from header DIFAT (109 entries) + DIFAT chain
        var fatSectorIDs: [UInt32] = []
        for i in 0..<109 {
            let sid = data.u32LE(at: 76 + i * 4)
            if sid < Self.freeSector && sid != Self.endOfChain {
                fatSectorIDs.append(sid)
            }
        }
        var difatSec = firstDIFATSector
        var difatGuard = 0
        while difatSec < Self.endOfChain && difatGuard < numDIFATSectors + 4 {
            let off = (Int(difatSec) + 1) * sectorSize
            guard off + sectorSize <= data.count else { break }
            let entriesPerSec = (sectorSize / 4) - 1
            for i in 0..<entriesPerSec {
                let sid = data.u32LE(at: off + i * 4)
                if sid < Self.freeSector && sid != Self.endOfChain {
                    fatSectorIDs.append(sid)
                }
            }
            difatSec = data.u32LE(at: off + entriesPerSec * 4)
            difatGuard += 1
        }

        // 2. Build FAT table
        var fatTable: [UInt32] = []
        fatTable.reserveCapacity(fatSectorIDs.count * (sectorSize / 4))
        for sid in fatSectorIDs {
            let off = (Int(sid) + 1) * sectorSize
            guard off + sectorSize <= data.count else { continue }
            for i in 0..<(sectorSize / 4) {
                fatTable.append(data.u32LE(at: off + i * 4))
            }
        }
        self.fat = fatTable

        // 3. Read Directory Stream
        let dirData = Self.readSectorChain(start: firstDirSector, data: data, sectorSize: sectorSize, fat: fatTable)
        var parsedEntries: [DirectoryEntry] = []
        let count = dirData.count / 128
        for i in 0..<count {
            let base = i * 128
            let nameLen = min(64, Int(dirData.u16LE(at: base + 64)))
            let nameData = nameLen >= 2 ? dirData.subdata(in: base..<(base + nameLen - 2)) : Data()
            let name = String(data: nameData, encoding: .utf16LittleEndian) ?? ""
            let objType = dirData[base + 66]
            let left = dirData.u32LE(at: base + 68)
            let right = dirData.u32LE(at: base + 72)
            let child = dirData.u32LE(at: base + 76)
            let startSec = dirData.u32LE(at: base + 116)
            let sizeLow = UInt64(dirData.u32LE(at: base + 120))
            let sizeHigh = sectorSize > 512 ? UInt64(dirData.u32LE(at: base + 124)) : 0
            let streamSize = sizeLow | (sizeHigh << 32)
            parsedEntries.append(DirectoryEntry(
                name: name,
                objectType: objType,
                leftSiblingID: left,
                rightSiblingID: right,
                childID: child,
                startSector: startSec,
                streamSize: streamSize
            ))
        }
        self.entries = parsedEntries

        // 4. Read MiniFAT
        var mFat: [UInt32] = []
        if firstMiniFATSector < Self.endOfChain && numMiniFATSectors > 0 {
            let miniFatData = Self.readSectorChain(start: firstMiniFATSector, data: data, sectorSize: sectorSize, fat: fatTable)
            for i in 0..<(miniFatData.count / 4) {
                mFat.append(miniFatData.u32LE(at: i * 4))
            }
        }
        self.miniFAT = mFat

        // 5. Read Root Entry's MiniStream
        if let root = parsedEntries.first, root.objectType == 5, root.startSector < Self.endOfChain {
            let raw = Self.readSectorChain(start: root.startSector, data: data, sectorSize: sectorSize, fat: fatTable)
            self.miniStreamData = raw.prefix(Int(min(UInt64(raw.count), root.streamSize)))
        } else {
            self.miniStreamData = Data()
        }
    }

    public func exists(_ path: [String]) -> Bool {
        findEntry(at: path) != nil
    }

    public func readStream(_ path: [String]) -> Data? {
        guard let entry = findEntry(at: path), entry.objectType == 2 else { return nil }
        let targetLen = Int(entry.streamSize)
        if targetLen == 0 { return Data() }

        if targetLen < miniStreamCutoff && !miniStreamData.isEmpty {
            var out = Data()
            var sec = entry.startSector
            var guardCount = 0
            while sec < Self.endOfChain && guardCount < 1_000_000 {
                let off = Int(sec) * miniSectorSize
                if off + miniSectorSize <= miniStreamData.count {
                    out.append(miniStreamData.subdata(in: off..<(off + miniSectorSize)))
                }
                guard Int(sec) < miniFAT.count else { break }
                sec = miniFAT[Int(sec)]
                guardCount += 1
            }
            return out.prefix(targetLen)
        } else {
            let raw = Self.readSectorChain(start: entry.startSector, data: data, sectorSize: sectorSize, fat: fat)
            return raw.prefix(min(targetLen, raw.count))
        }
    }

    private func findEntry(at path: [String]) -> DirectoryEntry? {
        guard !entries.isEmpty, !path.isEmpty else { return nil }
        var currentChildID = entries[0].childID
        var found: DirectoryEntry?

        for (depth, segment) in path.enumerated() {
            guard let matched = searchBST(rootID: currentChildID, name: segment) else {
                return nil
            }
            if depth == path.count - 1 {
                found = matched
            } else {
                currentChildID = matched.childID
            }
        }
        return found
    }

    private func searchBST(rootID: UInt32, name: String) -> DirectoryEntry? {
        var stack: [UInt32] = [rootID]
        var visited = Set<UInt32>()
        while let id = stack.popLast() {
            guard id != Self.noStream, Int(id) < entries.count, !visited.contains(id) else { continue }
            visited.insert(id)
            let e = entries[Int(id)]
            if e.name == name {
                return e
            }
            if e.leftSiblingID != Self.noStream { stack.append(e.leftSiblingID) }
            if e.rightSiblingID != Self.noStream { stack.append(e.rightSiblingID) }
        }
        return nil
    }

    private static func readSectorChain(start: UInt32, data: Data, sectorSize: Int, fat: [UInt32]) -> Data {
        var out = Data()
        var sec = start
        var guardCount = 0
        while sec < endOfChain && guardCount < 1_000_000 {
            let off = (Int(sec) + 1) * sectorSize
            if off + sectorSize <= data.count {
                out.append(data.subdata(in: off..<(off + sectorSize)))
            }
            guard Int(sec) < fat.count else { break }
            sec = fat[Int(sec)]
            guardCount += 1
        }
        return out
    }
}

private extension Data {
    func u16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
