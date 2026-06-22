import SwiftUI

struct InlineEditableText: View {
    var text: String
    var placeholder: String = ""
    var font: Font = .body
    var weight: Font.Weight?
    var isSecondary = false
    var lineLimit: Int?
    var textAlignment: TextAlignment = .leading
    var multiline = false
    var expandsHorizontally = false
    var activationTapCount = InlineEditableField.activationTapCount
    let onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if isEditing {
                editField
            } else {
                displayLabel
            }
        }
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if !focused && isEditing {
                commitEdit()
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                isFocused = true
            }
        }
    }

    private var displayLabel: some View {
        Text(trimmedText.isEmpty ? placeholder : text)
            .font(styledFont)
            .foregroundStyle(displayForegroundStyle)
            .lineLimit(lineLimit)
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: expandsHorizontally ? .infinity : nil, alignment: frameAlignment)
            .contentShape(Rectangle())
            .onTapGesture(count: activationTapCount, perform: beginEditing)
            .help(InlineEditableField.editHelpText)
    }

    private var displayForegroundStyle: Color {
        if trimmedText.isEmpty {
            return Color.secondary.opacity(0.6)
        }
        return isSecondary ? .secondary : .primary
    }

    @ViewBuilder
    private var editField: some View {
        if multiline {
            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...12)
                .font(styledFont)
                .textFieldStyle(.plain)
                .onSubmit(commitEdit)
        } else {
            TextField(placeholder, text: $draft)
                .font(styledFont)
                .textFieldStyle(.plain)
                .onSubmit(commitEdit)
        }
    }

    private var styledFont: Font {
        if let weight {
            return font.weight(weight)
        }
        return font
    }

    private var frameAlignment: Alignment {
        switch textAlignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func beginEditing() {
        draft = text
        isEditing = true
    }

    private func commitEdit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != trimmedText {
            onCommit(trimmed)
        }
        isEditing = false
        isFocused = false
    }
}

struct InlineEditableAmount: View {
    let minorUnits: Int
    let currency: AppCurrency
    var font: Font = .body.monospacedDigit()
    var activationTapCount = InlineEditableField.activationTapCount
    let onCommit: (Int) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(currency.minorUnitDivisor == 1 ? "0" : "0.00", text: $draft)
                    .font(font)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 72)
                    .onSubmit(commitEdit)
            } else {
                Text(MoneyFormatter.format(minorUnits: minorUnits, currency: currency))
                    .font(font)
                    .contentShape(Rectangle())
                    .onTapGesture(count: activationTapCount, perform: beginEditing)
                    .help(InlineEditableField.editHelpText)
            }
        }
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if !focused && isEditing {
                commitEdit()
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                isFocused = true
            }
        }
    }

    private func beginEditing() {
        draft = MoneyFormatter.majorUnitsString(minorUnits: minorUnits, currency: currency)
        isEditing = true
    }

    private func commitEdit() {
        if let parsed = MoneyFormatter.parseMajorUnits(draft, currency: currency), parsed != minorUnits {
            onCommit(parsed)
        }
        isEditing = false
        isFocused = false
    }
}

private enum InlineEditableField {
    static var activationTapCount: Int {
        #if os(iOS)
        1
        #else
        2
        #endif
    }

    static var editHelpText: String {
        #if os(iOS)
        "Tap to edit"
        #else
        "Double-click to edit"
        #endif
    }
}
