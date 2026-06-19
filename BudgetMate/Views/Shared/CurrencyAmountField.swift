import SwiftUI

struct CurrencyAmountField: View {
    let currency: AppCurrency
    @Binding var text: String
    var onCommit: (() -> Void)? = nil

    private var placeholder: String {
        currency.minorUnitDivisor == 1 ? "0" : "0.00"
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 100, maxWidth: 140)
            .overlay(alignment: .leading) {
                Text(currency.symbol)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }
            .padding(.leading, leadingPadding)
            .onSubmit { onCommit?() }
    }

    private var leadingPadding: CGFloat {
        currency.symbol.count > 2 ? 28 : 18
    }
}
