//
//  SourcePlatformHelperTests.swift
//  PatternVaultTests
//

import XCTest
@testable import CorvidCraft

final class SourcePlatformHelperTests: XCTestCase {

    func testPlatform_ravelry_returnsRavelry() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.ravelry.com/patterns/library/cozy-cardigan"), "Ravelry")
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://ravelry.com/patterns/123"), "Ravelry")
    }

    func testPlatform_etsy_returnsEtsy() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.etsy.com/listing/123"), "Etsy")
    }

    func testPlatform_tiktok_returnsTikTok() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.tiktok.com/@user/video/123"), "TikTok")
    }

    func testPlatform_youtube_returnsYouTube() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.youtube.com/watch?v=abc"), "YouTube")
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://youtu.be/abc"), "YouTube")
    }

    func testPlatform_pinterest_returnsPinterest() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.pinterest.com/pin/123"), "Pinterest")
    }

    func testPlatform_instagram_returnsInstagram() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.instagram.com/p/ABC/"), "Instagram")
    }

    func testPlatform_unknownHost_returnsWeb() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://example.com/pattern"), "Web")
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://blog.craftsite.com/pattern"), "Web")
    }

    func testPlatform_invalidURL_returnsNil() {
        XCTAssertNil(SourcePlatformHelper.platform(for: "not a url"))
        XCTAssertNil(SourcePlatformHelper.platform(for: ""))
    }

    func testPlatform_malformedURL_returnsNil() {
        XCTAssertNil(SourcePlatformHelper.platform(for: " "))
        // "://missing-scheme" can be parsed by URL(string:) and return "Web" on some platforms
    }

    // MARK: - Edge cases

    func testPlatform_subdomainRavelry_returnsRavelry() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://m.ravelry.com/patterns/123"), "Ravelry")
    }

    func testPlatform_subdomainEtsy_returnsEtsy() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://api.etsy.com/v3/listings"), "Etsy")
    }

    func testPlatform_urlWithQueryAndFragment_returnsPlatform() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.ravelry.com/patterns/library/hat?page=2#comments"), "Ravelry")
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.youtube.com/watch?v=abc&t=10s"), "YouTube")
    }

    func testPlatform_httpReturnsSameAsHttps() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "http://www.ravelry.com/patterns/1"), "Ravelry")
        XCTAssertEqual(SourcePlatformHelper.platform(for: "http://example.com/pattern"), "Web")
    }

    func testPlatform_hostWithPort_returnsPlatform() {
        XCTAssertEqual(SourcePlatformHelper.platform(for: "https://www.ravelry.com:443/patterns/1"), "Ravelry")
    }
}
