# -*- coding: utf-8 -*-
"""v4 M1 farm 镇机位截图 runner: temp-inject ProbeV4Shots -> run game -> restore project.godot."""
import subprocess, os
proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "probe_v4_shots_stdout.txt")
marker = 'ProbeV4Shots="*res://tools/probe_v4_shots.gd"'
with open(pg, encoding="utf-8") as f:
    original = f.read()
try:
    if marker not in original:
        patched = original.replace("[autoload]\n", "[autoload]\n\n" + marker + "\n", 1)
        with open(pg, "w", encoding="utf-8") as f:
            f.write(patched)
    if os.path.exists(gp):
        os.remove(gp)
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
    cur = cur.replace("[autoload]\n\n\n\n", "[autoload]\n\n").replace("[autoload]\n\n\n", "[autoload]\n\n")
    with open(pg, "w", encoding="utf-8") as f:
        f.write(cur)
    print("project.godot restored:", marker not in cur)
log = os.path.join(proj, "tools", "probe_v4_shots_log.txt")
print(open(log, encoding="utf-8", errors="replace").read() if os.path.exists(log) else "NO LOG")
