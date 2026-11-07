import Foundation
import Security
import CryptoKit

nonisolated enum UpdateTrust {
    enum Failure: Error { case signature, digest }

    static func requirement(team: String) throws -> String {
        guard team.count == 10, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
            throw Failure.signature
        }
        return "anchor apple generic and identifier \"\(AppIdentity.bundleIdentifier)\" "
            + "and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists "
            + "and certificate leaf[subject.OU] = \"\(team)\""
    }

    static func signingTeam(of app: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw Failure.signature }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String else { throw Failure.signature }
        try verify(app, team: team)
        return team
    }

    static func verify(_ app: URL, team: String) throws {
        var code: SecStaticCode?
        var rule: SecRequirement?
        let expression = try requirement(team: team)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(expression as CFString, [], &rule) == errSecSuccess,
              let code, let rule else { throw Failure.signature }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, rule) == errSecSuccess else { throw Failure.signature }
    }

    static func checkDigest(of url: URL, expected: String) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        while let bytes = try file.read(upToCount: 65_536), !bytes.isEmpty { digest.update(data: bytes) }
        let hex = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard hex == expected else { throw Failure.digest }
    }
}
