import SwiftUI

struct HolidayMarkdownText: View {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        if let attributed = Self.attributedString(from: markdown) {
            Text(attributed)
        } else {
            Text(markdown)
        }
    }

    private static func attributedString(from markdown: String) -> AttributedString? {
        try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )
    }
}
