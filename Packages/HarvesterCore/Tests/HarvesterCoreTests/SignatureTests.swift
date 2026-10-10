import Foundation
import Testing
@testable import HarvesterCore

private struct Fixture: Decodable {
    struct Peak: Decodable {
        var pass: UInt32
        var mag: UInt16
        var bin: UInt16
    }

    struct Small: Decodable {
        var numberOfSamples: Int
        var peaks: [[Peak]]
        var signatureBase64: String
    }

    var numberOfSamples: Int
    var sampleChecksum: Int
    var peakCounts: [Int]
    var peaks: [[Peak]]
    var signatureBase64: String
    var small: Small

    static func load() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "synthetic-signature", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}

private extension Array where Element == [Fixture.Peak] {
    var asPeaks: [[FrequencyPeak]] {
        map { $0.map { FrequencyPeak(fftPassNumber: $0.pass, magnitude: $0.mag, correctedBin: $0.bin) } }
    }
}

@Suite struct SignatureTests {
    @Test func syntheticSignalMatchesPython() throws {
        let fixture = try Fixture.load()
        let samples = SyntheticSignal.make()
        #expect(samples.count == fixture.numberOfSamples)
        let checksum = samples.enumerated().reduce(0) { $0 + Int($1.element) * ($1.offset % 7 + 1) }
        #expect(checksum == fixture.sampleChecksum)
    }

    @Test func encoderIsByteExact() throws {
        let small = try Fixture.load().small
        let signature = ShazamSignature(numberOfSamples: small.numberOfSamples, peaksByBand: small.peaks.asPeaks)
        #expect(signature.encoded().base64EncodedString() == small.signatureBase64)
    }

    @Test func crc32KnownValue() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func generatorMatchesReference() throws {
        let fixture = try Fixture.load()
        let signature = SignatureGenerator.makeSignature(samples: SyntheticSignal.make())
        #expect(signature.numberOfSamples == fixture.numberOfSamples)

        // Float rounding between numpy's FFT and ours can flip a borderline peak, so allow a sliver of drift.
        let expected = fixture.peaks.asPeaks
        var total = 0
        var mismatched = 0
        for band in 0..<4 {
            let got = signature.peaksByBand[band]
            let want = expected[band]
            total += want.count
            mismatched += abs(got.count - want.count)
            for (g, w) in zip(got, want) where g.fftPassNumber != w.fftPassNumber
                || g.correctedBin != w.correctedBin
                || abs(Int(g.magnitude) - Int(w.magnitude)) > 1 {
                mismatched += 1
            }
        }
        #expect(total > 100)
        #expect(Double(mismatched) / Double(total) < 0.02, "\(mismatched) of \(total) peaks differ")
    }

    @Test func dataURIRoundTrip() throws {
        let fixture = try Fixture.load()
        let signature = ShazamSignature(numberOfSamples: fixture.numberOfSamples, peaksByBand: fixture.peaks.asPeaks)
        let uri = signature.dataURI()
        #expect(uri.hasPrefix(ShazamSignature.uriPrefix))
        #expect(uri.dropFirst(ShazamSignature.uriPrefix.count) == Substring(fixture.signatureBase64))
    }
}
