import Foundation

/// Translates technical scheduling relationships (FS, SS, FF, SF + lag/lead)
/// into plain-English descriptions suitable for everyday users.
public enum HumanDependency {
    /// Picker label shown when choosing a relationship type in plain English.
    public static func pickerLabel(for type: DependencyType) -> String {
        switch type {
        case .finishToStart:
            return "Start after the other task is completed"
        case .startToStart:
            return "Begin at the same time as the other task"
        case .finishToFinish:
            return "Finish when the other task finishes"
        case .startToFinish:
            return "Finish before the other task can begin"
        }
    }

    /// Short plain-English phrase describing the dependency relative to `predecessorName`.
    public static func describe(
        _ dependency: TaskDependency,
        predecessorName: String,
        successorName: String? = nil
    ) -> String {
        let target = predecessorName.isEmpty ? "Untitled Task" : predecessorName
        let subject = successorName.map { $0.isEmpty ? "This task" : $0 } ?? "This task"
        let timing = timingPhrase(lagDays: dependency.lagDays)

        switch dependency.type {
        case .finishToStart:
            if dependency.lagDays == 0 {
                return "\(subject) starts after \"\(target)\" is completed"
            } else {
                return "\(subject) starts \(timing) \"\(target)\" is completed"
            }
        case .startToStart:
            if dependency.lagDays == 0 {
                return "\(subject) begins at the same time as \"\(target)\""
            } else {
                return "\(subject) begins \(timing) \"\(target)\" starts"
            }
        case .finishToFinish:
            if dependency.lagDays == 0 {
                return "\(subject) finishes when \"\(target)\" finishes"
            } else {
                return "\(subject) finishes \(timing) \"\(target)\" finishes"
            }
        case .startToFinish:
            if dependency.lagDays == 0 {
                return "\(subject) must finish before \"\(target)\" can begin"
            } else {
                return "\(subject) finishes \(timing) \"\(target)\" begins"
            }
        }
    }

    /// Concise scannable label for table cells and chips (no technical abbreviations).
    public static func compactLabel(
        _ dependency: TaskDependency,
        predecessorName: String
    ) -> String {
        let target = predecessorName.isEmpty ? "Untitled" : predecessorName
        let lagSuffix: String
        if dependency.lagDays > 0 {
            lagSuffix = " +\(dependency.lagDays)d"
        } else if dependency.lagDays < 0 {
            lagSuffix = " \(dependency.lagDays)d"
        } else {
            lagSuffix = ""
        }

        switch dependency.type {
        case .finishToStart:
            return "After \(target)\(lagSuffix)"
        case .startToStart:
            return dependency.lagDays == 0
                ? "With \(target)"
                : "\(abs(dependency.lagDays))d \(dependency.lagDays > 0 ? "after" : "before") \(target) starts"
        case .finishToFinish:
            return "Ends with \(target)\(lagSuffix)"
        case .startToFinish:
            return "Before \(target)\(lagSuffix)"
        }
    }

    /// Compact technical summary (only shown in the optional Advanced disclosure).
    public static func technicalSummary(for dependency: TaskDependency) -> String {
        if dependency.lagDays == 0 {
            return dependency.type.rawValue
        } else if dependency.lagDays > 0 {
            return "\(dependency.type.rawValue) +\(dependency.lagDays)d"
        } else {
            return "\(dependency.type.rawValue) \(dependency.lagDays)d"
        }
    }

    private static func timingPhrase(lagDays: Int) -> String {
        let absDays = abs(lagDays)
        let unit = absDays == 1 ? "day" : "days"
        if lagDays > 0 {
            return "\(absDays) \(unit) after"
        } else if lagDays < 0 {
            return "\(absDays) \(unit) before"
        }
        return ""
    }
}
