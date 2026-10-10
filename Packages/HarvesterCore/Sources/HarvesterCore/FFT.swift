import Foundation

/// Radix-2 FFT fixed at 2048 points, returning the 1025-bin power spectrum Shazam expects.
final class PowerSpectrum2048 {
    static let size = 2048
    static let bins = 1025

    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReversed: [Int]
    private var re = [Double](repeating: 0, count: size)
    private var im = [Double](repeating: 0, count: size)

    init() {
        let n = Self.size
        cosTable = (0..<n / 2).map { cos(2 * Double.pi * Double($0) / Double(n)) }
        sinTable = (0..<n / 2).map { sin(2 * Double.pi * Double($0) / Double(n)) }
        var rev = [Int](repeating: 0, count: n)
        let bits = 11
        for i in 0..<n {
            var x = i
            var r = 0
            for _ in 0..<bits {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            rev[i] = r
        }
        bitReversed = rev
    }

    /// `input` must hold 2048 windowed samples; writes 1025 values of (re² + im²) / 2^17, floored at 1e-10.
    func compute(_ input: UnsafeBufferPointer<Double>, into output: UnsafeMutableBufferPointer<Double>) {
        let n = Self.size
        re.withUnsafeMutableBufferPointer { re in
            im.withUnsafeMutableBufferPointer { im in
                cosTable.withUnsafeBufferPointer { cosT in
                    sinTable.withUnsafeBufferPointer { sinT in
                        bitReversed.withUnsafeBufferPointer { rev in
                            for i in 0..<n {
                                re[rev[i]] = input[i]
                                im[rev[i]] = 0
                            }
                            var size = 2
                            while size <= n {
                                let half = size >> 1
                                let step = n / size
                                var start = 0
                                while start < n {
                                    var k = 0
                                    for j in start..<(start + half) {
                                        let l = j + half
                                        let wr = cosT[k]
                                        let wi = -sinT[k]
                                        let tr = wr * re[l] - wi * im[l]
                                        let ti = wr * im[l] + wi * re[l]
                                        re[l] = re[j] - tr
                                        im[l] = im[j] - ti
                                        re[j] += tr
                                        im[j] += ti
                                        k += step
                                    }
                                    start += size
                                }
                                size <<= 1
                            }
                            let scale = Double(1 << 17)
                            for i in 0..<Self.bins {
                                output[i] = max((re[i] * re[i] + im[i] * im[i]) / scale, 0.0000000001)
                            }
                        }
                    }
                }
            }
        }
    }
}
