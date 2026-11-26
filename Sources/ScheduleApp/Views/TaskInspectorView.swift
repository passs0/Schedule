import SwiftUI
import ScheduleCore

struct TaskInspectorView: View {
    @Bindable var viewModel: ProjectViewModel
    let onAddDependency: (UUID) -> Void
    @State private var showTechnicalDetails = false

    var body: some View {
        if let task = viewModel.selectedTask {
            let isGroup = viewModel.document.tasks.contains { $0.parentID == task.id }
            Form {
                Section("Selected Task") {
                    TextField("Title", text: Binding(
                        get: { task.title },
                        set: { newVal in
                            viewModel.updateTask(task.id, actionName: "Rename Task") { t, _ in
                                t.title = newVal
                            }
                        }
                    ))

                    TextField("Identifier", text: Binding(
                        get: { task.identifier },
                        set: { newVal in
                            viewModel.updateTask(task.id, actionName: "Edit Identifier") { t, _ in
                                t.identifier = newVal
                            }
                        }
                    ))

                    HStack(spacing: 6) {
                        TextField("DRI (Optional)", text: Binding(
                            get: { task.dri ?? "" },
                            set: { newVal in
                                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                                viewModel.updateTask(task.id, actionName: "Assign DRI") { t, _ in
                                    t.dri = trimmed.isEmpty ? nil : newVal
                                }
                            }
                        ))
                        if !viewModel.knownDRIs.isEmpty || !(task.dri ?? "").isEmpty {
                            Menu {
                                ForEach(viewModel.knownDRIs, id: \.self) { name in
                                    Button(name) {
                                        viewModel.updateTask(task.id, actionName: "Assign DRI") { t, _ in
                                            t.dri = name
                                        }
                                    }
                                }
                                if !(task.dri ?? "").isEmpty {
                                    if !viewModel.knownDRIs.isEmpty { Divider() }
                                    Button("Clear DRI", role: .destructive) {
                                        viewModel.updateTask(task.id, actionName: "Clear DRI") { t, _ in
                                            t.dri = nil
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "person.crop.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Choose an existing DRI")
                        }
                    }

                    if !isGroup {
                        Toggle("Milestone", isOn: Binding(
                            get: { task.isMilestone },
                            set: { isM in
                                viewModel.updateTask(task.id, actionName: "Toggle Milestone") { t, cal in
                                    t.isMilestone = isM
                                    if isM {
                                        t.durationDays = 0
                                        t.endDate = t.startDate
                                    } else {
                                        t.durationDays = max(1, t.durationDays)
                                        t.endDate = cal.endDate(startingOn: t.startDate, durationDays: t.durationDays)
                                    }
                                }
                            }
                        ))

                        Toggle("Pin Start Date", isOn: Binding(
                            get: { task.isManuallyScheduled },
                            set: { manual in
                                viewModel.updateTask(task.id, actionName: "Toggle Pin Start Date") { t, _ in
                                    t.isManuallyScheduled = manual
                                }
                            }
                        ))
                    }
                }

                Section("Dates & Duration") {
                    DatePicker(
                        "Start",
                        selection: Binding(
                            get: { task.startDate.toDate() },
                            set: { date in
                                viewModel.updateTask(task.id, actionName: "Change Start Date") { t, cal in
                                    let day = cal.snapToWorkingDay(CalendarDay(date: date, calendar: .current), forward: true)
                                    t.startDate = day
                                    t.endDate = t.isMilestone ? day : cal.endDate(startingOn: day, durationDays: t.durationDays)
                                    t.isManuallyScheduled = true
                                }
                            }
                        ),
                        displayedComponents: .date
                    )
                    .disabled(isGroup)

                    if task.isMilestone {
                        LabeledContent("Finish") {
                            Text(task.endDate.toDate(), style: .date)
                                .foregroundStyle(.secondary)
                        }
                        if !task.dependencies.isEmpty {
                            Text("Auto-scheduled from dependencies.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        DatePicker(
                            "End",
                            selection: Binding(
                                get: { task.endDate.toDate() },
                                set: { date in
                                    viewModel.updateTask(task.id, actionName: "Change End Date") { t, cal in
                                        let day = cal.snapToWorkingDay(CalendarDay(date: date, calendar: .current), forward: false)
                                        let clampedEnd = max(t.startDate, day)
                                        t.endDate = clampedEnd
                                        t.durationDays = cal.workingDuration(from: t.startDate, to: clampedEnd)
                                    }
                                }
                            ),
                            displayedComponents: .date
                        )
                        .disabled(isGroup)

                        Stepper(
                            value: Binding(
                                get: { task.durationDays },
                                set: { dur in
                                    viewModel.updateTask(task.id, actionName: "Change Duration") { t, cal in
                                        t.durationDays = max(1, dur)
                                        t.endDate = cal.endDate(startingOn: t.startDate, durationDays: t.durationDays)
                                    }
                                }
                            ),
                            in: 1...365
                        ) {
                            LabeledContent("Duration") {
                                Text("\(task.durationDays) working \(task.durationDays == 1 ? "day" : "days")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isGroup)
                    }

                    if !isGroup {
                        Picker("Calendar / Owner", selection: Binding(
                            get: { task.calendarID },
                            set: { cid in
                                viewModel.updateTask(task.id, actionName: "Assign Calendar") { t, _ in
                                    t.calendarID = cid
                                }
                            }
                        )) {
                            Text("Default (Mon–Fri)").tag(Optional<UUID>.none)
                            ForEach(viewModel.document.calendars) { cal in
                                Text(cal.owner.isEmpty ? cal.name : "\(cal.name) (\(cal.owner))")
                                    .tag(Optional(cal.id))
                            }
                        }
                    }
                }

                Section {
                    if task.dependencies.isEmpty {
                        Text("No relationships yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        let taskMap = Dictionary(uniqueKeysWithValues: viewModel.document.tasks.map { ($0.id, $0) })
                        ForEach(task.dependencies) { dep in
                            let predName = taskMap[dep.predecessorID]?.title ?? "Unknown"
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(HumanDependency.describe(dep, predecessorName: predName))
                                        .font(.callout)
                                    if showTechnicalDetails {
                                        Text(HumanDependency.technicalSummary(for: dep))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    viewModel.removeDependency(from: task.id, dependencyID: dep.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove Relationship")
                            }
                        }
                    }

                    HStack {
                        Menu("Starts after…") {
                            ForEach(viewModel.document.tasks.filter { $0.id != task.id }) { candidate in
                                Button("\(candidate.identifier)  \(candidate.title)") {
                                    viewModel.addDependency(
                                        to: task.id,
                                        predecessorID: candidate.id,
                                        type: .finishToStart,
                                        lagDays: 0
                                    )
                                }
                            }
                        }
                        .disabled(isGroup)

                        Button("Custom…") {
                            onAddDependency(task.id)
                        }
                        .disabled(isGroup)
                    }

                    if !task.dependencies.isEmpty {
                        DisclosureGroup("Technical Details", isExpanded: $showTechnicalDetails) {
                            LabeledContent("Slack") {
                                Text("\(task.totalSlackDays) working \(task.totalSlackDays == 1 ? "day" : "days")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Dependencies")
                }

                Section("Progress") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Completion")
                            Spacer()
                            Text("\(Int(round(task.percentComplete)))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { task.percentComplete },
                                set: { pct in
                                    viewModel.updateTask(task.id, actionName: "Update Progress") { t, _ in
                                        t.percentComplete = pct
                                    }
                                }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        .disabled(isGroup)
                    }

                    if !isGroup {
                        Picker("Calendar / Owner", selection: Binding(
                            get: { task.calendarID },
                            set: { cid in
                                viewModel.updateTask(task.id, actionName: "Assign Calendar") { t, _ in
                                    t.calendarID = cid
                                }
                            }
                        )) {
                            Text("Default (Mon–Fri)").tag(Optional<UUID>.none)
                            ForEach(viewModel.document.calendars) { cal in
                                Text(cal.owner.isEmpty ? cal.name : "\(cal.name) (\(cal.owner))")
                                    .tag(Optional(cal.id))
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { task.notes },
                        set: { notes in
                            viewModel.updateTask(task.id, actionName: "Edit Notes") { t, _ in
                                t.notes = notes
                            }
                        }
                    ))
                    .font(.callout)
                    .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No Task Selected",
                systemImage: "sidebar.right",
                description: Text("Select a task to view its dates, relationships, and notes.")
            )
        }
    }
}
