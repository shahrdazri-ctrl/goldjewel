import JewelryKit
import SwiftUI

struct ProjectEditorView: View {
    @Binding var project: JewelryProject
    var onSave: () -> Void
    var onOpenOperations: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var assembly: HeadAssembly? { project.assembly }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                summary
                projectSection
                headSection
                gemAndRingSection
                gallerySection
                provenanceSection
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onOpenOperations()
                } label: {
                    Label("Operations", systemImage: "square.stack.3d.up")
                }
            }
        }
        .onChange(of: project) { _, _ in
            onSave()
        }
    }

    private var preview: some View {
        Group {
            if let assembly {
                HeadPreviewView(assembly: assembly)
                    .frame(height: horizontalSizeClass == .compact ? 300 : 420)
                    .id(previewKey)
            } else {
                ContentUnavailableView(
                    "Cannot build this head",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Check the gem and head dimensions.")
                )
                .frame(height: 260)
            }
        }
    }

    private var previewKey: String {
        "\(project.gemDiameterMM)-\(project.prongCount)-\(project.rail.enabled)-\(project.rail.position)-\(project.rail.height)"
    }

    private var summary: some View {
        HStack(spacing: 18) {
            Label("\(assembly?.triangleCount.formatted() ?? "—") triangles", systemImage: "triangle")
            Label("\(project.prongCount) prongs", systemImage: "circle.grid.2x2")
            if project.rail.enabled {
                Label("gallery rail", systemImage: "circle.dashed")
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var projectSection: some View {
        GroupBox("Project") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $project.name)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Saved documents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var headSection: some View {
        GroupBox("Head geometry") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Prongs", selection: $project.prongCount) {
                    Text("4").tag(4)
                    Text("6").tag(6)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)

                slider("Gem diameter", $project.gemDiameterMM, 4...12, step: 0.1, suffix: "mm")
                slider("Head height", $project.headHeightMM, -6...0, step: 0.1, suffix: "mm")
                slider("Prong height", $project.prongHeightMM, 0.2...4, step: 0.1, suffix: "mm")
                slider("Side angle X", $project.angleXDegrees, 0...30, step: 0.5, suffix: "°")
                slider("Side angle Y", $project.angleYDegrees, 0...30, step: 0.5, suffix: "°")
                slider("Top angle", $project.topAngleDegrees, -10...20, step: 0.5, suffix: "°")
                slider("Base angle", $project.baseAngleDegrees, -10...30, step: 0.5, suffix: "°")
                slider("Base position", $project.baseAnglePosition, 0...1, step: 0.05, suffix: "")
            }
            .padding(.top, 4)
        }
    }

    private var gemAndRingSection: some View {
        GroupBox("Gem and ring") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Metal", selection: $project.metalName) {
                    ForEach(JewelryProject.metalOptions, id: \.self) {
                        Text($0).tag($0)
                    }
                }

                Picker("Region", selection: $project.ringRegion) {
                    ForEach(RingSizeCatalog.bundled.regions, id: \.self) { region in
                        Text(region.abbreviation).tag(region)
                    }
                }
                .onChange(of: project.ringRegion) { _, region in
                    project.ringSizeName = RingSizeCatalog.bundled.sizes(for: region).first?.name ?? ""
                }

                let sizes = RingSizeCatalog.bundled.sizes(for: project.ringRegion)
                Picker("Size", selection: $project.ringSizeName) {
                    ForEach(sizes, id: \.name) { size in
                        Text(size.name).tag(size.name)
                    }
                }

                if let size = project.ringSize {
                    Text("\(size.name) · \(size.diameterMM.formatted()) mm inner diameter · \(size.circumferenceMM.formatted()) mm circumference")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var gallerySection: some View {
        GroupBox("Gallery rail") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show gallery rail", isOn: $project.rail.enabled)
                if project.rail.enabled {
                    slider("Height along rail", $project.rail.position, 0...1, step: 0.01, suffix: "")
                    slider("Width", $project.rail.width, 0.2...1.5, step: 0.05, suffix: "mm")
                    slider("Thickness", $project.rail.height, 0.1...1.2, step: 0.05, suffix: "mm")
                    slider("Gem offset", $project.rail.offset, -0.4...0.6, step: 0.05, suffix: "mm")
                }
            }
            .padding(.top, 4)
        }
    }

    private var provenanceSection: some View {
        GroupBox("Evidence") {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(HeadProvenance.all.count) IL literals traced to corpus v1")
                Text("Head and gallery placement are recovered; the prong section and rail band are stand-ins for authored profile curves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func slider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))\(suffix)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
