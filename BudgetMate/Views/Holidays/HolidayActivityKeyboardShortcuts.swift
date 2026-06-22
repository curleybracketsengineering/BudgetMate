import SwiftUI

struct HolidayActivityKeyboardShortcuts: ViewModifier {
    @FocusState.Binding var isFocused: Bool

    let canCopy: Bool
    let canPaste: Bool
    let onCopy: () -> Void
    let onPaste: () -> Void

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .focusable()
                    .focused($isFocused)
                    .onKeyPress(characters: CharacterSet(charactersIn: "cCvV")) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }

                        switch press.characters.lowercased() {
                        case "c":
                            guard canCopy else { return .ignored }
                            onCopy()
                            return .handled
                        case "v":
                            guard canPaste else { return .ignored }
                            onPaste()
                            return .handled
                        default:
                            return .ignored
                        }
                    }
            }
    }
}

extension View {
    func holidayActivityKeyboardShortcuts(
        isFocused: FocusState<Bool>.Binding,
        canCopy: Bool,
        canPaste: Bool,
        onCopy: @escaping () -> Void,
        onPaste: @escaping () -> Void
    ) -> some View {
        modifier(
            HolidayActivityKeyboardShortcuts(
                isFocused: isFocused,
                canCopy: canCopy,
                canPaste: canPaste,
                onCopy: onCopy,
                onPaste: onPaste
            )
        )
    }
}
