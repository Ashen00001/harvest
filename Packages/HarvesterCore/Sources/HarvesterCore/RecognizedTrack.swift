import Foundation

public struct RecognizedTrack: Codable, Hashable, Sendable {
    public var shazamKey: String
    public var title: String
    public var artist: String
    public var album: String?
    public var released: String?
    public var genre: String?
    public var isrc: String?
    public var coverArtURL: URL?
    public var coverArtHQURL: URL?
    public var shazamURL: URL?
    public var appleMusicID: String?
    public var previewURL: URL?

    public init(
        shazamKey: String,
        title: String,
        artist: String,
        album: String? = nil,
        released: String? = nil,
        genre: String? = nil,
        isrc: String? = nil,
        coverArtURL: URL? = nil,
        coverArtHQURL: URL? = nil,
        shazamURL: URL? = nil,
        appleMusicID: String? = nil,
        previewURL: URL? = nil
    ) {
        self.shazamKey = shazamKey
        self.title = title
        self.artist = artist
        self.album = album
        self.released = released
        self.genre = genre
        self.isrc = isrc
        self.coverArtURL = coverArtURL
        self.coverArtHQURL = coverArtHQURL
        self.shazamURL = shazamURL
        self.appleMusicID = appleMusicID
        self.previewURL = previewURL
    }

    var searchQuery: String { "\(title) \(artist)" }

    private var encodedQuery: String {
        searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
    }

    private var encodedPathQuery: String {
        searchQuery.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? searchQuery
    }

    /// Opens the Spotify app's search if installed.
    public var spotifyAppURL: URL? { URL(string: "spotify:search:\(encodedPathQuery)") }

    public var spotifyWebURL: URL? { URL(string: "https://open.spotify.com/search/\(encodedPathQuery)") }

    public var appleMusicURL: URL? {
        if let appleMusicID {
            return URL(string: "https://music.apple.com/us/song/\(appleMusicID)")
        }
        return URL(string: "https://music.apple.com/us/search?term=\(encodedQuery)")
    }

    public var youTubeMusicURL: URL? { URL(string: "https://music.youtube.com/search?q=\(encodedQuery)") }
}
