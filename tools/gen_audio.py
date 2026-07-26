#!/usr/bin/env python3
"""Generates Regolith's audio into assets/audio/ — stdlib only, no deps.

Everything the game plays is synthesized here so the sounds live in the repo as
regenerable source rather than opaque binaries: short chiptune-ish SFX (square /
triangle blips, noise crunches) and one long ambient bed.

Run with `make audio` after editing. Output is deterministic — the same script
always produces byte-identical WAVs.

The ambient loop is *mathematically* seamless: its length is a whole number of
seconds and every oscillator frequency is quantised to a multiple of
1/LOOP_SECONDS Hz, so every partial completes a whole number of cycles. The
noise layer instead gets its filter warmed up from the tail of the buffer, so
the loop point carries no click.
"""

import math
import os
import random
import struct
import wave

TAU = math.tau
SR = 22050                      # retro-friendly and small on disk
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
LOOP_SECONDS = 32               # ambient bed length


# --- oscillators -------------------------------------------------------------

def sine(f, t, phase=0.0):
    return math.sin(TAU * f * t + phase)


def square(f, t, phase=0.0):
    return 1.0 if ((f * t + phase / TAU) % 1.0) < 0.5 else -1.0


def triangle(f, t, phase=0.0):
    x = (f * t + phase / TAU) % 1.0
    return 4.0 * abs(x - 0.5) - 1.0


def saw(f, t, phase=0.0):
    return 2.0 * ((f * t + phase / TAU) % 1.0) - 1.0


# --- buffer helpers ----------------------------------------------------------

def buffer(seconds):
    return [0.0] * int(seconds * SR)


def add_tone(buf, start, dur, freq, amp, osc=sine, decay=6.0, attack=0.004,
             glide=1.0, vibrato=0.0, vibrato_hz=6.0):
    """Mixes one enveloped tone into `buf`. `glide` is the end/start frequency
    ratio (a sweep), `decay` the exponential fall-off rate over the tone."""
    i0 = int(start * SR)
    n = int(dur * SR)
    for i in range(n):
        if i0 + i >= len(buf):
            break
        t = i / SR
        u = i / n
        f = freq * (glide ** u)
        if vibrato:
            f *= 1.0 + vibrato * sine(vibrato_hz, t)
        a = math.exp(-decay * u)
        if t < attack:                      # tiny fade-in kills the click
            a *= t / attack
        buf[i0 + i] += amp * a * osc(f, t)


def add_noise(buf, start, dur, amp, decay=8.0, cutoff=4000.0, rng=None,
              attack=0.002):
    """A lowpassed noise burst — the crunch/thud half of the mechanical sounds.
    The short attack keeps the onset punchy without a DC step (which pops)."""
    rng = rng or random
    i0 = int(start * SR)
    n = int(dur * SR)
    a = math.exp(-TAU * cutoff / SR)
    na = max(1, int(attack * SR))
    y = 0.0
    for i in range(n):
        if i0 + i >= len(buf):
            break
        y = y * a + (1.0 - a) * rng.uniform(-1.0, 1.0)
        env = math.exp(-decay * i / n) * min(1.0, i / na)
        buf[i0 + i] += amp * env * y


def lowpass(buf, cutoff, circular=False):
    """One-pole lowpass, in place. `circular` warms the filter from the buffer's
    tail first, so a looping buffer has no discontinuity at the loop point."""
    a = math.exp(-TAU * cutoff / SR)
    y = 0.0
    if circular:
        for x in buf[-4096:]:
            y = y * a + (1.0 - a) * x
    for i, x in enumerate(buf):
        y = y * a + (1.0 - a) * x
        buf[i] = y


def normalize(buf, peak=0.85):
    hi = max((abs(x) for x in buf), default=0.0)
    if hi > 0.0:
        k = peak / hi
        for i in range(len(buf)):
            buf[i] *= k
    return buf


def write_wav(name, buf):
    path = os.path.normpath(os.path.join(OUT_DIR, name))
    frames = bytearray()
    for x in buf:
        v = max(-1.0, min(1.0, x))
        frames += struct.pack("<h", int(v * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("  %-22s %5.2fs  %6.1f kB" % (name, len(buf) / SR, len(frames) / 1024))


# --- sound effects -----------------------------------------------------------
# Kept short and dry: they sit on top of the ambient bed and fire often.

def sfx_ui_click():
    buf = buffer(0.07)
    add_tone(buf, 0.0, 0.05, 1180, 0.5, square, decay=14.0)
    add_noise(buf, 0.0, 0.02, 0.25, decay=20.0, cutoff=5000, rng=random.Random(1))
    lowpass(buf, 6000)
    return normalize(buf, 0.7)


def sfx_place():
    """Hydraulic thud plus a rising two-note confirm — a thing set down and
    switched on."""
    buf = buffer(0.34)
    add_tone(buf, 0.0, 0.20, 110, 0.9, sine, decay=7.0, glide=0.55)   # thud
    add_noise(buf, 0.0, 0.09, 0.4, decay=16.0, cutoff=1800, rng=random.Random(2))
    add_tone(buf, 0.06, 0.09, 523.25, 0.30, square, decay=6.0)        # C5
    add_tone(buf, 0.14, 0.16, 783.99, 0.28, square, decay=5.0)        # G5
    lowpass(buf, 7000)
    return normalize(buf, 0.85)


def sfx_denied():
    """Two detuned squares falling — the classic 'no'."""
    buf = buffer(0.24)
    add_tone(buf, 0.0, 0.20, 233.08, 0.5, square, decay=4.0, glide=0.72)
    add_tone(buf, 0.0, 0.20, 234.5, 0.5, square, decay=4.0, glide=0.72)
    lowpass(buf, 2600)
    return normalize(buf, 0.7)


def sfx_demolish():
    """Collapsing crunch: noise through a cutoff that falls as it decays."""
    buf = buffer(0.45)
    rng = random.Random(3)
    a_hi, a_lo = math.exp(-TAU * 3500 / SR), math.exp(-TAU * 400 / SR)
    y = 0.0
    n = len(buf)
    na = int(0.002 * SR)
    for i in range(n):
        u = i / n
        a = a_hi + (a_lo - a_hi) * u        # cutoff sweeps down
        y = y * a + (1.0 - a) * rng.uniform(-1.0, 1.0)
        buf[i] += 0.9 * math.exp(-5.0 * u) * min(1.0, i / na) * y
    add_tone(buf, 0.0, 0.30, 80, 0.7, sine, decay=6.0, glide=0.6)
    return normalize(buf, 0.85)


def sfx_alert_info():
    """Soft two-note rise — something good was discovered."""
    buf = buffer(0.30)
    add_tone(buf, 0.0, 0.10, 659.25, 0.5, triangle, decay=5.0)   # E5
    add_tone(buf, 0.09, 0.18, 987.77, 0.5, triangle, decay=4.0)  # B5
    return normalize(buf, 0.6)


def sfx_alert_warn():
    """Two flat beeps — a console warning light."""
    buf = buffer(0.40)
    for k in range(2):
        add_tone(buf, k * 0.16, 0.11, 493.88, 0.5, square, decay=3.0)
    lowpass(buf, 4000)
    return normalize(buf, 0.7)


def sfx_alert_crit():
    """Three descending klaxon beeps with a wobble — power is failing."""
    buf = buffer(0.62)
    for k, f in enumerate((740.0, 622.25, 466.16)):
        add_tone(buf, k * 0.15, 0.13, f, 0.5, square, decay=2.5,
                 vibrato=0.02, vibrato_hz=22.0)
    lowpass(buf, 4500)
    return normalize(buf, 0.8)


def sfx_win():
    """Rising major arpeggio, last note held — the beacon fires."""
    buf = buffer(1.9)
    notes = (523.25, 659.25, 783.99, 1046.50)     # C5 E5 G5 C6
    for k, f in enumerate(notes):
        last = k == len(notes) - 1
        add_tone(buf, k * 0.14, 1.2 if last else 0.3, f, 0.34, square,
                 decay=1.2 if last else 5.0)
        add_tone(buf, k * 0.14, 1.2 if last else 0.3, f / 2, 0.16, triangle,
                 decay=1.2 if last else 5.0)
    lowpass(buf, 7000)
    return normalize(buf, 0.8)


def sfx_lose():
    """Sagging minor fall — the colony goes quiet."""
    buf = buffer(2.3)
    notes = (440.0, 349.23, 293.66, 220.0)        # A4 F4 D4 A3
    for k, f in enumerate(notes):
        last = k == len(notes) - 1
        add_tone(buf, k * 0.22, 1.5 if last else 0.4, f, 0.4, triangle,
                 decay=0.9 if last else 4.0, glide=0.985 if last else 1.0)
    add_tone(buf, 0.66, 1.6, 110.0, 0.25, sine, decay=1.2)
    lowpass(buf, 3200)
    return normalize(buf, 0.75)


# --- ambient bed -------------------------------------------------------------

def q(f):
    """Quantises a frequency so it completes whole cycles over the loop."""
    return round(f * LOOP_SECONDS) / LOOP_SECONDS


def ambient():
    """A slow, cold pad over a low drone, with wind and sparse bell motes.

    Four 8-second chords (Am - F - C - G) fade in and out inside their own slot,
    so nothing is cut off at the loop seam.
    """
    n = LOOP_SECONDS * SR
    buf = [0.0] * n
    rng = random.Random(20260727)

    # Drone: root, fifth and a slightly detuned octave, breathing slowly.
    drone = [(q(55.0), 0.32), (q(82.5), 0.16), (q(110.3), 0.10)]
    for i in range(n):
        t = i / SR
        breath = 0.75 + 0.25 * sine(q(0.125), t)      # 4 cycles per loop
        s = 0.0
        for f, a in drone:
            s += a * (0.7 * sine(f, t) + 0.3 * triangle(f, t))
        buf[i] += 0.5 * breath * s

    # Pad: each chord swells and falls inside its own 8s slot.
    chords = (
        (220.00, 261.63, 329.63),   # Am
        (174.61, 220.00, 261.63),   # F
        (261.63, 329.63, 392.00),   # C
        (196.00, 246.94, 293.66),   # G
    )
    slot = LOOP_SECONDS / len(chords)
    for c, chord in enumerate(chords):
        i0 = int(c * slot * SR)
        ns = int(slot * SR)
        for i in range(ns):
            t = (i0 + i) / SR
            u = i / ns
            swell = math.sin(math.pi * u) ** 1.5       # 0 at both ends
            s = 0.0
            for f in chord:
                fq = q(f)
                s += 0.33 * (0.6 * triangle(fq, t) + 0.4 * sine(fq * 2, t) * 0.3)
            buf[i0 + i] += 0.22 * swell * s

    # Wind: lowpassed noise, filtered circularly so the seam is silent.
    wind = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    lowpass(wind, 520, circular=True)
    lowpass(wind, 520, circular=True)
    for i in range(n):
        t = i / SR
        gust = 0.55 + 0.45 * sine(q(0.0625), t) * sine(q(0.09375), t + 1.7)
        buf[i] += 2.6 * gust * wind[i]

    # Bell motes: sparse pentatonic pings, all decayed before the loop ends.
    scale = [q(f) for f in (440.0, 523.25, 587.33, 659.25, 783.99, 880.0)]
    t = 1.5
    while t < LOOP_SECONDS - 4.0:
        f = rng.choice(scale)
        amp = rng.uniform(0.05, 0.11)
        add_tone(buf, t, 3.0, f, amp, sine, decay=4.0, attack=0.01)
        add_tone(buf, t, 2.0, f * 2.0, amp * 0.3, sine, decay=6.0, attack=0.01)
        t += rng.uniform(2.6, 5.2)

    lowpass(buf, 6000)
    return normalize(buf, 0.62)


# --- main --------------------------------------------------------------------

SOUNDS = {
    "ui_click.wav": sfx_ui_click,
    "place.wav": sfx_place,
    "denied.wav": sfx_denied,
    "demolish.wav": sfx_demolish,
    "alert_info.wav": sfx_alert_info,
    "alert_warn.wav": sfx_alert_warn,
    "alert_crit.wav": sfx_alert_crit,
    "win.wav": sfx_win,
    "lose.wav": sfx_lose,
    "ambient.wav": ambient,
}


def main():
    os.makedirs(os.path.normpath(OUT_DIR), exist_ok=True)
    print("Generating %d sounds into %s" % (len(SOUNDS), os.path.normpath(OUT_DIR)))
    for name, fn in SOUNDS.items():
        write_wav(name, fn())


if __name__ == "__main__":
    main()
