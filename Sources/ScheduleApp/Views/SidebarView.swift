import SwiftUI
import ScheduleCore

private enum SidebarRowTag: Hashable {
    case favorite(UUID)
    case all(UUID)
    case recent(UUID)

    var projectID: UUID {
        switch self {
        case .favorite(let id), .all(let id), .recent(let id):
            return id
        }
    }
}

struct SidebarView: View {
    @Bindable var store: WorkspaceStore
    var viewModel: ProjectViewModel?
    let onNewProject: () -> Void
    let onSaveSnapshot: () -> Void
    let onCompareVersion: (ProjectVersion) -> Void

    @State private var selectedTag: SidebarRowTag?

    var body: some View {
        List(selection: $selectedTag) {
            if !store.favoriteProjects.isEmpty {
                Section("Favorites") {
                    ForEach(store.favoriteProjects) { project in
                        let tag = SidebarRowTag.favorite(project.id)
                        projectRow(project, tag: tag)
                            .tag(tag)
                    }
                }
            }

            Section("All Projects") {
                ForEach(store.projects) { project in
                    let tag = SidebarRowTag.all(project.id)
                    projectRow(project, tag: tag)
                        .tag(tag)
                }
            }

            if store.recentProjects.count > 1 {
                Section("Recent") {
                    ForEach(store.recentProjects.prefix(5)) { project in
                        let tag = SidebarRowTag.recent(project.id)
                        Label(project.name, systemImage: "clock")
                            .tag(tag)
                    }
                }
            }

            if let doc = viewModel?.document {
                Section("Project Versions") {
                    ForEach(doc.versions) { version in
                        Button {
                            onCompareVersion(version)
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(version.name)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                    Text(version.createdAt, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Compare current schedule against \"\(version.name)\"")
                    }

                    Button(action: onSaveSnapshot) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                            Text("Save Snapshot…")
                        }
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Schedule")
        .onAppear {
            if selectedTag == nil, let id = store.selectedProjectID {
                selectedTag = .all(id)
            }
        }
        .onChange(of: selectedTag) { _, newTag in
            if let newTag, store.selectedProjectID != newTag.projectID {
                store.selectProject(newTag.projectID)
            }
        }
        .onChange(of: store.selectedProjectID) { _, newID in
            if let newID, selectedTag?.projectID != newID {
                selectedTag = .all(newID)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNewProject) {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
                .help("New Project (⌘N)")
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: ProjectDocument, tag: SidebarRowTag) -> some View {
        let isSelected = selectedTag == tag

        HStack(spacing: 6) {
            Label {
                Text(project.name)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "calendar.day.timeline.leading")
                    .foregroundStyle(isSelected ? .white : .secondary)
            }

            Spacer(minLength: 4)

            Text("\(project.tasks.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary.opacity(0.6))
        }
        .contextMenu {
            Button(project.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(project.id)
            }
            Divider()
            Button("Delete Project", role: .destructive) {
                store.deleteProject(project.id)
            }
        }
    }
}
