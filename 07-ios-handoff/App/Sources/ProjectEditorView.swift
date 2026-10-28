import JewelryKit
import SwiftUI

struct ProjectEditorView: View {
    @Binding var project: JewelryProject
    var onSave: () -> Void
    var onOpenOperations: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var nameFieldFocused: Bool

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
                bezelSection
                haloSection
                provenanceSection
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(18)
        }
        // The fill belongs on the scroll view, not its content: inside the
        // scroll view it can resolve against the content's ideal width and let
        // the editor overflow a narrow detail column on iPad.
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("editor-scroll")
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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameFieldFocused = false }
                    .accessibilityIdentifier("dismiss-keyboard")
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
        let railOn: Double = project.rail.enabled ? 1 : 0
        let domeOn: Double = project.dome.enabled ? 1 : 0
        let bezelHeight: Double = project.bezel?.seatHeight ?? 0
        let bezelLength: Double = project.bezel?.seatLength ?? 0
        let bezelAngle: Double = project.bezel?.seatAngle ?? 0
        let haloDiameter: Double = project.halo?.gemDiameter ?? 0
        let haloSpacing: Double = project.halo?.spacing ?? 0
        let haloOffset: Double = project.halo?.offsetRailX ?? 0
        let haloZ: Double = project.halo?.offsetRailZ ?? 0
        let haloPhase: Double = project.halo?.fixPosition ?? 0
        let values: [Double] = [
            project.gemDiameterMM, Double(project.prongCount), railOn,
            project.rail.position, project.rail.height, domeOn, project.dome.height,
            bezelHeight, bezelLength, bezelAngle,
            haloDiameter, haloSpacing, haloOffset, haloZ, haloPhase
        ]
        return values.map { value in
            value.formatted(.number.precision(.fractionLength(4)))
        }.joined(separator: "-")
    }

    private var summary: some View {
        HStack(spacing: 18) {
            Label("\(assembly?.triangleCount.formatted() ?? "—") triangles", systemImage: "triangle")
            Label("\(project.prongCount) prongs", systemImage: "circle.grid.2x2")
            if project.rail.enabled {
                Label("gallery rail", systemImage: "circle.dashed")
            }
            if project.dome.enabled {
                Label("dome caps", systemImage: "circle.top")
            }
            if project.bezel != nil {
                Label("bezel", systemImage: "circle.circle")
            }
            if project.halo != nil {
                Label("halo", systemImage: "circle.grid.3x3")
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
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFieldFocused = false }
                    .accessibilityIdentifier("project-name")
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

                slider("Gem diameter", $project.gemDiameterMM, 4...12, step: 0.1, suffix: "mm",
                       identifier: "gem-diameter")
                slider("Head height", $project.headHeightMM, -6...0, step: 0.1, suffix: "mm")
                slider("Prong height", $project.prongHeightMM, 0.2...4, step: 0.1, suffix: "mm")
                slider("Side angle X", $project.angleXDegrees, 0...30, step: 0.5, suffix: "°")
                slider("Side angle Y", $project.angleYDegrees, 0...30, step: 0.5, suffix: "°")
                slider("Top angle", $project.topAngleDegrees, -10...20, step: 0.5, suffix: "°")
                slider("Base angle", $project.baseAngleDegrees, -10...30, step: 0.5, suffix: "°")
                slider("Base position", $project.baseAnglePosition, 0...1, step: 0.05, suffix: "")

                Divider()
                Toggle("Prong dome caps", isOn: $project.dome.enabled)
                    .accessibilityIdentifier("dome-toggle")
                if project.dome.enabled {
                    slider("Dome height", $project.dome.height, 0.1...2, step: 0.05, suffix: "mm",
                           identifier: "dome-height")
                    slider("Dome setting distance", $project.dome.settingDistance, -1...1, step: 0.05, suffix: "mm")
                    slider("Dome setting angle", $project.dome.settingAngle, -30...30, step: 1, suffix: "°")
                }
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
                    .accessibilityIdentifier("rail-toggle")
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

    private var bezelSection: some View {
        GroupBox("Bezel") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show bezel", isOn: Binding(
                    get: { project.bezel != nil },
                    set: { project.bezel = $0 ? .standard : nil }
                ))
                .accessibilityIdentifier("bezel-toggle")
                if project.bezel != nil {
                    slider("Seat height", bezelBinding(\.seatHeight), 0.1...1.5, step: 0.05, suffix: "mm",
                           identifier: "bezel-seat-height")
                    slider("Seat length", bezelBinding(\.seatLength), 0.1...1.2, step: 0.05, suffix: "mm")
                    slider("Seat angle", bezelBinding(\.seatAngle), 0...45, step: 1, suffix: "°")
                    Text("Seat construction is recovered from BezelProfile; the collar wall and radial normal are reconstructed/inferred.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var haloSection: some View {
        GroupBox("Halo / cluster") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show halo", isOn: Binding(
                    get: { project.halo != nil },
                    set: { project.halo = $0 ? .standard : nil }
                ))
                .accessibilityIdentifier("halo-toggle")
                if project.halo != nil {
                    slider("Melee diameter", haloBinding(\.gemDiameter), 0.8...3, step: 0.05, suffix: "mm",
                           identifier: "halo-diameter")
                    slider("Stone spacing", haloBinding(\.spacing), 0.05...0.6, step: 0.01, suffix: "mm")
                    slider("Rail offset", haloBinding(\.offsetRailX), 0.2...2.5, step: 0.05, suffix: "mm")
                    slider("Rail height", haloBinding(\.offsetRailZ), -0.5...0.8, step: 0.05, suffix: "mm")
                    slider("Rotate seats", haloBinding(\.fixPosition), 0...1, step: 0.01, suffix: "")
                    Toggle("Even stone count", isOn: Binding(
                        get: { project.halo?.even ?? false },
                        set: { value in
                            guard var settings = project.halo else { return }
                            settings.even = value
                            project.halo = settings
                        }
                    ))
                    Text("Seat count, spacing and phase come from PlaceGems; the metal band and proxy crowns are reconstructed/inferred.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func bezelBinding(_ path: WritableKeyPath<BezelParameters, Double>) -> Binding<Double> {
        Binding(
            get: { project.bezel?[keyPath: path] ?? 0 },
            set: { value in
                guard var settings = project.bezel else { return }
                settings[keyPath: path] = value
                project.bezel = settings
            }
        )
    }

    private func haloBinding(_ path: WritableKeyPath<HaloParameters, Double>) -> Binding<Double> {
        Binding(
            get: { project.halo?[keyPath: path] ?? 0 },
            set: { value in
                guard var settings = project.halo else { return }
                settings[keyPath: path] = value
                project.halo = settings
            }
        )
    }

    private var provenanceSection: some View {
        GroupBox("Evidence") {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(HeadProvenance.all.count) IL literals traced to corpus v1/v2")
                Text("Every family declares a grade: recovered (IL-traced), reconstructed (documented algorithm) or inferred (explicit substitute).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(partTiers) { entry in
                    LabeledContent(entry.id.capitalized, value: entry.tier.rawValue)
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private struct PartTier: Identifiable {
        let id: String
        let tier: ProvenanceTier
    }

    private var partTiers: [PartTier] {
        (assembly?.partTiers ?? [:]).map { PartTier(id: $0.key, tier: $0.value) }
            .sorted { $0.id < $1.id }
    }

    private func slider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        step: Double,
        suffix: String,
        identifier: String? = nil
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
                .accessibilityIdentifier(identifier ?? title)
        }
    }
}
