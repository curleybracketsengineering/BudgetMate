import SwiftUI

struct HolidaysView: View {
    var body: some View {
        PlaceholderSectionView(
            title: "Holidays & Events",
            message: "Plan holidays and push costs into your monthly forecast.",
            proFeature: .holidayPlanner
        )
        .navigationTitle("Holidays & Events")
    }
}
