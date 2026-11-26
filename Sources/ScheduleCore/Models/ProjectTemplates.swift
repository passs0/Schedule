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
            let usEng = NamedWorkingCalendar(name: "US Engineering", owner: "Core EE / ME", workingCalendar: cal)
            let szCM = NamedWorkingCalendar(
                name: "Shenzhen Factory (CM)",
                owner: "Manufacturing",
                workingCalendar: WorkingCalendar(workingWeekdays: [2, 3, 4, 5, 6, 7])
            )
            let euLab = NamedWorkingCalendar(name: "EU Compliance Lab", owner: "Regulatory", workingCalendar: cal)

            return buildTemplate(
                name: "Hardware Product — EVT to Mass Production",
                start: start,
                cal: cal,
                calendars: [usEng, szCM, euLab],
                phases: [
                    PhaseSpec("Architecture & Concept", "System requirements, block diagram, and architecture freeze.", [
                        TaskSpec("prd", "Product Requirements & Target Spec", 4, cal: usEng.id),
                        TaskSpec("arch", "System Architecture & Block Diagram", 5, after: ["prd"], cal: usEng.id),
                        TaskSpec("arch_freeze", "Architecture Freeze", 0, milestone: true, after: ["arch"], cal: usEng.id)
                    ]),
                    PhaseSpec("Electrical & PCB Layout", "Schematic capture, long-lead BOM, impedance layout, and EVT PCBA.", [
                        TaskSpec("sch", "Schematic Capture & Power Tree", 7, after: ["arch_freeze"], cal: usEng.id),
                        TaskSpec("bom", "Long-Lead Component Sourcing & BOM", 7, after: ["arch_freeze"], cal: usEng.id),
                        TaskSpec("pcb", "PCB Layout, Stackup & Impedance Control", 8, after: ["sch"], cal: usEng.id),
                        TaskSpec("dfm", "DFM / DFA Review & Gerber Release", 2, after: ["pcb"], cal: usEng.id),
                        TaskSpec("evt_pcba", "EVT Bare Board Fab & PCBA", 7, after: ["dfm", "bom"], lag: 2, cal: szCM.id)
                    ]),
                    PhaseSpec("Mechanical & Materials", "Enclosure CAD, CMF spec, FEA simulation, and soft tooling.", [
                        TaskSpec("cad", "Mechanical CAD & Enclosure Design", 10, after: ["arch_freeze"], cal: usEng.id),
                        TaskSpec("cmf", "Materials, Finish & CMF Specification", 6, after: ["arch_freeze"], cal: usEng.id),
                        TaskSpec("fea", "Thermal & Drop FEA Simulation", 4, after: ["cad"], cal: usEng.id),
                        TaskSpec("cnc", "CNC & Soft Tooling EVT Enclosures", 8, after: ["fea", "cmf"], cal: szCM.id)
                    ]),
                    PhaseSpec("EVT — Engineering Validation", "30-unit EVT assembly, bring-up, and RF/functional validation.", [
                        TaskSpec("evt_asm", "EVT Unit Assembly (30 Units)", 3, after: ["evt_pcba", "cnc"], cal: szCM.id),
                        TaskSpec("bringup", "Board Bring-Up & Firmware Integration", 5, after: ["evt_asm"], cal: usEng.id),
                        TaskSpec("evt_rf", "EVT Functional & RF Bench Validation", 5, after: ["bringup"], cal: usEng.id),
                        TaskSpec("evt_gate", "EVT Exit Gate", 0, milestone: true, after: ["evt_rf"], cal: usEng.id)
                    ]),
                    PhaseSpec("DVT — Design Validation", "Hard tooling T1/T2, Rev B PCBA, and 100-unit DVT reliability.", [
                        TaskSpec("mold", "Hard Tooling & Injection Mold (T1 / T2)", 12, after: ["evt_gate"], cal: szCM.id),
                        TaskSpec("revb", "PCB Layout Rev B & PCBA (100 Units)", 10, after: ["evt_gate"], cal: szCM.id),
                        TaskSpec("dvt_build", "DVT Pilot Build & Reliability Testing", 10, after: ["mold", "revb"], cal: szCM.id),
                        TaskSpec("dvt_gate", "DVT Exit Gate", 0, milestone: true, after: ["dvt_build"], cal: usEng.id)
                    ]),
                    PhaseSpec("Compliance & Certification", "EMC/RF chamber testing, FCC/CE/UL, and RoHS/REACH declarations.", [
                        TaskSpec("prescan", "Pre-Compliance EMC / RF Chamber Scan", 5, after: ["evt_gate"], cal: euLab.id),
                        TaskSpec("lab_cert", "FCC / CE / UL Lab Certification", 10, after: ["dvt_gate", "prescan"], cal: euLab.id),
                        TaskSpec("rohs", "RoHS / REACH Material Declarations", 6, after: ["dvt_gate"], cal: euLab.id),
                        TaskSpec("reg_gate", "Regulatory Certification Granted", 0, milestone: true, after: ["lab_cert", "rohs"], cal: euLab.id)
                    ]),
                    PhaseSpec("PVT & Mass Production", "Packaging, PVT line qualification, golden sample, and MP ramp.", [
                        TaskSpec("pkg", "Packaging, Regulatory Labels & Inserts", 7, after: ["dvt_gate"], cal: szCM.id),
                        TaskSpec("pvt", "PVT Line Trial & Yield Qualification", 7, after: ["dvt_gate", "pkg"], lag: 2, cal: szCM.id),
                        TaskSpec("golden", "Golden Sample Sign-Off", 3, after: ["pvt", "reg_gate"], cal: usEng.id),
                        TaskSpec("mp", "Mass Production Ramp (MP)", 0, milestone: true, after: ["golden"], cal: szCM.id)
                    ])
                ]
            )

        case .softwareRelease:
            let beCal = NamedWorkingCalendar(name: "Backend & Data", owner: "Core Services", workingCalendar: cal)
            let uiCal = NamedWorkingCalendar(name: "Client & UI", owner: "App Engineering", workingCalendar: cal)
            let sreCal = NamedWorkingCalendar(name: "Platform / SRE", owner: "Infrastructure", workingCalendar: cal)
            let qaCal = NamedWorkingCalendar(name: "QA & Security", owner: "Quality", workingCalendar: cal)

            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [beCal, uiCal, sreCal, qaCal],
                phases: [
                    PhaseSpec("Discovery & Architecture", "Requirements, API contracts, data model, and threat model.", [
                        TaskSpec("prd", "PRD & Acceptance Criteria", 3, cal: beCal.id),
                        TaskSpec("api", "API Schema & Contract Spec", 4, after: ["prd"], cal: beCal.id),
                        TaskSpec("model", "Data Model & Migration Plan", 3, after: ["prd"], cal: beCal.id),
                        TaskSpec("threat", "Security Threat Model", 2, after: ["api"], cal: qaCal.id),
                        TaskSpec("arch_gate", "Architecture Freeze", 0, milestone: true, after: ["api", "model", "threat"], cal: beCal.id)
                    ]),
                    PhaseSpec("Core Backend & Platform", "Auth, domain APIs, telemetry pipeline, and CI/CD.", [
                        TaskSpec("auth", "Service Scaffolding & Auth", 4, after: ["arch_gate"], cal: beCal.id),
                        TaskSpec("domain", "Core Domain APIs & Persistence", 7, after: ["auth"], cal: beCal.id),
                        TaskSpec("telemetry", "Event Pipeline & Telemetry", 4, after: ["auth"], cal: sreCal.id),
                        TaskSpec("cicd", "CI/CD & Feature Flag Infrastructure", 4, after: ["arch_gate"], cal: sreCal.id),
                        TaskSpec("be_gate", "Backend Integration Ready", 0, milestone: true, after: ["domain", "telemetry", "cicd"], cal: beCal.id)
                    ]),
                    PhaseSpec("Client & Firmware Engineering", "UI shell, core workflows, offline cache, and localization.", [
                        TaskSpec("shell", "Design System & Navigation Shell", 4, after: ["arch_gate"], cal: uiCal.id),
                        TaskSpec("flows", "Core Workflows & State Sync", 7, after: ["shell"], cal: uiCal.id),
                        TaskSpec("offline", "Offline Cache & Error Recovery", 4, after: ["flows"], cal: uiCal.id),
                        TaskSpec("l10n", "Accessibility & Localization", 3, after: ["flows"], cal: uiCal.id),
                        TaskSpec("fe_gate", "Client Feature Complete", 0, milestone: true, after: ["offline", "l10n", "be_gate"], cal: uiCal.id)
                    ]),
                    PhaseSpec("Integration & Performance Hardening", "E2E testing, load benchmarking, profiling, and bug bash.", [
                        TaskSpec("e2e", "End-to-End Integration Suite", 5, after: ["fe_gate"], cal: qaCal.id),
                        TaskSpec("load", "Load & Latency Benchmarking", 3, after: ["be_gate"], cal: sreCal.id),
                        TaskSpec("prof", "Memory & Battery Profiling", 3, after: ["fe_gate"], cal: uiCal.id),
                        TaskSpec("bash", "Bug Bash & P1 Triage", 3, after: ["e2e", "load", "prof"], cal: qaCal.id),
                        TaskSpec("freeze", "Code Freeze", 0, milestone: true, after: ["bash"], cal: qaCal.id)
                    ]),
                    PhaseSpec("Security & Release Readiness", "Pen-test, compliance check, runbooks, and RC sign-off.", [
                        TaskSpec("pentest", "Pen-Test & Dependency Audit", 4, after: ["freeze"], cal: qaCal.id),
                        TaskSpec("review", "Privacy & App Review Compliance", 3, after: ["freeze"], cal: qaCal.id),
                        TaskSpec("docs", "Release Notes & On-Call Runbooks", 2, after: ["freeze"], cal: sreCal.id),
                        TaskSpec("rc", "Release Candidate Sign-Off", 0, milestone: true, after: ["pentest", "review", "docs"], cal: qaCal.id)
                    ]),
                    PhaseSpec("Staged Rollout", "Canary rollout, staged expansion, GA, and retrospective.", [
                        TaskSpec("canary", "Canary 5% Rollout & Error Budget Check", 2, after: ["rc"], cal: sreCal.id),
                        TaskSpec("ramp", "50% Staged Production Expansion", 2, after: ["canary"], cal: sreCal.id),
                        TaskSpec("ga", "100% Production GA", 0, milestone: true, after: ["ramp"], cal: sreCal.id),
                        TaskSpec("retro", "Post-Launch Telemetry & Retro", 2, after: ["ga"], cal: beCal.id)
                    ])
                ]
            )

        case .systemCutover:
            let netCal = NamedWorkingCalendar(name: "Cloud Infra / Network", owner: "Infra Eng", workingCalendar: cal)
            let dbCal = NamedWorkingCalendar(name: "Database & Storage", owner: "Data Eng", workingCalendar: cal)
            let appCal = NamedWorkingCalendar(name: "App & Platform", owner: "Platform Eng", workingCalendar: cal)
            let opsCal = NamedWorkingCalendar(
                name: "SRE / 24x7 Cutover",
                owner: "Cutover Ops",
                workingCalendar: WorkingCalendar(workingWeekdays: [1, 2, 3, 4, 5, 6, 7])
            )
            let cutoverStart = cal.addWorkingDays(26, to: start)

            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [netCal, dbCal, appCal, opsCal],
                phases: [
                    PhaseSpec("Discovery & Landing Zone", "Dependency mapping, Terraform VPC, and IAM/KMS provisioning.", [
                        TaskSpec("inv", "Workload & Dependency Mapping", 3, cal: netCal.id),
                        TaskSpec("risk", "Risk & Rollback Matrix", 2, after: ["inv"], cal: opsCal.id),
                        TaskSpec("vpc", "IaC VPC & Transit Networking", 6, after: ["inv"], cal: netCal.id),
                        TaskSpec("iam", "IAM, KMS & Secrets Provisioning", 4, after: ["inv"], cal: netCal.id),
                        TaskSpec("lz_gate", "Landing Zone Ready", 0, milestone: true, after: ["risk", "vpc", "iam"], cal: netCal.id)
                    ]),
                    PhaseSpec("Data & Storage Replication", "Target DB provisioning, CDC pipeline, and parity verification.", [
                        TaskSpec("db_prov", "Target DB Provisioning & Sizing", 3, after: ["lz_gate"], cal: dbCal.id),
                        TaskSpec("cdc", "Schema Migration & CDC Pipeline", 7, after: ["db_prov"], cal: dbCal.id),
                        TaskSpec("obj", "Object Storage Sync & Checksums", 5, after: ["lz_gate"], cal: dbCal.id),
                        TaskSpec("parity", "Data Parity & Checksum Audit", 3, after: ["cdc", "obj"], cal: dbCal.id),
                        TaskSpec("data_gate", "Data Sync Gate", 0, milestone: true, after: ["parity"], cal: dbCal.id)
                    ]),
                    PhaseSpec("Application & Traffic Prep", "Containerization, DNS TTL lowering, shadow traffic, and load tests.", [
                        TaskSpec("helm", "Containerization & Helm Charts", 6, after: ["lz_gate"], cal: appCal.id),
                        TaskSpec("dns_prep", "DNS TTL Lowering & Ingress Rules", 2, after: ["lz_gate"], cal: netCal.id),
                        TaskSpec("shadow", "Shadow Traffic & Synthetic Probes", 4, after: ["helm", "dns_prep", "data_gate"], cal: opsCal.id),
                        TaskSpec("failover", "Load & Failover Benchmarking", 3, after: ["shadow"], cal: opsCal.id)
                    ]),
                    PhaseSpec("Dress Rehearsal & Go / No-Go", "Dry-run cutover, rollback timing drill, and war-room readiness.", [
                        TaskSpec("dryrun", "Full Cutover Dry-Run", 2, after: ["failover"], cal: opsCal.id),
                        TaskSpec("drill", "Rollback Drill & Timing Audit", 2, after: ["dryrun"], cal: opsCal.id),
                        TaskSpec("roster", "Runbook Freeze & War-Room Roster", 1, after: ["dryrun"], cal: opsCal.id),
                        TaskSpec("gonogo", "Go / No-Go Sign-Off", 0, milestone: true, after: ["drill", "roster"], cal: opsCal.id)
                    ]),
                    PhaseSpec("Production Cutover Window", "Pinned 24x7 cutover window, DNS switchover, and hypercare.", [
                        TaskSpec("freeze", "Pre-Cutover Freeze & Final Snapshot", 1, after: ["gonogo"], cal: dbCal.id),
                        TaskSpec("cutover", "Production Cutover Window", 2, after: ["freeze"], pinnedStart: cutoverStart, cal: opsCal.id),
                        TaskSpec("dns_cut", "DNS & Load Balancer Switchover", 1, after: ["cutover"], cal: opsCal.id),
                        TaskSpec("smoke", "Smoke & E2E Production Verification", 1, after: ["dns_cut"], cal: opsCal.id),
                        TaskSpec("hyper", "48-Hour Hypercare & SLO Monitoring", 3, after: ["smoke"], cal: opsCal.id),
                        TaskSpec("decomm", "Legacy Decommission & Closure", 0, milestone: true, after: ["hyper"], cal: netCal.id)
                    ])
                ]
            )

        case .complianceAudit:
            let compCal = NamedWorkingCalendar(name: "Compliance Engineering", owner: "Regulatory", workingCalendar: cal)
            let labCal = NamedWorkingCalendar(name: "Accredited Test Lab", owner: "Test House", workingCalendar: cal)
            let legalCal = NamedWorkingCalendar(name: "Quality & Legal", owner: "QA / Legal", workingCalendar: cal)

            return buildTemplate(
                name: title,
                start: start,
                cal: cal,
                calendars: [compCal, labCal, legalCal],
                phases: [
                    PhaseSpec("Regulatory Scope & Technical File", "Standards matrix, risk file, and safety BOM.", [
                        TaskSpec("matrix", "Target Market & Standards Matrix", 3, cal: compCal.id),
                        TaskSpec("risk", "Risk Assessment & Essential Requirements", 4, after: ["matrix"], cal: compCal.id),
                        TaskSpec("tcf", "Technical Construction File & Schematics", 5, after: ["matrix"], cal: compCal.id),
                        TaskSpec("cbom", "Critical Component & Safety BOM", 4, after: ["matrix"], cal: compCal.id),
                        TaskSpec("scope_gate", "Scope & Technical File Lock", 0, milestone: true, after: ["risk", "tcf", "cbom"], cal: compCal.id)
                    ]),
                    PhaseSpec("Internal Pre-Compliance", "EMC pre-scan, ESD/surge, thermal checks, and golden unit build.", [
                        TaskSpec("emc_pre", "Conducted & Radiated Pre-Scan", 4, after: ["scope_gate"], cal: compCal.id),
                        TaskSpec("esd_pre", "ESD, Surge & Immunity Pre-Check", 3, after: ["scope_gate"], cal: compCal.id),
                        TaskSpec("therm", "Thermal & Abnormal Operation Check", 3, after: ["scope_gate"], cal: compCal.id),
                        TaskSpec("golden", "Pre-Test Remediation & Golden Unit Build", 4, after: ["emc_pre", "esd_pre", "therm"], cal: compCal.id),
                        TaskSpec("pkg_gate", "Lab Submission Package Ready", 0, milestone: true, after: ["golden"], cal: compCal.id)
                    ]),
                    PhaseSpec("Accredited Lab Testing", "Booking lag, formal EMC/Safety/Wireless testing, and retest.", [
                        TaskSpec("queue", "Lab Queue & Sample Shipping", 2, after: ["pkg_gate"], lag: 4, cal: labCal.id),
                        TaskSpec("emc_lab", "Formal EMC / RF Chamber Testing", 5, after: ["queue"], cal: labCal.id),
                        TaskSpec("safety", "Safety, Hipot & Dielectric Testing", 4, after: ["queue"], cal: labCal.id),
                        TaskSpec("sar", "SAR / Wireless Protocol Testing", 4, after: ["queue"], cal: labCal.id),
                        TaskSpec("retest", "Lab Corrective Actions & Retest", 4, after: ["emc_lab", "safety", "sar"], cal: compCal.id)
                    ]),
                    PhaseSpec("Chemical & Environmental Declarations", "RoHS/REACH material screening, UN38.3, and WEEE compliance.", [
                        TaskSpec("rohs", "RoHS / REACH Lab Material Screening", 6, after: ["scope_gate"], cal: labCal.id),
                        TaskSpec("un383", "Battery Transport UN38.3 & MSDS", 5, after: ["scope_gate"], cal: compCal.id),
                        TaskSpec("weee", "Recycling & WEEE Packaging Compliance", 3, after: ["scope_gate"], cal: legalCal.id)
                    ]),
                    PhaseSpec("Filing & Market Access", "Test report audit, TCB filing, DoC, and final certification.", [
                        TaskSpec("audit", "Accredited Test Report Audit", 3, after: ["retest", "rohs"], cal: legalCal.id),
                        TaskSpec("tcb", "TCB / Notified Body Filing", 4, after: ["audit", "un383"], cal: legalCal.id),
                        TaskSpec("doc", "Declaration of Conformity & Regulatory Labels", 3, after: ["audit", "weee"], cal: compCal.id),
                        TaskSpec("cert", "Certification Granted", 0, milestone: true, after: ["tcb", "doc"], cal: legalCal.id)
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
