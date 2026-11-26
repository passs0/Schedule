import Foundation

/// Built-in project templates, each modeling a distinct scheduling structure
/// (long-lead physical gates with lag, parallel software sprints, pinned 7-day cutover windows, or lab compliance cycles).
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
            return "Schematic to MP ramp with fab/tooling lags, EVT/DVT/PVT gates, and factory calendars."
        case .softwareRelease:
            return "Concurrent backend, UI, and platform tracks converging at feature freeze, QA, and canary rollout."
        case .systemCutover:
            return "Parallel infra & CDC prep leading to a pinned 7-day cutover window and hypercare."
        case .complianceAudit:
            return "Technical file, internal pre-scan, external lab booking lag, rework, and TCB filing."
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
            let eeCal = NamedWorkingCalendar(name: "EE / PCB", owner: "Electrical Eng", workingCalendar: cal)
            let meCal = NamedWorkingCalendar(name: "ME / Tooling", owner: "Mechanical Eng", workingCalendar: cal)
            let cmCal = NamedWorkingCalendar(name: "Factory / CM", owner: "Contract Mfg", workingCalendar: WorkingCalendar(workingWeekdays: [2, 3, 4, 5, 6, 7]))
            let qaCal = NamedWorkingCalendar(name: "QA & Regulatory", owner: "Compliance", workingCalendar: cal)

            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [eeCal, meCal, cmCal, qaCal],
                phases: [
                    PhaseSpec("Architecture & Schematic", "System block diagram, BOM lock, and PCB layout.", [
                        TaskSpec("prd", "PRD & System Block Diagram", 4, cal: eeCal.id),
                        TaskSpec("bom", "Long-Lead Component & BOM Audit", 4, after: ["prd"], cal: eeCal.id),
                        TaskSpec("sch", "Schematic Capture & Peer Review", 6, after: ["bom"], cal: eeCal.id),
                        TaskSpec("pcb", "Multi-Layer PCB Layout & DFM", 8, after: ["sch"], cal: eeCal.id),
                        TaskSpec("gerber", "Gerber & ODB++ Release", 0, milestone: true, after: ["pcb"], cal: eeCal.id)
                    ]),
                    PhaseSpec("EVT (Engineering Validation)", "Bare-board fab, SMT assembly, and bench bring-up.", [
                        TaskSpec("smt", "Bare Board Fab & SMT Assembly", 6, after: ["gerber"], lag: 3, cal: cmCal.id),
                        TaskSpec("bringup", "Board Bring-Up & Power Sequencing", 5, after: ["smt"], cal: eeCal.id),
                        TaskSpec("si", "Signal Integrity & Thermal Bench Tests", 4, after: ["bringup"], cal: eeCal.id),
                        TaskSpec("fw_smoke", "EVT Firmware Smoke Test", 3, after: ["bringup"], cal: eeCal.id),
                        TaskSpec("evt_gate", "EVT Exit Review", 0, milestone: true, after: ["si", "fw_smoke"], cal: qaCal.id)
                    ]),
                    PhaseSpec("DVT (Design Validation & Tooling)", "Parallel enclosure tooling, environmental tests, and pre-compliance.", [
                        TaskSpec("tooling", "Hard Tooling & Enclosure Fit", 10, after: ["evt_gate"], cal: meCal.id),
                        TaskSpec("env", "Environmental, Drop & Vibration Tests", 5, after: ["evt_gate"], cal: qaCal.id),
                        TaskSpec("emc", "FCC / CE / UL Pre-Compliance & EMC", 6, after: ["evt_gate"], cal: qaCal.id),
                        TaskSpec("dvt_gate", "DVT Sign-Off Gate", 0, milestone: true, after: ["tooling", "env", "emc"], cal: qaCal.id)
                    ]),
                    PhaseSpec("PVT & Mass Production", "Factory ATE calibration, pilot yield audit, and MP ramp.", [
                        TaskSpec("ate", "ATE Test Fixture & Line Setup", 4, after: ["dvt_gate"], cal: cmCal.id),
                        TaskSpec("pvt", "PVT Pilot Run & Yield Audit", 6, after: ["ate"], lag: 2, cal: cmCal.id),
                        TaskSpec("pkg", "Packaging & Regulatory Labeling", 4, after: ["dvt_gate"], cal: meCal.id),
                        TaskSpec("mp", "Mass Production Ramp", 0, milestone: true, after: ["pvt", "pkg"], cal: cmCal.id)
                    ])
                ]
            )

        case .softwareRelease:
            let beCal = NamedWorkingCalendar(name: "Backend", owner: "Core Services", workingCalendar: cal)
            let uiCal = NamedWorkingCalendar(name: "Client / UI", owner: "App Engineering", workingCalendar: cal)
            let sreCal = NamedWorkingCalendar(name: "Platform / SRE", owner: "Infrastructure", workingCalendar: cal)
            let qaCal = NamedWorkingCalendar(name: "QA & Security", owner: "Quality", workingCalendar: cal)

            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [beCal, uiCal, sreCal, qaCal],
                phases: [
                    PhaseSpec("Discovery & Architecture", "Product scope, API contracts, and threat modeling.", [
                        TaskSpec("prd", "PRD & Acceptance Criteria", 3, cal: beCal.id),
                        TaskSpec("api", "API Schema & Data Model", 4, after: ["prd"], cal: beCal.id),
                        TaskSpec("threat", "Security Threat Model", 2, after: ["prd"], cal: qaCal.id),
                        TaskSpec("arch_gate", "Architecture Freeze", 0, milestone: true, after: ["api", "threat"], cal: beCal.id)
                    ]),
                    PhaseSpec("Engineering Sprints", "Parallel backend, client UI, and platform tracks.", [
                        TaskSpec("services", "Backend Services & APIs", 8, after: ["arch_gate"], cal: beCal.id),
                        TaskSpec("ui", "Client UI & State Management", 8, after: ["arch_gate"], cal: uiCal.id),
                        TaskSpec("auth", "Auth & Telemetry Instrumentation", 5, after: ["arch_gate"], cal: sreCal.id),
                        TaskSpec("ci", "CI/CD & Automated Test Harness", 5, after: ["arch_gate"], cal: sreCal.id),
                        TaskSpec("freeze", "Feature Complete Gate", 0, milestone: true, after: ["services", "ui", "auth", "ci"], cal: qaCal.id)
                    ]),
                    PhaseSpec("Hardening & Verification", "Concurrent integration QA, load testing, and security audit.", [
                        TaskSpec("qa", "End-to-End Integration QA", 5, after: ["freeze"], cal: qaCal.id),
                        TaskSpec("perf", "Performance & Load Benchmarking", 3, after: ["freeze"], cal: sreCal.id),
                        TaskSpec("sec", "Security & Pen-Test Audit", 4, after: ["freeze"], cal: qaCal.id),
                        TaskSpec("rc", "Release Candidate Sign-Off", 0, milestone: true, after: ["qa", "perf", "sec"], cal: qaCal.id)
                    ]),
                    PhaseSpec("Staged Rollout", "Canary deployment, full release, and post-launch review.", [
                        TaskSpec("canary", "Canary 10% Rollout & Monitoring", 2, after: ["rc"], cal: sreCal.id),
                        TaskSpec("ga", "Full Production Release", 0, milestone: true, after: ["canary"], cal: sreCal.id),
                        TaskSpec("retro", "Post-Launch Telemetry & Retro", 2, after: ["ga"], cal: beCal.id)
                    ])
                ]
            )

        case .systemCutover:
            let netCal = NamedWorkingCalendar(name: "Infra / Network", owner: "Cloud Infra", workingCalendar: cal)
            let dbCal = NamedWorkingCalendar(name: "Database / Data", owner: "Data Eng", workingCalendar: cal)
            let opsCal = NamedWorkingCalendar(name: "SRE / 24x7 Ops", owner: "Cutover Team", workingCalendar: WorkingCalendar(workingWeekdays: [1, 2, 3, 4, 5, 6, 7]))
            let cutoverStart = cal.addWorkingDays(20, to: start)

            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [netCal, dbCal, opsCal],
                phases: [
                    PhaseSpec("Assessment & Landing Zone", "Dependency audit, Terraform VPC, and IAM.", [
                        TaskSpec("audit", "Workload & Dependency Inventory", 3, cal: netCal.id),
                        TaskSpec("iac", "IaC Landing Zone & VPC Peering", 6, after: ["audit"], cal: netCal.id),
                        TaskSpec("iam", "IAM, KMS & Secrets Provisioning", 4, after: ["audit"], cal: netCal.id),
                        TaskSpec("lz_gate", "Landing Zone Ready", 0, milestone: true, after: ["iac", "iam"], cal: netCal.id)
                    ]),
                    PhaseSpec("Migration & Dry-Run", "Parallel CDC replication, containerization, and rehearsal.", [
                        TaskSpec("cdc", "Database Schema & CDC Replication", 8, after: ["lz_gate"], cal: dbCal.id),
                        TaskSpec("helm", "Service Containerization & Helm Charts", 7, after: ["lz_gate"], cal: netCal.id),
                        TaskSpec("shadow", "Shadow Traffic & Load Verification", 4, after: ["cdc", "helm"], cal: opsCal.id),
                        TaskSpec("dryrun", "Cutover Dry-Run & Rollback Drill", 3, after: ["shadow"], cal: opsCal.id),
                        TaskSpec("gonogo", "Go / No-Go Review", 0, milestone: true, after: ["dryrun"], cal: opsCal.id)
                    ]),
                    PhaseSpec("Production Cutover Window", "Pinned 7-day Ops cutover window and hypercare.", [
                        TaskSpec("freeze", "Pre-Cutover Freeze & Final Snapshot", 1, after: ["gonogo"], cal: dbCal.id),
                        TaskSpec("cutover", "Production Cutover Window", 2, after: ["freeze"], pinnedStart: cutoverStart, cal: opsCal.id),
                        TaskSpec("dns", "DNS Switch & Smoke Verification", 1, after: ["cutover"], cal: opsCal.id),
                        TaskSpec("hyper", "48-Hour Hypercare & SLO Check", 3, after: ["dns"], cal: opsCal.id),
                        TaskSpec("decomm", "Legacy Decommission & Sign-Off", 0, milestone: true, after: ["hyper"], cal: netCal.id)
                    ])
                ]
            )

        case .complianceAudit:
            let compCal = NamedWorkingCalendar(name: "Compliance Eng", owner: "Regulatory", workingCalendar: cal)
            let labCal = NamedWorkingCalendar(name: "Accredited Lab", owner: "Test House", workingCalendar: cal)
            let legalCal = NamedWorkingCalendar(name: "Quality / Legal", owner: "QA & Legal", workingCalendar: cal)

            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [compCal, labCal, legalCal],
                phases: [
                    PhaseSpec("Readiness & Documentation", "Standards matrix, technical file, and internal pre-scan.", [
                        TaskSpec("matrix", "Applicable Standards & Scope Matrix", 3, cal: compCal.id),
                        TaskSpec("tcf", "Technical Construction File & BOM", 5, after: ["matrix"], cal: compCal.id),
                        TaskSpec("prescan", "Internal Pre-Scan & Gap Analysis", 4, after: ["matrix"], cal: compCal.id),
                        TaskSpec("pkg_gate", "Lab Submission Package Ready", 0, milestone: true, after: ["tcf", "prescan"], cal: compCal.id)
                    ]),
                    PhaseSpec("Accredited Lab Testing", "External lab booking lag, formal tests, and rework.", [
                        TaskSpec("booking", "Lab Queue & Sample Logistics", 2, after: ["pkg_gate"], lag: 4, cal: labCal.id),
                        TaskSpec("emc_lab", "Conducted & Radiated Emissions", 4, after: ["booking"], cal: labCal.id),
                        TaskSpec("safety_lab", "Safety, Hipot & Thermal Tests", 4, after: ["booking"], cal: labCal.id),
                        TaskSpec("rework", "Corrective Actions & Retest", 4, after: ["emc_lab", "safety_lab"], cal: compCal.id)
                    ]),
                    PhaseSpec("Filing & Certification", "Report audit, TCB filing, and Declaration of Conformity.", [
                        TaskSpec("tcb", "Test Report Review & TCB Filing", 3, after: ["rework"], cal: legalCal.id),
                        TaskSpec("doc", "Declaration of Conformity & Labeling", 2, after: ["rework"], cal: compCal.id),
                        TaskSpec("cert", "Certification Issued", 0, milestone: true, after: ["tcb", "doc"], cal: legalCal.id)
                    ])
                ]
            )
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
        let calendarID: UUID?

        init(
            _ key: String,
            _ title: String,
            _ duration: Int,
            milestone: Bool = false,
            after: [String] = [],
            lag: Int = 0,
            pinnedStart: CalendarDay? = nil,
            cal calendarID: UUID? = nil
        ) {
            self.key = key
            self.title = title
            self.duration = duration
            self.isMilestone = milestone
            self.after = after
            self.lag = lag
            self.pinnedStart = pinnedStart
            self.calendarID = calendarID
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
        calendars: [NamedWorkingCalendar],
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
                        calendarID: item.calendarID,
                        calendar: cal
                    )
                )
            }
        }

        let scheduled = SchedulingEngine.recalculateAll(
            tasks: allTasks,
            projectStart: start,
            calendar: cal,
            namedCalendars: calendars
        )
        return ProjectDocument(
            name: name,
            projectStartDate: start,
            workingCalendar: cal,
            calendars: calendars,
            tasks: scheduled
        )
    }
}
