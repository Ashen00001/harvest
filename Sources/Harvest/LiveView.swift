import HarvesterCore
import SwiftUI

struct LiveView: View {
    @Environment(HarvestStore.self) private var store
    @Environment(HarvestEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    private var harvest: Harvest? {
        engine.activeHarvestID.flatMap { store.harvest(id: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    PulseView(level: engine.level)
                        .frame(width: 190, height: 190)
                        .padding(.top, 8)

                    status

                    if let track = engine.lastMatch {
                        NowPlayingCard(track: track)
                    }

                    if let harvest, !harvest.tracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Collected · \(harvest.tracks.count)")
                                .font(.headline)
                            ForEach(harvest.tracks.reversed()) { item in
                                TrackRow(item: item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                controls
            }
            .navigationTitle(harvest?.name ?? "Harvest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hide") { dismiss() }
                }
            }
            .onChange(of: engine.isRunning) { _, running in
                if !running { dismiss() }
            }
        }
    }

    private var status: some View {
        VStack(spacing: 6) {
            Text(engine.statusMessage)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdown(at: context.date))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Keep Harvest open or lock your screen — it keeps listening in the background.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private func countdown(at date: Date) -> String {
        switch engine.phase {
        case .identifying:
            return "Matching with Shazam…"
        case .idle:
            return ""
        case .warmingUp, .listening:
            guard let next = engine.nextCheck else { return "" }
            let seconds = max(0, Int(next.timeIntervalSince(date).rounded(.up)))
            return "Next check in \(seconds)s · \(engine.checksDone) checks so far"
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                engine.checkNow()
            } label: {
                Label("Check now", systemImage: "sparkle.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(engine.phase == .identifying)

            Button(role: .destructive) {
                engine.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
