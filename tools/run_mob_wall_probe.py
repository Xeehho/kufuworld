# -*- coding: utf-8 -*-
"""刷怪落点取证 runner：temp-inject ProbeMobWall -> run game -> restore project.godot -> report.
用法: python tools/run_mob_wall_probe.py"""
import subprocess, sys, os, json

proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "mob_wall_log.txt")
jp = os.path.join(proj, "tools", "mob_wall_data.json")
MARKER = 'ProbeMobWall="*res://tools/probe_mob_wall.gd"'


def main():
    with open(pg, encoding="utf-8") as f:
        original = f.read()
    try:
        if MARKER not in original:
            patched = original.replace("[autoload]\n", "[autoload]\n\n" + MARKER + "\n", 1)
            with open(pg, "w", encoding="utf-8") as f:
                f.write(patched)
        for p in (gp, jp):
            if os.path.exists(p):
                os.remove(p)
        gf = open(gp, "wb")
        proc = subprocess.Popen([exe, "--path", proj], cwd=proj, stdout=gf, stderr=subprocess.STDOUT)
        timed_out = False
        try:
            proc.communicate(timeout=240)
        except Exception:
            timed_out = True
            proc.kill()
        gf.close()
        if timed_out:
            print("FATAL: game run timed out (240s)")
            sys.exit(2)
    finally:
        with open(pg, "w", encoding="utf-8") as f:
            f.write(original)
        print("project.godot restored")
    if os.path.exists(jp):
        with open(jp, encoding="utf-8") as f:
            print(f.read())
    else:
        print("NO JSON OUTPUT; log tail:")
        with open(gp, "rb") as f:
            print(f.read()[-3000:].decode("utf-8", "replace"))


if __name__ == "__main__":
    main()
