import Foundation
import Testing
@testable import Toma

@Suite struct UpdateFeedTests {
    func payload(tag: String = "v1.4.0", digest: String? = "sha256:" + String(repeating: "a", count: 64),
                 asset: String = "https://github.com/eherrerosj/toma/releases/download/v1.4.0/Toma.dmg",
                 page: String = "https://github.com/eherrerosj/toma/releases/tag/v1.4.0") throws -> Data {
        var item: [String: Any] = ["name": "Toma.dmg", "browser_download_url": asset]
        if let digest { item["digest"] = digest }
        return try JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": page, "assets": [item]])
    }

    @Test func validPersonalRelease() throws {
        let update = try #require(UpdateFeed.parse(payload()))
        #expect(update.version == "1.4.0")
    }

    @Test func missingOrMalformedDigestIsRejected() throws {
        #expect(try UpdateFeed.parse(payload(digest: nil)) == nil)
        #expect(try UpdateFeed.parse(payload(digest: "sha256:bad")) == nil)
    }

    @Test func rejectsUntrustedLocations() throws {
        #expect(try UpdateFeed.parse(payload(asset: "http://github.com/eherrerosj/toma/releases/download/v1.4.0/Toma.dmg")) == nil)
        #expect(try UpdateFeed.parse(payload(asset: "https://github.com/felipebasurto/toma/releases/download/v1.4.0/Toma.dmg")) == nil)
        #expect(try UpdateFeed.parse(payload(page: "https://example.com/release")) == nil)
    }

    @Test func versionsRequireOnlyDottedNumbers() throws {
        #expect(!UpdateFeed.isNewer("9999junk", than: "1.3.0"))
        #expect(!UpdateFeed.isNewer("1..99", than: "1.3.0"))
        #expect(!UpdateFeed.isNewer("1.4.0-beta", than: "1.3.0"))
        #expect(UpdateFeed.isNewer("1.10", than: "1.9"))
        #expect(!UpdateFeed.isNewer("1.2.0", than: "1.2"))
        #expect(try UpdateFeed.parse(payload(tag: "v9999junk")) == nil)
    }
}
