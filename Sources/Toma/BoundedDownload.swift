import Foundation

nonisolated enum BoundedDownload {
    static let maximumBytes = 32 * 1024 * 1024
    enum Failure: Error { case response, size, redirect }

    static func allows(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "https" && parts.user == nil && parts.password == nil && parts.port == nil
            && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(parts.host)
    }

    static func copy(_ url: URL, to destination: URL) async throws {
        guard allows(url) else { throw Failure.redirect }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            let (stream, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let final = response.url, allows(final) else { throw Failure.response }
            guard response.expectedContentLength <= maximumBytes else { throw Failure.size }
            guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                                  attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            let file = try FileHandle(forWritingTo: destination)
            defer { try? file.close() }
            var count = 0
            var buffer = Data()
            buffer.reserveCapacity(65_536)
            for try await byte in stream {
                count += 1
                guard count <= maximumBytes else { throw Failure.size }
                buffer.append(byte)
                if buffer.count == 65_536 {
                    try Task.checkCancellation()
                    try file.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            try file.write(contentsOf: buffer)
            try Task.checkCancellation()
        } onCancel: { session.invalidateAndCancel() }
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(request.url.flatMap { BoundedDownload.allows($0) ? request : nil })
        }
    }
}
