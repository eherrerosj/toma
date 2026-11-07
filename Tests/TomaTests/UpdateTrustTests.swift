import Foundation
import Testing
@testable import Toma

@Suite struct UpdateTrustTests {
    @Test func adHocCodeCannotSupplyAnUpdateIdentity() throws {
        let binary = try #require(Bundle.main.executableURL)
        #expect(throws: (any Error).self) { try UpdateTrust.signingTeam(of: binary) }
    }

    @Test func unrelatedAppleSignedCodeCannotReplaceToma() {
        #expect(throws: (any Error).self) {
            try UpdateTrust.verify(URL(fileURLWithPath: "/usr/bin/true"), team: "ABCDEFGHIJ")
        }
    }

    @Test func invalidTeamCannotChangeTheCodeRequirement() {
        #expect(throws: (any Error).self) { try UpdateTrust.requirement(team: "bad\" or true") }
    }

    @Test func downloadsRejectUntrustedRedirectsAndOversizedFiles() {
        #expect(BoundedDownload.allows(URL(string: "https://release-assets.githubusercontent.com/file")!))
        #expect(!BoundedDownload.allows(URL(string: "http://github.com/file")!))
        #expect(!BoundedDownload.allows(URL(string: "https://github.com.attacker.test/file")!))
        #expect(!BoundedDownload.allows(URL(string: "https://user@github.com/file")!))
        #expect(BoundedDownload.maximumBytes <= 32 * 1024 * 1024)
    }
}
