import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum PrintService {
    static let pageWidth: CGFloat = 595
    static let contentPadding: CGFloat = 44

    @MainActor
    static func print<V: View>(title: String, @ViewBuilder content: () -> V) {
        let document = documentView(title: title, content: content)

        #if os(macOS)
        printOnMac(document, jobName: title)
        #endif
    }

    @MainActor
    @discardableResult
    static func exportPDF<V: View>(title: String, @ViewBuilder content: () -> V) -> Bool {
        let document = documentView(title: title, content: content)
        guard let data = renderPDF(from: document) else { return false }
        return ExportService.save(
            data: data,
            suggestedFilename: sanitizedFilename(title) + ".pdf",
            contentType: .pdf
        )
    }

    @MainActor
    private static func documentView<V: View>(title: String, @ViewBuilder content: () -> V) -> some View {
        PrintDocumentShell(title: title) {
            content()
        }
        .environment(\.colorScheme, .light)
    }

    @MainActor
    private static func renderPDF<V: View>(from view: V) -> Data? {
        let contentWidth = pageWidth - (contentPadding * 2)

        #if os(macOS)
        let renderer = ImageRenderer(content: view.frame(width: contentWidth))
        guard let image = renderer.nsImage else { return nil }
        return pdfData(from: image)
        #elseif canImport(UIKit)
        let host = UIHostingController(rootView: view.frame(width: contentWidth))
        host.view.backgroundColor = .white

        let fittedSize = host.sizeThatFits(in: CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        let pageSize = CGSize(width: pageWidth, height: max(fittedSize.height + contentPadding * 2, pageWidth * 1.414))
        host.view.bounds = CGRect(origin: .zero, size: fittedSize)

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return pdfRenderer.pdfData { context in
            context.beginPage()
            let origin = CGPoint(x: contentPadding, y: contentPadding)
            host.view.drawHierarchy(in: CGRect(origin: origin, size: fittedSize), afterScreenUpdates: true)
        }
        #else
        return nil
        #endif
    }

    #if os(macOS)
    @MainActor
    private static func printOnMac<V: View>(_ view: V, jobName: String) {
        guard let pdfData = renderPDF(from: view),
              let pdfDocument = PDFDocument(data: pdfData),
              let page = pdfDocument.page(at: 0) else {
            return
        }

        let pageRect = page.bounds(for: .mediaBox)
        let pdfView = PDFView(frame: pageRect)
        pdfView.document = pdfDocument
        pdfView.autoScales = true

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.jobDisposition = .spool

        let printOperation = NSPrintOperation(view: pdfView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.jobTitle = jobName
        printOperation.run()
    }

    private static func pdfData(from image: NSImage) -> Data? {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: image.size)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }
        context.beginPDFPage(nil)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: mediaBox)
        }
        context.endPDFPage()
        context.closePDF()
        return pdfData as Data
    }
    #endif

    private static func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PrintDocumentShell<Content: View>: View {
    let title: String
    var printedAt: Date = .now
    let content: Content

    init(title: String, printedAt: Date = .now, @ViewBuilder content: () -> Content) {
        self.title = title
        self.printedAt = printedAt
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BudgetMate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(title)
                    .font(.title.weight(.bold))
                Text(printedAt, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(PrintService.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}
