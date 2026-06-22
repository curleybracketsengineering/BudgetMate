import SwiftUI

/// Integer stepper for use inside `Form` rows. Uses a fixed `LabeledContent` label and
/// custom buttons instead of `Stepper`, which can scroll macOS forms when the value changes.
struct FormIntegerStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var valueLabel: (Int) -> String

    init(
        _ label: String,
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        valueLabel: @escaping (Int) -> String = { "\($0)" }
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.valueLabel = valueLabel
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Text(valueLabel(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 56, alignment: .trailing)

                stepperButtons
            }
        }
    }

    private var stepperButtons: some View {
        VStack(spacing: 0) {
            stepperButton(systemImage: "chevron.up", enabled: value < range.upperBound) {
                value += 1
            }
            stepperButton(systemImage: "chevron.down", enabled: value > range.lowerBound) {
                value -= 1
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.mini)
    }

    private func stepperButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 16, height: 10)
        }
        .disabled(!enabled)
    }
}
