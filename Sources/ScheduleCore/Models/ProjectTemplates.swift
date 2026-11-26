import Foundation

/// Built-in project templates, each modeling a comprehensive, real-world engineering schedule
/// with multi-phase WBS, parallel cross-functional tracks, regional/team calendars, lags, and milestones.
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
        case .hardwareNPI: return "EVT → MP"
        case .softwareRelease: return "Parallel Sprints"
        case .systemCutover: return "Pinned Window"
        case .complianceAudit: return "Lab & TCB"
        }
    }

    public var subtitle: String {
        switch self {
        case .blank:
            return "Clean slate with a single kickoff task."
        case .hardwareNPI:
            return "Concept to mass production across EE, ME, Shenzhen CM, and compliance lab calendars."
        case .softwareRelease:
            return "Architecture, parallel backend & client tracks, hardening, security audit, and canary GA."
        case .systemCutover:
            return "Landing zone, CDC replication, dress rehearsal, pinned 24x7 cutover window, and hypercare."
        case .complianceAudit:
            return "Technical file, internal pre-scans, accredited lab testing, RoHS/REACH, and TCB filing."
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
            // Only the factory has a different working calendar (6-day Mon–Sat); teams are tracked via Owner.
            let szCM = NamedWorkingCalendar(
                name: "Shenzhen Factory (6-Day)",
                owner: "Manufacturing",
                workingCalendar: WorkingCalendar(workingWeekdays: [2, 3, 4, 5, 6, 7])
            )

            return buildTemplate(
                name: "Hardware Product — EVT to Mass Production",
                start: start,
                cal: cal,
                calendars: [szCM],
                phases: [
                    PhaseSpec("Architecture & Concept", "System requirements, block diagram, and architecture freeze.", [
                        TaskSpec("prd", "Product Requirements & Target Spec", 4, owner: "Systems"),
                        TaskSpec("arch", "System Architecture & Block Diagram", 5, after: ["prd"], owner: "Systems"),
                        TaskSpec("arch_freeze", "Architecture Freeze", 0, milestone: true, after: ["arch"], owner: "Systems")
                    ]),
                    PhaseSpec("Electrical & PCB Layout", "Schematic capture, long-lead BOM, impedance layout, and EVT PCBA.", [
                        TaskSpec("sch", "Schematic Capture & Power Tree", 7, after: ["arch_freeze"], owner: "EE"),
                        TaskSpec("bom", "Long-Lead Component Sourcing & BOM", 7, after: ["arch_freeze"], owner: "Supply Chain"),
                        TaskSpec("pcb", "PCB Layout, Stackup & Impedance Control", 8, after: ["sch"], owner: "EE"),
                        TaskSpec("dfm", "DFM / DFA Review & Gerber Release", 2, after: ["pcb"], owner: "EE"),
                        TaskSpec("evt_pcba", "EVT Bare Board Fab & PCBA", 7, after: ["dfm", "bom"], lag: 2, owner: "Factory CM", cal: szCM.id)
                    ]),
                    PhaseSpec("Mechanical & Materials", "Enclosure CAD, CMF spec, FEA simulation, and soft tooling.", [
                        TaskSpec("cad", "Mechanical CAD & Enclosure Design", 10, after: ["arch_freeze"], owner: "ME"),
                        TaskSpec("cmf", "Materials, Finish & CMF Specification", 6, after: ["arch_freeze"], owner: "ID / CMF"),
                        TaskSpec("fea", "Thermal & Drop FEA Simulation", 4, after: ["cad"], owner: "ME"),
                        TaskSpec("cnc", "CNC & Soft Tooling EVT Enclosures", 8, after: ["fea", "cmf"], owner: "Factory CM", cal: szCM.id)
                    ]),
                    PhaseSpec("EVT — Engineering Validation", "30-unit EVT assembly, bring-up, and RF/functional validation.", [
                        TaskSpec("evt_asm", "EVT Unit Assembly (30 Units)", 3, after: ["evt_pcba", "cnc"], owner: "Factory CM", cal: szCM.id),
                        TaskSpec("bringup", "Board Bring-Up & Firmware Integration", 5, after: ["evt_asm"], owner: "Firmware"),
                        TaskSpec("evt_rf", "EVT Functional & RF Bench Validation", 5, after: ["bringup"], owner: "EE"),
                        TaskSpec("evt_gate", "EVT Exit Gate", 0, milestone: true, after: ["evt_rf"], owner: "Systems")
                    ]),
                    PhaseSpec("DVT — Design Validation", "Hard tooling T1/T2, Rev B PCBA, and 100-unit DVT reliability.", [
                        TaskSpec("mold", "Hard Tooling & Injection Mold (T1 / T2)", 12, after: ["evt_gate"], owner: "Factory CM", cal: szCM.id),
                        TaskSpec("revb", "PCB Layout Rev B & PCBA (100 Units)", 10, after: ["evt_gate"], owner: "Factory CM", cal: szCM.id),
                        TaskSpec("dvt_build", "DVT Pilot Build & Reliability Testing", 10, after: ["mold", "revb"], owner: "Factory CM", cal: szCM.id),
                        TaskSpec("dvt_gate", "DVT Exit Gate", 0, milestone: true, after: ["dvt_build"], owner: "Systems")
                    ]),
                    PhaseSpec("Compliance & Certification", "EMC/RF chamber testing, FCC/CE/UL, and RoHS/REACH declarations.", [
                        TaskSpec("prescan", "Pre-Compliance EMC / RF Chamber Scan", 5, after: ["evt_gate"], owner: "Compliance"),
                        TaskSpec("lab_cert", "FCC / CE / UL Lab Certification", 10, after: ["dvt_gate", "prescan"], owner: "Compliance"),
                        TaskSpec("rohs", "RoHS / REACH Material Declarations", 6, after: ["dvt_gate"], owner: "Compliance"),
                        TaskSpec("reg_gate", "Regulatory Certification Granted", 0, milestone: true, after: ["lab_cert", "rohs"], owner: "Compliance")
                    ]),
                    PhaseSpec("PVT & Mass Production", "Packaging, PVT line qualification, golden sample, and MP ramp.", [
                        TaskSpec("pkg", "Packaging, Regulatory Labels & Inserts", 7, after: ["dvt_gate"], owner: "ME"),
                        TaskSpec("pvt", "PVT Line Trial & Yield Qualification", 7, after: ["dvt_gate", "pkg"], lag: 2, owner: "Factory CM", cal: szCM.id),
                        TaskSpec("golden", "Golden Sample Sign-Off", 3, after: ["pvt", "reg_gate"], owner: "Systems"),
                        TaskSpec("mp", "Mass Production Ramp (MP)", 0, milestone: true, after: ["golden"], owner: "Factory CM", cal: szCM.id)
                    ])
                ]
            )

        case .softwareRelease:
            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [],
                phases: [
                    PhaseSpec("Discovery & Architecture", "Requirements, API contracts, data model, and threat model.", [
                        TaskSpec("prd", "PRD & Acceptance Criteria", 3, owner: "Product"),
                        TaskSpec("api", "API Schema & Contract Spec", 4, after: ["prd"], owner: "Backend"),
                        TaskSpec("model", "Data Model & Migration Plan", 3, after: ["prd"], owner: "Backend"),
                        TaskSpec("threat", "Security Threat Model", 2, after: ["api"], owner: "Security"),
                        TaskSpec("arch_gate", "Architecture Freeze", 0, milestone: true, after: ["api", "model", "threat"], owner: "Tech Lead")
                    ]),
                    PhaseSpec("Core Backend & Platform", "Auth, domain APIs, telemetry pipeline, and CI/CD.", [
                        TaskSpec("auth", "Service Scaffolding & Auth", 4, after: ["arch_gate"], owner: "Backend"),
                        TaskSpec("domain", "Core Domain APIs & Persistence", 7, after: ["auth"], owner: "Backend"),
                        TaskSpec("telemetry", "Event Pipeline & Telemetry", 4, after: ["auth"], owner: "SRE"),
                        TaskSpec("cicd", "CI/CD & Feature Flag Infrastructure", 4, after: ["arch_gate"], owner: "SRE"),
                        TaskSpec("be_gate", "Backend Integration Ready", 0, milestone: true, after: ["domain", "telemetry", "cicd"], owner: "Backend")
                    ]),
                    PhaseSpec("Client & Firmware Engineering", "UI shell, core workflows, offline cache, and localization.", [
                        TaskSpec("shell", "Design System & Navigation Shell", 4, after: ["arch_gate"], owner: "Client UI"),
                        TaskSpec("flows", "Core Workflows & State Sync", 7, after: ["shell"], owner: "Client UI"),
                        TaskSpec("offline", "Offline Cache & Error Recovery", 4, after: ["flows"], owner: "Client UI"),
                        TaskSpec("l10n", "Accessibility & Localization", 3, after: ["flows"], owner: "Client UI"),
                        TaskSpec("fe_gate", "Client Feature Complete", 0, milestone: true, after: ["offline", "l10n", "be_gate"], owner: "Client UI")
                    ]),
                    PhaseSpec("Integration & Performance Hardening", "E2E testing, load benchmarking, profiling, and bug bash.", [
                        TaskSpec("e2e", "End-to-End Integration Suite", 5, after: ["fe_gate"], owner: "QA"),
                        TaskSpec("load", "Load & Latency Benchmarking", 3, after: ["be_gate"], owner: "SRE"),
                        TaskSpec("prof", "Memory & Battery Profiling", 3, after: ["fe_gate"], owner: "Client UI"),
                        TaskSpec("bash", "Bug Bash & P1 Triage", 3, after: ["e2e", "load", "prof"], owner: "QA"),
                        TaskSpec("freeze", "Code Freeze", 0, milestone: true, after: ["bash"], owner: "Tech Lead")
                    ]),
                    PhaseSpec("Security & Release Readiness", "Pen-test, compliance check, runbooks, and RC sign-off.", [
                        TaskSpec("pentest", "Pen-Test & Dependency Audit", 4, after: ["freeze"], owner: "Security"),
                        TaskSpec("review", "Privacy & App Review Compliance", 3, after: ["freeze"], owner: "QA"),
                        TaskSpec("docs", "Release Notes & On-Call Runbooks", 2, after: ["freeze"], owner: "SRE"),
                        TaskSpec("rc", "Release Candidate Sign-Off", 0, milestone: true, after: ["pentest", "review", "docs"], owner: "QA")
                    ]),
                    PhaseSpec("Staged Rollout", "Canary rollout, staged expansion, GA, and retrospective.", [
                        TaskSpec("canary", "Canary 5% Rollout & Error Budget Check", 2, after: ["rc"], owner: "SRE"),
                        TaskSpec("ramp", "50% Staged Production Expansion", 2, after: ["canary"], owner: "SRE"),
                        TaskSpec("ga", "100% Production GA", 0, milestone: true, after: ["ramp"], owner: "SRE"),
                        TaskSpec("retro", "Post-Launch Telemetry & Retro", 2, after: ["ga"], owner: "Tech Lead")
                    ])
                ]
            )

        case .systemCutover:
            // Only the 24x7 cutover/hypercare window uses a 7-day calendar.
            let opsCal = NamedWorkingCalendar(
                name: "24×7 Cutover Ops",
                owner: "SRE",
                workingCalendar: WorkingCalendar(workingWeekdays: [1, 2, 3, 4, 5, 6, 7])
            )
            let cutoverStart = cal.addWorkingDays(26, to: start)

            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [opsCal],
                phases: [
                    PhaseSpec("Discovery & Landing Zone", "Dependency mapping, Terraform VPC, and IAM/KMS provisioning.", [
                        TaskSpec("inv", "Workload & Dependency Mapping", 3, owner: "Infra"),
                        TaskSpec("risk", "Risk & Rollback Matrix", 2, after: ["inv"], owner: "SRE"),
                        TaskSpec("vpc", "IaC VPC & Transit Networking", 6, after: ["inv"], owner: "Infra"),
                        TaskSpec("iam", "IAM, KMS & Secrets Provisioning", 4, after: ["inv"], owner: "Security"),
                        TaskSpec("lz_gate", "Landing Zone Ready", 0, milestone: true, after: ["risk", "vpc", "iam"], owner: "Infra")
                    ]),
                    PhaseSpec("Data & Storage Replication", "Target DB provisioning, CDC pipeline, and parity verification.", [
                        TaskSpec("db_prov", "Target DB Provisioning & Sizing", 3, after: ["lz_gate"], owner: "Database"),
                        TaskSpec("cdc", "Schema Migration & CDC Pipeline", 7, after: ["db_prov"], owner: "Database"),
                        TaskSpec("obj", "Object Storage Sync & Checksums", 5, after: ["lz_gate"], owner: "Database"),
                        TaskSpec("parity", "Data Parity & Checksum Audit", 3, after: ["cdc", "obj"], owner: "Database"),
                        TaskSpec("data_gate", "Data Sync Gate", 0, milestone: true, after: ["parity"], owner: "Database")
                    ]),
                    PhaseSpec("Application & Traffic Prep", "Containerization, DNS TTL lowering, shadow traffic, and load tests.", [
                        TaskSpec("helm", "Containerization & Helm Charts", 6, after: ["lz_gate"], owner: "Platform"),
                        TaskSpec("dns_prep", "DNS TTL Lowering & Ingress Rules", 2, after: ["lz_gate"], owner: "Infra"),
                        TaskSpec("shadow", "Shadow Traffic & Synthetic Probes", 4, after: ["helm", "dns_prep", "data_gate"], owner: "SRE"),
                        TaskSpec("failover", "Load & Failover Benchmarking", 3, after: ["shadow"], owner: "SRE")
                    ]),
                    PhaseSpec("Dress Rehearsal & Go / No-Go", "Dry-run cutover, rollback timing drill, and war-room readiness.", [
                        TaskSpec("dryrun", "Full Cutover Dry-Run", 2, after: ["failover"], owner: "SRE"),
                        TaskSpec("drill", "Rollback Drill & Timing Audit", 2, after: ["dryrun"], owner: "SRE"),
                        TaskSpec("roster", "Runbook Freeze & War-Room Roster", 1, after: ["dryrun"], owner: "SRE"),
                        TaskSpec("gonogo", "Go / No-Go Sign-Off", 0, milestone: true, after: ["drill", "roster"], owner: "SRE")
                    ]),
                    PhaseSpec("Production Cutover Window", "Pinned 24x7 cutover window, DNS switchover, and hypercare.", [
                        TaskSpec("freeze", "Pre-Cutover Freeze & Final Snapshot", 1, after: ["gonogo"], owner: "Database"),
                        TaskSpec("cutover", "Production Cutover Window", 2, after: ["freeze"], pinnedStart: cutoverStart, owner: "SRE", cal: opsCal.id),
                        TaskSpec("dns_cut", "DNS & Load Balancer Switchover", 1, after: ["cutover"], owner: "Infra", cal: opsCal.id),
                        TaskSpec("smoke", "Smoke & E2E Production Verification", 1, after: ["dns_cut"], owner: "SRE", cal: opsCal.id),
                        TaskSpec("hyper", "48-Hour Hypercare & SLO Monitoring", 3, after: ["smoke"], owner: "SRE", cal: opsCal.id),
                        TaskSpec("decomm", "Legacy Decommission & Closure", 0, milestone: true, after: ["hyper"], owner: "Infra")
                    ])
                ]
            )

        case .complianceAudit:
            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [],
                phases: [
                    PhaseSpec("Regulatory Scope & Technical File", "Standards matrix, risk file, and safety BOM.", [
                        TaskSpec("matrix", "Target Market & Standards Matrix", 3, owner: "Compliance"),
                        TaskSpec("risk", "Risk Assessment & Essential Requirements", 4, after: ["matrix"], owner: "Compliance"),
                        TaskSpec("tcf", "Technical Construction File & Schematics", 5, after: ["matrix"], owner: "Compliance"),
                        TaskSpec("cbom", "Critical Component & Safety BOM", 4, after: ["matrix"], owner: "EE"),
                        TaskSpec("scope_gate", "Scope & Technical File Lock", 0, milestone: true, after: ["risk", "tcf", "cbom"], owner: "Compliance")
                    ]),
                    PhaseSpec("Internal Pre-Compliance", "EMC pre-scan, ESD/surge, thermal checks, and golden unit build.", [
                        TaskSpec("emc_pre", "Conducted & Radiated Pre-Scan", 4, after: ["scope_gate"], owner: "Compliance"),
                        TaskSpec("esd_pre", "ESD, Surge & Immunity Pre-Check", 3, after: ["scope_gate"], owner: "EE"),
                        TaskSpec("therm", "Thermal & Abnormal Operation Check", 3, after: ["scope_gate"], owner: "ME"),
                        TaskSpec("golden", "Pre-Test Remediation & Golden Unit Build", 4, after: ["emc_pre", "esd_pre", "therm"], owner: "Compliance"),
                        TaskSpec("pkg_gate", "Lab Submission Package Ready", 0, milestone: true, after: ["golden"], owner: "Compliance")
                    ]),
                    PhaseSpec("Accredited Lab Testing", "Booking lag, formal EMC/Safety/Wireless testing, and retest.", [
                        TaskSpec("queue", "Lab Queue & Sample Shipping", 2, after: ["pkg_gate"], lag: 4, owner: "Test Lab"),
                        TaskSpec("emc_lab", "Formal EMC / RF Chamber Testing", 5, after: ["queue"], owner: "Test Lab"),
                        TaskSpec("safety", "Safety, Hipot & Dielectric Testing", 4, after: ["queue"], owner: "Test Lab"),
                        TaskSpec("sar", "SAR / Wireless Protocol Testing", 4, after: ["queue"], owner: "Test Lab"),
                        TaskSpec("retest", "Lab Corrective Actions & Retest", 4, after: ["emc_lab", "safety", "sar"], owner: "Compliance")
                    ]),
                    PhaseSpec("Chemical & Environmental Declarations", "RoHS/REACH material screening, UN38.3, and WEEE compliance.", [
                        TaskSpec("rohs", "RoHS / REACH Lab Material Screening", 6, after: ["scope_gate"], owner: "Test Lab"),
                        TaskSpec("un383", "Battery Transport UN38.3 & MSDS", 5, after: ["scope_gate"], owner: "Compliance"),
                        TaskSpec("weee", "Recycling & WEEE Packaging Compliance", 3, after: ["scope_gate"], owner: "Legal")
                    ]),
                    PhaseSpec("Filing & Market Access", "Test report audit, TCB filing, DoC, and final certification.", [
                        TaskSpec("audit", "Accredited Test Report Audit", 3, after: ["retest", "rohs"], owner: "Legal"),
                        TaskSpec("tcb", "TCB / Notified Body Filing", 4, after: ["audit", "un383"], owner: "Legal"),
                        TaskSpec("doc", "Declaration of Conformity & Regulatory Labels", 3, after: ["audit", "weee"], owner: "Compliance"),
                        TaskSpec("cert", "Certification Granted", 0, milestone: true, after: ["tcb", "doc"], owner: "Legal")
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
        let owner: String?
        let calendarID: UUID?

        init(
            _ key: String,
            _ title: String,
            _ duration: Int,
            milestone: Bool = false,
            after: [String] = [],
            lag: Int = 0,
            pinnedStart: CalendarDay? = nil,
            owner: String? = nil,
            cal calendarID: UUID? = nil
        ) {
            self.key = key
            self.title = title
            self.duration = duration
            self.isMilestone = milestone
            self.after = after
            self.lag = lag
            self.pinnedStart = pinnedStart
            self.owner = owner
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
                        dri: item.owner,
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
