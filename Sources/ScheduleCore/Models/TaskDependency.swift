import Foundation

/// Underlying scheduling relationship type.
/// Hidden from the default UI in favor of plain-English descriptions in `HumanDependency`.
public enum DependencyType: String, Codable, CaseIterable, Hashable, Sendable {
    case finishToStart = "FS"
    case startToStart = "SS"
    case finishToFinish = "FF"
    case startToFinish = "SF"

    /// Microsoft Project XML `PredecessorLink/Type` integer mapping:
    /// 0 = FF, 1 = FS, 2 = SF, 3 = SS.
    public var mspTypeCode: Int {
        switch self {
        case .finishToFinish: return 0
        case .finishToStart: return 1
        case .startToFinish: return 2
        case .startToStart: return 3
        }
    }

    public init?(mspTypeCode: Int) {
        switch mspTypeCode {
        case 0: self = .finishToFinish
        case 1: self = .finishToStart
        case 2: self = .startToFinish
        case 3: self = .startToStart
        default: return nil
        }
    }
}

/// A directed dependency from a predecessor task to the owning successor task.
public struct TaskDependency: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var predecessorID: UUID
    public var type: DependencyType
    /// Positive values represent a waiting period (lag) in working days;
    /// negative values represent an overlap (lead) in working days.
    public var lagDays: Int

    public init(
        id: UUID = UUID(),
        predecessorID: UUID,
        type: DependencyType = .finishToStart,
        lagDays: Int = 0
    ) {
        self.id = id
        self.predecessorID = predecessorID
        self.type = type
        self.lagDays = lagDays
    }
}
