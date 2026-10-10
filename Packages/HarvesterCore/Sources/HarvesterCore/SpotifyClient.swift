import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SpotifyTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

public struct SpotifyPlaylist: Codable, Sendable, Equatable {
    public var id: String
    public var url: URL?
}

public struct SpotifyTrackResult: Sendable, Equatable {
    public var uri: String
    public var name: String
    public var artists: [String]
    public var isrc: String?
}

public enum SpotifyError: Error, LocalizedError, Equatable {
    case authorizationFailed(String)
    case unauthorized
    case forbidden(String)
    case notFound
    case rateLimited
    case http(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .authorizationFailed(let reason): "Spotify login failed: \(reason)"
        case .unauthorized: "Your Spotify login expired. Reconnect Spotify in Settings."
        case .forbidden(let message):
            "Spotify refused the request (\(message)). Make sure your Spotify email is listed under User Management for the Harvest app in the Spotify developer dashboard."
        case .notFound: "Spotify couldn't find that playlist."
        case .rateLimited: "Spotify is rate-limiting requests. Try again in a minute."
        case .http(let code, let message): "Spotify error \(code): \(message)"
        case .invalidResponse: "Couldn't read Spotify's response."
        }
    }
}

/// Minimal Spotify Web API client: PKCE auth, track search, playlist create/fill.
/// Uses the post-February-2026 dev-mode endpoints (`/me/playlists`, `/playlists/{id}/items`).
public struct SpotifyClient: Sendable {
    public static let scopes = ["playlist-modify-private", "playlist-modify-public"]

    public var clientID: String
    public var redirectURI: String
    var accountsBase = URL(string: "https://accounts.spotify.com")!
    var apiBase = URL(string: "https://api.spotify.com/v1")!

    public init(clientID: String, redirectURI: String) {
        self.clientID = clientID
        self.redirectURI = redirectURI
    }

    // MARK: - Auth

    public func authorizationURL(codeChallenge: String, state: String) -> URL {
        var components = URLComponents(url: accountsBase.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    public func exchangeCode(_ code: String, verifier: String) async throws -> SpotifyTokens {
        let request = tokenRequest([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", verifier),
        ])
        return try Self.parseTokens(await perform(request), previous: nil)
    }

    public func refresh(_ tokens: SpotifyTokens) async throws -> SpotifyTokens {
        let request = tokenRequest([
            ("grant_type", "refresh_token"),
            ("refresh_token", tokens.refreshToken),
            ("client_id", clientID),
        ])
        do {
            return try Self.parseTokens(await perform(request), previous: tokens)
        } catch SpotifyError.http(400, _) {
            throw SpotifyError.unauthorized // refresh token revoked or expired
        }
    }

    func tokenRequest(_ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: accountsBase.appendingPathComponent("api/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.formBody(fields)
        return request
    }

    // MARK: - Search

    public func searchTracks(query: String, limit: Int, token: String) async throws -> [SpotifyTrackResult] {
        let request = try apiRequest("GET", "search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: String(min(limit, 10))),
        ], token: token)
        return try Self.parseSearch(await perform(request))
    }

    /// Exact ISRC lookup first, then a title/artist search that only accepts a confident match.
    public func findTrackURI(for track: RecognizedTrack, token: String) async throws -> String? {
        if let isrc = track.isrc, !isrc.isEmpty {
            let results = try await searchTracks(query: "isrc:\(isrc)", limit: 3, token: token)
            if let hit = SpotifyMatcher.bestMatch(for: track, in: results) ?? results.first {
                return hit.uri
            }
        }
        let title = SpotifyMatcher.searchTitle(track.title)
        let artist = SpotifyMatcher.primaryArtist(track.artist)
        let fielded = try await searchTracks(query: "track:\(title) artist:\(artist)", limit: 5, token: token)
        if let hit = SpotifyMatcher.bestMatch(for: track, in: fielded) {
            return hit.uri
        }
        let loose = try await searchTracks(query: "\(title) \(artist)", limit: 5, token: token)
        return SpotifyMatcher.bestMatch(for: track, in: loose)?.uri
    }

    // MARK: - Playlists

    public func createPlaylist(name: String, description: String, token: String) async throws -> SpotifyPlaylist {
        let request = try apiRequest("POST", "me/playlists", json: [
            "name": name,
            "description": description,
            "public": false,
        ], token: token)
        return try Self.parsePlaylist(await perform(request))
    }

    /// Replaces the playlist's contents with `uris` (in order).
    public func setPlaylistItems(_ playlistID: String, uris: [String], token: String) async throws {
        let chunks = stride(from: 0, to: uris.count, by: 100).map { Array(uris[$0..<min($0 + 100, uris.count)]) }
        try await sendItems("PUT", playlistID: playlistID, uris: chunks.first ?? [], token: token)
        for chunk in chunks.dropFirst() {
            try await sendItems("POST", playlistID: playlistID, uris: chunk, token: token)
        }
    }

    private func sendItems(_ method: String, playlistID: String, uris: [String], token: String) async throws {
        do {
            _ = try await perform(apiRequest(method, "playlists/\(playlistID)/items", json: ["uris": uris], token: token))
        } catch SpotifyError.http(405, _) {
            // Some accounts still only accept the pre-2026 path.
            _ = try await perform(apiRequest(method, "playlists/\(playlistID)/tracks", json: ["uris": uris], token: token))
        }
    }

    // MARK: - Plumbing

    func apiRequest(_ method: String, _ path: String, query: [URLQueryItem] = [], json: Any? = nil, token: String) throws -> URLRequest {
        var components = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    func perform(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            let (data, response) = try await HTTP.send(request)
            switch response.statusCode {
            case 200..<300:
                return data
            case 429 where attempt < 2:
                attempt += 1
                let wait = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
                try await Task.sleep(nanoseconds: UInt64(min(max(wait, 1), 30) * 1_000_000_000))
            case 429:
                throw SpotifyError.rateLimited
            case 401:
                throw SpotifyError.unauthorized
            case 403:
                throw SpotifyError.forbidden(Self.errorMessage(data) ?? "403")
            case 404:
                throw SpotifyError.notFound
            default:
                throw SpotifyError.http(response.statusCode, Self.errorMessage(data) ?? "unknown error")
            }
        }
    }

    // MARK: - Parsing

    static func parseTokens(_ data: Data, previous: SpotifyTokens?, now: Date = .now) throws -> SpotifyTokens {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? (json["expires_in"] as? Int).map(Double.init),
              let refresh = (json["refresh_token"] as? String) ?? previous?.refreshToken
        else { throw SpotifyError.invalidResponse }
        return SpotifyTokens(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(expiresIn))
    }

    static func parseSearch(_ data: Data) throws -> [SpotifyTrackResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracks = json["tracks"] as? [String: Any]
        else { throw SpotifyError.invalidResponse }
        let items = tracks["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let uri = item["uri"] as? String, let name = item["name"] as? String else { return nil }
            let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let isrc = (item["external_ids"] as? [String: Any])?["isrc"] as? String
            return SpotifyTrackResult(uri: uri, name: name, artists: artists, isrc: isrc)
        }
    }

    static func parsePlaylist(_ data: Data) throws -> SpotifyPlaylist {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String
        else { throw SpotifyError.invalidResponse }
        let url = ((json["external_urls"] as? [String: Any])?["spotify"] as? String).flatMap(URL.init(string:))
        return SpotifyPlaylist(id: id, url: url ?? URL(string: "https://open.spotify.com/playlist/\(id)"))
    }

    static func errorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return (json["error_description"] as? String) ?? (json["error"] as? String)
    }
}
