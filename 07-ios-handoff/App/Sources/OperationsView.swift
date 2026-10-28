import SwiftUI

/// Browses the 88 operations the capability matrix puts in v1. The list is
/// generated from `08-reports/capability-matrix.csv`; tapping an operation
/// opens its entry point, whether or not the implementation exists yet.
struct OperationsView: View {
    @ObservedObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [AppOperation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return OperationCatalog.all }
        return OperationCatalog.all.filter {
            $0.id.localizedCaseInsensitiveContains(trimmed)
                || $0.cluster.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var groups: [(String, [AppOperation])] {
        Dictionary(grouping: filtered, by: \.cluster)
            .map { ($0.key, $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(OperationCatalog.wired.count) operations are wired to this shell. The rest are registered entry points waiting for an implementation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.0) { cluster, operations in
                    Section(cluster) {
                        ForEach(operations) { operation in
                            NavigationLink(value: operation) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(operation.id)
                                            .font(.subheadline.monospaced())
                                        Text(operation.reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: operation.isWired ? "checkmark.circle.fill" : "circle.dotted")
                                        .foregroundStyle(operation.isWired ? .green : .secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("v1 operations")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Operation or cluster")
            .navigationDestination(for: AppOperation.self) { operation in
                OperationDetailView(operation: operation, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct OperationDetailView: View {
    let operation: AppOperation
    @ObservedObject var store: ProjectStore
    @State private var result: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: operation.isWired ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(operation.isWired ? .green : .secondary)
                    Text(operation.isWired ? "Wired" : "Entry point only")
                        .font(.headline)
                }

                GroupBox("Contract") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Operation", value: operation.id)
                        LabeledContent("Cluster", value: operation.cluster)
                        LabeledContent("Why v1", value: operation.reason)
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }

                if operation.isWired {
                    Button("Run operation") {
                        result = store.perform(operation: operation.id)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("The entry point is present and appears in the shell. Its geometry or data path is not part of this milestone, so running it reports that it is pending rather than pretending to succeed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let result {
                    GroupBox("Result") {
                        Text(result)
                            .font(.subheadline.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(operation.id)
        .navigationBarTitleDisplayMode(.inline)
    }
}
