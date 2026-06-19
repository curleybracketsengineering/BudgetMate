import SwiftUI

struct TravelSearchSettingsView: View {
    @Environment(TravelSearchStore.self) private var travelSearch

    var body: some View {
        Form {
            Section("Travel search") {
                Picker("Flights", selection: Bindable(travelSearch).flightSearchProvider) {
                    ForEach([TravelSearchProvider.skyscanner, .googleFlights], id: \.id) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                Picker("Hotels", selection: Bindable(travelSearch).hotelSearchProvider) {
                    Text(TravelSearchProvider.googleHotels.displayName)
                        .tag(TravelSearchProvider.googleHotels)
                }
                Picker("Car hire", selection: Bindable(travelSearch).carHireSearchProvider) {
                    Text(TravelSearchProvider.kayakCars.displayName)
                        .tag(TravelSearchProvider.kayakCars)
                }
                Text("Used when you tap Find prices on a holiday.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Travel search")
    }
}
