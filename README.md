# Harvest

**Steal the playlist.** Harvest is an iPhone app for when you're somewhere with great music: a café, a party, a store. Start a harvest, put your phone on the table, and it identifies every song it hears and builds the list for you. Then send it to Spotify as a playlist in one tap.

- Listens in the background (screen locked is fine) and checks every 30 s
- Fingerprints audio **on-device**; only the fingerprint is sent to identify the song, never the audio
- Knows the difference between a new song, one that's still playing, and a replay
- One-tap **Export to Spotify** (private playlist; re-exporting updates the same one)
- Open any song in Spotify, Apple Music, YouTube Music or Shazam; export as text or CSV

## Requirements

- Mac with **Xcode 16 or newer**
- iPhone on **iOS 17 or newer**
- An Apple ID (the free Personal Team works; apps signed with it expire after 7 days)
- Optional: Spotify Premium + a Spotify developer app for playlist export

## Build and run with Xcode

1. Clone the repo and open **`Harvest.xcodeproj`**. Xcode resolves the local `HarvesterCore` package automatically.
2. Select the **Harvest** target → **Signing & Capabilities** → pick your **Team**. If Xcode says the bundle ID is taken, change `com.ashen.Harvest` to something unique.
3. Plug in your iPhone, select it as the run destination, and press **Run** (⌘R).
4. First time on the phone: **Settings → Privacy & Security → Developer Mode → On**, then **Settings → General → VPN & Device Management** → trust your developer certificate.

Background audio and the microphone prompt are configured in `Support/Info.plist`. No extra capabilities or entitlements are needed.

## Spotify export

Detail screen → **⋯ → Export to Spotify**. The first time, Spotify's own login page appears (OAuth with PKCE). The app only requests `playlist-modify-private` and `playlist-modify-public`, and the token is stored in the iOS Keychain.

Songs are matched by **ISRC** first, then by a title + artist search that only accepts a confident match (so you won't get karaoke covers). Anything Spotify doesn't have is listed afterwards.

**Using your own Spotify app** (needed if you fork this):

1. [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) → **Create app**
2. Redirect URI: `harvest://spotify-callback`, API: **Web API**
3. Put your Client ID in `Sources/Harvest/SpotifyAccount.swift` (`clientID`). It's a public identifier, not a secret.
4. Under **User Management**, add the Spotify accounts that will use it. Spotify's development-mode rules (Feb 2026): the owner needs Premium, and the app is limited to 5 users.

No Spotify? **⋯ → Copy song list** gives `Title - Artist` lines you can paste into TuneMyMusic or Soundiiz.

## How it works

| Piece | What it does |
|---|---|
| `AudioCapture` | Keeps the mic running for the whole harvest (iOS won't let an app *start* recording from the background) and holds the last 12 s in a ring buffer |
| `HarvestEngine` | Every interval: snapshot → resample to 16 kHz mono → fingerprint → identify → record |
| `HarvesterCore` (Swift package) | Platform-independent: Swift port of [SongRec](https://github.com/marin-m/SongRec)'s Shazam fingerprint algorithm, Shazam client, Spotify client + matcher |
| `HarvestStore` | Harvests saved as JSON in Application Support |
| `Tools/` | Python reference fingerprinter (verified against live Shazam) and the generator for the golden test fixtures |

Recognition goes through Shazam's public web endpoint (the same one SongRec and shazamio use) rather than ShazamKit, because ShazamKit has to be enabled on a paid developer account. With a paid account, swapping in ShazamKit would mean replacing `ShazamClient`.

## Tests

`HarvesterCore` builds and tests on macOS and Linux:

```bash
cd Packages/HarvesterCore
swift test
# optional live check against Shazam with a 16 kHz mono s16le clip:
HARVEST_LIVE_CLIP=/path/to/clip.raw swift test --filter liveRecognition
```

The fingerprint generator is checked byte-for-byte against the Python reference in `Tools/`.

## Limitations

- **Phone placement matters.** In a pocket the mic is muffled; face up on a table works best.
- DJ mixes, live sets, remixes and heavy crowd noise often won't match.
- Phone calls, Siri or recording video take the mic and pause harvesting. Open the app to resume.
- The Shazam endpoint is unofficial and could change. `ShazamClient.swift` is the only file to update.
- Free Apple ID builds expire after 7 days. Rebuild from Xcode to renew; your harvests are kept.

## No Mac? Build with xtool

The project also builds from Windows (WSL) or Linux with [xtool](https://github.com/xtool-org/xtool), using the root `Package.swift` and `xtool.yml`:

1. Windows: run `setup/1-windows-setup.ps1` as admin (installs WSL, mirrored networking, Apple Devices), then reboot
2. In Ubuntu: `bash setup/2-wsl-setup.sh` (Swift 6.4, xtool, runs the core tests)
3. `xtool setup` (Apple ID + Xcode `.xip` for the iOS SDK)
4. `bash setup/run.sh` to build a release build and install it on the connected iPhone

xtool's password login uses Apple's private APIs, which is one reason Xcode is the recommended path.

---

Not affiliated with Shazam, Apple or Spotify.
