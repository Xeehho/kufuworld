# -*- coding: utf-8 -*-
"""竹林实机截图 runner：temp-inject ProbeBambooShot -> run game windowed -> restore project.godot。
（模式同 run_shots.py；陷阱#34：stdout 落文件句柄而非 PIPE）"""
import subprocess, sys, os

proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "probe_bamboo_stdout.txt")
MARKER = 'ProbeBambooShot="*res://tools/probe_bamboo_shot.gd"'

with open(pg, encoding="utf-8") as f:
    original = f.read()
try:
    if MARKER not in original:
        patched = original.replace("[autoload]\n", "[autoload]\n\n" + MARKER + "\n", 1)
        with open(pg, "w", encoding="utf-8") as f:
            f.write(patched)
    if os.path.exists(gp):
        os.remove(gp)
    gf = open(gp, "wb")
    proc = subprocess.Popen([exe, "--path", proj], cwd=proj, stdout=gf, stderr=subprocess.STDOUT)
    timed_out = False
    try:
        proc.communicate(timeout=120)
    except Exception:
        timed_out = True
        proc.kill()
    gf.close()
    if timed_out:
        print("FATAL: probe timed out (120s)")
        sys.exit(2)
finally:
    with open(pg, encoding="utf-8") as f:
        cur = f.read()
    cur = cur.replace("\n" + MARKER, "").replace(MARKER, "")
    cur = cur.replace("[autoload]\n\n\n", "[autoload]\n\n")
    with open(pg, "w", encoding="utf-8") as f:
        f.write(cur)

shot = os.path.join(proj, "docs", "shots", "bamboo_mw_ingame.png")
print("shot exists:", os.path.exists(shot))
log = open(gp, encoding="utf-8", errors="replace").read()
tail = [ln for ln in log.splitlines() if "BambooProbe" in ln or "ERROR" in ln or "SCRIPT" in ln]
print("\n".join(tail[-8:]))
