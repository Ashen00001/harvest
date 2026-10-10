import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @AppStorage("checkInterval") private var interval: Double = 30
    @AppStorage("notifyNewSongs") private var notifyNewSongs = true
    @Environment(\.dismiss) private var dismiss
    @Environment(SpotifyAccount.self) private var spotify
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var spotifyError: String?

    private let intervals: [Double] = [15, 30, 45, 60, 120]

    private func connectSpotify() async {
        do {
            try await spotify.connect(using: webAuthenticationSession)
            spotifyError = nil
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // backed out of the login sheet
        } catch {
            spotifyError = error.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Check every", selection: $interval) {
                        ForEach(intervals, id: \.self) { value in
                            Text(value < 60 ? "\(Int(value)) seconds" : value == 60 ? "1 minute" : "\(Int(value / 60)) minutes").tag(value)
                        }
                    }
                } footer: {
                    Text("Each check identifies the last 12 seconds of audio. Shorter intervals catch more songs but use more battery and data.")
                }

                Section {
                    Toggle("Notify for new songs", isOn: $notifyNewSongs)
                } footer: {
                    Text("Sends a notification when a new song is added while Harvest is in the background.")
                }

                Section {
                    if spotify.isConnected {
                        Label("Connected to Spotify", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Disconnect Spotify", role: .destructive) {
                            spotify.disconnect()
                        }
                    } else {
                        Button {
                            Task { await connectSpotify() }
                        } label: {
                            Label("Connect Spotify", systemImage: "link")
                        }
                    }
                } header: {
                    Text("Spotify")
                } footer: {
                    Text(spotifyError ?? "Harvest can only create and edit playlists. It can't see your listening history.")
                }

                Section("How it works") {
                    Text("Harvest keeps the mic on while a harvest is running and fingerprints what it hears on-device. Only the fingerprint is sent to Shazam to identify the song — no audio leaves your phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    Text("Song recognition uses Shazam's public web endpoint. Not affiliated with Shazam or Apple.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
