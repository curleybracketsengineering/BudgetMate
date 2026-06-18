import Foundation
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum ExportService {
    @MainActor
    @discardableResult
    static func save(data: Data, suggestedFilename: String, contentType: UTType) -> Bool {
        #if os(macOS)
        saveOnMac(data: data, suggestedFilename: suggestedFilename, contentType: contentType)
        #elseif canImport(UIKit)
        saveOnUIKit(data: data, suggestedFilename: suggestedFilename)
        #else
        false
        #endif
    }

    @MainActor
    @discardableResult
    static func saveCSV(data: Data, suggestedFilename: String) -> Bool {
        save(data: data, suggestedFilename: suggestedFilename, contentType: .commaSeparatedText)
    }

    static func csvData(rows: [PrintableMonthRow], currency: AppCurrency) -> Data {
        var lines = ["Month,Opening,Income,Expenses,Net,Closing,Locked"]
        for row in rows {
            let net = row.income - row.expense
            let fields = [
                csvField(row.isLocked ? "\(row.title) (Locked)" : row.title),
                csvField(MoneyFormatter.majorUnitsString(minorUnits: row.opening, currency: currency)),
                csvField(MoneyFormatter.majorUnitsString(minorUnits: row.income, currency: currency)),
                csvField(MoneyFormatter.majorUnitsString(minorUnits: row.expense, currency: currency)),
                csvField(MoneyFormatter.majorUnitsString(minorUnits: net, currency: currency)),
                csvField(MoneyFormatter.majorUnitsString(minorUnits: row.closing, currency: currency)),
                row.isLocked ? "Yes" : "No"
            ]
            lines.append(fields.joined(separator: ","))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func budgetRulesCSVData(
        summary: BudgetRuleService.Summary,
        currency: AppCurrency,
        incoming: [PrintableBudgetRuleRow],
        outgoing: [PrintableBudgetRuleRow],
        other: [PrintableBudgetRuleRow],
        footnote: String? = nil
    ) -> Data {
        var lines: [String] = []

        if let footnote {
            lines.append(csvField("Note: \(footnote)"))
            lines.append("")
        }

        lines.append("Metric,Value")
        lines.append("\(csvField("Active rules")),\(summary.activeCount)")
        lines.append("\(csvField("Income / month")),\(csvField(MoneyFormatter.majorUnitsString(minorUnits: summary.incomeMinorUnits, currency: currency)))")
        lines.append("\(csvField("Bills / month")),\(csvField(MoneyFormatter.majorUnitsString(minorUnits: summary.expenseMinorUnits, currency: currency)))")
        if summary.savingMinorUnits > 0 {
            lines.append("\(csvField("Savings / month")),\(csvField(MoneyFormatter.majorUnitsString(minorUnits: summary.savingMinorUnits, currency: currency)))")
        }
        lines.append("\(csvField("Net / month")),\(csvField(MoneyFormatter.majorUnitsString(minorUnits: summary.netMinorUnits, currency: currency)))")
        lines.append("")
        lines.append("Section,Name,Details,Amount,Status")

        for section in [("Incoming", incoming), ("Outgoing", outgoing), ("Other", other)] {
            for rule in section.1 {
                lines.append([
                    csvField(section.0),
                    csvField(rule.name),
                    csvField(rule.metadata),
                    csvField(rule.amount),
                    csvField(rule.badge ?? "")
                ].joined(separator: ","))
            }
        }

        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    #if os(macOS)
    @MainActor
    private static func saveOnMac(data: Data, suggestedFilename: String, contentType: UTType) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [contentType]
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
    #endif

    #if canImport(UIKit) && !os(macOS)
    @MainActor
    private static func saveOnUIKit(data: Data, suggestedFilename: String) -> Bool {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            return false
        }

        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else {
            return false
        }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let activity = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        }
        presenter.present(activity, animated: true)
        return true
    }
    #endif
}
