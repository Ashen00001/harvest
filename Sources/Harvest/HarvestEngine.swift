import AVFoundation
import Foundation
import HarvesterCore
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class HarvestEngine {
    enum Phase: Equatable {
        case idle
        case warmingUp
        case listening
        case identifying
    }

    static let windowSeconds: Double = 12

    private(set) var phase: Phase = .idle
    private(set) var activeHarvestID: UUID?
    private(set) var lastMatch: RecognizedTrack?
    private(set) var statusMessage = ""
    private(set) var nextCheck: Date?
    private(set) var level: Float = 0
    private(set) var checksDone = 0
    var errorMessage: String?

    private let store: HarvestStore
    private let capture = AudioCapture(windowSeconds: HarvestEngine.windowSeconds)
    private let client = ShazamClient()
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    @ObservationIgnored private var lastKey: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(store: HarvestStore) {
        self.store = store
    }

    var isRunning: Bool { activeHarvestID != nil }

    private var interval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "checkInterval")
        return stored > 0 ? stored : 30
    }

    private var notifyOnNewSong: Bool {
        UserDefaults.standard.object(forKey: "notifyNewSongs") as? Bool ?? true
    }

    func start(name: String) async {
        guard !isRunning else { return }
        guard await AudioCapture.requestPermission() else {
            errorMessage = "Harvest needs the microphone. Turn it on in Settings → Privacy & Security → Microphone."
            return
        }
        if notifyOnNewSong {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        do {
            try capture.start()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        activeHarvestID = store.startHarvest(named: name)
        lastKey = nil
        lastMatch = nil
        checksDone = 0
        phase = .warmingUp
        statusMessage = "Listening…"
        observeAudioSession()

        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if UIApplication.shared.applicationState == .active {
                    self.level = self.capture.level
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        levelTask?.cancel()
        loopTask = nil
        levelTask = nil
        capture.stop()
        removeObservers()
        if let id = activeHarvestID {
            store.endHarvest(id: id)
        }
        activeHarvestID = nil
        phase = .idle
        nextCheck = nil
        level = 0
        statusMessage = ""
    }

    func checkNow() {
        guard isRunning, phase != .identifying else { return }
        Task { await identify() }
    }

    private func runLoop() async {
        // Give the ring buffer time to fill before the first attempt.
        await waitForNextCheck(in: min(Self.windowSeconds, interval))
        while !Task.isCancelled && isRunning {
            await identify()
            await waitForNextCheck(in: interval)
        }
    }

    private func waitForNextCheck(in seconds: TimeInterval) async {
        nextCheck = Date.now.addingTimeInterval(seconds)
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func identify() async {
        guard let harvestID = activeHarvestID, phase != .identifying else { return }
        let (samples, sampleRate) = capture.snapshot()
        guard sampleRate > 0, Double(samples.count) / sampleRate >= 5 else {
            statusMessage = "Warming up…"
            return
        }

        phase = .identifying
        statusMessage = "Identifying…"
        checksDone += 1
        defer {
            if activeHarvestID != nil { phase = .listening }
        }

        let signature = await Task.detached(priority: .userInitiated) { () -> ShazamSignature? in
            let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
            guard meanSquare.squareRoot() > 0.0008 else { return nil }
            let pcm = PCMConverter.to16kInt16(samples, sampleRate: sampleRate)
            guard pcm.count >= SignatureGenerator.sampleRate * 5 else { return nil }
            return SignatureGenerator.makeSignature(samples: pcm)
        }.value

        guard let signature else {
            statusMessage = "Too quiet — waiting for music"
            return
        }

        do {
            switch try await client.recognize(signature) {
            case .match(let track):
                let outcome = store.record(track, in: harvestID, isContinuation: track.shazamKey == lastKey)
                lastKey = track.shazamKey
                lastMatch = track
                switch outcome {
                case .new:
                    statusMessage = "Added \(track.title)"
                    announce(track)
                case .repeatPlay:
                    statusMessage = "\(track.title) is playing again"
                case .stillPlaying:
                    statusMessage = "Still playing \(track.title)"
                }
            case .noMatch:
                statusMessage = "Couldn't recognize that — trying again soon"
            }
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? "Network problem — will retry"
        }
    }

    private func announce(_ track: RecognizedTrack) {
        if UIApplication.shared.applicationState == .active {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        guard notifyOnNewSong else { return }
        let content = UNMutableNotificationContent()
        content.title = "Added to your harvest"
        content.body = "\(track.title) — \(track.artist)"
        let request = UNNotificationRequest(identifier: "harvest-\(track.shazamKey)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Audio session events

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)))
            }
        })
        for name in [Notification.Name.AVAudioEngineConfigurationChange, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.restartCapture()
                }
            })
        }
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began:
            statusMessage = "Paused — another app took the mic"
        case .ended:
            restartCapture()
        default:
            break
        }
    }

    private func restartCapture() {
        guard isRunning else { return }
        do {
            try capture.restart()
            statusMessage = "Listening…"
        } catch {
            statusMessage = "Mic unavailable — open Harvest to resume"
        }
    }
}
