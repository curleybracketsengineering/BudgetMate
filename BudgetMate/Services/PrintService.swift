import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum PrintPageOrientation {
    case portrait
    case landscape
}

struct PrintDocumentOptions {
    var orientation: PrintPageOrientation = .portrait
}

enum PrintService {
    static let pageWidth: CGFloat = 595
    static let contentPadding: CGFloat = 44
    static let portraitPageSize = CGSize(width: 595, height: 842)
    static let landscapePageSize = CGSize(width: 842, height: 595)

    static func contentSize(for pageSize: CGSize) -> CGSize {
        CGSize(
            width: pageSize.width - (contentPadding * 2),
            height: pageSize.height - (contentPadding * 2)
        )
    }

    @MainActor
    static func print<V: View>(title: String, @ViewBuilder content: () -> V) {
        let document = documentView(title: title, content: content)

        #if os(macOS)
        printPDFDataOnMac(
            renderPDF(from: document),
            jobName: title,
            orientation: .portrait
        )
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
    static func printPaginated<Page: View>(
        title: String,
        orientation: PrintPageOrientation,
        pages: [Page]
    ) {
        let pageSize = pageSize(for: orientation)
        guard let data = renderMultiPagePDF(pages: pages, pageSize: pageSize) else { return }

        #if os(macOS)
        printPDFDataOnMac(data, jobName: title, orientation: orientation)
        #endif
    }

    @MainActor
    @discardableResult
    static func exportPaginatedPDF<Page: View>(
        title: String,
        orientation: PrintPageOrientation,
        pages: [Page]
    ) -> Bool {
        let pageSize = pageSize(for: orientation)
        guard let data = renderMultiPagePDF(pages: pages, pageSize: pageSize) else { return false }
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

    private static func pageSize(for orientation: PrintPageOrientation) -> CGSize {
        switch orientation {
        case .portrait: portraitPageSize
        case .landscape: landscapePageSize
        }
    }

    @MainActor
    private static func renderPDF<V: View>(from view: V) -> Data? {
        let contentWidth = pageWidth - (contentPadding * 2)

        #if os(macOS)
        let wrapped = view
            .frame(width: contentWidth, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: wrapped)
        renderer.isOpaque = true
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        let pageSize = CGSize(
            width: contentWidth,
            height: image.size.height / renderer.scale
        )
        return pdfData(from: image, pageSize: pageSize)
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

    @MainActor
    private static func renderMultiPagePDF<Page: View>(pages: [Page], pageSize: CGSize) -> Data? {
        guard !pages.isEmpty else { return nil }

        let contentSize = contentSize(for: pageSize)

        #if os(macOS)
        let merged = PDFDocument()

        for page in pages {
            let pageView = page
                .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                .padding(contentPadding)
                .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                .background(Color.white)
                .environment(\.colorScheme, .light)

            guard let pageData = renderBitmapPDF(from: pageView, pageSize: pageSize),
                  let document = PDFDocument(data: pageData),
                  let pdfPage = document.page(at: 0) else {
                continue
            }
            merged.insert(pdfPage, at: merged.pageCount)
        }

        guard merged.pageCount > 0 else { return nil }
        return merged.dataRepresentation()
        #elseif canImport(UIKit)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return pdfRenderer.pdfData { context in
            for page in pages {
                context.beginPage()

                let pageView = page
                    .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                    .padding(contentPadding)
                    .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)

                let host = UIHostingController(rootView: pageView)
                host.view.backgroundColor = .white
                host.view.bounds = CGRect(origin: .zero, size: pageSize)
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
        }
        #else
        return nil
        #endif
    }

    #if os(macOS)
    @MainActor
    private static func printPDFDataOnMac(
        _ data: Data?,
        jobName: String,
        orientation: PrintPageOrientation
    ) {
        guard let data,
              let pdfDocument = PDFDocument(data: data),
              pdfDocument.pageCount > 0 else {
            return
        }

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.orientation = orientation == .landscape ? .landscape : .portrait
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.jobDisposition = .spool

        guard let printOperation = pdfDocument.printOperation(
            for: printInfo,
            scalingMode: .pageScaleDownToFit,
            autoRotate: true
        ) else {
            return
        }

        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.jobTitle = jobName
        printOperation.run()
    }

    @MainActor
    private static func renderBitmapPDF<V: View>(from view: V, pageSize: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.isOpaque = true
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        return pdfData(from: image, pageSize: pageSize)
    }

    private static func pdfData(from image: NSImage, pageSize: CGSize) -> Data? {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
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
                    .font(PrintTypography.documentBrand)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(title)
                    .font(PrintTypography.documentTitle)
                Text(printedAt, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(PrintTypography.documentDate)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(PrintService.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}
