import SwiftUI
import ScheduleCore

struct MainWindowView: View {
    @Bindable var store: WorkspaceStore
    @State private var viewModel: ProjectViewModel?
    @State private var scrollSync = ScrollSyncState()

    @State private var dependencyTargetID: UUID?
    @State private var showingSnapshotSheet = false
    @State private var showingCalendarManager = false
    @State private var showingTemplateChooser = false
    @State private var pendingTemplate: ProjectTemplate?
    @State private var alertInfo: AlertInfo?
    @State private var splitRatio: CGFloat = 0.50
    @State private var dragStartRatio: CGFloat?

    @Environment(\.undoManager) private var undoManager

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                splitViewContent(vm: vm)
                    .frame(minWidth: 960, minHeight: 600)
            } else {
                ContentUnavailableView {
                    Label("No Project Open", systemImage: "calendar.day.timeline.leading")
                } description: {
                    Text("Create a new project or open an existing schedule file.")
                } actions: {
                    Button("Open File…") {
                        handleImport()
                    }
                    Button("New Project…") {
                        showingTemplateChooser = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(minWidth: 960, minHeight: 600)
            }
        }
        .onAppear {
            syncViewModel()
        }
            .onChange(of: store.selectedProjectID) { _, _ in
                syncViewModel()
            }
            .onChange(of: undoManager) { _, newUndo in
                viewModel?.undoManager = newUndo
            }
            .onChange(of: viewModel?.cycleWarningMessage) { _, msg in
                if let msg {
                    alertInfo = AlertInfo(title: "Circular Dependency", message: msg)
                    viewModel?.cycleWarningMessage = nil
                }
            }
            .modifier(MenuNotificationModifier(
                onNewProject: { showingTemplateChooser = true },
                onSave: { handleSave(saveAs: false) },
                onSaveAs: { handleSave(saveAs: true) },
                onOpen: { handleImport() },
                onNewTask: { viewModel?.addTask(after: viewModel?.selectedTaskID, isMilestone: false) },
                onNewMilestone: { viewModel?.addTask(after: viewModel?.selectedTaskID, isMilestone: true) },
                onIndent: { if let id = viewModel?.selectedTaskID { viewModel?.indentTask(id) } },
                onOutdent: { if let id = viewModel?.selectedTaskID { viewModel?.outdentTask(id) } },
                onLinkPrevious: { if let id = viewModel?.selectedTaskID { viewModel?.linkToPreviousTask(id) } },
                onAddDependency: { if let id = viewModel?.selectedTaskID { dependencyTargetID = id } },
                onToggleInspector: { viewModel?.isInspectorPresented.toggle() }
            ))
            .sheet(item: Binding(
                get: { dependencyTargetID.map { IdentifiableUUID(id: $0) } },
                set: { dependencyTargetID = $0?.id }
            )) { item in
                if let vm = viewModel {
                    DependencyEditorSheet(viewModel: vm, targetTaskID: item.id)
                }
            }
            .sheet(isPresented: $showingSnapshotSheet) {
                if let vm = viewModel {
                    SnapshotSheet(viewModel: vm)
                }
            }
            .sheet(isPresented: $showingCalendarManager) {
                if let vm = viewModel {
                    CalendarManagerSheet(viewModel: vm)
                }
            }
            .sheet(isPresented: $showingTemplateChooser, onDismiss: {
                if let template = pendingTemplate {
                    pendingTemplate = nil
                    _ = store.createNewProject(template: template)
                    syncViewModel()
                }
            }) {
                TemplateChooserView(
                    onSelectTemplate: { template in
                        pendingTemplate = template
                        showingTemplateChooser = false
                    },
                    onCancel: {
                        pendingTemplate = nil
                        showingTemplateChooser = false
                    }
                )
                .frame(width: 720, height: 460)
            }
            .alert(
                alertInfo?.title ?? "",
                isPresented: Binding(
                    get: { alertInfo != nil },
                    set: { if !$0 { alertInfo = nil } }
                ),
                presenting: alertInfo
            ) { _ in
                Button("OK", role: .cancel) {
                    alertInfo = nil
                }
            } message: { info in
                Text(info.message)
            }
    }

    @ViewBuilder
    private func splitViewContent(vm: ProjectViewModel) -> some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                viewModel: vm,
                onNewProject: {
                    showingTemplateChooser = true
                },
                onSaveSnapshot: {
                    showingSnapshotSheet = true
                },
                onCompareVersion: { _ in
                    vm.isComparingVersions = true
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 290)
        } detail: {
            detailContent(vm: vm)
        }
    }

    @ViewBuilder
    private func detailContent(vm: ProjectViewModel) -> some View {
        Group {
            if vm.isComparingVersions {
                VersionComparisonView(viewModel: vm)
            } else {
                mainWorkspace(vm: vm)
            }
        }
        .navigationTitle(vm.document.name)
        .navigationSubtitle("\(vm.document.tasks.count) items")
        .searchable(
            text: Binding(
                get: { vm.searchText },
                set: { vm.searchText = $0 }
            ),
            placement: .toolbar,
            prompt: "Filter tasks"
        )
        .inspector(isPresented: Binding(
            get: { vm.isInspectorPresented && !vm.isComparingVersions },
            set: { vm.isInspectorPresented = $0 }
        )) {
            TaskInspectorView(viewModel: vm) { taskID in
                dependencyTargetID = taskID
            }
            .inspectorColumnWidth(min: 270, ideal: 300, max: 360)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    vm.addTask(after: vm.selectedTaskID, isMilestone: false)
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .help("New Task")

                Button {
                    vm.addTask(after: vm.selectedTaskID, isMilestone: true)
                } label: {
                    Label("New Milestone", systemImage: "diamond")
                }
                .help("New Milestone (⇧⌘M)")

                Button {
                    if let id = vm.selectedTaskID {
                        dependencyTargetID = id
                    }
                } label: {
                    Label("Add Relationship", systemImage: "link.badge.plus")
                }
                .disabled(vm.selectedTaskID == nil)
                .help("Add Relationship (⌘D)")
            }

            ToolbarItem(placement: .principal) {
                Picker("View Mode", selection: Binding(
                    get: { vm.viewMode },
                    set: { vm.viewMode = $0 }
                )) {
                    ForEach(WorkspaceViewMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Switch between Split, List, or Gantt view")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingCalendarManager = true
                } label: {
                    Label("Calendars", systemImage: "calendar")
                }
                .help("Owner Calendars & Holidays")

                Button {
                    vm.isComparingVersions.toggle()
                } label: {
                    Label("Compare Versions", systemImage: "uiwindow.split.2x1")
                }
                .help("Compare Project Versions in Split View")

                Button {
                    handleImport()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import Microsoft Project XML or Schedule File")

                Button {
                    ExportMenuPresenter.show { format in
                        handleExport(format: format, viewModel: vm)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export Schedule (Excel, Numbers, Microsoft Project XML)")
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle Inspector (⌘I)")
            }
        }
    }

    @ViewBuilder
    private func mainWorkspace(vm: ProjectViewModel) -> some View {
        GeometryReader { geo in
            let totalWidth = max(1, geo.size.width)
            let clampedListWidth = min(max(340, totalWidth * splitRatio), max(340, totalWidth - 380))
            let dividerWidth: CGFloat = vm.viewMode == .split ? 1 : 0
            let listWidth: CGFloat = {
                switch vm.viewMode {
                case .listOnly: return totalWidth
                case .split: return clampedListWidth
                case .ganttOnly: return 0
                }
            }()
            let ganttWidth: CGFloat = {
                switch vm.viewMode {
                case .listOnly: return 0
                case .split: return max(380, totalWidth - clampedListWidth - dividerWidth)
                case .ganttOnly: return totalWidth
                }
            }()

            HStack(spacing: 0) {
                TaskListView(
                    viewModel: vm,
                    scrollSync: scrollSync,
                    onAddDependency: { dependencyTargetID = $0 }
                )
                .frame(width: listWidth)
                .clipped()
                .opacity(vm.viewMode == .ganttOnly ? 0 : 1)
                .allowsHitTesting(vm.viewMode != .ganttOnly)

                if vm.viewMode == .split {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                        .overlay {
                            Color.clear
                                .frame(width: 8)
                                .contentShape(Rectangle())
                                .pointerStyle(.columnResize)
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { value in
                                            let base = dragStartRatio ?? splitRatio
                                            if dragStartRatio == nil { dragStartRatio = base }
                                            let nextRatio = base + (value.translation.width / totalWidth)
                                            let minRatio = 340 / totalWidth
                                            let maxRatio = max(minRatio, (totalWidth - 380) / totalWidth)
                                            splitRatio = min(max(nextRatio, minRatio), maxRatio)
                                        }
                                        .onEnded { _ in
                                            dragStartRatio = nil
                                        }
                                )
                        }
                }

                GanttChartView(
                    viewModel: vm,
                    scrollSync: scrollSync
                )
                .frame(width: ganttWidth)
                .clipped()
                .opacity(vm.viewMode == .listOnly ? 0 : 1)
                .allowsHitTesting(vm.viewMode != .listOnly)
            }
        }
    }

    private func syncViewModel() {
        if let doc = store.currentProject {
            if viewModel?.document.id != doc.id {
                if let oldVM = viewModel {
                    undoManager?.removeAllActions(withTarget: oldVM)
                }
                let vm = ProjectViewModel(document: doc) { updated in
                    store.updateProject(updated)
                }
                vm.undoManager = undoManager
                viewModel = vm
                scrollSync.reset()
            }
        } else {
            if let oldVM = viewModel {
                undoManager?.removeAllActions(withTarget: oldVM)
            }
            viewModel = nil
        }
    }

    private func handleImport() {
        guard let result = FileDialogs.importProject() else { return }
        switch result {
        case .success(let doc):
            store.importProject(doc)
            syncViewModel()
        case .failure(let error):
            let nsErr = error as NSError
            let msg = [error.localizedDescription, nsErr.localizedRecoverySuggestion]
                .compactMap { $0 }
                .joined(separator: "\n\n")
            alertInfo = AlertInfo(title: "Import Notice", message: msg)
        }
    }

    private func handleSave(saveAs: Bool) {
        guard let vm = viewModel else { return }
        let existing = saveAs ? nil : store.linkedFileURLs[vm.document.id]
        let result = FileDialogs.saveScheduleDocument(vm.document, existingURL: existing)
        if let url = result.url {
            store.linkedFileURLs[vm.document.id] = url
        } else if let error = result.error {
            alertInfo = AlertInfo(title: "Save Failed", message: error)
        }
    }

    private func handleExport(format: ExportFormat, viewModel: ProjectViewModel) {
        let outcome = FileDialogs.exportProject(viewModel, format: format)
        if !outcome.success, let message = outcome.message {
            alertInfo = AlertInfo(title: "Export Notice", message: message)
        }
    }
}

extension Notification.Name {
    static let scheduleNewProject = Notification.Name("scheduleNewProject")
    static let scheduleSaveDocument = Notification.Name("scheduleSaveDocument")
    static let scheduleSaveDocumentAs = Notification.Name("scheduleSaveDocumentAs")
    static let scheduleOpenDocument = Notification.Name("scheduleOpenDocument")
    static let scheduleNewTask = Notification.Name("scheduleNewTask")
    static let scheduleNewMilestone = Notification.Name("scheduleNewMilestone")
    static let scheduleIndentTask = Notification.Name("scheduleIndentTask")
    static let scheduleOutdentTask = Notification.Name("scheduleOutdentTask")
    static let scheduleLinkPrevious = Notification.Name("scheduleLinkPrevious")
    static let scheduleAddDependency = Notification.Name("scheduleAddDependency")
    static let scheduleToggleInspector = Notification.Name("scheduleToggleInspector")
}

private struct IdentifiableUUID: Identifiable {
    let id: UUID
}

private struct MenuNotificationModifier: ViewModifier {
    let onNewProject: () -> Void
    let onSave: () -> Void
    let onSaveAs: () -> Void
    let onOpen: () -> Void
    let onNewTask: () -> Void
    let onNewMilestone: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onLinkPrevious: () -> Void
    let onAddDependency: () -> Void
    let onToggleInspector: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .scheduleNewProject)) { _ in onNewProject() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleSaveDocument)) { _ in onSave() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleSaveDocumentAs)) { _ in onSaveAs() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleOpenDocument)) { _ in onOpen() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleNewTask)) { _ in onNewTask() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleNewMilestone)) { _ in onNewMilestone() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleIndentTask)) { _ in onIndent() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleOutdentTask)) { _ in onOutdent() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleLinkPrevious)) { _ in onLinkPrevious() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleAddDependency)) { _ in onAddDependency() }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleToggleInspector)) { _ in onToggleInspector() }
    }
}
