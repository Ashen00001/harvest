import Foundation
import Observation
import HarvesterCore

@MainActor
@Observable
final class HarvestStore {
    enum RecordOutcome {
        case new
        case repeatPlay
        case stillPlaying
    }

    private(set) var harvests: [Harvest] = []
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("harvests.json")
        load()
    }

    func harvest(id: UUID) -> Harvest? {
        harvests.first { $0.id == id }
    }

    func startHarvest(named name: String) -> UUID {
        let harvest = Harvest(id: UUID(), name: name, startedAt: .now, endedAt: nil, tracks: [])
        harvests.insert(harvest, at: 0)
        save()
        return harvest.id
    }

    func endHarvest(id: UUID) {
        mutate(id) { $0.endedAt = .now }
    }

    /// `isContinuation` means the previous match was this same song, i.e. it's still playing.
    func record(_ track: RecognizedTrack, in id: UUID, isContinuation: Bool) -> RecordOutcome {
        var outcome = RecordOutcome.new
        mutate(id) { harvest in
            if let index = harvest.tracks.firstIndex(where: { $0.id == track.shazamKey }) {
                harvest.tracks[index].lastHeard = .now
                if isContinuation {
                    outcome = .stillPlaying
                } else {
                    harvest.tracks[index].plays += 1
                    outcome = .repeatPlay
                }
            } else {
                harvest.tracks.append(HarvestedTrack(track: track, firstHeard: .now, lastHeard: .now, plays: 1))
            }
        }
        return outcome
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id) { $0.name = trimmed }
    }

    func removeTrack(_ trackID: String, from id: UUID) {
        mutate(id) { $0.tracks.removeAll { $0.id == trackID } }
    }

    func setSpotifyURIs(_ uris: [String: String], in id: UUID) {
        guard !uris.isEmpty else { return }
        mutate(id) { harvest in
            for index in harvest.tracks.indices {
                if let uri = uris[harvest.tracks[index].id] {
                    harvest.tracks[index].spotifyURI = uri
                }
            }
        }
    }

    func setSpotifyPlaylist(_ playlist: SpotifyPlaylist, in id: UUID) {
        mutate(id) {
            $0.spotifyPlaylistID = playlist.id
            $0.spotifyPlaylistURL = playlist.url
        }
    }

    func delete(_ id: UUID) {
        harvests.removeAll { $0.id == id }
        save()
    }

    private func mutate(_ id: UUID, _ change: (inout Harvest) -> Void) {
        guard let index = harvests.firstIndex(where: { $0.id == id }) else { return }
        change(&harvests[index])
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        harvests = (try? decoder.decode([Harvest].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(harvests) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
