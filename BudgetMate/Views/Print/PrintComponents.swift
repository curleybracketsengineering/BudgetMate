import SwiftUI

enum PrintTypography {
    static let documentBrand = Font.system(size: 8, weight: .semibold)
    static let documentTitle = Font.system(size: 9, weight: .semibold)
    static let documentDate = Font.system(size: 8)
    static let sectionTitle = Font.system(size: 9, weight: .semibold)
    static let sectionHeader = Font.system(size: 8, weight: .semibold)
    static let body = Font.system(size: 8)
    static let bodyMedium = Font.system(size: 8, weight: .medium)
    static let bodySemibold = Font.system(size: 8, weight: .semibold)
    static let label = Font.system(size: 8)
    static let metadata = Font.system(size: 8)
    static let amount = Font.system(size: 8).monospacedDigit()
    static let amountSemibold = Font.system(size: 8, weight: .semibold).monospacedDigit()
    static let icon = Font.system(size: 8)
}

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
                        .font(PrintTypography.label)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(PrintTypography.amountSemibold)
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
            .font(PrintTypography.sectionHeader)
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
            .font(PrintTypography.metadata)
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
                        .font(PrintTypography.bodyMedium)
                    Text(metadata)
                        .font(PrintTypography.metadata)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(amount)
                        .font(PrintTypography.amountSemibold)
                    if let badge {
                        Text(badge)
                            .font(PrintTypography.metadata)
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
                    .font(PrintTypography.sectionHeader)
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
                    .font(isBold ? PrintTypography.amountSemibold : PrintTypography.amount)
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}
