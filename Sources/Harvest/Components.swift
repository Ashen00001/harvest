import HarvesterCore
import SwiftUI

struct ArtworkView: View {
    var url: URL?
    var size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient.harvest
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }
}

struct TrackRow: View {
    var item: HarvestedTrack

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: item.track.coverArtURL, size: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(item.track.artist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts = ["Heard \(item.firstHeard.formatted(date: .omitted, time: .shortened))"]
        if item.plays > 1 { parts.append("played \(item.plays)×") }
        return parts.joined(separator: " · ")
    }
}

struct PulseView: View {
    var level: Float

    var body: some View {
        let energy = CGFloat(min(1, Double(level).squareRoot() * 4))
        ZStack {
            Circle()
                .fill(Color.harvestAccent.opacity(0.14))
                .scaleEffect(0.62 + 0.38 * energy)
            Circle()
                .fill(Color.harvestAccent.opacity(0.28))
                .scaleEffect(0.48 + 0.26 * energy)
            Circle()
                .fill(LinearGradient.harvest)
                .scaleEffect(0.4)
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
        }
        .animation(.easeOut(duration: 0.15), value: energy)
    }
}

struct NowPlayingCard: View {
    var track: RecognizedTrack

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(url: track.coverArtHQURL ?? track.coverArtURL, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text("Last identified")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.harvestAccent)
                    .textCase(.uppercase)
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(track.artist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let album = track.album {
                    Text([album, track.released].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct HarvestRow: View {
    var harvest: Harvest
    var isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            CoverStack(urls: harvest.tracks.suffix(3).reversed().map { $0.track.coverArtURL })
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(harvest.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if isActive {
                        Text("LIVE")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text("\(harvest.tracks.count) \(harvest.tracks.count == 1 ? "song" : "songs") · \(harvest.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CoverStack: View {
    var urls: [URL?]

    var body: some View {
        ZStack(alignment: .leading) {
            if urls.isEmpty {
                ArtworkView(url: nil, size: 48)
            }
            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                ArtworkView(url: url, size: 48)
                    .overlay(RoundedRectangle(cornerRadius: 48 * 0.18, style: .continuous).stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    .offset(x: CGFloat(index) * 10)
                    .zIndex(Double(urls.count - index))
            }
        }
        .frame(width: 48 + CGFloat(max(0, urls.count - 1)) * 10, alignment: .leading)
    }
}

struct EmptyHarvestsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(LinearGradient.harvest)
            Text("No harvests yet")
                .font(.headline)
            Text("At a café, a party, a store with a good playlist — tap Start harvesting and Harvest will identify every song it hears and build the list for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
