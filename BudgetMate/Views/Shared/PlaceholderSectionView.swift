import SwiftUI

struct PlaceholderSectionView: View {
    let title: String
    let message: String
    var proFeature: FeatureGateService.ProFeature?

    @Environment(FeatureGateService.self) private var featureGate

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if let proFeature, !featureGate.isAvailable(proFeature) {
                Label("Pro feature — \(proFeature.displayName)", systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
