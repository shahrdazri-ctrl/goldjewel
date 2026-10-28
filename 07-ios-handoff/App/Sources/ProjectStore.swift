import Combine
import Foundation

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

    var selectedProject: JewelryProject? {
        projects.first { $0.id == selectedID }
    }

    var documentURL: URL { fileURL }

    init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GoldJewel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? directory.appending(path: "projects.json")
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

    func save() {
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

    /// Runs the operations this shell actually implements. Every other v1
    /// operation is listed with an entry point but reports that it is pending.
    @discardableResult
    func perform(operation id: String) -> String {
        switch id {
        case "WriteJsonToDocument":
            save()
            return "Saved to \(fileURL.lastPathComponent)"
        case "ReadJsonFromDocument":
            reload()
            return statusMessage ?? "Reloaded"
        case "GetActiveDocPath":
            return fileURL.path
        case "GetCurrentFileIsModified":
            return "Autosave is on; the in-memory projects are always the saved state."
        case "SetCurrentFileAsNoModified":
            save()
            return "Marked saved"
        case "DeleteBuilder":
            if let selectedID {
                delete(selectedID)
                return "Deleted the selected project"
            }
            return "No project selected"
        case "ExecuteBuilderCommand":
            guard let project = selectedProject, let assembly = project.assembly else {
                return "The selected project does not build"
            }
            return "Rebuilt \(assembly.triangleCount.formatted()) triangles"
        case "GetRingSizeRegionAbrvs":
            return RingSizeCatalog.bundled.regions.map(\.abbreviation).joined(separator: ", ")
        case "GetRingSizesFromRegionAbrv":
            guard let project = selectedProject else { return "No project selected" }
            return "\(RingSizeCatalog.bundled.sizes(for: project.ringRegion).count) sizes in \(project.ringRegion.abbreviation)"
        case "GetDefaultRingSizeRegionAbrv":
            return JewelryProject().ringRegion.abbreviation
        case "SetDefaultRingSizeRegionAbrv":
            return "The project stores its own region; the app default is US."
        case "ResizeRing":
            return "Ring resizing geometry is not part of the head milestone; the size is stored for the shank builder."
        default:
            return "\(id) is in the v1 contract but has no implementation yet."
        }
    }

    private struct Payload: Codable {
        var projects: [JewelryProject]
        var savedAt: Date
    }
}
