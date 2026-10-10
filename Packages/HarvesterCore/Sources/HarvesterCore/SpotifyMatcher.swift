import Foundation

/// Decides whether a Spotify search result is really the song Shazam heard.
public enum SpotifyMatcher {
    public static func bestMatch(for track: RecognizedTrack, in results: [SpotifyTrackResult]) -> SpotifyTrackResult? {
        if let isrc = track.isrc, let exact = results.first(where: { $0.isrc == isrc }) {
            return exact
        }
        let wantTitle = normalize(track.title)
        let wantArtist = normalize(primaryArtist(track.artist))
        guard !wantTitle.isEmpty, !wantArtist.isEmpty else { return nil }

        var best: (score: Int, result: SpotifyTrackResult)?
        for result in results {
            let artists = result.artists.map(normalize)
            guard artists.contains(where: { $0 == wantArtist || $0.contains(wantArtist) || wantArtist.contains($0) && !$0.isEmpty }) else {
                continue
            }
            let title = normalize(result.name)
            let score: Int
            if title == wantTitle {
                score = 2
            } else if title.contains(wantTitle) || wantTitle.contains(title) && !title.isEmpty {
                score = 1
            } else {
                continue
            }
            if best == nil || score > best!.score {
                best = (score, result)
            }
        }
        return best?.result
    }

    /// Title without "(feat. …)", "[Remastered]", " - Radio Edit" etc., for searching.
    public static func searchTitle(_ title: String) -> String {
        var t = title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        if let dash = t.range(of: " - ") {
            t = String(t[..<dash.lowerBound])
        }
        for marker in [" feat. ", " feat ", " ft. ", " featuring "] {
            if let range = t.range(of: marker, options: .caseInsensitive) {
                t = String(t[..<range.lowerBound])
            }
        }
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// "Calvin Harris & Dua Lipa" -> "Calvin Harris"
    public static func primaryArtist(_ artist: String) -> String {
        var a = artist
        for separator in [" & ", ", ", " feat. ", " feat ", " ft. ", " x ", " X ", " and ", " with "] {
            if let range = a.range(of: separator, options: .caseInsensitive) {
                a = String(a[..<range.lowerBound])
            }
        }
        return a.trimmingCharacters(in: .whitespaces)
    }

    static func normalize(_ text: String) -> String {
        let folded = searchTitle(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "&", with: "and")
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }
}
