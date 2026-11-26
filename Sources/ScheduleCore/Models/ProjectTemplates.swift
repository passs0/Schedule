import Foundation

/// Built-in project templates, each modeling a distinct scheduling structure
/// (long-lead physical gates with lag, parallel software sprints, pinned cutover windows, or lab compliance cycles).
public enum ProjectTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank
    case hardwareNPI
    case softwareRelease
    case systemCutover
    case complianceAudit

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blank: return "Blank"
        case .hardwareNPI: return "Hardware & Electronics NPI"
        case .softwareRelease: return "Software & Firmware Release"
        case .systemCutover: return "System Cutover & Migration"
        case .complianceAudit: return "Compliance & Lab Certification"
        }
    }

    public var badge: String {
        switch self {
        case .blank: return "Empty"
        case .hardwareNPI: return "Long-Lead & Gates"
        case .softwareRelease: return "Parallel Sprints"
        case .systemCutover: return "Pinned Window"
        case .complianceAudit: return "Lab & Remediation"
        }
    }

    public var subtitle: String {
        switch self {
        case .blank:
            return "Clean slate with a single kickoff task."
        case .hardwareNPI:
            return "EVT/DVT/PVT gates with supplier fab lead-time lags and tooling."
        case .softwareRelease:
            return "Concurrent engineering tracks converging at code freeze, QA, and rollout."
        case .systemCutover:
            return "Parallel prep converging on a pinned production cutover window."
        case .complianceAudit:
            return "Pre-scan, external lab lead times, corrective fixes, and certification."
        }
    }

    public var systemImage: String {
        switch self {
        case .blank: return "doc"
        case .hardwareNPI: return "cpu"
        case .softwareRelease: return "chevron.left.forwardslash.chevron.right"
        case .systemCutover: return "arrow.triangle.swap"
        case .complianceAudit: return "checkmark.seal"
        }
    }

    public func makeDocument(referenceDate: CalendarDay = .today) -> ProjectDocument {
        let cal = WorkingCalendar.standard
        let start = cal.snapToWorkingDay(referenceDate, forward: true)

        switch self {
        case .blank:
            return ProjectDocument(
                name: "Untitled Project",
                projectStartDate: start,
                tasks: [
                    ScheduleTask(identifier: "1", title: "Kickoff", startDate: start, durationDays: 1, calendar: cal)
                ]
            )

        case .hardwareNPI:
            // Models physical product NPI: fab/shipping lag times and strict EVT -> DVT -> PVT gates.
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("Design & EVT", "Schematic, PCB layout, and first-article bring-up.", [
                    TaskSpec("spec", "Architecture & BOM Lock", 5),
                    TaskSpec("pcb", "Schematic & PCB Layout", 8, after: ["spec"]),
                    TaskSpec("evt_fab", "EVT Fab & SMT Assembly", 5, after: ["pcb"], lag: 3), // shipping/fab queue lag
                    TaskSpec("evt_bringup", "EVT Bring-Up & Rework", 5, after: ["evt_fab"]),
                    TaskSpec("evt_gate", "EVT Exit Gate", 0, milestone: true, after: ["evt_bringup"])
                ]),
                PhaseSpec("DVT & Tooling", "Hard tooling and regulatory pre-compliance in parallel.", [
                    TaskSpec("tooling", "Enclosure Tooling & Fit", 10, after: ["evt_gate"]),
                    TaskSpec("emc", "EMC / Safety Pre-Compliance", 6, after: ["evt_gate"]),
                    TaskSpec("dvt_gate", "DVT Sign-Off", 0, milestone: true, after: ["tooling", "emc"])
                ]),
                PhaseSpec("PVT & Mass Production", "Pilot line qualification and MP ramp.", [
                    TaskSpec("pvt", "PVT Pilot Run & Yield Audit", 6, after: ["dvt_gate"], lag: 2),
                    TaskSpec("mp", "Mass Production Ramp", 0, milestone: true, after: ["pvt"])
                ])
            ])

        case .softwareRelease:
            // Models iterative software/firmware: concurrent tracks converging at Feature Freeze, overlapping QA & Security.
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("Planning & Architecture", "Scope lock and API/interface contracts.", [
                    TaskSpec("scope", "Product Spec & Scope Lock", 3),
                    TaskSpec("api", "Architecture & API Contracts", 4, after: ["scope"]),
                    TaskSpec("arch_gate", "Design Freeze", 0, milestone: true, after: ["api"])
                ]),
                PhaseSpec("Engineering Tracks", "Parallel implementation streams converging at feature freeze.", [
                    TaskSpec("core", "Core Services / Firmware", 8, after: ["arch_gate"]),
                    TaskSpec("ui", "Client UI & State Layer", 8, after: ["arch_gate"]),
                    TaskSpec("infra", "Telemetry, Auth & CI Pipeline", 5, after: ["arch_gate"]),
                    TaskSpec("freeze", "Feature Freeze", 0, milestone: true, after: ["core", "ui", "infra"])
                ]),
                PhaseSpec("Hardening & Rollout", "Concurrent QA, security review, and staged release.", [
                    TaskSpec("qa", "Regression & Integration QA", 5, after: ["freeze"]),
                    TaskSpec("sec", "Security & Performance Audit", 3, after: ["freeze"]),
                    TaskSpec("release", "Production Rollout", 0, milestone: true, after: ["qa", "sec"])
                ])
            ])

        case .systemCutover:
            // Models infrastructure cutover: parallel prep + dry-run leading to a pinned cutover window.
            let cutoverStart = cal.addWorkingDays(18, to: start)
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("Preparation", "Parallel landing zone and data replication setup.", [
                    TaskSpec("audit", "Dependency & Risk Audit", 3),
                    TaskSpec("iac", "Landing Zone & Network Peering", 6, after: ["audit"]),
                    TaskSpec("cdc", "Data Replication & Sync", 7, after: ["audit"]),
                    TaskSpec("dryrun", "Dry-Run Cutover & Load Test", 3, after: ["iac", "cdc"]),
                    TaskSpec("go_nogo", "Go / No-Go Review", 0, milestone: true, after: ["dryrun"])
                ]),
                PhaseSpec("Cutover Window", "Pinned production switchover and hypercare.", [
                    TaskSpec("cutover", "Production Cutover Window", 2, after: ["go_nogo"], pinnedStart: cutoverStart),
                    TaskSpec("hyper", "Hypercare & SLO Verification", 3, after: ["cutover"]),
                    TaskSpec("complete", "Cutover Complete", 0, milestone: true, after: ["hyper"])
                ])
            ])

        case .complianceAudit:
            // Models external lab / certification: internal pre-check, external lab queue lag, remediation, final cert.
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("Readiness & Pre-Test", "Documentation package and internal pre-scan.", [
                    TaskSpec("docs", "Technical File & Evidence Prep", 5),
                    TaskSpec("prescan", "Internal Pre-Scan & Dry Audit", 4, after: ["docs"])
                ]),
                PhaseSpec("External Lab / Audit", "Accredited lab testing with booking lead-time lag.", [
                    TaskSpec("lab", "Accredited Lab / Formal Audit", 5, after: ["prescan"], lag: 4),
                    TaskSpec("remediate", "Corrective Actions & Retest", 4, after: ["lab"]),
                    TaskSpec("certified", "Certification Issued", 0, milestone: true, after: ["remediate"])
                ])
            ])
        }
    }

    private struct TaskSpec {
        let key: String
        let title: String
        let duration: Int
        let isMilestone: Bool
        let after: [String]
        let lag: Int
        let pinnedStart: CalendarDay?

        init(
            _ key: String,
            _ title: String,
            _ duration: Int,
            milestone: Bool = false,
            after: [String] = [],
            lag: Int = 0,
            pinnedStart: CalendarDay? = nil
        ) {
            self.key = key
            self.title = title
            self.duration = duration
            self.isMilestone = milestone
            self.after = after
            self.lag = lag
            self.pinnedStart = pinnedStart
        }
    }

    private struct PhaseSpec {
        let title: String
        let notes: String
        let tasks: [TaskSpec]

        init(_ title: String, _ notes: String, _ tasks: [TaskSpec]) {
            self.title = title
            self.notes = notes
            self.tasks = tasks
        }
    }

    private func buildTemplate(
        name: String,
        start: CalendarDay,
        cal: WorkingCalendar,
        phases: [PhaseSpec]
    ) -> ProjectDocument {
        var allTasks: [ScheduleTask] = []
        var idByKey: [String: UUID] = [:]

        for phase in phases {
            for item in phase.tasks {
                idByKey[item.key] = UUID()
            }
        }

        for (pIndex, phase) in phases.enumerated() {
            let groupID = UUID()
            allTasks.append(
                ScheduleTask(
                    id: groupID,
                    identifier: "\(pIndex + 1)",
                    title: phase.title,
                    startDate: start,
                    durationDays: 1,
                    percentComplete: 0,
                    notes: phase.notes,
                    calendar: cal
                )
            )

            for (tIndex, item) in phase.tasks.enumerated() {
                let taskID = idByKey[item.key] ?? UUID()
                let deps: [TaskDependency] = item.after.compactMap { predKey in
                    guard let predID = idByKey[predKey] else { return nil }
                    return TaskDependency(predecessorID: predID, type: .finishToStart, lagDays: item.lag)
                }
                allTasks.append(
                    ScheduleTask(
                        id: taskID,
                        identifier: "\(pIndex + 1).\(tIndex + 1)",
                        title: item.title,
                        startDate: item.pinnedStart ?? start,
                        durationDays: item.isMilestone ? 0 : item.duration,
                        isMilestone: item.isMilestone,
                        percentComplete: 0,
                        parentID: groupID,
                        dependencies: deps,
                        isManuallyScheduled: item.pinnedStart != nil,
                        calendar: cal
                    )
                )
            }
        }

        let scheduled = SchedulingEngine.recalculateAll(
            tasks: allTasks,
            projectStart: start,
            calendar: cal
        )
        return ProjectDocument(
            name: name,
            projectStartDate: start,
            workingCalendar: cal,
            tasks: scheduled
        )
    }
}
