import SwiftUI

struct CurrencyAmountField: View {
    let currency: AppCurrency
    @Binding var text: String
    var onCommit: (() -> Void)? = nil

    private var placeholder: String {
        currency.minorUnitDivisor == 1 ? "0" : "0.00"
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(currency.symbol)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 80, maxWidth: 120)
                .onSubmit { onCommit?() }
        }
    }
}
