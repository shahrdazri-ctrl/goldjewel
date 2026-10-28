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
    private let gemSizes = [6.0, 6.5, 7.0, 7.5, 8.0]
    @State private var gemSizeIndex = 1
    @State private var prongCount = 4

    private var parameters: HeadShapeParameters {
        let gem = gemSizes[gemSizeIndex]
        let base = HeadShapeParameters.solitaire
        let step = 360.0 / Double(prongCount)
        let prongs = (0..<prongCount).map { index in
            ProngPlacement(
                angleDegrees: 45 + step * Double(index),
                topX: 0.9, topY: 0.6, baseX: 1.0, baseY: 0.7
            )
        }
        return HeadShapeParameters(
            gemXSizeMM: gem,
            gemYSizeMM: gem,
            headHeightMM: base.headHeightMM,
            baseOffsetMM: base.baseOffsetMM,
            prongHeightMM: base.prongHeightMM,
            angleXDegrees: base.angleXDegrees,
            angleYDegrees: base.angleYDegrees,
            topAngleDegrees: base.topAngleDegrees,
            baseAngleDegrees: base.baseAngleDegrees,
            baseAnglePosition: base.baseAnglePosition,
            bezelParameter: base.bezelParameter,
            prongs: prongs
        )
    }

    private var assembly: HeadAssembly? {
        try? HeadAssembly(parameters: parameters)
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("GoldJewel")
                    .font(.largeTitle.weight(.semibold))
                Text("Recovered head builder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let assembly {
                HeadPreviewView(assembly: assembly)
                    .frame(maxWidth: 560)
                    .aspectRatio(1.05, contentMode: .fit)
                    .id("\(gemSizeIndex)-\(prongCount)")

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
            } else {
                Text("Unable to build head")
                    .foregroundStyle(.red)
            }

            VStack(spacing: 10) {
                Picker("Gem size", selection: $gemSizeIndex) {
                    ForEach(gemSizes.indices, id: \.self) { index in
                        Text("\(gemSizes[index].formatted()) mm").tag(index)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Prongs", selection: $prongCount) {
                    Text("4").tag(4)
                    Text("6").tag(6)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: 420)
        }
        .padding(20)
    }
}
