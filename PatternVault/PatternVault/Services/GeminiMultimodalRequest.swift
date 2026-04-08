//
//  GeminiMultimodalRequest.swift
//  PatternVault
//
//  Builds Gemini API request bodies that include both text and inline images
//  for multimodal vision analysis (chart detection, pattern page understanding).
//

import Foundation

enum GeminiMultimodalRequest {
    struct ImageInput {
        let data: Data
        let mimeType: String
        let label: String
    }

    /// Builds a Gemini `generateContent` request body with text + inline images.
    /// Images are base64-encoded as `inline_data` parts alongside the text prompt.
    static func buildRequestBody(
        prompt: String,
        images: [ImageInput],
        maxOutputTokens: Int = 8192
    ) -> [String: Any] {
        var parts: [[String: Any]] = []
        parts.append(["text": prompt])

        for image in images {
            let base64 = image.data.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": image.mimeType,
                    "data": base64
                ]
            ])
        }

        return [
            "contents": [["parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": maxOutputTokens,
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]
    }

    /// Builds a text-only request body (no images). Convenience for when no images are available.
    static func buildTextOnlyRequestBody(
        prompt: String,
        maxOutputTokens: Int = 4096
    ) -> [String: Any] {
        return [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": maxOutputTokens,
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]
    }

    /// Prepares image inputs from raw image data arrays, labeling each by index.
    /// Automatically detects PNG vs JPEG from magic bytes.
    static func imageInputs(from imageDataArray: [Data], prefix: String = "image") -> [ImageInput] {
        imageDataArray.enumerated().map { index, data in
            ImageInput(data: data, mimeType: detectMimeType(data), label: "\(prefix)_\(index)")
        }
    }

    /// Prepares image inputs from PDFPageRenderer output.
    static func imageInputs(from renderedPages: [PDFPageRenderer.RenderedPage]) -> [ImageInput] {
        renderedPages.map { page in
            ImageInput(data: page.imageData, mimeType: detectMimeType(page.imageData), label: "page_\(page.pageIndex)")
        }
    }

    /// Detects image MIME type from magic bytes. Defaults to JPEG.
    private static func detectMimeType(_ data: Data) -> String {
        guard data.count >= 4 else { return "image/jpeg" }
        let header = [UInt8](data.prefix(4))
        // PNG magic: 0x89 0x50 0x4E 0x47
        if header[0] == 0x89, header[1] == 0x50, header[2] == 0x4E, header[3] == 0x47 {
            return "image/png"
        }
        return "image/jpeg"
    }
}
