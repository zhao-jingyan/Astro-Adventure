#!/usr/bin/env python3
"""生成原创的 8-bit 太空探索背景音乐原型。

音乐由两个短动机构成：
- SIGNAL_A：稳定、短促，用于探索主段。
- SIGNAL_B：舒缓、上行，用于发现和展开段。

两个动机在异常段都会被拆成碎片。脚本只使用 Python 标准库，
直接输出可供 Godot 导入的立体声 WAV 文件。
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
import wave
from array import array
from dataclasses import dataclass
from pathlib import Path


SAMPLE_RATE = 32_000
BPM = 112.0
BEATS_PER_SECTION = 32
TAU = math.tau


@dataclass(frozen=True)
class Event:
    """一个待渲染的乐器事件；时间与长度都以拍为单位。"""

    beat: float
    duration: float
    kind: str
    midi: float = 0.0
    gain: float = 1.0
    pan: float = 0.0
    variant: int = 0


# 第一版的原创动机：只保留短小、可辨认的音程轮廓。
SIGNAL_A = (
    (0.00, 0.50, 69),
    (0.75, 0.25, 72),
    (1.00, 0.75, 76),
    (2.00, 0.35, 74),
    (2.50, 0.35, 72),
    (3.00, 0.75, 69),
)

SIGNAL_A_ANSWER = (
    (0.00, 0.50, 76),
    (0.75, 0.25, 79),
    (1.00, 0.50, 76),
    (1.75, 0.50, 74),
    (2.50, 0.50, 72),
    (3.25, 0.60, 69),
)

SIGNAL_B = (
    (0.00, 0.75, 74),
    (0.75, 0.75, 77),
    (1.50, 1.25, 81),
    (2.75, 0.50, 79),
    (3.25, 0.60, 77),
)

BASS_PATTERNS = (
    (45, ((0.00, 45), (0.75, 45), (1.50, 48), (2.00, 45), (2.75, 52), (3.50, 48))),
    (41, ((0.00, 41), (0.75, 41), (1.50, 48), (2.00, 41), (2.75, 53), (3.50, 48))),
    (48, ((0.00, 48), (0.75, 48), (1.50, 55), (2.00, 48), (2.75, 60), (3.50, 55))),
    (43, ((0.00, 43), (0.75, 43), (1.50, 50), (2.00, 43), (2.75, 59), (3.50, 50))),
)

DISCOVERY_BASS = (
    (38, ((0.00, 38), (1.50, 38), (2.50, 45), (3.50, 41))),
    (34, ((0.00, 34), (1.50, 34), (2.50, 41), (3.50, 38))),
    (41, ((0.00, 41), (1.50, 41), (2.50, 48), (3.50, 45))),
    (36, ((0.00, 36), (1.50, 36), (2.50, 43), (3.50, 40))),
)

DISCOVERY_CHORDS = (
    (50, 53, 57),
    (46, 50, 53),
    (53, 57, 60),
    (48, 52, 55),
)


def midi_to_hz(midi: float) -> float:
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def note_envelope(
    time_s: float,
    duration_s: float,
    attack_s: float = 0.008,
    release_s: float = 0.045,
    decay_rate: float = 2.2,
) -> float:
    attack = min(1.0, time_s / max(attack_s, 0.0001))
    release = min(1.0, max(0.0, duration_s - time_s) / max(release_s, 0.0001))
    decay = 0.62 + 0.38 * math.exp(-decay_rate * time_s / max(duration_s, 0.001))
    return attack * release * decay


def add_signal(
    events: list[Event],
    phrase: tuple[tuple[float, float, int], ...],
    beat_offset: float,
    transpose: int = 0,
    gain: float = 1.0,
    pan: float = 0.0,
    echo: bool = True,
) -> None:
    """写入一条方波主旋律及其短回声。"""

    for local_beat, duration, midi in phrase:
        beat = beat_offset + local_beat
        events.append(
            Event(
                beat=beat,
                duration=duration,
                kind="lead",
                midi=midi + transpose,
                gain=gain,
                pan=pan,
            )
        )
        if echo:
            events.append(
                Event(
                    beat=beat + 0.375,
                    duration=duration * 0.82,
                    kind="echo",
                    midi=midi + transpose,
                    gain=gain * 0.19,
                    pan=-pan * 1.6,
                )
            )


def add_drum(
    events: list[Event],
    beat: float,
    kind: str,
    gain: float = 1.0,
    pan: float = 0.0,
) -> None:
    duration = {
        "kick": 0.28,
        "snare": 0.20,
        "hat": 0.055,
        "open_hat": 0.17,
        "crash": 1.25,
        "riser": 2.0,
        "static": 1.4,
    }[kind]
    events.append(
        Event(
            beat=beat,
            duration=duration / (60.0 / BPM),
            kind=kind,
            gain=gain,
            pan=pan,
        )
    )


def build_main_section() -> list[Event]:
    """稳定探索段：低音锁拍、方波主旋律与电子四拍。"""

    events: list[Event] = []
    for bar in range(8):
        bar_beat = bar * 4.0
        _, bass_pattern = BASS_PATTERNS[bar % 4]
        for local_beat, midi in bass_pattern:
            events.append(
                Event(
                    beat=bar_beat + local_beat,
                    duration=0.42,
                    kind="bass",
                    midi=midi,
                    gain=0.82,
                )
            )

        phrase = SIGNAL_A if bar % 4 < 2 else SIGNAL_A_ANSWER
        add_signal(
            events,
            phrase,
            bar_beat,
            transpose=12 if bar >= 4 and bar % 2 == 1 else 0,
            gain=0.68 if bar % 2 == 0 else 0.54,
            pan=-0.16 if bar % 2 == 0 else 0.12,
        )

        add_drum(events, bar_beat, "kick", 0.78)
        add_drum(events, bar_beat + 0.75, "kick", 0.32)
        add_drum(events, bar_beat + 2.00, "kick", 0.68)
        add_drum(events, bar_beat + 2.75, "kick", 0.32)
        add_drum(events, bar_beat + 1.00, "snare", 0.60)
        add_drum(events, bar_beat + 3.00, "snare", 0.68)

        for step in range(8):
            add_drum(
                events,
                bar_beat + step * 0.5,
                "hat",
                0.23 if step % 2 else 0.31,
                pan=-0.24 if step % 2 else 0.24,
            )

        if bar in (3, 7):
            add_drum(events, bar_beat + 3.50, "snare", 0.32, pan=-0.18)
            add_drum(events, bar_beat + 3.75, "snare", 0.46, pan=0.18)

    add_drum(events, 0.0, "crash", 0.34, pan=-0.28)
    add_drum(events, 16.0, "crash", 0.30, pan=0.28)
    return events


def build_discovery_section() -> list[Event]:
    """发现与展开段：长音、开放琶音和逐渐加密的鼓组。"""

    events: list[Event] = []
    for bar in range(8):
        bar_beat = bar * 4.0
        _, bass_pattern = DISCOVERY_BASS[bar % 4]
        for local_beat, midi in bass_pattern:
            events.append(
                Event(
                    beat=bar_beat + local_beat,
                    duration=0.62,
                    kind="bass",
                    midi=midi + (12 if bar >= 4 else 0),
                    gain=0.66,
                )
            )

        transpose = 12 if bar >= 4 else 0
        add_signal(
            events,
            SIGNAL_B,
            bar_beat,
            transpose=transpose,
            gain=0.78 if bar in (2, 3, 6, 7) else 0.62,
            pan=0.16,
            echo=True,
        )

        chord = DISCOVERY_CHORDS[bar % 4]
        arp_order = (0, 1, 2, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 2, 1)
        if bar >= 2:
            for step, chord_index in enumerate(arp_order):
                events.append(
                    Event(
                        beat=bar_beat + step * 0.25,
                        duration=0.18,
                        kind="harmonic",
                        midi=chord[chord_index] + 12,
                        gain=0.15 if bar < 4 else 0.19,
                        pan=-0.34 if step % 2 else 0.34,
                    )
                )

        add_drum(events, bar_beat, "kick", 0.72)
        add_drum(events, bar_beat + 2.50, "kick", 0.48)
        add_drum(events, bar_beat + 2.00, "snare", 0.68)
        add_drum(events, bar_beat, "open_hat", 0.18, pan=0.28)

        hat_step = 0.25 if bar >= 4 else 0.5
        for step_index in range(int(4.0 / hat_step)):
            add_drum(
                events,
                bar_beat + step_index * hat_step,
                "hat",
                0.16 + (0.10 if step_index % 4 == 0 else 0.0),
                pan=0.30 if step_index % 2 else -0.18,
            )

    add_drum(events, 0.0, "crash", 0.50, pan=-0.36)
    add_drum(events, 16.0, "crash", 0.42, pan=0.36)
    for step in range(8):
        add_drum(events, 30.0 + step * 0.25, "snare", 0.20 + step * 0.05)
    add_drum(events, 30.5, "riser", 0.40, pan=0.22)
    return events


def build_anomaly_section() -> list[Event]:
    """失序段：保留低频脉搏，将两个动机切成不稳定的信号碎片。"""

    events: list[Event] = []
    rng = random.Random(0x8B17)

    for beat in (0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0):
        events.append(
            Event(
                beat=beat,
                duration=1.10,
                kind="bass",
                midi=33,
                gain=0.52,
            )
        )

    for beat, intensity in ((0.0, 0.42), (8.0, 0.54), (16.0, 0.66), (24.0, 0.78)):
        add_drum(events, beat, "static", intensity, pan=-0.44 if int(beat) % 16 == 0 else 0.44)
        add_drum(events, beat + 0.5, "riser", intensity * 0.62, pan=0.36)
        add_drum(events, beat, "kick", 0.32)

    fragments = (
        (69, 0.00),
        (72, 0.75),
        (76, 1.50),
        (74, 3.50),
        (81, 4.75),
        (79, 6.00),
        (72, 8.50),
        (69, 9.25),
        (77, 11.50),
        (81, 13.00),
        (76, 15.25),
        (74, 17.50),
        (72, 19.00),
        (69, 21.75),
        (79, 23.50),
        (77, 25.00),
        (74, 27.50),
        (69, 29.25),
    )
    for index, (midi, beat) in enumerate(fragments):
        detune = rng.choice((-12, -5, 0, 0, 5, 12))
        events.append(
            Event(
                beat=beat,
                duration=rng.choice((0.12, 0.18, 0.28, 0.42)),
                kind="fragment",
                midi=midi + detune,
                gain=0.35 + rng.random() * 0.18,
                pan=rng.uniform(-0.55, 0.55),
                variant=rng.randrange(4),
            )
        )

    for index in range(22):
        beat = rng.uniform(0.0, 31.5)
        drum_kind = rng.choice(("hat", "snare", "kick", "open_hat"))
        gain = rng.uniform(0.08, 0.26)
        add_drum(events, beat, drum_kind, gain, pan=rng.uniform(-0.55, 0.55))

    add_drum(events, 31.0, "riser", 0.45, pan=-0.24)
    add_drum(events, 31.0, "crash", 0.30, pan=0.30)
    return events


def pan_gains(pan: float) -> tuple[float, float]:
    angle = (max(-1.0, min(1.0, pan)) + 1.0) * math.pi * 0.25
    return math.cos(angle), math.sin(angle)


def render_event(
    event: Event,
    sample_rate: int,
    beat_seconds: float,
) -> tuple[list[float], list[float]]:
    duration_s = event.duration * beat_seconds
    frame_count = max(1, int(round(duration_s * sample_rate)))
    left = [0.0] * frame_count
    right = [0.0] * frame_count
    left_gain, right_gain = pan_gains(event.pan)
    rng = random.Random(
        (int(event.beat * 1000) * 1_000_003)
        ^ (int(event.midi * 131) + 17)
        ^ (event.variant + 1) * 7919
        ^ sum(ord(char) for char in event.kind)
    )
    phase = 0.0
    previous_noise = 0.0

    for index in range(frame_count):
        time_s = index / sample_rate
        value = 0.0

        if event.kind in ("lead", "echo"):
            frequency = midi_to_hz(event.midi)
            vibrato = 0.0028 * math.sin(TAU * 5.4 * time_s)
            phase += frequency * (1.0 + vibrato) / sample_rate
            duty = 0.25 if event.kind == "lead" else 0.375
            square = 1.0 if (phase % 1.0) < duty else -1.0
            upper = 1.0 if ((phase * 2.0) % 1.0) < 0.125 else -1.0
            value = (square * 0.70 + upper * 0.08)
            value *= note_envelope(time_s, duration_s, 0.006, 0.050, 2.8)
        elif event.kind == "harmonic":
            frequency = midi_to_hz(event.midi)
            phase += frequency / sample_rate
            square = 1.0 if (phase % 1.0) < 0.125 else -1.0
            value = square * note_envelope(time_s, duration_s, 0.004, 0.035, 5.0)
        elif event.kind == "fragment":
            frequency = midi_to_hz(event.midi)
            drift = 1.0 + 0.018 * math.sin(TAU * (1.7 + event.variant * 0.53) * time_s)
            phase += frequency * drift / sample_rate
            duty = 0.125 + event.variant * 0.075
            square = 1.0 if (phase % 1.0) < duty else -1.0
            noise = rng.uniform(-1.0, 1.0)
            value = square * 0.58 + (noise - previous_noise) * 0.09
            value *= note_envelope(time_s, duration_s, 0.002, 0.020, 7.0)
            previous_noise = noise
        elif event.kind == "bass":
            frequency = midi_to_hz(event.midi)
            phase += frequency / sample_rate
            wrapped = phase % 1.0
            triangle = 1.0 - 4.0 * abs(wrapped - 0.5)
            sub = math.sin(TAU * phase)
            value = triangle * 0.74 + sub * 0.20
            value *= note_envelope(time_s, duration_s, 0.004, 0.055, 1.8)
        elif event.kind == "kick":
            frequency = 43.0 + 125.0 * math.exp(-time_s * 26.0)
            phase += frequency / sample_rate
            body = math.sin(TAU * phase) * math.exp(-time_s * 11.5)
            click = rng.uniform(-1.0, 1.0) * math.exp(-time_s * 180.0)
            value = body * 0.92 + click * 0.15
        elif event.kind == "snare":
            noise = rng.uniform(-1.0, 1.0)
            high_noise = noise - previous_noise * 0.55
            previous_noise = noise
            body = math.sin(TAU * 182.0 * time_s) * math.exp(-time_s * 22.0)
            value = high_noise * math.exp(-time_s * 24.0) * 0.66 + body * 0.23
        elif event.kind in ("hat", "open_hat"):
            noise = rng.uniform(-1.0, 1.0)
            high_noise = noise - previous_noise * 0.82
            previous_noise = noise
            decay = 90.0 if event.kind == "hat" else 22.0
            value = high_noise * math.exp(-time_s * decay) * 0.58
        elif event.kind == "crash":
            noise = rng.uniform(-1.0, 1.0)
            high_noise = noise - previous_noise * 0.68
            previous_noise = noise
            shimmer = math.sin(TAU * (3170.0 + 160.0 * math.sin(TAU * 3.0 * time_s)) * time_s)
            value = (high_noise * 0.72 + shimmer * 0.08) * math.exp(-time_s * 2.6)
        elif event.kind == "riser":
            noise = rng.uniform(-1.0, 1.0)
            high_noise = noise - previous_noise * (0.55 - 0.35 * min(1.0, time_s / duration_s))
            previous_noise = noise
            reveal = (time_s / duration_s) ** 1.7
            value = high_noise * reveal * 0.62
        elif event.kind == "static":
            noise = rng.uniform(-1.0, 1.0)
            gate = 0.52 + 0.48 * math.sin(TAU * 7.0 * time_s + event.variant)
            value = (noise - previous_noise) * gate * math.exp(-time_s * 1.8) * 0.30
            previous_noise = noise

        sample = value * event.gain
        left[index] = sample * left_gain
        right[index] = sample * right_gain

    return left, right


def render_track(
    events: list[Event],
    total_beats: int,
    sample_rate: int,
    wrap_tails: bool,
) -> tuple[list[float], list[float]]:
    beat_seconds = 60.0 / BPM
    frame_count = int(round(total_beats * beat_seconds * sample_rate))
    left = [0.0] * frame_count
    right = [0.0] * frame_count

    for event in sorted(events, key=lambda item: item.beat):
        start = int(round(event.beat * beat_seconds * sample_rate))
        if start >= frame_count:
            continue
        event_left, event_right = render_event(event, sample_rate, beat_seconds)
        for index, (left_sample, right_sample) in enumerate(zip(event_left, event_right)):
            target = start + index
            if target >= frame_count:
                if not wrap_tails:
                    break
                target %= frame_count
            left[target] += left_sample
            right[target] += right_sample

    for index in range(frame_count):
        left[index] = math.tanh(left[index] * 1.18)
        right[index] = math.tanh(right[index] * 1.18)

    return left, right


def smooth_loop_edges(
    left: list[float],
    right: list[float],
    sample_rate: int,
    fade_ms: float = 4.0,
) -> None:
    """在循环首尾做极短淡入淡出，消除音频块边界产生的爆音。"""

    fade_frames = min(len(left) // 2, max(1, int(sample_rate * fade_ms / 1000.0)))
    for index in range(fade_frames):
        gain = index / max(1, fade_frames - 1)
        left[index] *= gain
        right[index] *= gain
        tail_index = -1 - index
        left[tail_index] *= gain
        right[tail_index] *= gain


def write_wav(
    path: Path,
    left: list[float],
    right: list[float],
    sample_rate: int,
    target_peak: float = 0.80,
) -> dict[str, float | int]:
    peak = max(
        max((abs(sample) for sample in left), default=0.0),
        max((abs(sample) for sample in right), default=0.0),
        0.000001,
    )
    scale = target_peak / peak
    pcm = array("h")
    pcm_append = pcm.append
    square_sum = 0.0

    for left_sample, right_sample in zip(left, right):
        left_value = left_sample * scale
        right_value = right_sample * scale
        square_sum += left_value * left_value + right_value * right_value
        pcm_append(int(max(-32767, min(32767, round(left_value * 32767)))))
        pcm_append(int(max(-32767, min(32767, round(right_value * 32767)))))

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(pcm.tobytes())

    frame_count = len(left)
    rms = math.sqrt(square_sum / max(1, frame_count * 2))
    return {
        "frames": frame_count,
        "duration_seconds": round(frame_count / sample_rate, 3),
        "rms_dbfs": round(20.0 * math.log10(max(rms, 0.000001)), 2),
        "peak_dbfs": round(20.0 * math.log10(target_peak), 2),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="生成原创 8-bit 太空探索背景音乐")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("assets/audio/generated"),
        help="WAV 与清单文件的输出目录",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sections = {
        "a_main": build_main_section(),
        "b_discovery": build_discovery_section(),
        "c_anomaly": build_anomaly_section(),
    }
    rendered: dict[str, tuple[list[float], list[float]]] = {}

    for name, events in sections.items():
        print(f"渲染 {name} ...")
        rendered[name] = render_track(
            events,
            total_beats=BEATS_PER_SECTION,
            sample_rate=SAMPLE_RATE,
            wrap_tails=True,
        )
        smooth_loop_edges(rendered[name][0], rendered[name][1], SAMPLE_RATE)

    manifest: dict[str, object] = {
        "title": "Astral Signal 8-bit",
        "description": "原创三段式太空探索配乐，复用 SIGNAL_A 与 SIGNAL_B 两个动机。",
        "bpm": BPM,
        "sample_rate": SAMPLE_RATE,
        "beats_per_section": BEATS_PER_SECTION,
        "motifs": {
            "SIGNAL_A": "稳定探索动机",
            "SIGNAL_B": "发现与展开动机",
        },
        "files": {},
    }
    files_manifest: dict[str, object] = manifest["files"]  # type: ignore[assignment]

    for name, (left, right) in rendered.items():
        path = args.output_dir / f"astral_signal_{name}.wav"
        files_manifest[name] = write_wav(path, left, right, SAMPLE_RATE)
        files_manifest[name]["path"] = str(path)

    suite_events: list[Event] = []
    for section_index, name in enumerate(("a_main", "b_discovery", "c_anomaly")):
        offset = section_index * BEATS_PER_SECTION
        for event in sections[name]:
            suite_events.append(
                Event(
                    beat=event.beat + offset,
                    duration=event.duration,
                    kind=event.kind,
                    midi=event.midi,
                    gain=event.gain,
                    pan=event.pan,
                    variant=event.variant,
                )
            )

    suite_path = args.output_dir / "astral_signal_suite.wav"
    suite_left, suite_right = render_track(
        suite_events,
        total_beats=BEATS_PER_SECTION * len(sections),
        sample_rate=SAMPLE_RATE,
        wrap_tails=False,
    )
    files_manifest["suite"] = write_wav(suite_path, suite_left, suite_right, SAMPLE_RATE)
    files_manifest["suite"]["path"] = str(suite_path)

    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"完成：{args.output_dir}")
    print(f"试听：{suite_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
