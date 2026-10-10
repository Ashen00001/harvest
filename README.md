# Harvest

Passive playlist harvester for iPhone. Start a harvest at a café, party or store. It listens in the background, identifies every song, and builds the list for you.

## How it works

- `AudioCapture` keeps the mic running for the whole harvest (iOS won't let an app *start* recording from the background) and holds the last 12 s in a ring buffer.
- Every 30 s (configurable), `HarvestEngine` takes that 12 s, resamples to 16 kHz mono, and fingerprints it on-device.
- `HarvesterCore` is a Swift port of SongRec's Shazam fingerprint algorithm. Only the fingerprint is sent to Shazam's discovery endpoint, never the audio.
- Uses no Apple capabilities (no ShazamKit/MusicKit), so it works on a **free** Apple ID.

## Layout

| Path | What |
|---|---|
| `Packages/HarvesterCore` | Platform-independent fingerprinting + Shazam client. Builds and tests on Linux. |
| `Sources/Harvest` | SwiftUI app: engine, audio capture, storage, views |
| `Support/Info.plist` | Mic permission, background audio, display name |
| `setup/` | One-time setup scripts + `run.sh` to build/install |
| `Tools/` | Python reference fingerprinter (`shazam_ref.py`, verified against live Shazam) and `gen_fixtures.py`, which regenerates the golden test fixtures |

## Build

One-time setup: `setup/1-windows-setup.ps1` (admin, then reboot), then `setup/2-wsl-setup.sh` in Ubuntu, then `xtool setup`.

Every build / re-sign:

```bash
bash '/mnt/c/path/to/harvest/setup/run.sh'
```

Core tests (Linux):

```bash
cd ~/harvest/Packages/HarvesterCore && swift test
# live test against Shazam with a 16 kHz mono s16le clip:
HARVEST_LIVE_CLIP=/path/to/clip.raw swift test --filter liveRecognition
```

## Spotify export

Detail screen → ⋯ → **Export to Spotify**. The first time, you log in through Spotify's own page (PKCE, nothing stored but the token, which lives in the iOS Keychain).

- Songs are matched by ISRC first, then by a title/artist search that only accepts a confident match. Anything not found is listed afterwards.
- It creates a **private** playlist named after the harvest. Exporting again replaces the contents of that same playlist, so deleting a song in Harvest removes it on Spotify too.
- Spotify dev app "Harvest" (Client ID in `SpotifyAccount.swift`, redirect URI `harvest://spotify-callback`). Dev-mode rules: owner needs Premium, max 5 users. If you get a 403, add your Spotify email under the app's **User Management** in the dashboard.
- Fallback without Spotify: ⋯ → **Copy song list**, then paste it into TuneMyMusic.

## Notes

- Free Apple ID: the app expires after 7 days. Re-run `run.sh` to re-sign (your harvests are kept).
- Shazam's endpoint is unofficial. If it ever changes, `ShazamClient.swift` is the only file to touch.
