//
//  PDFPageRenderer.swift
//  SaveToPatternVault
//
//  Renders PDF pages as JPEG images for Gemini Vision chart detection.
//  Share Extension copy — kept separate due to target isolation.
//

import Foundation
import PDFKit
import UIKit

enum PDFPageRenderer {
    struct RenderedPage {
        let pageIndex: Int
        let imageData: Data
    }

    static func renderPages(
        from data: Data,
        maxPages: Int = 3,
        scale: CGFloat = 1.0,
        jpegQuality: CGFloat = 0.6
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
}
