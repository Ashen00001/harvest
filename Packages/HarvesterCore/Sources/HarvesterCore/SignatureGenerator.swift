import Foundation

/// Port of SongRec's Shazam fingerprinting algorithm.
/// Feed it signed 16-bit, 16 kHz mono PCM (ideally ~12 seconds) and send the result to `ShazamClient`.
public enum SignatureGenerator {
    public static let sampleRate = 16000

    private static let hanning: [Double] = (1...2048).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / 2049) }
    private static let neighborOffsets = [-10, -7, -4, -3, 1, 2, 5, 8]
    private static let otherOffsets = [-53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249]

    public static func makeSignature(samples: [Int16]) -> ShazamSignature {
        let bins = PowerSpectrum2048.bins
        let fft = PowerSpectrum2048()

        var ring = [Int16](repeating: 0, count: 2048)
        var ringIndex = 0
        var fftOutputs = [Double](repeating: 0, count: 256 * bins)
        var fftIndex = 0
        var spread = [Double](repeating: 0, count: 256 * bins)
        var spreadIndex = 0
        var done = 0

        var windowed = [Double](repeating: 0, count: 2048)
        var power = [Double](repeating: 0, count: bins)
        var bands: [[FrequencyPeak]] = Array(repeating: [], count: FrequencyBand.allCases.count)

        let chunks = samples.count / 128
        samples.withUnsafeBufferPointer { input in
            hanning.withUnsafeBufferPointer { window in
                for chunk in 0..<chunks {
                    let offset = chunk * 128
                    for i in 0..<128 {
                        ring[ringIndex + i] = input[offset + i]
                    }
                    ringIndex = (ringIndex + 128) & 2047

                    for i in 0..<2048 {
                        windowed[i] = Double(ring[(i + ringIndex) & 2047]) * window[i]
                    }
                    windowed.withUnsafeBufferPointer { w in
                        power.withUnsafeMutableBufferPointer { p in
                            fft.compute(w, into: p)
                        }
                    }

                    let fftBase = fftIndex * bins
                    for i in 0..<bins {
                        fftOutputs[fftBase + i] = power[i]
                    }
                    fftIndex = (fftIndex + 1) & 255

                    // Frequency-domain spreading (power is reused as scratch from here on)
                    for p in 0..<(bins - 2) {
                        power[p] = max(power[p], power[p + 1], power[p + 2])
                    }

                    // Time-domain spreading into the previous 1st, 3rd and 6th rows
                    for former in [1, 3, 6] {
                        let base = ((spreadIndex - former) & 255) * bins
                        for i in 0..<bins where power[i] > spread[base + i] {
                            spread[base + i] = power[i]
                        }
                    }
                    let spreadBase = spreadIndex * bins
                    for i in 0..<bins {
                        spread[spreadBase + i] = power[i]
                    }
                    spreadIndex = (spreadIndex + 1) & 255
                    done += 1

                    if done >= 46 {
                        findPeaks(
                            fftOutputs: fftOutputs,
                            spread: spread,
                            fftIndex: fftIndex,
                            spreadIndex: spreadIndex,
                            fftPassNumber: done - 46,
                            into: &bands
                        )
                    }
                }
            }
        }

        return ShazamSignature(numberOfSamples: samples.count, peaksByBand: bands)
    }

    private static func magnitude(_ x: Double) -> Double {
        log(max(1.0 / 64.0, x)) * 1477.3 + 6144
    }

    private static func findPeaks(
        fftOutputs: [Double],
        spread: [Double],
        fftIndex: Int,
        spreadIndex: Int,
        fftPassNumber: Int,
        into bands: inout [[FrequencyPeak]]
    ) {
        let bins = PowerSpectrum2048.bins
        let f46 = ((fftIndex - 46) & 255) * bins
        let f49 = ((spreadIndex - 49) & 255) * bins

        for bin in 10...1014 {
            let value = fftOutputs[f46 + bin]
            guard value >= 1.0 / 64.0, value >= spread[f49 + bin - 1] else { continue }

            var maxNeighbor = 0.0
            for offset in neighborOffsets {
                maxNeighbor = max(maxNeighbor, spread[f49 + bin + offset])
            }
            guard value > maxNeighbor else { continue }

            var maxOther = maxNeighbor
            for offset in otherOffsets {
                maxOther = max(maxOther, spread[((spreadIndex + offset) & 255) * bins + bin - 1])
            }
            guard value > maxOther else { continue }

            let peak = magnitude(value)
            let before = magnitude(fftOutputs[f46 + bin - 1])
            let after = magnitude(fftOutputs[f46 + bin + 1])
            let variation1 = peak * 2 - before - after
            guard variation1 > 0 else { continue }
            let variation2 = (after - before) * 32 / variation1

            let correctedBin = bin * 64 + Int(variation2)
            let hz = Double(correctedBin) * (16000.0 / 2 / 1024 / 64)
            guard let band = FrequencyBand(hz: hz) else { continue }

            bands[band.rawValue].append(FrequencyPeak(
                fftPassNumber: UInt32(fftPassNumber),
                magnitude: UInt16(clamping: Int(peak)),
                correctedBin: UInt16(truncatingIfNeeded: correctedBin)
            ))
        }
    }
}
