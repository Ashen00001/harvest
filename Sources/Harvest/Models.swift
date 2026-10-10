import Foundation
import HarvesterCore

struct HarvestedTrack: Identifiable, Codable, Hashable, Sendable {
    var track: RecognizedTrack
    var firstHeard: Date
    var lastHeard: Date
    var plays: Int
    var spotifyURI: String? = nil

    var id: String { track.shazamKey }
}

struct Harvest: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var tracks: [HarvestedTrack]
    var spotifyPlaylistID: String? = nil
    var spotifyPlaylistURL: URL? = nil
}
