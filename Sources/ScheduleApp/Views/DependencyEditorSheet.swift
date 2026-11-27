import SwiftUI
import ScheduleCore

struct DependencyEditorSheet: View {
    @Bindable var viewModel: ProjectViewModel
    let targetTaskID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPredecessorID: UUID?
    @State private var selectedType: DependencyType = .finishToStart
    @State private var offsetDirection: OffsetDirection = .after
    @State private var offsetDays: Int = 0
    @State private var showTechnicalDetails = false
    @State private var errorMessage: String?

    enum OffsetDirection: String, CaseIterable, Identifiable {
        case after = "After"
        case before = "Before"
        var id: String { rawValue }
    }

    private var targetTask: ScheduleTask? {
        viewModel.document.tasks.first { $0.id == targetTaskID }
    }

    private var candidatePredecessors: [ScheduleTask] {
        viewModel.document.tasks.filter { $0.id != targetTaskID }
    }

    private var effectiveLagDays: Int {
        if offsetDays == 0 { return 0 }
        return offsetDirection == .after ? offsetDays : -offsetDays
    }

    private var previewDependency: TaskDependency? {
        guard let predID = selectedPredecessorID else { return nil }
        return TaskDependency(predecessorID: predID, type: selectedType, lagDays: effectiveLagDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    LabeledContent("Task") {
                        Text(targetTask?.title ?? "Selected Task")
                            .fontWeight(.medium)
                    }

                    Picker("Depends On", selection: $selectedPredecessorID) {
                        Text("Choose a task…").tag(Optional<UUID>.none)
                        ForEach(candidatePredecessors) { task in
                            Text("\(task.identifier)  \(task.title)")
                                .tag(Optional(task.id))
                        }
                    }

                    Picker("Relationship", selection: $selectedType) {
                        ForEach(DependencyType.allCases, id: \.self) { type in
                            Text(HumanDependency.pickerLabel(for: type)).tag(type)
                        }
                    }
                } header: {
                    Text("Add Relationship")
                }

                Section("Timing (Optional)") {
                    HStack(alignment: .center, spacing: 12) {
                        Stepper(value: $offsetDays, in: 0...120) {
                            Text(offsetDays == 0 ? "No waiting period" : "\(offsetDays) working \(offsetDays == 1 ? "day" : "days")")
                        }
                        if offsetDays > 0 {
                            Picker("", selection: $offsetDirection) {
                                ForEach(OffsetDirection.allCases) { dir in
                                    Text(LocalizedStringKey(dir.rawValue)).tag(dir)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 130)
                        }
                    }
                }

                if let dep = previewDependency,
                   let pred = candidatePredecessors.first(where: { $0.id == dep.predecessorID }) {
                    Section("Summary") {
                        Text(HumanDependency.describe(dep, predecessorName: pred.title, successorName: targetTask?.title))
                            .font(.callout)
                            .foregroundStyle(.primary)

                        DisclosureGroup("Technical Details", isExpanded: $showTechnicalDetails) {
                            LabeledContent("Notation") {
                                Text(HumanDependency.technicalSummary(for: dep))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Relationship") {
                    guard let predID = selectedPredecessorID else { return }
                    let ok = viewModel.addDependency(
                        to: targetTaskID,
                        predecessorID: predID,
                        type: selectedType,
                        lagDays: effectiveLagDays
                    )
                    if ok {
                        dismiss()
                    } else {
                        errorMessage = viewModel.cycleWarningMessage
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedPredecessorID == nil)
            }
            .padding()
        }
        .frame(width: 460, height: 420)
        .onAppear {
            if selectedPredecessorID == nil {
                selectedPredecessorID = candidatePredecessors.first?.id
            }
        }
    }
}
