# -*- coding: utf-8 -*-
"""群系/建筑机位视觉审计 runner（2026-08-31 优化验收）:
temp-inject ProbeBiomeShots -> run game windowed -> restore project.godot. 结构复用 run_shots.py。"""
import subprocess, sys, os
proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "probe_biome_stdout.txt")
with open(pg, encoding="utf-8") as f:
    original = f.read()
marker = 'ProbeBiomeShots="*res://tools/probe_biome_shots.gd"'
try:
    if marker not in original:
        patched = original.replace("[autoload]\n", "[autoload]\n\n" + marker + "\n", 1)
        with open(pg, "w", encoding="utf-8") as f:
            f.write(patched)
    if os.path.exists(gp): os.remove(gp)
    gf = open(gp, "wb")
    proc = subprocess.Popen([exe, "--path", proj], cwd=proj, stdout=gf, stderr=subprocess.STDOUT)
    timed_out = False
    try:
        proc.communicate(timeout=150)
    except Exception:
        timed_out = True
        proc.kill()
    gf.close()
    print("timed_out:", timed_out)
finally:
    with open(pg, encoding="utf-8") as f:
        cur = f.read()
    cur = cur.replace("\n" + marker, "").replace(marker, "")
    with open(pg, "w", encoding="utf-8") as f:
        f.write(cur)
    print("project.godot restored:", marker not in cur)
game = open(gp, encoding="utf-8", errors="replace").read() if os.path.exists(gp) else ""
gerrs = [l for l in game.splitlines() if "SCRIPT ERROR" in l or "ERROR:" in l]
print("=== game error lines:", len(gerrs))
for e in gerrs[:10]: print(e)
bl = os.path.join(proj, "tools", "probe_biome_log.txt")
if os.path.exists(bl):
    print("=== probe log tail ===")
    print("".join(open(bl, encoding="utf-8", errors="replace").readlines()[-12:]))
shots = [f for f in os.listdir(os.path.join(proj, "tools")) if f.startswith("vshot_") and ("city" in f or "town" in f or "snow" in f or "yamen" in f)]
print("shots:", sorted(shots))
