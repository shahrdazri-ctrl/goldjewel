import JewelryKit
import SwiftUI

@main
struct GoldJewelApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    private let assembly = HeadAssembly.solitaire

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("GoldJewel")
                    .font(.largeTitle.weight(.semibold))
                Text("Recovered head builder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HeadPreviewView()
                .frame(maxWidth: 560)
                .aspectRatio(1.05, contentMode: .fit)

            HStack(spacing: 18) {
                Label("\(assembly.prongs.count) prongs", systemImage: "circle.grid.2x2")
                Label("\(assembly.triangleCount.formatted()) triangles", systemImage: "triangle")
                Label("\(RingSizeRegion.allCases.count) ring regions", systemImage: "circle.dashed")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Text("\(assembly.provenance.count) literals traced to IL · \(assembly.parameters.gemXSizeMM.formatted()) mm round")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
    }
}
