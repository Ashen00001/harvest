import Foundation
import Testing
@testable import HarvesterCore

@Suite struct ShazamClientTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func parsesMatch() throws {
        let result = try ShazamClient.parse(fixture("shazam-match-response"))
        guard case .match(let track) = result else {
            Issue.record("expected a match, got \(result)")
            return
        }
        #expect(track.shazamKey == "357027")
        #expect(track.title == "Never Gonna Give You Up")
        #expect(track.artist == "Rick Astley")
        #expect(track.album == "Whenever You Need Somebody")
        #expect(track.released == "1987")
        #expect(track.isrc == "GBARL9300135")
        #expect(track.appleMusicID == "1559885421")
        #expect(track.coverArtURL != nil)
        #expect(track.previewURL?.absoluteString.hasSuffix(".m4a") == true)
        #expect(track.appleMusicURL?.absoluteString == "https://music.apple.com/us/song/1559885421")
        #expect(track.spotifyAppURL?.absoluteString == "spotify:search:Never%20Gonna%20Give%20You%20Up%20Rick%20Astley")
    }

    @Test func parsesNoMatch() throws {
        #expect(try ShazamClient.parse(fixture("shazam-nomatch-response")) == .noMatch)
    }

    @Test func requestShape() throws {
        let signature = ShazamSignature(numberOfSamples: 16000 * 12, peaksByBand: [[], [], [], []])
        let request = try ShazamClient(timeZone: "America/Los_Angeles").makeRequest(signature)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "amp.shazam.com")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sig = try #require(json["signature"] as? [String: Any])
        #expect(sig["samplems"] as? Int == 12000)
        #expect((sig["uri"] as? String)?.hasPrefix(ShazamSignature.uriPrefix) == true)
    }

    /// Hits the real Shazam API. Run with HARVEST_LIVE_CLIP=/path/to/16k-mono-s16le.raw swift test
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HARVEST_LIVE_CLIP"] != nil))
    func liveRecognition() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["HARVEST_LIVE_CLIP"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        let result = try await ShazamClient().recognize(SignatureGenerator.makeSignature(samples: samples))
        guard case .match(let track) = result else {
            Issue.record("no match")
            return
        }
        print("LIVE MATCH:", track.title, "-", track.artist)
    }
}
