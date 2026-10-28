import Combine
import Foundation
import JewelryKit

/// Loads and autosaves the project list. The desktop product persists designs
/// as JSON in the document; this shell uses the same idea in Application
/// Support so the app has real documents rather than view-only state.
@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [JewelryProject]
    @Published var selectedID: UUID?
    @Published private(set) var lastSaved: Date?
    @Published private(set) var statusMessage: String?

    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?

    var selectedProject: JewelryProject? {
        projects.first { $0.id == selectedID }
    }

    var documentURL: URL { fileURL }

    init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GoldJewel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? directory.appending(path: "projects.json")
        // Runtime tests start from a clean document. This is a launch-argument
        // switch so it cannot be triggered by normal app usage.
        if ProcessInfo.processInfo.arguments.contains("-reset-projects") {
            try? FileManager.default.removeItem(at: self.fileURL)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if
            let data = try? Data(contentsOf: self.fileURL),
            let decoded = try? decoder.decode(Payload.self, from: data),
            !decoded.projects.isEmpty
        {
            self.projects = decoded.projects
            self.selectedID = decoded.projects.first?.id
            self.lastSaved = decoded.savedAt
        } else {
            let first = JewelryProject()
            self.projects = [first]
            self.selectedID = first.id
        }
    }

    func index(of id: UUID) -> Int? {
        projects.firstIndex { $0.id == id }
    }

    func update(_ id: UUID, _ mutate: (inout JewelryProject) -> Void) {
        guard let index = index(of: id) else { return }
        mutate(&projects[index])
        projects[index].updatedAt = Date()
        save()
    }

    func addProject() {
        let next = JewelryProject(name: "Solitaire \(projects.count + 1)")
        projects.append(next)
        selectedID = next.id
        save()
    }

    func delete(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if projects.isEmpty {
            let replacement = JewelryProject()
            projects = [replacement]
            selectedID = replacement.id
        } else if selectedID == id {
            selectedID = projects.first?.id
        }
        save()
    }

    /// Coalesces the saves triggered by typing and slider drags. Writing on
    /// every keystroke published `lastSaved` mid-edit, which re-rendered the
    /// split view and could drop the name field's focus mid-word.
    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Writes any coalesced change before the app leaves the foreground.
    func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        write()
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        write()
    }

    private func write() {
        do {
            let payload = Payload(projects: projects, savedAt: Date())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(payload).write(to: fileURL, options: .atomic)
            lastSaved = Date()
        } catch {
            statusMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    func clearStatus() {
        statusMessage = nil
    }

    func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(Payload.self, from: data)
            projects = payload.projects
            selectedID = payload.projects.first?.id
            lastSaved = payload.savedAt
            statusMessage = "Reloaded \(payload.projects.count) project(s)"
        } catch {
            statusMessage = "Could not reload: \(error.localizedDescription)"
        }
    }

    /// Runs the operations this shell actually implements. The wired set is
    /// generated from `Tools/operation_catalog.py`; switching on the generated
    /// enum makes a newly wired operation a compile error until it has a case.
    @discardableResult
    func perform(operation id: String) -> String {
        guard let operation = WiredOperation(rawValue: id) else {
            return "\(id) is in the v1 contract but has no implementation yet."
        }
        return perform(operation)
    }

    private func perform(_ operation: WiredOperation) -> String {
        switch operation {
        case .writeJsonToDocument:
            save()
            return "Saved to \(fileURL.lastPathComponent)"
        case .readJsonFromDocument:
            reload()
            return statusMessage ?? "Reloaded"
        case .getActiveDocPath:
            return fileURL.path
        case .getCurrentFileIsModified:
            return "Autosave is on; the in-memory projects are always the saved state."
        case .setCurrentFileAsNoModified:
            save()
            return "Marked saved"
        case .deleteBuilder:
            if let selectedID {
                delete(selectedID)
                return "Deleted the selected project"
            }
            return "No project selected"
        case .executeBuilderCommand:
            guard let project = selectedProject, let assembly = project.assembly else {
                return "The selected project does not build"
            }
            return "Rebuilt \(assembly.triangleCount.formatted()) triangles across \(assembly.partTiers.count) graded families"
        case .getActiveBuilderId:
            return selectedID?.uuidString ?? "No active builder"
        case .getAllBuilderGuids:
            return projects.map(\.id.uuidString).joined(separator: ", ")
        case .getRingSizeRegionAbrvs:
            return RingSizeCatalog.bundled.regions.map(\.abbreviation).joined(separator: ", ")
        case .getRingSizesFromRegionAbrv:
            guard let project = selectedProject else { return "No project selected" }
            return "\(RingSizeCatalog.bundled.sizes(for: project.ringRegion).count) sizes in \(project.ringRegion.abbreviation)"
        case .getDefaultRingSizeRegionAbrv:
            return JewelryProject().ringRegion.abbreviation
        }
    }

    private struct Payload: Codable {
        var projects: [JewelryProject]
        var savedAt: Date
    }
}
