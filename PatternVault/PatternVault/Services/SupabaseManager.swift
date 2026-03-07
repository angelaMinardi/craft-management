//
//  SupabaseManager.swift
//  PatternVault
//

import Foundation
import Supabase

enum SupabaseManager {
    static let client: SupabaseClient = {
        let url = URL(string: Bundle.main.supabaseURL)!
        let key = Bundle.main.supabaseAnonKey
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}

// MARK: - Configuration (load from xcconfig or Info.plist; no keys in repo)
private extension Bundle {
    var supabaseURL: String {
        (infoDictionary?["SUPABASE_URL"] as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://placeholder.supabase.co"
    }

    var supabaseAnonKey: String {
        (infoDictionary?["SUPABASE_ANON_KEY"] as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? "placeholder-anon-key"
    }
}
