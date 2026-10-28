import JewelryKit
import SwiftUI

@main
struct GoldJewelApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}

struct RootView: View {
    @ObservedObject var store: ProjectStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showOperations = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectListView(store: store)
                .navigationTitle("Projects")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            store.addProject()
                        } label: {
                            Label("New project", systemImage: "plus")
                        }
                        .accessibilityIdentifier("new-project")
                    }
                }
        } detail: {
            if let id = store.selectedID, let index = store.index(of: id) {
                ProjectEditorView(
                    project: $store.projects[index],
                    onSave: { store.scheduleSave() },
                    onOpenOperations: { showOperations = true }
                )
            } else {
                ContentUnavailableView(
                    "No project selected",
                    systemImage: "diamond",
                    description: Text("Choose a project or create one.")
                )
            }
        }
        .sheet(isPresented: $showOperations) {
            OperationsView(store: store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.flushPendingSave()
            }
        }
        .alert(
            "GoldJewel",
            isPresented: Binding(
                get: { store.statusMessage != nil },
                set: { if !$0 { store.clearStatus() } }
            )
        ) {
            Button("OK") { store.clearStatus() }
        } message: {
            Text(store.statusMessage ?? "")
        }
    }
}

struct ProjectListView: View {
    @ObservedObject var store: ProjectStore

    var body: some View {
        List(selection: $store.selectedID) {
            ForEach(store.projects) { project in
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.headline)
                    Text("\(project.gemDiameterMM.formatted()) mm · \(project.prongCount) prongs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("project-row")
                .accessibilityValue(project.id.uuidString)
                .tag(project.id)
                .swipeActions {
                    Button(role: .destructive) {
                        store.delete(project.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Text("\(OperationCatalog.all.count) v1 operations · \(OperationCatalog.wired.count) wired")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(store.lastSaved.map { "Saved \($0.formatted(date: .omitted, time: .shortened))" }
                     ?? "Autosaved")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}
