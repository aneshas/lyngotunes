import Foundation

/// The one seam to the network, so every client can be tested with canned responses.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTP: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

extension CharacterSet {
    /// RFC 3986 unreserved characters: safe inside a form or query value.
    static let formValueAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

func formEncoded(_ fields: [(String, String)]) -> Data {
    fields.map { key, value in
        let v = value.addingPercentEncoding(withAllowedCharacters: .formValueAllowed) ?? value
        return "\(key)=\(v)"
    }.joined(separator: "&").data(using: .utf8)!
}
