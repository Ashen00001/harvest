import base64
import json
import sys

import numpy as np

import shazam_ref as ref


def synth(seconds=8):
    """Integer-only synthetic signal, mirrored exactly by SyntheticSignal.swift."""
    state = 12345

    def nxt():
        nonlocal state
        state = (state * 1103515245 + 12345) & 0xFFFFFFFF
        return (state >> 16) & 0x7FFF

    phases = [0, 0, 0]
    incs = [0, 0, 0]
    out = []
    for i in range(16000 * seconds):
        if i % 4000 == 0:
            for t in range(3):
                freq = 300 + nxt() % 4500
                incs[t] = ((freq << 32) // 16000) & 0xFFFFFFFF
        s = 0
        for t in range(3):
            phases[t] = (phases[t] + incs[t]) & 0xFFFFFFFF
            p = phases[t] >> 16
            tri = p - 16384 if p < 32768 else 49151 - p
            s += tri >> 2
        s += nxt() % 1024 - 512
        out.append(s)
    return np.array(out, dtype=np.int16)


def peaks_json(bands):
    return [[{"pass": p, "mag": m, "bin": b} for (p, m, b) in bands[i]] for i in range(4)]


if __name__ == "__main__":
    out_dir = sys.argv[1]
    samples = synth()
    n, bands = ref.make_signature(samples)
    sig = ref.encode(n, bands)

    small = {0: [(0, 6000, 20000), (3, 6100, 20100)], 1: [], 2: [(10, 7000, 40000), (300, 7100, 40010)], 3: []}
    small_sig = ref.encode(16000 * 12, small)

    fixture = {
        "numberOfSamples": int(n),
        "sampleChecksum": int(np.sum(samples.astype(np.int64) * (np.arange(len(samples)) % 7 + 1))),
        "peakCounts": [len(bands[i]) for i in range(4)],
        "peaks": peaks_json(bands),
        "signatureBase64": base64.b64encode(sig).decode(),
        "small": {
            "numberOfSamples": 16000 * 12,
            "peaks": peaks_json(small),
            "signatureBase64": base64.b64encode(small_sig).decode(),
        },
    }
    with open(f"{out_dir}/synthetic-signature.json", "w") as f:
        json.dump(fixture, f, indent=1)
    print("samples", n, "checksum", fixture["sampleChecksum"], "peaks", fixture["peakCounts"], "bytes", len(sig))
