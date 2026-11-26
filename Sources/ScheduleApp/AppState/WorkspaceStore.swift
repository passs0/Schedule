import Foundation
import ScheduleCore

/// Manages local-first storage of `.schedule` project files in Application Support,
/// plus opening/saving external `.schedule` files on disk.
@MainActor
@Observable
public final class WorkspaceStore {
    public var projects: [ProjectDocument] = []
    public var recentProjectIDs: [UUID] = []
    public var selectedProjectID: UUID?
    public var linkedFileURLs: [UUID: URL] = [:]

    private let projectsDirectory: URL
    private let metadataURL: URL

    private struct StoreMetadata: Codable {
        var recentIDs: [UUID]
        var lastSelectedID: UUID?
    }

    public init(baseDirectory: URL? = nil) {
        let appSupport = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("Schedule", isDirectory: true)
        self.projectsDirectory = root.appendingPathComponent("Projects", isDirectory: true)
        self.metadataURL = root.appendingPathComponent("workspace.json")

        try? FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        loadAll()
    }

    public var currentProject: ProjectDocument? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    public var favoriteProjects: [ProjectDocument] {
        projects.filter(\.isFavorite)
    }

    public var recentProjects: [ProjectDocument] {
        let map = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let ordered = recentProjectIDs.compactMap { map[$0] }
        if !ordered.isEmpty { return ordered }
        return projects.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func loadAll() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [ProjectDocument] = []
        for url in files where url.pathExtension == "schedule" {
            if let data = try? Data(contentsOf: url),
               let doc = try? ProjectDocument.decodeJSON(from: data) {
                loaded.append(doc)
            }
        }

        if loaded.isEmpty {
            let sample = ProjectDocument.sampleProject()
            loaded = [sample]
            saveToDisk(sample)
        }

        projects = loaded.sorted { $0.modifiedAt > $1.modifiedAt }

        if let metaData = try? Data(contentsOf: metadataURL),
           let meta = try? JSONDecoder().decode(StoreMetadata.self, from: metaData) {
            recentProjectIDs = meta.recentIDs
            if let lastID = meta.lastSelectedID, projects.contains(where: { $0.id == lastID }) {
                selectedProjectIDsUpdate(lastID)
                return
            }
        }
        if let first = projects.first {
            selectedProjectIDsUpdate(first.id)
        }
    }

    public func selectProject(_ id: UUID) {
        selectedProjectIDsUpdate(id)
        saveMetadata()
    }

    public func createNewProject(template: ProjectTemplate) -> ProjectDocument {
        let doc = template.makeDocument()
        projects.insert(doc, at: 0)
        selectedProjectIDsUpdate(doc.id)
        saveToDisk(doc)
        saveMetadata()
        return doc
    }

    public func createNewProject(name: String = "Untitled Project") -> ProjectDocument {
        let doc = ProjectDocument(
            name: name,
            tasks: [
                ScheduleTask(identifier: "1", title: "Kickoff", startDate: .today, durationDays: 2)
            ]
        )
        projects.insert(doc, at: 0)
        selectedProjectIDsUpdate(doc.id)
        saveToDisk(doc)
        saveMetadata()
        return doc
    }

    public func importProject(_ doc: ProjectDocument) {
        var copy = doc
        copy.modifiedAt = Date()
        if let idx = projects.firstIndex(where: { $0.id == copy.id }) {
            projects[idx] = copy
        } else {
            projects.insert(copy, at: 0)
        }
        selectedProjectIDsUpdate(copy.id)
        saveToDisk(copy)
        saveMetadata()
    }

    public func updateProject(_ doc: ProjectDocument) {
        var updated = doc
        updated.modifiedAt = Date()
        if let idx = projects.firstIndex(where: { $0.id == updated.id }) {
            projects[idx] = updated
        } else {
            projects.insert(updated, at: 0)
        }
        saveToDisk(updated)
    }

    public func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        recentProjectIDs.removeAll { $0 == id }
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id
        }
        saveMetadata()
    }

    public func toggleFavorite(_ id: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].isFavorite.toggle()
        saveToDisk(projects[idx])
    }

    private func selectedProjectIDsUpdate(_ id: UUID) {
        selectedProjectID = id
        recentProjectIDs.removeAll { $0 == id }
        recentProjectIDs.insert(id, at: 0)
        if recentProjectIDs.count > 10 {
            recentProjectIDs = Array(recentProjectIDs.prefix(10))
        }
    }

    private func fileURL(for id: UUID) -> URL {
        projectsDirectory.appendingPathComponent("\(id.uuidString).schedule")
    }

    private func saveToDisk(_ doc: ProjectDocument) {
        if let data = try? doc.encodeJSON() {
            try? data.write(to: fileURL(for: doc.id), options: .atomic)
            if let linkedURL = linkedFileURLs[doc.id] {
                try? data.write(to: linkedURL, options: .atomic)
            }
        }
    }

    private func saveMetadata() {
        let meta = StoreMetadata(recentIDs: recentProjectIDs, lastSelectedID: selectedProjectID)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }
}
