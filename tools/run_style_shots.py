# -*- coding: utf-8 -*-
"""风格重构截图 runner: temp-inject ProbeStyleShots -> run game -> restore project.godot."""
import subprocess, sys, os
proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "probe_style_stdout.txt")
with open(pg, encoding="utf-8") as f:
    original = f.read()
marker = 'ProbeStyleShots="*res://tools/probe_style_shots.gd"'
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
        proc.communicate(timeout=180)
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
for e in gerrs[:15]: print(e)
shots = [f for f in os.listdir(os.path.join(proj, "tools")) if f.startswith("sshot_")]
print("shots:", sorted(shots))
log = os.path.join(proj, "tools", "probe_style_log.txt")
if os.path.exists(log):
    print("--- probe log ---")
    with open(log, encoding="utf-8", errors="replace") as f:
        print(f.read())
