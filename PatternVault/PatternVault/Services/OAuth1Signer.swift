//
//  OAuth1Signer.swift
//  PatternVault
//
//  OAuth 1.0a HMAC-SHA1 signing for Ravelry API.
//

import Foundation
import CommonCrypto

enum OAuth1Signer {

    static func sign(
        method: String,
        url: URL,
        consumerKey: String,
        consumerSecret: String,
        accessToken: String? = nil,
        accessTokenSecret: String? = nil,
        extraParams: [String: String] = [:]
    ) -> [String: String] {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let timestamp = String(Int(Date().timeIntervalSince1970))
        var params: [String: String] = [
            "oauth_consumer_key": consumerKey,
            "oauth_nonce": nonce,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": timestamp,
            "oauth_version": "1.0"
        ]
        if let t = accessToken {
            params["oauth_token"] = t
        }
        for (k, v) in extraParams {
            params[k] = v
        }
        let signingKey = [consumerSecret, accessTokenSecret ?? ""].joined(separator: "&")
        let signatureBaseString = buildSignatureBaseString(method: method, url: url, params: params)
        let signature = hmacSha1(key: signingKey, value: signatureBaseString)
        params["oauth_signature"] = signature
        return params
    }

    static func authorizationHeader(_ params: [String: String]) -> String {
        params
            .sorted(by: { $0.key < $1.key })
            .map { "\(rfc3986Encode($0.key))=\"\(rfc3986Encode($0.value))\"" }
            .joined(separator: ", ")
    }

    private static func buildSignatureBaseString(method: String, url: URL, params: [String: String]) -> String {
        let baseUrl = "\(url.scheme ?? "https")://\(url.host ?? "")\(url.path)"
        let encodedParams = params
            .sorted(by: { $0.key < $1.key })
            .map { "\(rfc3986Encode($0.key))=\(rfc3986Encode($0.value))" }
            .joined(separator: "&")
        return [method.uppercased(), rfc3986Encode(baseUrl), rfc3986Encode(encodedParams)].joined(separator: "&")
    }

    private static func rfc3986Encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func hmacSha1(key: String, value: String) -> String {
        guard let keyData = key.data(using: .utf8),
              let valueData = value.data(using: .utf8) else { return "" }
        var result = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBytes in
            valueData.withUnsafeBytes { valueBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA1),
                    keyBytes.baseAddress, keyBytes.count,
                    valueBytes.baseAddress, valueBytes.count,
                    &result
                )
            }
        }
        return Data(result).base64EncodedString()
    }
}
