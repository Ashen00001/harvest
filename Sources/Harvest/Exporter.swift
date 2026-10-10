import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum Exporter {
    static let tuneMyMusicURL = URL(string: "https://www.tunemymusic.com/transfer")!

    /// One "Title - Artist" per line, the format TuneMyMusic and Soundiiz accept as pasted text.
    static func songList(for harvest: Harvest) -> String {
        harvest.tracks.map { "\($0.track.title) - \($0.track.artist)" }.joined(separator: "\n")
    }

    static func csv(for harvest: Harvest) -> String {
        let header = "Title,Artist,Album,Released,Genre,ISRC,First heard,Plays,Apple Music,Shazam"
        let rows = harvest.tracks.map { item -> String in
            let t = item.track
            return [
                t.title,
                t.artist,
                t.album ?? "",
                t.released ?? "",
                t.genre ?? "",
                t.isrc ?? "",
                item.firstHeard.formatted(.iso8601),
                String(item.plays),
                t.appleMusicURL?.absoluteString ?? "",
                t.shazamURL?.absoluteString ?? "",
            ].map(escape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct CSVExport: Transferable {
    var harvest: Harvest

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(Exporter.csv(for: export.harvest).utf8)
        }
        .suggestedFileName("Harvest.csv")
    }
}
