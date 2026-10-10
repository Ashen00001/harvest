import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RecognitionResult: Sendable, Equatable {
    case match(RecognizedTrack)
    case noMatch
}

public enum ShazamError: Error, LocalizedError, Equatable {
    case rateLimited
    case badStatus(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .rateLimited: "Shazam is rate-limiting this network. Try a longer interval."
        case .badStatus(let code): "Shazam returned HTTP \(code)."
        case .invalidResponse: "Couldn't read Shazam's response."
        }
    }
}

/// Talks to Shazam's (unofficial) discovery endpoint, same one SongRec and shazamio use.
public struct ShazamClient: Sendable {
    public var timeZone: String
    public var userAgent: String

    public init(
        timeZone: String = TimeZone.current.identifier,
        userAgent: String = "Dalvik/2.1.0 (Linux; U; Android 13; Pixel 7 Build/TQ3A.230805.001)"
    ) {
        self.timeZone = timeZone
        self.userAgent = userAgent
    }

    public func recognize(_ signature: ShazamSignature) async throws -> RecognitionResult {
        let request = try makeRequest(signature)
        let (data, http) = try await HTTP.send(request)
        if http.statusCode == 429 { throw ShazamError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw ShazamError.badStatus(http.statusCode) }
        return try Self.parse(data)
    }

    func makeRequest(_ signature: ShazamSignature) throws -> URLRequest {
        let first = UUID().uuidString.uppercased()
        let second = UUID().uuidString.lowercased()
        var components = URLComponents(string: "https://amp.shazam.com/discovery/v5/en/US/android/-/tag/\(first)/\(second)")!
        components.queryItems = [
            URLQueryItem(name: "sync", value: "true"),
            URLQueryItem(name: "webv3", value: "true"),
            URLQueryItem(name: "sampling", value: "true"),
            URLQueryItem(name: "connected", value: ""),
            URLQueryItem(name: "shazamapiversion", value: "v3"),
            URLQueryItem(name: "sharehub", value: "true"),
            URLQueryItem(name: "video", value: "v3"),
        ]

        let now = Int(Date().timeIntervalSince1970 * 1000)
        let body: [String: Any] = [
            "geolocation": ["altitude": 300, "latitude": 45, "longitude": 2],
            "signature": [
                "samplems": signature.durationMilliseconds,
                "timestamp": now,
                "uri": signature.dataURI(),
            ],
            "timestamp": now,
            "timezone": timeZone,
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en_US", forHTTPHeaderField: "Content-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func parse(_ data: Data) throws -> RecognitionResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShazamError.invalidResponse
        }
        let matches = root["matches"] as? [[String: Any]] ?? []
        guard !matches.isEmpty,
              let track = root["track"] as? [String: Any],
              let key = track["key"] as? String,
              let title = track["title"] as? String
        else {
            return .noMatch
        }

        let images = track["images"] as? [String: Any]
        let genres = track["genres"] as? [String: Any]
        let hub = track["hub"] as? [String: Any]
        let actions = hub?["actions"] as? [[String: Any]] ?? []

        var songMetadata: [String: String] = [:]
        for section in track["sections"] as? [[String: Any]] ?? [] where section["type"] as? String == "SONG" {
            for item in section["metadata"] as? [[String: Any]] ?? [] {
                if let name = item["title"] as? String, let text = item["text"] as? String {
                    songMetadata[name] = text
                }
            }
        }

        let appleMusicID = actions.first { $0["type"] as? String == "applemusicplay" }?["id"] as? String
        let preview = actions.first {
            ($0["type"] as? String == "uri") && (($0["uri"] as? String)?.hasPrefix("https://") ?? false)
        }?["uri"] as? String

        return .match(RecognizedTrack(
            shazamKey: key,
            title: title,
            artist: track["subtitle"] as? String ?? "Unknown artist",
            album: songMetadata["Album"],
            released: songMetadata["Released"],
            genre: genres?["primary"] as? String,
            isrc: track["isrc"] as? String,
            coverArtURL: (images?["coverart"] as? String).flatMap(URL.init(string:)),
            coverArtHQURL: (images?["coverarthq"] as? String).flatMap(URL.init(string:)),
            shazamURL: (track["url"] as? String).flatMap(URL.init(string:)),
            appleMusicID: appleMusicID,
            previewURL: preview.flatMap(URL.init(string:))
        ))
    }
}
