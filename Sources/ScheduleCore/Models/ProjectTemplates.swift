import Foundation

/// Built-in project templates tailored for technology, software, and electronics engineering teams.
public enum ProjectTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank
    case hardwareProduct
    case softwareDevelopment
    case electronicsManufacturing
    case siliconTapeOut
    case embeddedFirmware
    case cloudMigration
    case roboticsIntegration

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blank: return "Blank Project"
        case .hardwareProduct: return "Hardware Product Development"
        case .softwareDevelopment: return "Software Release"
        case .electronicsManufacturing: return "Electronics Manufacturing (EVT/DVT/PVT)"
        case .siliconTapeOut: return "ASIC / Silicon Tape-Out"
        case .embeddedFirmware: return "Embedded Firmware & IoT"
        case .cloudMigration: return "Cloud Infrastructure Migration"
        case .roboticsIntegration: return "Robotics & Mechatronics"
        }
    }

    public var category: String {
        switch self {
        case .blank: return "Starter"
        case .hardwareProduct: return "Hardware"
        case .softwareDevelopment: return "Software"
        case .electronicsManufacturing: return "Manufacturing"
        case .siliconTapeOut: return "Semiconductor"
        case .embeddedFirmware: return "Firmware"
        case .cloudMigration: return "Infrastructure"
        case .roboticsIntegration: return "Robotics"
        }
    }

    public var subtitle: String {
        switch self {
        case .blank:
            return "Start from a clean slate with a single kickoff task."
        case .hardwareProduct:
            return "Industrial design, prototyping, manufacturing, packaging, and launch."
        case .softwareDevelopment:
            return "Architecture, parallel backend/UI/auth streams, QA & security, and rollout."
        case .electronicsManufacturing:
            return "Schematic & PCB layout through EVT, parallel DVT tooling/EMC, PVT, and MP."
        case .siliconTapeOut:
            return "RTL freeze, verification & synthesis, place & route, tape-out, and bring-up."
        case .embeddedFirmware:
            return "BSP & bootloader, parallel driver/wireless/OTA tracks, profiling, and soak."
        case .cloudMigration:
            return "Landing zone, parallel DB & service migration, dry-run, and cutover."
        case .roboticsIntegration:
            return "CAD, parallel procurement & harness, kinematics & sensor fusion, and FAT."
        }
    }

    public var systemImage: String {
        switch self {
        case .blank: return "doc"
        case .hardwareProduct: return "shippingbox"
        case .softwareDevelopment: return "chevron.left.forwardslash.chevron.right"
        case .electronicsManufacturing: return "cpu"
        case .siliconTapeOut: return "memorychip"
        case .embeddedFirmware: return "wave.3.right"
        case .cloudMigration: return "cloud"
        case .roboticsIntegration: return "gearshape.2"
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

        case .hardwareProduct:
            var doc = ProjectDocument.sampleProject(referenceDate: start)
            doc.name = "Hardware Product Development"
            doc.tasks = doc.tasks.map { task in
                var copy = task
                copy.percentComplete = 0
                return copy
            }
            return doc

        case .softwareDevelopment:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("Discovery & Architecture", "Requirements, API contracts, and system design.", [
                    TaskSpec("spec", "Product Spec & Scope Freeze", 4),
                    TaskSpec("arch", "System Architecture & API Contracts", 5, after: ["spec"]),
                    TaskSpec("arch_gate", "Architecture Sign-Off", 0, milestone: true, after: ["arch"])
                ]),
                PhaseSpec("Core Engineering", "Parallel backend, client UI, and platform tracks.", [
                    TaskSpec("backend", "Backend Services & Data Layer", 10, after: ["arch_gate"]),
                    TaskSpec("frontend", "Client UI & State Management", 10, after: ["arch_gate"]),
                    TaskSpec("auth", "Auth, Telemetry & CI/CD", 6, after: ["arch_gate"]),
                    TaskSpec("feat_gate", "Feature Complete", 0, milestone: true, after: ["backend", "frontend", "auth"])
                ]),
                PhaseSpec("Verification & Release", "QA regression, security review, and staged rollout.", [
                    TaskSpec("qa", "Integration & Regression QA", 5, after: ["feat_gate"]),
                    TaskSpec("sec", "Security & Performance Audit", 3, after: ["feat_gate"]),
                    TaskSpec("rollout", "Production Rollout", 0, milestone: true, after: ["qa", "sec"])
                ])
            ])

        case .electronicsManufacturing:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("Schematic & PCB Layout", "EE design, component selection, and fab release.", [
                    TaskSpec("sch", "Schematic Capture & BOM Lock", 6),
                    TaskSpec("pcb", "Multi-Layer PCB Layout & DFM", 8, after: ["sch"]),
                    TaskSpec("gerber", "Gerber Release to Fab", 0, milestone: true, after: ["pcb"])
                ]),
                PhaseSpec("EVT (Engineering Validation)", "PCBA bring-up, rework, and functional validation.", [
                    TaskSpec("smt", "Bare Board Fab & SMT Assembly", 10, after: ["gerber"]),
                    TaskSpec("bringup", "Board Bring-Up & Power Rail Tests", 5, after: ["smt"]),
                    TaskSpec("evt_gate", "EVT Exit Review", 0, milestone: true, after: ["bringup"])
                ]),
                PhaseSpec("DVT (Design Validation)", "Parallel enclosure tooling and compliance testing.", [
                    TaskSpec("tooling", "Hard Tooling & Mechanical Fit", 10, after: ["evt_gate"]),
                    TaskSpec("emc", "FCC / CE / UL Pre-Compliance & EMC", 7, after: ["evt_gate"]),
                    TaskSpec("dvt_gate", "DVT Sign-Off", 0, milestone: true, after: ["tooling", "emc"])
                ]),
                PhaseSpec("PVT & Mass Production", "ATE calibration, pilot run, and MP ramp.", [
                    TaskSpec("ate", "ATE Test Fixture Calibration", 4, after: ["dvt_gate"]),
                    TaskSpec("pvt", "PVT Pilot Run & Yield Audit", 6, after: ["ate"]),
                    TaskSpec("mp", "Mass Production Ramp", 0, milestone: true, after: ["pvt"])
                ])
            ])

        case .siliconTapeOut:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("RTL Design & Microarchitecture", "Block specs, RTL coding, and CDC checks.", [
                    TaskSpec("uarch", "Microarchitecture Spec", 6),
                    TaskSpec("rtl", "RTL Implementation & CDC Checks", 12, after: ["uarch"]),
                    TaskSpec("rtl_freeze", "RTL Freeze", 0, milestone: true, after: ["rtl"])
                ]),
                PhaseSpec("Verification & Synthesis", "UVM regression and logic synthesis.", [
                    TaskSpec("uvm", "UVM Functional Verification", 12, after: ["rtl_freeze"]),
                    TaskSpec("synth", "Logic Synthesis & DFT Insertion", 6, after: ["rtl_freeze"], lag: 4),
                    TaskSpec("netlist", "Netlist Handoff", 0, milestone: true, after: ["uvm", "synth"])
                ]),
                PhaseSpec("Physical Design & Tape-Out", "Place & route, STA timing closure, and DRC/LVS.", [
                    TaskSpec("pnr", "Floorplan, Place & Route", 10, after: ["netlist"]),
                    TaskSpec("sta", "Static Timing Analysis & DRC/LVS", 6, after: ["pnr"]),
                    TaskSpec("gds", "GDSII Tape-Out", 0, milestone: true, after: ["sta"])
                ]),
                PhaseSpec("Silicon Bring-Up", "Foundry shuttle and lab characterization.", [
                    TaskSpec("fab", "Wafer Fab & Packaging", 15, after: ["gds"]),
                    TaskSpec("bench", "Bench Bring-Up & Shmoo Testing", 8, after: ["fab"]),
                    TaskSpec("samples", "Engineering Samples Ready", 0, milestone: true, after: ["bench"])
                ])
            ])

        case .embeddedFirmware:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("BSP & Bootloader", "Board bring-up, secure boot, and RTOS configuration.", [
                    TaskSpec("rtos", "Toolchain & RTOS Bring-Up", 4),
                    TaskSpec("boot", "Secure Bootloader & Partitioning", 5, after: ["rtos"]),
                    TaskSpec("bsp_gate", "BSP Milestone", 0, milestone: true, after: ["boot"])
                ]),
                PhaseSpec("Drivers & Connectivity", "Parallel sensor drivers, wireless stack, and OTA.", [
                    TaskSpec("drivers", "Peripheral & Sensor Drivers", 8, after: ["bsp_gate"]),
                    TaskSpec("ble", "Wireless Stack & Cloud Telemetry", 7, after: ["bsp_gate"]),
                    TaskSpec("ota", "Signed OTA Update Pipeline", 5, after: ["bsp_gate"])
                ]),
                PhaseSpec("Profiling & Field Trial", "Power/thermal tuning and soak testing.", [
                    TaskSpec("power", "Power & Thermal Profiling", 5, after: ["drivers", "ble", "ota"]),
                    TaskSpec("soak", "72-Hour Soak & Field Trial", 6, after: ["power"]),
                    TaskSpec("fw_freeze", "Production Firmware Freeze", 0, milestone: true, after: ["soak"])
                ])
            ])

        case .cloudMigration:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("Assessment & Landing Zone", "Dependency mapping, Terraform VPC, and IAM.", [
                    TaskSpec("audit", "Workload & Dependency Audit", 4),
                    TaskSpec("iac", "IaC Landing Zone & Network Peering", 6, after: ["audit"]),
                    TaskSpec("lz_gate", "Landing Zone Ready", 0, milestone: true, after: ["iac"])
                ]),
                PhaseSpec("Data & Service Migration", "Parallel database replication and containerization.", [
                    TaskSpec("db", "Database Schema & CDC Replication", 8, after: ["lz_gate"]),
                    TaskSpec("svc", "Service Containerization & CI/CD", 7, after: ["lz_gate"]),
                    TaskSpec("dryrun", "Dry-Run Cutover & Load Test", 4, after: ["db", "svc"])
                ]),
                PhaseSpec("Cutover & Hardening", "DNS switch, monitoring, and hypercare.", [
                    TaskSpec("cutover", "Production Cutover Window", 2, after: ["dryrun"]),
                    TaskSpec("hyper", "48-Hour Hypercare & SLO Check", 3, after: ["cutover"]),
                    TaskSpec("done", "Migration Complete", 0, milestone: true, after: ["hyper"])
                ])
            ])

        case .roboticsIntegration:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                PhaseSpec("Mechanical & Harnessing", "CAD assemblies, machining, and control harness.", [
                    TaskSpec("cad", "CAD Assembly & Tolerance Stack", 7),
                    TaskSpec("cnc", "CNC Machining & Actuator Procurement", 10, after: ["cad"]),
                    TaskSpec("harness", "Control Harness & Safety Interlocks", 6, after: ["cad"]),
                    TaskSpec("mech_gate", "Mechanical & Harness Integration", 0, milestone: true, after: ["cnc", "harness"])
                ]),
                PhaseSpec("Motion & Sensor Fusion", "Parallel kinematics tuning and sensor calibration.", [
                    TaskSpec("motion", "Motion Control & Kinematics Tuning", 8, after: ["mech_gate"]),
                    TaskSpec("fusion", "Sensor Fusion & Calibration", 6, after: ["mech_gate"])
                ]),
                PhaseSpec("Burn-In & Acceptance", "Cycle testing and factory acceptance.", [
                    TaskSpec("burnin", "Continuous Cycle Burn-In", 7, after: ["motion", "fusion"]),
                    TaskSpec("fat", "Factory Acceptance Test (FAT)", 0, milestone: true, after: ["burnin"])
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

        init(_ key: String, _ title: String, _ duration: Int, milestone: Bool = false, after: [String] = [], lag: Int = 0) {
            self.key = key
            self.title = title
            self.duration = duration
            self.isMilestone = milestone
            self.after = after
            self.lag = lag
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

        // Pre-assign UUIDs so any task can reference any predecessor key
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
                        startDate: start,
                        durationDays: item.isMilestone ? 0 : item.duration,
                        isMilestone: item.isMilestone,
                        percentComplete: 0,
                        parentID: groupID,
                        dependencies: deps,
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
