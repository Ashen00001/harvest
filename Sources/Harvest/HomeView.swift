import HarvesterCore
import SwiftUI

struct HomeView: View {
    @Environment(HarvestStore.self) private var store
    @Environment(HarvestEngine.self) private var engine

    @State private var showingNamePrompt = false
    @State private var newName = ""
    @State private var showingLive = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if let id = engine.activeHarvestID, let harvest = store.harvest(id: id) {
                    Section {
                        Button {
                            showingLive = true
                        } label: {
                            activeBanner(harvest)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    if store.harvests.isEmpty {
                        EmptyHarvestsView()
                            .listRowBackground(Color.clear)
                    }
                    ForEach(store.harvests) { harvest in
                        NavigationLink(value: harvest.id) {
                            HarvestRow(harvest: harvest, isActive: harvest.id == engine.activeHarvestID)
                        }
                        .deleteDisabled(harvest.id == engine.activeHarvestID)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.harvests[$0].id }
                        for id in ids {
                            store.delete(id)
                        }
                    }
                } header: {
                    if !store.harvests.isEmpty {
                        Text("Your harvests")
                    }
                }
            }
            .navigationTitle("Harvest")
            .navigationDestination(for: UUID.self) { id in
                HarvestDetailView(harvestID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                startButton
            }
            .alert("Name this harvest", isPresented: $showingNamePrompt) {
                TextField("Where are you?", text: $newName)
                Button("Start") { start() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Like \"Victor's Coffee\" — you can rename it later.")
            }
            .alert("Can't start harvesting", isPresented: errorShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(engine.errorMessage ?? "")
            }
            .fullScreenCover(isPresented: $showingLive) {
                LiveView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )
    }

    private func activeBanner(_ harvest: Harvest) -> some View {
        HStack(spacing: 14) {
            PulseView(level: engine.level)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Harvesting now")
                    .font(.headline)
                Text("\(harvest.tracks.count) \(harvest.tracks.count == 1 ? "song" : "songs") · \(engine.statusMessage)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var startButton: some View {
        Button {
            if engine.isRunning {
                showingLive = true
            } else {
                newName = ""
                showingNamePrompt = true
            }
        } label: {
            Label(engine.isRunning ? "Back to live harvest" : "Start harvesting", systemImage: engine.isRunning ? "waveform" : "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func start() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Harvest · \(Date.now.formatted(date: .abbreviated, time: .shortened))" : trimmed
        Task {
            await engine.start(name: name)
            if engine.isRunning {
                showingLive = true
            }
        }
    }
}
