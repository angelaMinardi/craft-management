//
//  KeychainHelper.swift
//  PatternVault
//
//  Secure storage for Ravelry OAuth tokens, keyed by app user id.
//

import Foundation
import Security

enum KeychainHelper {

    private static let serviceName = "com.patternvault.app.ravelry"

    /// OAuth 2.0: pass accessToken and "" for accessTokenSecret.
    static func saveRavelryTokens(userId: UUID, accessToken: String, accessTokenSecret: String = "") throws {
        let key = "ravelry_\(userId.uuidString)"
        let data = accessTokenSecret.isEmpty ? "\(accessToken)\n".data(using: .utf8)! : "\(accessToken)\n\(accessTokenSecret)".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary) // remove existing
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadRavelryTokens(userId: UUID) -> (accessToken: String, accessTokenSecret: String)? {
        let key = "ravelry_\(userId.uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parts = string.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count >= 1, !parts[0].isEmpty else { return nil }
        let secret = parts.count == 2 ? String(parts[1]) : ""
        return (String(parts[0]), secret)
    }

    static func deleteRavelryTokens(userId: UUID) {
        let key = "ravelry_\(userId.uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
