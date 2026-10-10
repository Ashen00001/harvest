import AuthenticationServices
import CryptoKit
import Foundation
import HarvesterCore
import Observation

@MainActor
@Observable
final class SpotifyAccount {
    struct ExportResult {
        var playlistName: String
        var playlistURL: URL?
        var added: Int
        var missing: [HarvestedTrack]
        var updatedExisting: Bool
    }

    static let clientID = "1595680016eb436597d77967bcc66bd3"
    static let redirectURI = "harvest://spotify-callback"
    private static let keychainAccount = "spotify-tokens"

    private(set) var isConnected = false
    private(set) var isExporting = false
    private(set) var exportDone = 0
    private(set) var exportTotal = 0

    private let client = SpotifyClient(clientID: SpotifyAccount.clientID, redirectURI: SpotifyAccount.redirectURI)
    @ObservationIgnored private var tokens: SpotifyTokens?

    init() {
        if let data = Keychain.load(account: Self.keychainAccount) {
            tokens = try? JSONDecoder().decode(SpotifyTokens.self, from: data)
        }
        isConnected = tokens != nil
    }

    // MARK: - Login (PKCE)

    func connect(using session: WebAuthenticationSession) async throws {
        let verifier = Self.randomVerifier()
        let state = UUID().uuidString
        let url = client.authorizationURL(codeChallenge: Self.challenge(for: verifier), state: state)

        let callback = try await session.authenticate(using: url, callbackURLScheme: "harvest", preferredBrowserSession: .shared)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw SpotifyError.authorizationFailed(error == "access_denied" ? "you cancelled" : error)
        }
        guard value("state") == state, let code = value("code") else {
            throw SpotifyError.authorizationFailed("Spotify didn't send back a login code")
        }
        save(try await client.exchangeCode(code, verifier: verifier))
    }

    func disconnect() {
        Keychain.delete(account: Self.keychainAccount)
        tokens = nil
        isConnected = false
    }

    private func save(_ newTokens: SpotifyTokens) {
        tokens = newTokens
        if let data = try? JSONEncoder().encode(newTokens) {
            Keychain.save(data, account: Self.keychainAccount)
        }
        isConnected = true
    }

    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw SpotifyError.unauthorized }
        guard forceRefresh || current.isExpired else { return current.accessToken }
        do {
            let refreshed = try await client.refresh(current)
            save(refreshed)
            return refreshed.accessToken
        } catch SpotifyError.unauthorized {
            disconnect()
            throw SpotifyError.unauthorized
        }
    }

    // MARK: - Export

    /// Creates (or refreshes) a private playlist mirroring the harvest's song list.
    func export(_ harvest: Harvest, store: HarvestStore) async throws -> ExportResult {
        isExporting = true
        exportDone = 0
        exportTotal = harvest.tracks.count
        defer { isExporting = false }

        do {
            return try await performExport(harvest, store: store, token: accessToken())
        } catch SpotifyError.unauthorized {
            // Access token was rejected early; refresh once and retry.
            return try await performExport(harvest, store: store, token: accessToken(forceRefresh: true))
        }
    }

    private func performExport(_ harvest: Harvest, store: HarvestStore, token: String) async throws -> ExportResult {
        var uris: [String] = []
        var missing: [HarvestedTrack] = []
        var newMatches: [String: String] = [:]

        exportDone = 0
        for item in harvest.tracks {
            if let cached = item.spotifyURI {
                uris.append(cached)
            } else if let uri = try await client.findTrackURI(for: item.track, token: token) {
                uris.append(uri)
                newMatches[item.id] = uri
            } else {
                missing.append(item)
            }
            exportDone += 1
        }
        store.setSpotifyURIs(newMatches, in: harvest.id)

        var seen = Set<String>()
        let unique = uris.filter { seen.insert($0).inserted }

        if let existingID = harvest.spotifyPlaylistID {
            do {
                try await client.setPlaylistItems(existingID, uris: unique, token: token)
                return ExportResult(playlistName: harvest.name, playlistURL: harvest.spotifyPlaylistURL, added: unique.count, missing: missing, updatedExisting: true)
            } catch SpotifyError.notFound {
                // Deleted on Spotify's side; fall through and make a new one.
            }
        }

        let started = harvest.startedAt.formatted(date: .abbreviated, time: .shortened)
        let playlist = try await client.createPlaylist(
            name: harvest.name,
            description: "Harvested \(started) with Harvest.",
            token: token
        )
        store.setSpotifyPlaylist(playlist, in: harvest.id)
        try await client.setPlaylistItems(playlist.id, uris: unique, token: token)
        return ExportResult(playlistName: harvest.name, playlistURL: playlist.url, added: unique.count, missing: missing, updatedExisting: false)
    }

    // MARK: - PKCE helpers

    private static func randomVerifier() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<64).map { _ in alphabet.randomElement(using: &generator)! })
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
