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
    var body: some View {
        VStack(spacing: 12) {
            Text("GoldJewel")
                .font(.largeTitle.weight(.semibold))
            Text("\(RingSizeRegion.allCases.count) ring-size regions")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
