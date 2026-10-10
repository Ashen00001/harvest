"""Reference Shazam signature generator (port of SongRec's Rust algorithm) + live recognizer.

Mirrors the Swift implementation in HarvesterCore so it can produce golden test vectors.
"""
import base64
import binascii
import json
import struct
import sys
import time
import uuid

import numpy as np
import requests

HANNING = np.array([0.5 - 0.5 * np.cos(2 * np.pi * n / 2049) for n in range(1, 2049)], dtype=np.float64)
OTHER_OFFSETS = [-53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249]
NEIGHBOR_OFFSETS = [-10, -7, -4, -3, 1, 2, 5, 8]


def magnitude(x, mode):
    if mode == "rust":
        return max(np.log(x), 1 / 64) * 1477.3 + 6144
    return np.log(max(1 / 64, x)) * 1477.3 + 6144


def make_signature(samples: np.ndarray, mode="python"):
    """samples: int16 mono 16 kHz. Returns (number_samples, {band: [(fft_pass, magnitude, bin)]})."""
    ring = np.zeros(2048, dtype=np.int16)
    ring_idx = 0
    fft_outputs = np.zeros((256, 1025), dtype=np.float64)
    fft_idx = 0
    spread = np.zeros((256, 1025), dtype=np.float64)
    spread_idx = 0
    done = 0
    bands = {0: [], 1: [], 2: [], 3: []}

    for c in range(0, len(samples) - 127, 128):
        ring[ring_idx:ring_idx + 128] = samples[c:c + 128]
        ring_idx = (ring_idx + 128) & 2047
        reordered = np.concatenate([ring[ring_idx:], ring[:ring_idx]]).astype(np.float64) * HANNING
        out = np.fft.rfft(reordered)
        fft_outputs[fft_idx] = np.maximum((out.real ** 2 + out.imag ** 2) / (1 << 17), 1e-10)
        fft_idx = (fft_idx + 1) & 255

        s = fft_outputs[(fft_idx - 1) & 255].copy()
        for p in range(1023):
            s[p] = max(s[p], s[p + 1], s[p + 2])
        for former in (1, 3, 6):
            row = spread[(spread_idx - former) & 255]
            np.maximum(row, s, out=row)
        spread[spread_idx] = s
        spread_idx = (spread_idx + 1) & 255
        done += 1

        if done < 46:
            continue
        f46 = fft_outputs[(fft_idx - 46) & 255]
        f49 = spread[(spread_idx - 49) & 255]
        for b in range(10, 1015):
            v = f46[b]
            if not (v >= 1 / 64 and v >= f49[b - 1]):
                continue
            mx = 0.0
            for o in NEIGHBOR_OFFSETS:
                mx = max(mx, f49[b + o])
            if not v > mx:
                continue
            mo = mx
            for o in OTHER_OFFSETS:
                mo = max(mo, spread[(spread_idx + o) & 255][b - 1])
            if not v > mo:
                continue
            pm = magnitude(v, mode)
            pb = magnitude(f46[b - 1], mode)
            pa = magnitude(f46[b + 1], mode)
            var1 = pm * 2 - pb - pa
            if var1 <= 0:
                continue
            var2 = (pa - pb) * 32 / var1
            corrected = b * 64 + int(var2)
            hz = corrected * (16000 / 2 / 1024 / 64)
            if 250 <= hz < 520:
                band = 0
            elif 520 <= hz < 1450:
                band = 1
            elif 1450 <= hz < 3500:
                band = 2
            elif 3500 <= hz <= 5500:
                band = 3
            else:
                continue
            bands[band].append((done - 46, int(pm), corrected & 0xFFFF))
    return len(samples), bands


def encode(number_samples, bands):
    contents = bytearray()
    for band in sorted(bands):
        peaks = bands[band]
        if not peaks:
            continue
        pb = bytearray()
        last = 0
        for fft_pass, mag, fbin in peaks:
            if fft_pass - last >= 255:
                pb += b"\xff" + struct.pack("<I", fft_pass)
                last = fft_pass
            pb += bytes([fft_pass - last]) + struct.pack("<HH", mag, fbin)
            last = fft_pass
        contents += struct.pack("<II", 0x60030040 + band, len(pb)) + pb + b"\x00" * (-len(pb) % 4)
    size = len(contents) + 8
    header = struct.pack(
        "<IIII3II2III",
        0xCAFE2580, 0, size, 0x94119C00, 0, 0, 0, 3 << 27, 0, 0,
        int(number_samples + 16000 * 0.24), (15 << 19) + 0x40000,
    )
    body = struct.pack("<II", 0x40000000, size) + bytes(contents)
    full = bytearray(header + body)
    crc = binascii.crc32(bytes(full[8:])) & 0xFFFFFFFF
    full[4:8] = struct.pack("<I", crc)
    return bytes(full)


def recognize(sig: bytes, number_samples: int):
    now = int(time.time() * 1000)
    url = (
        f"https://amp.shazam.com/discovery/v5/en/US/android/-/tag/{str(uuid.uuid4()).upper()}/{uuid.uuid4()}"
        "?sync=true&webv3=true&sampling=true&connected=&shazamapiversion=v3&sharehub=true&video=v3"
    )
    body = {
        "geolocation": {"altitude": 300, "latitude": 45, "longitude": 2},
        "signature": {
            "samplems": int(number_samples / 16000 * 1000),
            "timestamp": now,
            "uri": "data:audio/vnd.shazam.sig;base64," + base64.b64encode(sig).decode(),
        },
        "timestamp": now,
        "timezone": "America/Los_Angeles",
    }
    r = requests.post(
        url,
        json=body,
        headers={
            "Content-Language": "en_US",
            "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 13; Pixel 7 Build/TQ3A.230805.001)",
        },
        timeout=20,
    )
    return r.status_code, r.json() if r.headers.get("content-type", "").startswith("application/json") else r.text[:300]


if __name__ == "__main__":
    for path in sys.argv[1:]:
        samples = np.fromfile(path, dtype="<i2")
        for mode in ("python", "rust"):
            n, bands = make_signature(samples, mode)
            sig = encode(n, bands)
            status, resp = recognize(sig, n)
            track = resp.get("track", {}) if isinstance(resp, dict) else {}
            print(f"{path.split(chr(92))[-1]:20} mode={mode:6} peaks={[len(v) for v in bands.values()]} bytes={len(sig)} "
                  f"http={status} matches={len(resp.get('matches', [])) if isinstance(resp, dict) else '?'} "
                  f"-> {track.get('title')} / {track.get('subtitle')}")
