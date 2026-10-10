import AuthenticationServices
import HarvesterCore
import SwiftUI
import UIKit

struct HarvestDetailView: View {
    let harvestID: UUID

    @Environment(HarvestStore.self) private var store
    @Environment(HarvestEngine.self) private var engine
    @Environment(SpotifyAccount.self) private var spotify
    @Environment(\.openURL) private var openURL
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var selected: HarvestedTrack?
    @State private var renaming = false
    @State private var newName = ""
    @State private var toast: String?
    @State private var exportResult: SpotifyAccount.ExportResult?
    @State private var exportError: String?

    var body: some View {
        if let harvest = store.harvest(id: harvestID) {
            content(harvest)
        } else {
            ContentUnavailableView("Harvest deleted", systemImage: "trash")
        }
    }

    private func content(_ harvest: Harvest) -> some View {
        List {
            Section {
                summary(harvest)
                if let url = harvest.spotifyPlaylistURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open playlist in Spotify", systemImage: "arrow.up.right.square")
                    }
                }
            }

            Section {
                if harvest.tracks.isEmpty {
                    Text(harvest.id == engine.activeHarvestID ? "Listening — songs will show up here." : "No songs were identified.")
                        .foregroundStyle(.secondary)
                }
                ForEach(harvest.tracks) { item in
                    Button {
                        selected = item
                    } label: {
                        TrackRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let ids = offsets.map { harvest.tracks[$0].id }
                    for id in ids {
                        store.removeTrack(id, from: harvestID)
                    }
                }
            } header: {
                if !harvest.tracks.isEmpty {
                    Text("Songs")
                }
            } footer: {
                if !harvest.tracks.isEmpty {
                    Text("⋯ → Export to Spotify makes a private playlist. Exporting again updates the same playlist.")
                }
            }
        }
        .navigationTitle(harvest.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                menu(harvest)
            }
        }
        .confirmationDialog(
            selected?.track.title ?? "",
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            titleVisibility: .visible,
            presenting: selected
        ) { item in
            Button("Open in Spotify") { openInSpotify(item.track) }
            if let url = item.track.appleMusicURL {
                Button("Open in Apple Music") { openURL(url) }
            }
            if let url = item.track.youTubeMusicURL {
                Button("Open in YouTube Music") { openURL(url) }
            }
            if let url = item.track.shazamURL {
                Button("View on Shazam") { openURL(url) }
            }
            Button("Copy title") {
                UIPasteboard.general.string = "\(item.track.title) - \(item.track.artist)"
                show("Copied")
            }
        } message: { item in
            Text(item.track.artist)
        }
        .alert("Rename harvest", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { store.rename(harvestID, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toast)
        .overlay {
            if spotify.isExporting {
                exportProgress
            }
        }
        .alert(
            exportResult?.updatedExisting == true ? "Playlist updated" : "Playlist created",
            isPresented: Binding(get: { exportResult != nil }, set: { if !$0 { exportResult = nil } }),
            presenting: exportResult
        ) { result in
            if let url = result.playlistURL {
                Button("Open in Spotify") { openURL(url) }
            }
            Button("Done", role: .cancel) {}
        } message: { result in
            Text(exportSummary(result))
        }
        .alert("Spotify export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func summary(_ harvest: Harvest) -> some View {
        HStack(spacing: 14) {
            CoverStack(urls: harvest.tracks.prefix(3).map { $0.track.coverArtURL })
            VStack(alignment: .leading, spacing: 3) {
                Text("\(harvest.tracks.count) \(harvest.tracks.count == 1 ? "song" : "songs")")
                    .font(.title3.weight(.bold))
                Text(timeRange(harvest))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func menu(_ harvest: Harvest) -> some View {
        Menu {
            Button {
                Task { await exportToSpotify(harvest) }
            } label: {
                Label(harvest.spotifyPlaylistID == nil ? "Export to Spotify" : "Update Spotify playlist", systemImage: "music.note.list")
            }
            .disabled(harvest.tracks.isEmpty || spotify.isExporting)
            Divider()
            Button {
                UIPasteboard.general.string = Exporter.songList(for: harvest)
                show("Copied \(harvest.tracks.count) songs")
            } label: {
                Label("Copy song list", systemImage: "doc.on.doc")
            }
            ShareLink(item: Exporter.songList(for: harvest)) {
                Label("Share song list", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: CSVExport(harvest: harvest), preview: SharePreview("\(harvest.name).csv")) {
                Label("Export CSV", systemImage: "tablecells")
            }
            Divider()
            Button {
                openURL(Exporter.tuneMyMusicURL)
            } label: {
                Label("Open TuneMyMusic", systemImage: "arrow.up.right.square")
            }
            Button {
                newName = harvest.name
                renaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(harvest.tracks.isEmpty && harvest.id != engine.activeHarvestID)
    }

    private func timeRange(_ harvest: Harvest) -> String {
        let start = harvest.startedAt.formatted(date: .abbreviated, time: .shortened)
        guard let end = harvest.endedAt else {
            return harvest.id == engine.activeHarvestID ? "\(start) · live now" : start
        }
        let minutes = Int(end.timeIntervalSince(harvest.startedAt) / 60)
        let duration = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        return "\(start) · \(duration)"
    }

    private var exportProgress: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(spotify.exportDone), total: Double(max(spotify.exportTotal, 1)))
            Text("Matching songs on Spotify… \(spotify.exportDone)/\(spotify.exportTotal)")
                .font(.subheadline.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func exportToSpotify(_ harvest: Harvest) async {
        do {
            if !spotify.isConnected {
                try await spotify.connect(using: webAuthenticationSession)
            }
            exportResult = try await spotify.export(harvest, store: store)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // backed out of the Spotify login sheet
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportSummary(_ result: SpotifyAccount.ExportResult) -> String {
        var text = "\(result.added) \(result.added == 1 ? "song" : "songs") in “\(result.playlistName)”."
        if !result.missing.isEmpty {
            let names = result.missing.prefix(5).map { "\($0.track.title) – \($0.track.artist)" }
            let more = result.missing.count > 5 ? "\n+\(result.missing.count - 5) more" : ""
            text += "\n\nNot found on Spotify:\n" + names.joined(separator: "\n") + more
        }
        return text
    }

    private func openInSpotify(_ track: RecognizedTrack) {
        guard let appURL = track.spotifyAppURL else { return }
        openURL(appURL) { accepted in
            if !accepted, let web = track.spotifyWebURL {
                openURL(web)
            }
        }
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == message { toast = nil }
        }
    }
}
