# -*- coding: utf-8 -*-
"""Phase H probe runner: temp-inject ProbeAutoload -> run game -> restore project.godot."""
import subprocess, sys, os
proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
lp = os.path.join(proj, "tools", "probe_h_log.txt")
gp = os.path.join(proj, "tools", "probe_h_stdout.txt")
with open(pg, encoding="utf-8") as f:
    original = f.read()
marker = 'ProbeAutoload="*res://tools/probe_phase_h.gd"'
killed = False
try:
    if marker not in original:
        patched = original.replace("[autoload]\n", "[autoload]\n\n" + marker + "\n", 1)
        with open(pg, "w", encoding="utf-8") as f:
            f.write(patched)
    for pth in (lp, gp):
        if os.path.exists(pth): os.remove(pth)
    gf = open(gp, "wb")
    proc = subprocess.Popen([exe, "--path", proj], cwd=proj, stdout=gf, stderr=subprocess.STDOUT)
    timed_out = False
    try:
        proc.communicate(timeout=110)
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
log = open(lp, encoding="utf-8").read() if os.path.exists(lp) else "(no probe log)"
game = open(gp, encoding="utf-8", errors="replace").read() if os.path.exists(gp) else ""
gerrs = [l for l in game.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l or "ERROR:" in l]
print("=== game error lines:", len(gerrs))
for e in gerrs[:12]: print(e)
print("=== probe log tail ===")
sys.stdout.buffer.write(("\n".join(log.splitlines()[-60:])).encode("utf-8"))
