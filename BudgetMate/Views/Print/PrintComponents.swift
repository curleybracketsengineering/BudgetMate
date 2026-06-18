import SwiftUI

struct PrintSummaryItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var tint: Color = .primary
}

struct PrintSummaryGrid: View {
    let items: [PrintSummaryItem]

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(item.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Color(white: 0.96),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(white: 0.88), lineWidth: 0.5)
                )
            }
        }
    }
}

struct PrintSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .padding(.top, 2)
            .padding(.bottom, 2)
    }
}

struct PrintFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

struct PrintRuleRow: View {
    let name: String
    let metadata: String
    let amount: String
    var badge: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.body.weight(.medium))
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(amount)
                        .font(.body.weight(.semibold).monospacedDigit())
                    if let badge {
                        Text(badge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            Divider()
        }
    }
}

struct PrintTableHeader: View {
    let columns: [String]
    var alignments: [HorizontalAlignment] = []

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                let alignment = index < alignments.count ? alignments[index] : .leading
                Text(column)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct PrintTableRow: View {
    let values: [String]
    var tints: [Color] = []
    var alignments: [HorizontalAlignment] = []
    var isBold: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let alignment = index < alignments.count ? alignments[index] : .leading
                let tint = index < tints.count ? tints[index] : .primary
                Text(value)
                    .font(isBold ? .subheadline.weight(.semibold).monospacedDigit() : .subheadline.monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}
