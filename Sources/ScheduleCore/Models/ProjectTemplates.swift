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
            return "Architecture, backend & frontend sprints, QA, security, and release."
        case .electronicsManufacturing:
            return "Schematic & PCB layout through EVT, DVT compliance, PVT, and MP ramp."
        case .siliconTapeOut:
            return "RTL freeze, verification, physical synthesis, timing closure, and foundry."
        case .embeddedFirmware:
            return "BSP & bootloader, peripheral drivers, OTA, power profiling, and field trial."
        case .cloudMigration:
            return "Landing zone, IAM & data replication, load testing, and cutover."
        case .roboticsIntegration:
            return "Mechanical CAD, control electronics, sensor fusion, and burn-in."
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
            return doc

        case .softwareDevelopment:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                ("Discovery & Architecture", "Requirements, API contracts, and system design.", [
                    ("Product Spec & Scope Freeze", 4, 100, false),
                    ("System Architecture & API Contracts", 5, 60, false),
                    ("Architecture Sign-Off", 0, 0, true)
                ]),
                ("Core Engineering", "Backend services, client UI, and integrations.", [
                    ("Backend Services & Data Layer", 10, 0, false),
                    ("Client UI & State Management", 10, 0, false),
                    ("Auth, Telemetry & Integrations", 5, 0, false),
                    ("Feature Complete", 0, 0, true)
                ]),
                ("Verification & Release", "QA regression, security review, and staged rollout.", [
                    ("Integration & Regression QA", 5, 0, false),
                    ("Security & Performance Audit", 3, 0, false),
                    ("Production Rollout", 0, 0, true)
                ])
            ])

        case .electronicsManufacturing:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                ("Schematic & PCB Layout", "EE design, component selection, and fab release.", [
                    ("Schematic Capture & BOM Lock", 6, 100, false),
                    ("Multi-Layer PCB Layout & DFM", 8, 40, false),
                    ("Gerber Release to Fab", 0, 0, true)
                ]),
                ("EVT (Engineering Validation)", "PCBA bring-up, rework, and functional validation.", [
                    ("Bare Board Fab & SMT Assembly", 10, 0, false),
                    ("Board Bring-Up & Power Rail Tests", 5, 0, false),
                    ("EVT Exit Review", 0, 0, true)
                ]),
                ("DVT (Design Validation)", "Enclosure tooling, environmental stress, and compliance.", [
                    ("Hard Tooling & Mechanical Fit", 10, 0, false),
                    ("FCC / CE / UL Pre-Compliance & EMC", 7, 0, false),
                    ("DVT Sign-Off", 0, 0, true)
                ]),
                ("PVT & Mass Production", "Pilot line qualification and MP ramp.", [
                    ("PVT Pilot Run & Yield Audit", 6, 0, false),
                    ("ATE Test Fixture Calibration", 4, 0, false),
                    ("Mass Production Ramp", 0, 0, true)
                ])
            ])

        case .siliconTapeOut:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                ("RTL Design & Microarchitecture", "Block specs, RTL coding, and lint.", [
                    ("Microarchitecture Spec", 6, 100, false),
                    ("RTL Implementation & CDC Checks", 12, 50, false),
                    ("RTL Freeze", 0, 0, true)
                ]),
                ("Verification & Synthesis", "UVM regression, formal verification, and gate-level sim.", [
                    ("UVM Functional Verification", 12, 0, false),
                    ("Logic Synthesis & DFT Insertion", 6, 0, false),
                    ("Netlist Handoff", 0, 0, true)
                ]),
                ("Physical Design & Tape-Out", "Place & route, STA timing closure, and DRC/LVS.", [
                    ("Floorplan, Place & Route", 10, 0, false),
                    ("Static Timing Analysis & DRC/LVS", 6, 0, false),
                    ("GDSII Tape-Out", 0, 0, true)
                ]),
                ("Silicon Bring-Up", "Foundry shuttle, ATE patterns, and lab characterization.", [
                    ("Wafer Fab & Packaging", 15, 0, false),
                    ("Bench Bring-Up & Shmoo Testing", 8, 0, false),
                    ("Engineering Samples Ready", 0, 0, true)
                ])
            ])

        case .embeddedFirmware:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                ("BSP & Bootloader", "Board bring-up, secure boot, and RTOS configuration.", [
                    ("Toolchain & RTOS Bring-Up", 4, 100, false),
                    ("Secure Bootloader & Partitioning", 5, 30, false),
                    ("BSP Milestone", 0, 0, true)
                ]),
                ("Drivers & Connectivity", "Sensor drivers, BLE/Wi-Fi stack, and OTA updates.", [
                    ("Peripheral & Sensor Drivers", 8, 0, false),
                    ("Wireless Stack & Cloud Telemetry", 7, 0, false),
                    ("Signed OTA Update Pipeline", 5, 0, false)
                ]),
                ("Profiling & Field Trial", "Battery/thermal tuning and soak testing.", [
                    ("Power & Thermal Profiling", 5, 0, false),
                    ("72-Hour Soak & Field Trial", 6, 0, false),
                    ("Production Firmware Freeze", 0, 0, true)
                ])
            ])

        case .cloudMigration:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                ("Assessment & Landing Zone", "Dependency mapping, Terraform VPC, and IAM.", [
                    ("Workload & Dependency Audit", 4, 100, false),
                    ("IaC Landing Zone & Network Peering", 6, 50, false),
                    ("Landing Zone Ready", 0, 0, true)
                ]),
                ("Data & Service Migration", "Database replication, containerization, and secrets.", [
                    ("Database Schema & CDC Replication", 8, 0, false),
                    ("Service Containerization & CI/CD", 7, 0, false),
                    ("Dry-Run Cutover & Load Test", 4, 0, false)
                ]),
                ("Cutover & Hardening", "DNS switch, monitoring, and legacy decommission.", [
                    ("Production Cutover Window", 2, 0, false),
                    ("48-Hour Hypercare & SLO Check", 3, 0, false),
                    ("Migration Complete", 0, 0, true)
                ])
            ])

        case .roboticsIntegration:
            return buildTemplate(name: title, start: start, cal: cal, phases: [
                ("Mechanical & Actuation", "CAD assemblies, machining, and drive train.", [
                    ("CAD Assembly & Tolerance Stack", 7, 80, false),
                    ("CNC Parts & Actuator Procurement", 10, 0, false),
                    ("Mechanical Subassembly", 0, 0, true)
                ]),
                ("Electronics & Control", "Motor drivers, safety E-stop, and wiring harness.", [
                    ("Control Harness & Safety Interlocks", 6, 0, false),
                    ("Motion Control & Kinematics Tuning", 8, 0, false),
                    ("Sensor Fusion & Calibration", 6, 0, false)
                ]),
                ("Burn-In & Acceptance", "Cycle testing and factory acceptance.", [
                    ("Continuous Cycle Burn-In", 7, 0, false),
                    ("Factory Acceptance Test (FAT)", 0, 0, true)
                ])
            ])
        }
    }

    private func buildTemplate(
        name: String,
        start: CalendarDay,
        cal: WorkingCalendar,
        phases: [(title: String, notes: String, tasks: [(title: String, duration: Int, progress: Double, isMilestone: Bool)])]
    ) -> ProjectDocument {
        var allTasks: [ScheduleTask] = []
        var previousTailID: UUID?

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
                let taskID = UUID()
                let deps: [TaskDependency] = previousTailID.map {
                    [TaskDependency(predecessorID: $0, type: .finishToStart, lagDays: 0)]
                } ?? []
                allTasks.append(
                    ScheduleTask(
                        id: taskID,
                        identifier: "\(pIndex + 1).\(tIndex + 1)",
                        title: item.title,
                        startDate: start,
                        durationDays: item.isMilestone ? 0 : item.duration,
                        isMilestone: item.isMilestone,
                        percentComplete: item.progress,
                        parentID: groupID,
                        dependencies: deps,
                        calendar: cal
                    )
                )
                previousTailID = taskID
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
