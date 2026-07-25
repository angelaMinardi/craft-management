//
//  BarcodeLookupService.swift
//  PatternVault
//
//  Looks up a scanned product barcode (EAN/UPC) against a free product
//  database so the yarn-stash form can auto-fill brand/name. Best-effort:
//  returns nil when nothing is found or the network call fails, so the
//  caller can fall back to saving just the raw barcode.
//

import Foundation

struct BarcodeProductInfo: Sendable {
    /// Full product title, e.g. "Red Heart Super Saver Yarn, Cherry Red".
    let title: String?
    /// Brand name, e.g. "Red Heart".
    let brand: String?

    var isEmpty: Bool {
        (title?.isEmpty ?? true) && (brand?.isEmpty ?? true)
    }
}

enum BarcodeLookupService {

    /// Look up product info for a barcode using the free UPCitemdb trial API.
    /// No API key required (rate-limited ~100 lookups/day). Returns nil if the
    /// barcode isn't found or the request fails.
    static func lookup(barcode: String) async -> BarcodeProductInfo? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty,
              let url = URL(string: "https://api.upcitemdb.com/prod/trial/lookup?upc=\(code)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let items = json?["items"] as? [[String: Any]],
                  let first = items.first else {
                return nil
            }
            let title = (first["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let brand = (first["brand"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let info = BarcodeProductInfo(
                title: title?.isEmpty == true ? nil : title,
                brand: brand?.isEmpty == true ? nil : brand
            )
            return info.isEmpty ? nil : info
        } catch {
            #if DEBUG
            print("[BarcodeLookupService] lookup failed: \(error)")
            #endif
            return nil
        }
    }
}
