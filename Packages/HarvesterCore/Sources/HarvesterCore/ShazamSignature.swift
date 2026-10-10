import Foundation

public enum FrequencyBand: Int, CaseIterable, Sendable {
    case hz250to520 = 0
    case hz520to1450 = 1
    case hz1450to3500 = 2
    case hz3500to5500 = 3

    init?(hz: Double) {
        switch hz {
        case 250..<520: self = .hz250to520
        case 520..<1450: self = .hz520to1450
        case 1450..<3500: self = .hz1450to3500
        case 3500...5500: self = .hz3500to5500
        default: return nil
        }
    }
}

public struct FrequencyPeak: Equatable, Hashable, Sendable {
    public var fftPassNumber: UInt32
    public var magnitude: UInt16
    public var correctedBin: UInt16

    public init(fftPassNumber: UInt32, magnitude: UInt16, correctedBin: UInt16) {
        self.fftPassNumber = fftPassNumber
        self.magnitude = magnitude
        self.correctedBin = correctedBin
    }
}

public struct ShazamSignature: Sendable {
    public static let uriPrefix = "data:audio/vnd.shazam.sig;base64,"

    public var sampleRate = SignatureGenerator.sampleRate
    public var numberOfSamples: Int
    /// Indexed by `FrequencyBand.rawValue`; peaks within a band are in fft-pass order.
    public var peaksByBand: [[FrequencyPeak]]

    public init(numberOfSamples: Int, peaksByBand: [[FrequencyPeak]]) {
        self.numberOfSamples = numberOfSamples
        self.peaksByBand = peaksByBand
    }

    public var peakCount: Int { peaksByBand.reduce(0) { $0 + $1.count } }

    public var durationMilliseconds: Int { numberOfSamples * 1000 / sampleRate }

    public func encoded() -> Data {
        var contents = Data()
        for (band, peaks) in peaksByBand.enumerated() where !peaks.isEmpty {
            var peakBytes = Data()
            var last: UInt32 = 0
            for peak in peaks {
                if peak.fftPassNumber - last >= 255 {
                    peakBytes.append(0xFF)
                    peakBytes.appendLE(peak.fftPassNumber)
                    last = peak.fftPassNumber
                }
                peakBytes.append(UInt8(peak.fftPassNumber - last))
                peakBytes.appendLE(peak.magnitude)
                peakBytes.appendLE(peak.correctedBin)
                last = peak.fftPassNumber
            }
            contents.appendLE(UInt32(0x6003_0040 + band))
            contents.appendLE(UInt32(peakBytes.count))
            contents.append(peakBytes)
            let padding = (4 - peakBytes.count % 4) % 4
            contents.append(Data(repeating: 0, count: padding))
        }

        let sizeMinusHeader = UInt32(contents.count + 8)
        var message = Data()
        message.appendLE(UInt32(0xCAFE_2580))
        message.appendLE(UInt32(0)) // CRC-32, filled in below
        message.appendLE(sizeMinusHeader)
        message.appendLE(UInt32(0x9411_9C00))
        for _ in 0..<3 { message.appendLE(UInt32(0)) }
        message.appendLE(UInt32(3 << 27)) // sample rate id 3 = 16 kHz
        for _ in 0..<2 { message.appendLE(UInt32(0)) }
        message.appendLE(UInt32(Double(numberOfSamples) + Double(sampleRate) * 0.24))
        message.appendLE(UInt32((15 << 19) + 0x40000))
        message.appendLE(UInt32(0x4000_0000))
        message.appendLE(sizeMinusHeader)
        message.append(contents)

        let crc = CRC32.checksum(message.dropFirst(8))
        message.replaceSubrange(4..<8, with: withUnsafeBytes(of: crc.littleEndian) { Data($0) })
        return message
    }

    public func dataURI() -> String {
        Self.uriPrefix + encoded().base64EncodedString()
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum<D: DataProtocol>(_ data: D) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
