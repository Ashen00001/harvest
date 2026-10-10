import Foundation
import Testing
@testable import HarvesterCore

@Suite struct SpotifyTests {
    let client = SpotifyClient(clientID: "abc123", redirectURI: "harvest://spotify-callback")

    private func result(_ name: String, _ artists: [String], isrc: String? = nil) -> SpotifyTrackResult {
        SpotifyTrackResult(uri: "spotify:track:\(name.hashValue)", name: name, artists: artists, isrc: isrc)
    }

    @Test func authorizationURL() throws {
        let url = client.authorizationURL(codeChallenge: "CHAL", state: "STATE")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let q = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "accounts.spotify.com")
        #expect(url.path == "/authorize")
        #expect(q["client_id"] == "abc123")
        #expect(q["response_type"] == "code")
        #expect(q["redirect_uri"] == "harvest://spotify-callback")
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["code_challenge"] == "CHAL")
        #expect(q["state"] == "STATE")
        #expect(q["scope"] == "playlist-modify-private playlist-modify-public")
    }

    @Test func tokenRequestIsFormEncoded() throws {
        let request = client.tokenRequest([("redirect_uri", "harvest://spotify-callback"), ("code", "a b+c")])
        #expect(request.url?.absoluteString == "https://accounts.spotify.com/api/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body == "redirect_uri=harvest%3A%2F%2Fspotify-callback&code=a%20b%2Bc")
    }

    @Test func parsesTokens() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fresh = try SpotifyClient.parseTokens(Data(#"{"access_token":"AT","token_type":"Bearer","expires_in":3600,"refresh_token":"RT","scope":"x"}"#.utf8), previous: nil, now: now)
        #expect(fresh == SpotifyTokens(accessToken: "AT", refreshToken: "RT", expiresAt: now.addingTimeInterval(3600)))

        // Refresh responses may omit refresh_token: keep the old one.
        let refreshed = try SpotifyClient.parseTokens(Data(#"{"access_token":"AT2","expires_in":3600}"#.utf8), previous: fresh, now: now)
        #expect(refreshed.refreshToken == "RT")
        #expect(refreshed.accessToken == "AT2")
    }

    @Test func parsesSearchAndPlaylist() throws {
        let search = #"{"tracks":{"items":[{"uri":"spotify:track:0VjIjW4GlUZAMYd2vXMi3b","name":"Blinding Lights","artists":[{"name":"The Weeknd"}],"external_ids":{"isrc":"USUG11904206"}}],"total":1}}"#
        let results = try SpotifyClient.parseSearch(Data(search.utf8))
        #expect(results == [SpotifyTrackResult(uri: "spotify:track:0VjIjW4GlUZAMYd2vXMi3b", name: "Blinding Lights", artists: ["The Weeknd"], isrc: "USUG11904206")])

        let playlist = try SpotifyClient.parsePlaylist(Data(#"{"id":"PL1","external_urls":{"spotify":"https://open.spotify.com/playlist/PL1"}}"#.utf8))
        #expect(playlist == SpotifyPlaylist(id: "PL1", url: URL(string: "https://open.spotify.com/playlist/PL1")))
    }

    @Test func errorMessages() {
        #expect(SpotifyClient.errorMessage(Data(#"{"error":{"status":403,"message":"Forbidden"}}"#.utf8)) == "Forbidden")
        #expect(SpotifyClient.errorMessage(Data(#"{"error":"invalid_grant","error_description":"Invalid refresh token"}"#.utf8)) == "Invalid refresh token")
    }

    @Test func apiRequestShape() throws {
        let request = try client.apiRequest("POST", "playlists/PL1/items", json: ["uris": ["spotify:track:1"]], token: "TOK")
        #expect(request.url?.absoluteString == "https://api.spotify.com/v1/playlists/PL1/items")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer TOK")
        let json = try #require(try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: [String]])
        #expect(json["uris"] == ["spotify:track:1"])
    }

    @Test func titleAndArtistCleanup() {
        #expect(SpotifyMatcher.searchTitle("Don't Start Now (feat. Someone) [Remastered]") == "Don't Start Now")
        #expect(SpotifyMatcher.searchTitle("Bohemian Rhapsody - Remastered 2011") == "Bohemian Rhapsody")
        #expect(SpotifyMatcher.searchTitle("(I Can't Get No) Satisfaction") == "Satisfaction")
        #expect(SpotifyMatcher.primaryArtist("Calvin Harris & Dua Lipa") == "Calvin Harris")
        #expect(SpotifyMatcher.primaryArtist("Drake Feat. Rihanna") == "Drake")
        #expect(SpotifyMatcher.primaryArtist("Lil Nas X") == "Lil Nas X")
        #expect(SpotifyMatcher.normalize("Beyoncé") == "beyonce")
    }

    @Test func matcherPicksTheRightSong() {
        let heard = RecognizedTrack(shazamKey: "1", title: "One Kiss", artist: "Calvin Harris & Dua Lipa")
        let candidates = [
            result("One Kiss - Instrumental", ["Some Cover Band"]),
            result("One Kiss (with Dua Lipa)", ["Calvin Harris", "Dua Lipa"]),
            result("Kiss", ["Calvin Harris"]),
        ]
        #expect(SpotifyMatcher.bestMatch(for: heard, in: candidates)?.name == "One Kiss (with Dua Lipa)")

        let wrongArtist = [result("One Kiss", ["Karaoke Kings"])]
        #expect(SpotifyMatcher.bestMatch(for: heard, in: wrongArtist) == nil)

        var withISRC = heard
        withISRC.isrc = "GBARL1800368"
        let isrcHit = [result("Something Else", ["X"]), result("One Kiss", ["Calvin Harris"], isrc: "GBARL1800368")]
        #expect(SpotifyMatcher.bestMatch(for: withISRC, in: isrcHit)?.isrc == "GBARL1800368")
    }
}
