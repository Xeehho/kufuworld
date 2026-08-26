# -*- coding: utf-8 -*-
"""Phase D: 程序合成音效+BGM占位WAV（22050Hz/16bit/mono）。
产物: sprites同级 audio/sfx/*.wav 与 audio/bgm/jianghu_loop.wav
重跑安全：覆盖写。运行: python tools/make_phase_d_audio.py
"""
import wave, struct, math, random, os

SR = 22050
ROOT = os.path.join(os.path.dirname(__file__), "..")
SFX_DIR = os.path.normpath(os.path.join(ROOT, "audio", "sfx"))
BGM_DIR = os.path.normpath(os.path.join(ROOT, "audio", "bgm"))
os.makedirs(SFX_DIR, exist_ok=True)
os.makedirs(BGM_DIR, exist_ok=True)

def write_wav(path, samples):
    samples = [max(-1.0, min(1.0, s)) for s in samples]
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wav:", os.path.basename(path), len(samples) / SR, "s")

def t_axis(dur): return [i / SR for i in range(int(dur * SR))]

def env_decay(t, dur, k=8.0):
    return math.exp(-k * t / max(dur, 1e-6))

def lowpass(samples, alpha):
    out, y = [], 0.0
    for s in samples:
        y += alpha * (s - y)
        out.append(y)
    return out

def sine(f, t): return math.sin(2 * math.pi * f * t)

def pluck(f, dur, k=6.0, harmonics=((1, 1.0), (2, 0.45), (3, 0.22))):
    out = []
    for t in t_axis(dur):
        e = env_decay(t, dur, k)
        v = sum(a * sine(f * h, t) for h, a in harmonics)
        # 拨弦起振瞬态
        attack = min(1.0, t / 0.008)
        out.append(v * e * attack * 0.6)
    return out

# ---- 各音效 ----
def swing():
    dur = 0.18; rnd = random.Random(7)
    raw = [ (rnd.random() * 2 - 1) for _ in t_axis(dur) ]
    sm = lowpass(raw, 0.25)
    out = []
    for i, t in enumerate(t_axis(dur)):
        p = t / dur
        amp = math.sin(math.pi * p) ** 1.5          # 中段最响
        pitch_lift = sm[i] * (0.5 + 1.4 * p)        # 越挥越高频感
        out.append(pitch_lift * amp * 0.8)
    return out

def hit():
    dur = 0.14; out = []; rnd = random.Random(3)
    for t in t_axis(dur):
        thump = sine(110 - 40 * t / dur, t)
        click = (rnd.random() * 2 - 1) * env_decay(t, dur, 40)
        out.append((thump * 0.9 + click * 0.5) * env_decay(t, dur, 14))
    return out

def hurt():
    dur = 0.22; out = []
    for t in t_axis(dur):
        f = 210 - 120 * (t / dur)
        v = sine(f, t) * 0.7 + sine(f * 0.5, t) * 0.3
        trem = 0.75 + 0.25 * math.sin(2 * math.pi * 26 * t)
        out.append(v * env_decay(t, dur, 7) * trem)
    return out

def mob_die():
    dur = 0.42; out = []
    for t in t_axis(dur):
        f = 300 * math.exp(-3.2 * t)
        ph = 0.0; v = 0.0
        steps = 24
        for i in range(steps):
            tt = i * dur / steps
            ff = 300 * math.exp(-3.2 * tt)
            v += math.sin(2 * math.pi * ff * t) / steps
        out.append(v * env_decay(t, dur, 6) * 1.4)
    return out

def player_die():
    dur = 1.3; out = []
    for t in t_axis(dur):
        gong = sine(82, t) + 0.5 * sine(164, t) + 0.28 * sine(247, t) + 0.15 * sine(331, t)
        beat = 1.0 + 0.12 * math.sin(2 * math.pi * 5.5 * t)
        out.append(gong * env_decay(t, dur, 3.2) * beat * 0.32)
    return lowpass(out, 0.6)

def till():
    dur = 0.16; rnd = random.Random(11)
    raw = [ (rnd.random() * 2 - 1) for _ in t_axis(dur) ]
    sm = lowpass(raw, 0.12)   # 土的闷
    return [s * env_decay(t, dur, 9) * 1.5 for t, s in zip(t_axis(dur), sm)]

def water():
    dur = 0.30; rnd = random.Random(5); out = []
    raw = [ (rnd.random() * 2 - 1) for _ in t_axis(dur) ]
    hi = []  # 粗高通：原信号减低通
    lp = lowpass(raw, 0.35)
    for a, b in zip(raw, lp): hi.append((a - b) * 1.2)
    for t, h in zip(t_axis(dur), hi):
        bub = sine(320 + 240 * math.sin(2 * math.pi * 13 * t), t) * 0.35
        fade_in = min(1.0, t / 0.02)
        out.append((h * 0.55 + bub) * env_decay(t, dur, 6) * fade_in)
    return out

def plant():
    dur = 0.10; out = []
    for t in t_axis(dur):
        f = 480 + 260 * (t / dur)
        out.append(sine(f, t) * env_decay(t, dur, 10) * 0.7)
    return out

def harvest():
    a = pluck(659.3, 0.16, 7); b = pluck(880.0, 0.20, 7)
    gap = [0.0] * int(0.055 * SR)
    return a + gap + b

def craft_ok():
    seq = [(523.3, 0.13), (659.3, 0.13), (784.0, 0.22)]
    out = []
    for i, (f, d) in enumerate(seq):
        seg = pluck(f, d, 6)
        if i < len(seq) - 1:
            overlap = int(0.03 * SR)
            tail = seg[-overlap:]; seg = seg[:-overlap]
            if out:
                for j in range(overlap):
                    if j < len(out): out[-overlap + j] += tail[j]
            else:
                out += tail
        out += seg
    return out

def craft_fail():
    dur = 0.24; out = []
    for t in t_axis(dur):
        gate = 1.0 if (t % 0.11) < 0.07 else 0.0
        v = (sine(140, t) * 0.6 + sine(99, t) * 0.4)
        out.append(v * gate * 0.8)
    return out

def ui():
    dur = 0.05
    return [sine(1250, t) * env_decay(t, dur, 16) * 0.5 for t in t_axis(dur)]

# ---- BGM：五声羽调古筝式拨弦循环 ~26s ----
def bgm():
    rnd = random.Random(20240601)
    bpm = 84.0; beat = 60.0 / bpm            # 0.714s
    step = beat / 2                          # 八分音符
    scale = [293.66, 349.23, 392.00, 440.00, 523.25, 587.33]  # D4 F4 G4 A4 C5 D5
    drone_f = 146.83                         # D3
    total_steps = 72
    dur = total_steps * step + 2.0
    n = int(dur * SR)
    mix = [0.0] * n
    # 低音持续音垫
    for i in range(n):
        t = i / SR
        mix[i] += 0.055 * (math.sin(2 * math.pi * drone_f * t) + 0.4 * math.sin(2 * math.pi * drone_f * 2 * t))
    # 旋律：带休止的随机游走，句尾回落主音
    cur = 2
    pattern = []
    for s_i in range(total_steps):
        bar_pos = s_i % 8
        r = rnd.random()
        if bar_pos == 7 and rnd.random() < 0.7:
            note = 0                          # 句尾落D4
        elif r < 0.30:
            note = None                       # 休止
        else:
            cur = max(0, min(len(scale) - 1, cur + rnd.choice([-2, -1, -1, 1, 1, 2])))
            note = cur
        pattern.append(note)
    for s_i, note in enumerate(pattern):
        if note is None: continue
        f = scale[note]
        seg = pluck(f, min(step * 2.2, 1.4), k=5.0)
        start = int(s_i * step * SR)
        vel = 0.34 if s_i % 4 == 0 else 0.26
        for j, sv in enumerate(seg):
            idx = start + j
            if idx < n: mix[idx] += sv * vel
    # 首尾交叉拼接保证无缝循环
    xf = int(0.8 * SR)
    for i in range(xf):
        a = i / xf
        mix[i] = mix[i] * a + mix[n - xf + i] * (1 - a)
    return mix[: n - xf]

if __name__ == "__main__":
    write_wav(os.path.join(SFX_DIR, "swing.wav"), swing())
    write_wav(os.path.join(SFX_DIR, "hit.wav"), hit())
    write_wav(os.path.join(SFX_DIR, "hurt.wav"), hurt())
    write_wav(os.path.join(SFX_DIR, "mob_die.wav"), mob_die())
    write_wav(os.path.join(SFX_DIR, "player_die.wav"), player_die())
    write_wav(os.path.join(SFX_DIR, "till.wav"), till())
    write_wav(os.path.join(SFX_DIR, "water.wav"), water())
    write_wav(os.path.join(SFX_DIR, "plant.wav"), plant())
    write_wav(os.path.join(SFX_DIR, "harvest.wav"), harvest())
    write_wav(os.path.join(SFX_DIR, "craft_ok.wav"), craft_ok())
    write_wav(os.path.join(SFX_DIR, "craft_fail.wav"), craft_fail())
    write_wav(os.path.join(SFX_DIR, "ui.wav"), ui())
    write_wav(os.path.join(BGM_DIR, "jianghu_loop.wav"), bgm())
    print("done")
