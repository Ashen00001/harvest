import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum HTTP {
    struct NoResponse: Error {}

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data, http))
                } else {
                    continuation.resume(throwing: NoResponse())
                }
            }.resume()
        }
    }

    /// application/x-www-form-urlencoded body
    static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}
