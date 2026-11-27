import SwiftUI
@preconcurrency import EventKit
import AppKit
import UniformTypeIdentifiers
import ScheduleCore

struct CalendarManagerSheet: View {
    @Bindable var viewModel: ProjectViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCalendarID: UUID?
    @State private var newHolidayDate: Date = Date()
    @State private var newHolidayLabel: String = "Holiday"
    @State private var importStatusMessage: String?
    @State private var appleCalendars: [EKCalendar] = []
    @State private var selectedAppleCalendarID: String = ""
    @State private var icsURLText: String = ""
    @State private var isImportingICS: Bool = false

    private var selectedIndex: Int? {
        guard let id = selectedCalendarID else { return nil }
        return viewModel.document.calendars.firstIndex { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCalendarID) {
                Section("Owner & Region Calendars") {
                    ForEach(viewModel.document.calendars) { cal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cal.name)
                                .font(.callout.weight(.medium))
                            if !cal.owner.isEmpty {
                                Text(cal.owner)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(cal.id)
                        .contextMenu {
                            Button("Delete Calendar", role: .destructive) {
                                deleteCalendar(cal.id)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem {
                    Button {
                        let newCal = NamedWorkingCalendar(name: "New Team Calendar", owner: "Team")
                        viewModel.upsertCalendar(newCal)
                        selectedCalendarID = newCal.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New Owner Calendar")
                }
            }
        } detail: {
            if let idx = selectedIndex {
                let cal = viewModel.document.calendars[idx]
                calendarDetailForm(cal: cal)
            } else {
                ContentUnavailableView(
                    "Select a Calendar",
                    systemImage: "calendar",
                    description: Text("Choose an owner or region calendar to configure working days and holidays.")
                )
            }
        }
        .frame(width: 740, height: 540)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            if selectedCalendarID == nil {
                selectedCalendarID = viewModel.document.calendars.first?.id
            }
        }
    }

    @ViewBuilder
    private func calendarDetailForm(cal: NamedWorkingCalendar) -> some View {
        Form {
            Section("Identity") {
                TextField("Calendar Name", text: Binding(
                    get: { cal.name },
                    set: { val in
                        var updated = cal
                        updated.name = val
                        viewModel.upsertCalendar(updated)
                    }
                ))
                TextField("Owner / Team", text: Binding(
                    get: { cal.owner },
                    set: { val in
                        var updated = cal
                        updated.owner = val
                        viewModel.upsertCalendar(updated)
                    }
                ))
            }

            Section("Working Week") {
                let weekdays: [(Int, String)] = [
                    (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")
                ]
                HStack(spacing: 8) {
                    ForEach(weekdays, id: \.0) { dayNum, label in
                        let active = cal.workingCalendar.workingWeekdays.contains(dayNum)
                        Toggle(label, isOn: Binding(
                            get: { active },
                            set: { on in
                                var updated = cal
                                if on {
                                    updated.workingCalendar.workingWeekdays.insert(dayNum)
                                } else if updated.workingCalendar.workingWeekdays.count > 1 {
                                    updated.workingCalendar.workingWeekdays.remove(dayNum)
                                }
                                viewModel.upsertCalendar(updated)
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }

            Section("Add Holiday") {
                HStack(alignment: .center, spacing: 10) {
                    DatePicker("", selection: $newHolidayDate, displayedComponents: .date)
                        .labelsHidden()
                    TextField("", text: $newHolidayLabel, prompt: Text("Holiday name"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        var updated = cal
                        let day = CalendarDay(date: newHolidayDate, calendar: .current)
                        updated.addHoliday(day, label: newHolidayLabel.isEmpty ? "Holiday" : newHolidayLabel)
                        viewModel.upsertCalendar(updated)
                    }
                }
            }

            Section("Import Holidays") {
                Menu("Subscribe to Apple Regional Holiday Calendar…") {
                    ForEach(Self.appleHolidayFeeds, id: \.code) { feed in
                        Button(feed.label) {
                            importApplePublicFeed(code: feed.code, label: feed.label, into: cal)
                        }
                    }
                }
                .disabled(isImportingICS)

                if appleCalendars.isEmpty {
                    Button {
                        loadAppleCalendars()
                    } label: {
                        Label("Load Subscribed Apple / Google Calendars…", systemImage: "calendar.badge.plus")
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        Picker("", selection: $selectedAppleCalendarID) {
                            ForEach(appleCalendars, id: \.calendarIdentifier) { ekCal in
                                Text("\(ekCal.title) (\(ekCal.source.title))")
                                    .tag(ekCal.calendarIdentifier)
                            }
                        }
                        .labelsHidden()
                        Button("Import") {
                            importSelectedAppleCalendar(into: cal)
                        }
                        .disabled(selectedAppleCalendarID.isEmpty)
                    }
                }

                HStack(alignment: .center, spacing: 8) {
                    TextField("", text: $icsURLText, prompt: Text("Paste .ics or webcal:// URL"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Button(isImportingICS ? "Importing…" : "Fetch") {
                        importFromICSURL(into: cal)
                    }
                    .disabled(icsURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImportingICS)
                    Button(".ics File…") {
                        importFromLocalICSFile(into: cal)
                    }
                }

                if let importStatusMessage {
                    Text(importStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Holidays (\(cal.workingCalendar.holidays.count))") {

                let sortedDays = cal.workingCalendar.holidays.sorted()
                ForEach(sortedDays, id: \.self) { day in
                    HStack {
                        Text(day.isoString)
                            .font(.callout.monospacedDigit())
                        Text(cal.holidayNames[day.isoString] ?? "Holiday")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            var updated = cal
                            updated.removeHoliday(day)
                            viewModel.upsertCalendar(updated)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                Button("Delete Calendar", role: .destructive) {
                    deleteCalendar(cal.id)
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let appleHolidayFeeds: [(code: String, label: String)] = [
        ("us_en", "United States Holidays"),
        ("cn_zh", "China Holidays"),
        ("tw_zh", "Taiwan Holidays"),
        ("hk_zh", "Hong Kong Holidays"),
        ("jp_ja", "Japan Holidays"),
        ("kr_ko", "South Korea Holidays"),
        ("sg_en", "Singapore Holidays"),
        ("gb_en", "United Kingdom Holidays"),
        ("de_de", "Germany Holidays"),
        ("fr_fr", "France Holidays"),
        ("ca_en", "Canada Holidays"),
        ("au_en", "Australia Holidays")
    ]

    private func deleteCalendar(_ id: UUID) {
        viewModel.deleteCalendar(id)
        if selectedCalendarID == id {
            selectedCalendarID = viewModel.document.calendars.first?.id
        }
    }

    private func importApplePublicFeed(code: String, label: String, into target: NamedWorkingCalendar) {
        icsURLText = "https://calendars.icloud.com/holidays/\(code).ics"
        importFromICSURL(into: target, sourceLabel: label)
    }

    private func loadAppleCalendars() {
        Task { @MainActor in
            let store = EKEventStore()
            do {
                let granted = try await store.requestFullAccessToEvents()
                guard granted else {
                    importStatusMessage = "Calendar access was not granted in System Settings."
                    return
                }
                let all = store.calendars(for: .event).sorted {
                    let aSub = ($0.type == .subscription || $0.title.localizedCaseInsensitiveContains("holiday"))
                    let bSub = ($1.type == .subscription || $1.title.localizedCaseInsensitiveContains("holiday"))
                    if aSub != bSub { return aSub }
                    return $0.title < $1.title
                }
                appleCalendars = all
                selectedAppleCalendarID = all.first?.calendarIdentifier ?? ""
                importStatusMessage = all.isEmpty
                    ? "No calendars found in Apple Calendar."
                    : "Loaded \(all.count) calendars. Pick one and click Import."
            } catch {
                importStatusMessage = error.localizedDescription
            }
        }
    }

    private func importSelectedAppleCalendar(into target: NamedWorkingCalendar) {
        let store = EKEventStore()
        guard let ekCal = store.calendars(for: .event).first(where: { $0.calendarIdentifier == selectedAppleCalendarID }) else {
            importStatusMessage = "Selected calendar is no longer available."
            return
        }
        let start = Date()
        let end = Calendar.current.date(byAdding: .year, value: 2, to: start) ?? start
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: [ekCal])
        let events = store.events(matching: pred).filter(\.isAllDay)

        var updated = target
        var added = 0
        for event in events {
            let day = CalendarDay(date: event.startDate, calendar: .current)
            if !updated.workingCalendar.holidays.contains(day) {
                updated.addHoliday(day, label: event.title ?? "Holiday")
                added += 1
            }
        }
        viewModel.upsertCalendar(updated)
        importStatusMessage = "Imported \(added) holiday\(added == 1 ? "" : "s") from \"\(ekCal.title)\"."
    }

    private func importFromICSURL(into target: NamedWorkingCalendar, sourceLabel: String? = nil) {
        var raw = icsURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("webcal://") {
            raw = "https://" + raw.dropFirst("webcal://".count)
        }
        guard let url = URL(string: raw) else {
            importStatusMessage = "Invalid calendar URL."
            return
        }
        isImportingICS = true
        Task {
            defer { Task { @MainActor in isImportingICS = false } }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let text = String(data: data, encoding: .utf8) ?? ""
                let parsed = ICSParser.parseHolidays(from: text)
                await MainActor.run {
                    var updated = target
                    var added = 0
                    for ev in parsed {
                        if !updated.workingCalendar.holidays.contains(ev.day) {
                            updated.addHoliday(ev.day, label: ev.summary)
                            added += 1
                        }
                    }
                    viewModel.upsertCalendar(updated)
                    let src = sourceLabel ?? "iCal feed"
                    importStatusMessage = "Imported \(added) holiday\(added == 1 ? "" : "s") from \(src)."
                }
            } catch {
                await MainActor.run {
                    importStatusMessage = "Could not fetch .ics feed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importFromLocalICSFile(into target: NamedWorkingCalendar) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = ICSParser.parseHolidays(from: text)
        var updated = target
        var added = 0
        for ev in parsed {
            if !updated.workingCalendar.holidays.contains(ev.day) {
                updated.addHoliday(ev.day, label: ev.summary)
                added += 1
            }
        }
        viewModel.upsertCalendar(updated)
        importStatusMessage = "Imported \(added) event\(added == 1 ? "" : "s") from \(url.lastPathComponent)."
    }
}
