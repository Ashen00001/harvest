/// Integer-only test signal; mirrors `synth()` in the Python reference so both sides get identical samples.
enum SyntheticSignal {
    static func make(seconds: Int = 8) -> [Int16] {
        var state: UInt32 = 12345
        func next() -> UInt32 {
            state = state &* 1_103_515_245 &+ 12345
            return (state >> 16) & 0x7FFF
        }

        var phases: [UInt32] = [0, 0, 0]
        var increments: [UInt32] = [0, 0, 0]
        var out: [Int16] = []
        out.reserveCapacity(16000 * seconds)

        for i in 0..<(16000 * seconds) {
            if i % 4000 == 0 {
                for t in 0..<3 {
                    let freq = UInt64(300 + next() % 4500)
                    increments[t] = UInt32(truncatingIfNeeded: (freq << 32) / 16000)
                }
            }
            var sample: Int32 = 0
            for t in 0..<3 {
                phases[t] = phases[t] &+ increments[t]
                let p = Int32(phases[t] >> 16)
                let triangle = p < 32768 ? p - 16384 : 49151 - p
                sample += triangle >> 2
            }
            sample += Int32(next() % 1024) - 512
            out.append(Int16(sample))
        }
        return out
    }
}
