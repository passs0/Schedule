import Foundation

/// A timezone-independent calendar date (year, month, day) to avoid DST and timezone drift in project schedules.
public struct CalendarDay: Codable, Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .gregorianUTC) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = comps.year ?? 2026
        self.month = comps.month ?? 1
        self.day = comps.day ?? 1
    }

    public static var today: CalendarDay {
        CalendarDay(date: Date(), calendar: .current)
    }

    public func toDate(calendar: Calendar = .gregorianUTC) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return calendar.date(from: comps) ?? Date()
    }

    public func addingCalendarDays(_ days: Int) -> CalendarDay {
        let date = toDate(calendar: .gregorianUTC)
        let next = Calendar.gregorianUTC.date(byAdding: .day, value: days, to: date) ?? date
        return CalendarDay(date: next, calendar: .gregorianUTC)
    }

    public func calendarDays(until other: CalendarDay) -> Int {
        let d1 = toDate(calendar: .gregorianUTC)
        let d2 = other.toDate(calendar: .gregorianUTC)
        return Calendar.gregorianUTC.dateComponents([.day], from: d1, to: d2).day ?? 0
    }

    /// Weekday index matching Foundation Calendar (1 = Sunday ... 7 = Saturday).
    public var weekday: Int {
        let date = toDate(calendar: .gregorianUTC)
        return Calendar.gregorianUTC.component(.weekday, from: date)
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

public extension Calendar {
    static let gregorianUTC: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return cal
    }()
}

/// Defines working days of the week and non-working holidays for schedule calculations.
public struct WorkingCalendar: Codable, Equatable, Hashable, Sendable {
    /// Weekday integers (1 = Sunday ... 7 = Saturday). Default: Mon(2)...Fri(6).
    public var workingWeekdays: Set<Int>
    public var holidays: Set<CalendarDay>

    public static let standard = WorkingCalendar(
        workingWeekdays: [2, 3, 4, 5, 6],
        holidays: []
    )

    public init(workingWeekdays: Set<Int> = [2, 3, 4, 5, 6], holidays: Set<CalendarDay> = []) {
        self.workingWeekdays = workingWeekdays.isEmpty ? [2, 3, 4, 5, 6] : workingWeekdays
        self.holidays = holidays
    }

    public func isWorkingDay(_ day: CalendarDay) -> Bool {
        workingWeekdays.contains(day.weekday) && !holidays.contains(day)
    }

    public func snapToWorkingDay(_ day: CalendarDay, forward: Bool = true) -> CalendarDay {
        var current = day
        var guardCount = 0
        while !isWorkingDay(current) && guardCount < 366 {
            current = current.addingCalendarDays(forward ? 1 : -1)
            guardCount += 1
        }
        return current
    }

    /// Moves `day` by `offset` working days (positive = forward, negative = backward, 0 = snap if needed).
    public func addWorkingDays(_ offset: Int, to day: CalendarDay) -> CalendarDay {
        if offset == 0 {
            return day
        }
        let step = offset > 0 ? 1 : -1
        var remaining = abs(offset)
        var current = day
        var guardCount = 0
        while remaining > 0 && guardCount < 10_000 {
            current = current.addingCalendarDays(step)
            if isWorkingDay(current) {
                remaining -= 1
            }
            guardCount += 1
        }
        return current
    }

    /// Calculates inclusive working duration in days from `start` to `end` (at least 1 if `end >= start`).
    public func workingDuration(from start: CalendarDay, to end: CalendarDay) -> Int {
        if end < start { return 0 }
        var count = 0
        var current = start
        var guardCount = 0
        while current <= end && guardCount < 10_000 {
            if isWorkingDay(current) {
                count += 1
            }
            current = current.addingCalendarDays(1)
            guardCount += 1
        }
        return max(1, count)
    }

    /// Computes end date given a start date and a working-day duration (duration = 1 -> end == start).
    public func endDate(startingOn start: CalendarDay, durationDays: Int) -> CalendarDay {
        if durationDays <= 0 {
            return start
        }
        let snappedStart = snapToWorkingDay(start, forward: true)
        return addWorkingDays(durationDays - 1, to: snappedStart)
    }

    /// Computes start date given an end date and a working-day duration.
    public func startDate(endingOn end: CalendarDay, durationDays: Int) -> CalendarDay {
        if durationDays <= 0 {
            return end
        }
        let snappedEnd = snapToWorkingDay(end, forward: false)
        return addWorkingDays(-(durationDays - 1), to: snappedEnd)
    }
}

/// A named owner/region working calendar with holidays that can be assigned to individual tasks.
public struct NamedWorkingCalendar: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var owner: String
    public var workingCalendar: WorkingCalendar
    /// Optional holiday names keyed by `CalendarDay.isoString` (e.g., "2027-02-06": "Lunar New Year").
    public var holidayNames: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        owner: String = "",
        workingCalendar: WorkingCalendar = .standard,
        holidayNames: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.workingCalendar = workingCalendar
        self.holidayNames = holidayNames
    }

    public mutating func addHoliday(_ day: CalendarDay, label: String = "Holiday") {
        workingCalendar.holidays.insert(day)
        holidayNames[day.isoString] = label
    }

    public mutating func removeHoliday(_ day: CalendarDay) {
        workingCalendar.holidays.remove(day)
        holidayNames.removeValue(forKey: day.isoString)
    }

    public static func defaultPresets() -> [NamedWorkingCalendar] {
        var us = NamedWorkingCalendar(name: "US Engineering", owner: "US Team")
        us.addHoliday(CalendarDay(year: 2026, month: 11, day: 26), label: "Thanksgiving")
        us.addHoliday(CalendarDay(year: 2026, month: 12, day: 25), label: "Christmas Day")
        us.addHoliday(CalendarDay(year: 2027, month: 1, day: 1), label: "New Year's Day")
        us.addHoliday(CalendarDay(year: 2027, month: 5, day: 31), label: "Memorial Day")
        us.addHoliday(CalendarDay(year: 2027, month: 7, day: 5), label: "Independence Day")

        var cn = NamedWorkingCalendar(name: "Shenzhen Factory (CM)", owner: "Contract Manufacturer")
        cn.addHoliday(CalendarDay(year: 2027, month: 1, day: 1), label: "New Year's Day")
        // Lunar New Year 2027 (Feb 5 - Feb 11)
        for d in 5...11 {
            cn.addHoliday(CalendarDay(year: 2027, month: 2, day: d), label: "Lunar New Year")
        }
        cn.addHoliday(CalendarDay(year: 2027, month: 5, day: 1), label: "Labor Day")

        var eu = NamedWorkingCalendar(name: "EU Compliance Lab", owner: "TÜV / Cert Lab")
        eu.addHoliday(CalendarDay(year: 2026, month: 12, day: 25), label: "Christmas Day")
        eu.addHoliday(CalendarDay(year: 2026, month: 12, day: 26), label: "Boxing Day")
        eu.addHoliday(CalendarDay(year: 2027, month: 1, day: 1), label: "New Year's Day")

        return [us, cn, eu]
    }
}
