import SwiftUI

@main
struct HarvestApp: App {
    @State private var store: HarvestStore
    @State private var engine: HarvestEngine
    @State private var spotify = SpotifyAccount()

    init() {
        let store = HarvestStore()
        _store = State(initialValue: store)
        _engine = State(initialValue: HarvestEngine(store: store))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(engine)
                .environment(spotify)
                .tint(Color.harvestAccent)
        }
    }
}

extension Color {
    static let harvestAccent = Color(red: 0.96, green: 0.52, blue: 0.18)
    static let harvestDeep = Color(red: 0.42, green: 0.16, blue: 0.55)
}

extension LinearGradient {
    static let harvest = LinearGradient(
        colors: [.harvestAccent, .harvestDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
