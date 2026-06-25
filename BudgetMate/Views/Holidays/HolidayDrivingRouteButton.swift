import SwiftUI

struct HolidayDrivingRouteButton: View {
    @Environment(\.openURL) private var openURL

    let origin: String
    let destination: String
    let countryName: String
    var style: Style = .icon

    enum Style {
        case icon
        case labeled
    }

    private var url: URL? {
        TravelDeepLinkService.googleDrivingDirectionsURL(
            origin: origin,
            destination: destination,
            countryName: countryName
        )
    }

    var body: some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                switch style {
                case .icon:
                    Image(systemName: "map")
                case .labeled:
                    Label("Open route in Google Maps", systemImage: "map")
                }
            }
            .buttonStyle(.borderless)
            .help("Open driving route in Google Maps")
            .accessibilityLabel("Open driving route in Google Maps")
        }
    }
}

extension HolidayDrivingRouteButton {
    init(activity: HolidayActivity, holiday: Holiday, style: Style = .icon) {
        self.origin = HolidayItineraryService.explicitOriginName(activity: activity)
        self.destination = HolidayItineraryService.explicitDestinationName(activity: activity)
        self.countryName = HolidayItineraryService.resolvedCountryName(activity: activity, holiday: holiday)
        self.style = style
    }
}
