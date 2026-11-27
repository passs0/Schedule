import SwiftUI
import ScheduleCore

struct MainWindowView: View {
    @Bindable var store: WorkspaceStore
    @State private var viewModel: ProjectViewModel?
    @State private var scrollSync = ScrollSyncState()

    @State private var dependencyTargetID: UUID?
    @State private var showingSnapshotSheet = false
    @State private var showingCalendarManager = false
    @State private var showingExportPopover = false
    @State private var showingTemplateChooser = false
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
                WelcomeView(
                    recentProjects: store.recentProjects,
                    onOpenProject: { id in
                        store.selectProject(id)
                        syncViewModel()
                    },
                    onOpenFile: {
                        handleImport()
                    },
                    onNewDocument: {
                        showingTemplateChooser = true
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WindowSizeController(isWorkspaceOpen: viewModel != nil))
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
            .sheet(isPresented: $showingTemplateChooser) {
                TemplateChooserView(
                    onSelectTemplate: { template in
                        showingTemplateChooser = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            _ = store.createNewProject(template: template)
                            syncViewModel()
                        }
                    },
                    onCancel: {
                        showingTemplateChooser = false
                    }
                )
                .frame(width: 720, height: 460)
            }
            .alert(item: $alertInfo) { info in
                Alert(
                    title: Text(info.title),
                    message: Text(info.message),
                    dismissButton: .default(Text("OK"))
                )
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
                    Image(systemName: "plus")
                        .font(.system(size: 13.5, weight: .medium))
                }
                .help("New Task")

                Button {
                    vm.addTask(after: vm.selectedTaskID, isMilestone: true)
                } label: {
                    Image(systemName: "diamond")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .help("New Milestone (⇧⌘M)")

                Button {
                    if let id = vm.selectedTaskID {
                        dependencyTargetID = id
                    }
                } label: {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .disabled(vm.selectedTaskID == nil)
                .help("Add Relationship (⌘D)")
            }

            ToolbarItem(placement: .principal) {
                Picker("View Mode", selection: Binding(
                    get: { vm.viewMode },
                    set: { newMode in
                        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                            vm.viewMode = newMode
                        }
                    }
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
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .medium))
                }
                .help("Owner Calendars & Holidays")

                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                        vm.isComparingVersions.toggle()
                    }
                } label: {
                    Image(systemName: "uiwindow.split.2x1")
                        .font(.system(size: 13, weight: .medium))
                }
                .help("Compare Project Versions in Split View")

                Button {
                    handleImport()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                }
                .help("Import Microsoft Project XML or Schedule File")

                Button {
                    showingExportPopover.toggle()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium))
                }
                .help("Export Schedule (Excel, Numbers, Microsoft Project XML)")
                .popover(isPresented: $showingExportPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Export Schedule")
                            .font(.headline)
                            .padding(.bottom, 2)
                        ForEach(ExportFormat.allCases) { format in
                            Button {
                                showingExportPopover = false
                                handleExport(format: format, viewModel: vm)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: format.systemImage)
                                        .frame(width: 20)
                                        .foregroundStyle(ScheduleTheme.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(LocalizedStringKey(format.rawValue))
                                            .font(.callout.weight(.medium))
                                        Text(LocalizedStringKey(format.subtitle))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .frame(width: 310)
                }
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        vm.isInspectorPresented.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13.5, weight: .medium))
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
                                .onHover { hovering in
                                    if hovering {
                                        NSCursor.resizeLeftRight.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
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
            .animation(.snappy(duration: 0.24, extraBounce: 0), value: vm.viewMode)
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

private struct WindowSizeController: NSViewRepresentable {
    let isWorkspaceOpen: Bool

    final class Coordinator {
        var lastState: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.lastState != isWorkspaceOpen else { return }
        context.coordinator.lastState = isWorkspaceOpen
        let open = isWorkspaceOpen

        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            if open {
                window.styleMask.insert(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = true
                window.minSize = NSSize(width: 960, height: 600)
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                window.setFrame(visible, display: true, animate: false)
                window.alphaValue = 0.88
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.16
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1.0
                }
            } else {
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                let targetW: CGFloat = 560
                let targetH: CGFloat = 480
                window.minSize = NSSize(width: targetW, height: targetH)
                window.maxSize = NSSize(width: targetW, height: targetH)
                let x = visible.midX - targetW / 2
                let y = visible.midY - targetH / 2
                window.setFrame(NSRect(x: x, y: y, width: targetW, height: targetH), display: true, animate: false)
            }
        }
    }
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
