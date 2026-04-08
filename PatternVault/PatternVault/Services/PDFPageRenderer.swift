//
//  PDFPageRenderer.swift
//  PatternVault
//
//  Renders PDF pages as JPEG images for Gemini Vision analysis.
//  Memory-managed: renders one page at a time to stay within Share Extension limits.
//

import Foundation
import PDFKit
import UIKit

enum PDFPageRenderer {
    struct RenderedPage {
        let pageIndex: Int
        let imageData: Data
    }

    /// Renders up to `maxPages` pages from PDF data as JPEG images.
    /// - Parameters:
    ///   - data: Raw PDF file data.
    ///   - maxPages: Maximum number of pages to render (3-5 for Share Extension, higher for main app).
    ///   - scale: Render scale (1.0 for Share Extension memory efficiency, 2.0 for main app quality).
    ///   - jpegQuality: JPEG compression quality (0.0-1.0).
    /// - Returns: Array of rendered pages with JPEG data, or empty if PDF is invalid.
    static func renderPages(
        from data: Data,
        maxPages: Int = 5,
        scale: CGFloat = 1.0,
        jpegQuality: CGFloat = 0.7
    ) -> [RenderedPage] {
        guard let document = PDFDocument(data: data) else { return [] }
        let pageCount = min(document.pageCount, maxPages)
        guard pageCount > 0 else { return [] }

        var results: [RenderedPage] = []
        results.reserveCapacity(pageCount)

        for i in 0..<pageCount {
            autoreleasepool {
                guard let page = document.page(at: i) else { return }
                let mediaBox = page.bounds(for: .mediaBox)
                let targetSize = CGSize(
                    width: mediaBox.width * scale,
                    height: mediaBox.height * scale
                )
                let image = page.thumbnail(of: targetSize, for: .mediaBox)
                if let jpegData = image.jpegData(compressionQuality: jpegQuality) {
                    results.append(RenderedPage(pageIndex: i, imageData: jpegData))
                }
            }
        }

        return results
    }

    /// Renders a single page from PDF data as a UIImage (for chart cropping).
    static func renderPage(from data: Data, pageIndex: Int, scale: CGFloat = 2.0) -> UIImage? {
        guard let document = PDFDocument(data: data),
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else { return nil }
        let mediaBox = page.bounds(for: .mediaBox)
        let targetSize = CGSize(
            width: mediaBox.width * scale,
            height: mediaBox.height * scale
        )
        return page.thumbnail(of: targetSize, for: .mediaBox)
    }

    /// Renders a single PDF page at high quality using Core Graphics for crisp chart images.
    /// Uses CGBitmapContext for precise control over rendering, producing lossless PNG data.
    /// - Parameters:
    ///   - data: Raw PDF file data.
    ///   - pageIndex: 0-based page index.
    ///   - scale: Render scale (3.0-4.0 recommended for chart detail).
    /// - Returns: PNG image data of the rendered page, or nil on failure.
    static func renderPageHighQuality(from data: Data, pageIndex: Int, scale: CGFloat = 3.0) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdfDoc = CGPDFDocument(provider),
              let pdfPage = pdfDoc.page(at: pageIndex + 1) else { return nil } // CGPDFDocument is 1-indexed

        let mediaBox = pdfPage.getBoxRect(.mediaBox)
        let width = Int(mediaBox.width * scale)
        let height = Int(mediaBox.height * scale)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // White background
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale and draw the PDF page
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(pdfPage)

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }
}
