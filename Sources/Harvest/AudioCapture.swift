import AVFoundation

/// Keeps the mic running and holds the most recent `windowSeconds` of audio in a ring buffer.
/// The engine has to stay running the whole harvest: iOS won't let an app start recording from the background.
final class AudioCapture: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noInput

        var errorDescription: String? {
            "No microphone input is available."
        }
    }

    let windowSeconds: Double

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var ring: [Float] = []
    private var writeIndex = 0
    private var filled = 0
    private var sampleRate: Double = 0
    private var latestLevel: Float = 0

    init(windowSeconds: Double) {
        self.windowSeconds = windowSeconds
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        try startEngine()
    }

    func restart() throws {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try AVAudioSession.sharedInstance().setActive(true)
        try startEngine()
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var level: Float {
        lock.withLock { latestLevel }
    }

    /// Most recent audio, oldest sample first.
    func snapshot() -> (samples: [Float], sampleRate: Double) {
        lock.withLock {
            let capacity = ring.count
            guard filled > 0, capacity > 0 else { return ([], sampleRate) }
            var out = [Float]()
            out.reserveCapacity(filled)
            let start = (writeIndex - filled + capacity) % capacity
            for i in 0..<filled {
                out.append(ring[(start + i) % capacity])
            }
            return (out, sampleRate)
        }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }

        lock.withLock {
            sampleRate = format.sampleRate
            ring = [Float](repeating: 0, count: Int(format.sampleRate * windowSeconds))
            writeIndex = 0
            filled = 0
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sumSquares: Float = 0
        for i in 0..<count {
            sumSquares += channel[i] * channel[i]
        }

        lock.withLock {
            let capacity = ring.count
            guard capacity > 0 else { return }
            for i in 0..<count {
                ring[writeIndex] = channel[i]
                writeIndex += 1
                if writeIndex == capacity { writeIndex = 0 }
            }
            filled = min(filled + count, capacity)
            latestLevel = (sumSquares / Float(count)).squareRoot()
        }
    }
}

enum PCMConverter {
    /// Mono float samples at any rate -> 16 kHz signed 16-bit, peak-normalized (the mic runs without AGC).
    static func to16kInt16(_ samples: [Float], sampleRate: Double) -> [Int16] {
        guard !samples.isEmpty,
              let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let destination = inBuffer.floatChannelData?[0]
        else { return [] }

        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let gain: Float = peak > 0 ? min(0.9 / peak, 30) : 1
        for i in 0..<samples.count {
            destination[i] = samples[i] * gain
        }
        inBuffer.frameLength = AVAudioFrameCount(samples.count)

        let capacity = AVAudioFrameCount(Double(samples.count) * 16000 / sampleRate) + 4096
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return [] }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return inBuffer
        }
        guard status != .error, let data = outBuffer.int16ChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(outBuffer.frameLength)))
    }
}
