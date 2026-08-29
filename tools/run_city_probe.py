# -*- coding: utf-8 -*-
"""回归探针runner: temp-inject ProbeCity -> run game windowed -> restore project.godot."""
import subprocess, sys, os
proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "probe_city_stdout.txt")
with open(pg, encoding="utf-8") as f:
    original = f.read()
marker = 'ProbeCity="*res://tools/probe_city.gd"'
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
key_lines = [l for l in game.splitlines() if ("[T0]" in l or "[T1]" in l or "[T2]" in l or "[T3]" in l or "City[" in l or "NPCSpawner" in l or "Meditation" in l or "ALL_CITY_PROBE_DONE" in l)]
print("=== key lines:")
for l in key_lines: print(l)
errs = [l for l in game.splitlines() if ("SCRIPT ERROR" in l or "ERROR:" in l or "WARNING" in l and "WorldGen" in l)]
print("=== error lines:", len(errs))
for e in errs[:15]: print(e)
