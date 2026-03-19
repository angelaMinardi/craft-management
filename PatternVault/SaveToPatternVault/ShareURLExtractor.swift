//
//  ShareURLExtractor.swift
//  SaveToPatternVault
//

import Foundation

public enum ShareURLExtractor {
    public static func extractURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = detector?.firstMatch(in: trimmed, range: range), let url = match.url {
            return url.absoluteString
        }

        if let regex = try? NSRegularExpression(pattern: "https?://[^\\s]+", options: []),
           let match = regex.firstMatch(in: trimmed, range: range),
           let matchRange = Range(match.range, in: trimmed) {
            var urlString = String(trimmed[matchRange])
            while urlString.last == "." || urlString.last == "," || urlString.last == ")" || urlString.last == ">" {
                urlString.removeLast()
            }
            return urlString
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }

        return nil
    }

    public static func extractURL(fromSharedItem item: Any?) -> String? {
        if let url = item as? URL {
            return url.absoluteString
        }
        if let text = item as? String {
            return extractURL(from: text)
        }
        if let attributed = item as? NSAttributedString {
            return extractURL(from: attributed.string)
        }
        if let data = item as? Data {
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) {
                return extractURL(fromSharedItem: plist)
            }
            if let text = String(data: data, encoding: .utf8),
               let extracted = extractURL(from: text) {
                return extracted
            }
            if let url = URL(dataRepresentation: data, relativeTo: nil),
               let scheme = url.scheme?.lowercased(),
               (scheme == "http" || scheme == "https"),
               url.host != nil {
                return url.absoluteString
            }
        }
        if let dict = item as? [AnyHashable: Any] {
            let candidateKeys = ["url", "URL", "sourceURL", "source_url", "link", "href"]
            for key in candidateKeys {
                if let value = dict[key], let extracted = extractURL(fromSharedItem: value) {
                    return extracted
                }
            }
            for value in dict.values {
                if let extracted = extractURL(fromSharedItem: value) {
                    return extracted
                }
            }
        }
        if let array = item as? [Any] {
            for value in array {
                if let extracted = extractURL(fromSharedItem: value) {
                    return extracted
                }
            }
        }
        return nil
    }
}
