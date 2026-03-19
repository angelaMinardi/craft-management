//
//  SupabaseManager.swift
//  PatternVault
//

import Foundation
import Supabase

enum SupabaseManager {
    static let client: SupabaseClient = {
        let key = Bundle.main.supabaseAnonKey
        let url = Bundle.main.resolvedSupabaseURL(anonKey: key)
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
        )
        return SupabaseClient(supabaseURL: url, supabaseKey: key, options: options)
    }()
}

// MARK: - Configuration (load from xcconfig or Info.plist; no keys in repo)
private extension Bundle {
    /// Raw value from plist/env (may be invalid, e.g. "https:" if xcconfig is wrong).
    var supabaseURL: String {
        (infoDictionary?["SUPABASE_URL"] as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? ""
    }

    /// Returns a valid Supabase base URL. If configured URL is invalid, derives from anon key JWT (ref) when possible.
    func resolvedSupabaseURL(anonKey: String) -> URL {
        let raw = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty,
           let u = URL(string: raw),
           u.host?.contains("supabase.co") == true {
            return u
        }
        if let ref = projectRefFromAnonKey(anonKey), !ref.isEmpty {
            let derived = "https://\(ref).supabase.co"
            if let u = URL(string: derived) { return u }
        }
        return URL(string: "https://placeholder.supabase.co")!
    }

    /// Decode JWT payload and return "ref" (Supabase project ref) if present.
    private func projectRefFromAnonKey(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payload = String(parts[1])
        guard let data = Data(base64Encoded: base64URLDecode(payload)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ref = json["ref"] as? String else { return nil }
        return ref
    }

    private func base64URLDecode(_ s: String) -> String {
        var b64 = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = b64.count % 4
        if pad > 0 { b64 += String(repeating: "=", count: 4 - pad) }
        return b64
    }

    var supabaseAnonKey: String {
        (infoDictionary?["SUPABASE_ANON_KEY"] as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? "placeholder-anon-key"
    }
}
