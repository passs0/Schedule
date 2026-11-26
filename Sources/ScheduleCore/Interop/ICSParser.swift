import Foundation

/// Minimal RFC 5545 iCalendar (.ics) parser for importing public holidays and
/// subscribed calendars (Apple Calendar, Google Calendar `.ics` feeds, etc.).
public enum ICSParser {
    public struct HolidayEvent: Equatable, Sendable {
        public let day: CalendarDay
        public let summary: String
    }

    public static func parseHolidays(from icsText: String) -> [HolidayEvent] {
        // Unfold RFC 5545 folded lines (CRLF/LF followed by space or tab)
        let normalized = icsText
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")

        var events: [HolidayEvent] = []
        var inEvent = false
        var currentDay: CalendarDay?
        var currentSummary: String = "Holiday"
        var yearlyCount: Int = 1

        for line in normalized.components(separatedBy: "\n") {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                currentDay = nil
                currentSummary = "Holiday"
                yearlyCount = 1
            } else if line == "END:VEVENT" {
                if inEvent, let day = currentDay {
                    for offset in 0..<min(yearlyCount, 10) {
                        events.append(HolidayEvent(
                            day: CalendarDay(year: day.year + offset, month: day.month, day: day.day),
                            summary: currentSummary
                        ))
                    }
                }
                inEvent = false
            } else if inEvent {
                if line.hasPrefix("DTSTART") {
                    if let colonIdx = line.firstIndex(of: ":") {
                        let val = String(line[line.index(after: colonIdx)...])
                        currentDay = parseICSDate(val)
                    }
                } else if line.hasPrefix("RRULE:") && line.contains("FREQ=YEARLY") {
                    if let countRange = line.range(of: "COUNT=") {
                        let rest = line[countRange.upperBound...]
                        let digits = rest.prefix(while: { $0.isNumber })
                        if let c = Int(digits), c > 1 {
                            yearlyCount = c
                        }
                    }
                } else if line.hasPrefix("SUMMARY") {
                    if let colonIdx = line.firstIndex(of: ":") {
                        let val = String(line[line.index(after: colonIdx)...])
                            .replacingOccurrences(of: "\\,", with: ",")
                            .replacingOccurrences(of: "\\;", with: ";")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !val.isEmpty {
                            currentSummary = val
                        }
                    }
                }
            }
        }
        return events
    }

    private static func parseICSDate(_ raw: String) -> CalendarDay? {
        let digits = raw.prefix(8)
        guard digits.count == 8,
              let y = Int(digits.prefix(4)),
              let m = Int(digits.dropFirst(4).prefix(2)),
              let d = Int(digits.dropFirst(6).prefix(2)) else {
            return nil
        }
        return CalendarDay(year: y, month: m, day: d)
    }
}
