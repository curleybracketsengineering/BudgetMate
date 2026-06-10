import SwiftUI

struct PlanningStartPicker: View {
    @Binding var month: Int
    @Binding var year: Int
    var label: LocalizedStringKey = "Planning start"

    static let minYear = 2020
    static let maxYear = 2100

    var body: some View {
        LabeledContent(label) {
            Menu {
                Section("Month") {
                    ForEach(1...12, id: \.self) { monthValue in
                        Button {
                            month = monthValue
                        } label: {
                            if month == monthValue {
                                Label(monthName(monthValue), systemImage: "checkmark")
                            } else {
                                Text(monthName(monthValue))
                            }
                        }
                    }
                }

                Section("Year") {
                    ForEach((Self.minYear...Self.maxYear).reversed(), id: \.self) { yearValue in
                        Button {
                            year = yearValue
                        } label: {
                            if year == yearValue {
                                Label(String(yearValue), systemImage: "checkmark")
                            } else {
                                Text(verbatim: String(yearValue))
                            }
                        }
                    }
                }
            } label: {
                Text(displayText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var displayText: String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return "\(monthName(month)) \(year)"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func monthName(_ month: Int) -> String {
        Calendar.current.monthSymbols[month - 1]
    }
}
