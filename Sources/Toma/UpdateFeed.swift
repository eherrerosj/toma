import Foundation

/// A release newer than the running app, as GitHub describes it.
nonisolated struct Update: Sendable {
    let version: String
    let dmg: URL
    /// Required SHA-256 supplied by the release feed.
    let sha256: String
    /// The release page: the manual fallback when installing in place is not possible.
    let page: URL
}

/// Everything Toma knows about where releases live and how to read them. Pure: no UI, no network,
/// so the version rules and the parsing are testable on their own.
nonisolated enum UpdateFeed {
    static let latest = URL(string: "https://api.github.com/repos/\(AppIdentity.repository)/releases/latest")!
    static let assetName = "Toma.dmg"

    nonisolated private struct Payload: Decodable {
        let tag_name: String
        let html_url: URL
        let assets: [Asset]

        nonisolated struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?
        }
    }

    /// The release described by GitHub's `releases/latest` response, or nil if it is malformed or
    /// carries no `Toma.dmg`. Says nothing about whether it is newer; see `isNewer`.
    static func parse(_ data: Data) -> Update? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              components(version(fromTag: payload.tag_name)) != nil,
              let asset = payload.assets.first(where: { $0.name == assetName }),
              let digest = asset.digest, digest.hasPrefix("sha256:"),
              trustedURL(payload.html_url, path: "/\(AppIdentity.repository)/releases/tag/\(payload.tag_name)"),
              trustedURL(asset.browser_download_url, path: "/\(AppIdentity.repository)/releases/download/\(payload.tag_name)/\(assetName)")
        else { return nil }
        let sha = String(digest.dropFirst(7)).lowercased()
        guard sha.count == 64, sha.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return Update(version: version(fromTag: payload.tag_name), dmg: asset.browser_download_url,
                      sha256: sha, page: payload.html_url)
    }

    private static func trustedURL(_ url: URL, path: String) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "https" && parts.host == "github.com" && parts.path == path
            && parts.user == nil && parts.password == nil && parts.port == nil
            && parts.query == nil && parts.fragment == nil
    }

    /// "v1.3.0" → "1.3.0".
    static func version(fromTag tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Dotted-number comparison: "1.10" is newer than "1.9", and "1.2" equals "1.2.0".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = components(candidate), let b = components(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let values = parts.compactMap { Int($0) }
        return values.count == parts.count ? values : nil
    }

}
