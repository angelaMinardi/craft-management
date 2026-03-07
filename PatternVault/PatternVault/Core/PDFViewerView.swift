//
//  PDFViewerView.swift
//  PatternVault
//
//  Presents a PDF from a URL using Quick Look.
//

import SwiftUI
import QuickLook

private final class PDFPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    init(url: URL) {
        self.previewItemURL = url
    }
}

struct PDFViewerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            PDFPreviewItem(url: url)
        }
    }
}
