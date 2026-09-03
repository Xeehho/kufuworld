# -*- coding: utf-8 -*-
"""山地死路取证 runner：temp-inject ProbeMtnMaze -> run game -> restore project.godot -> report.
用法: python tools/run_mtn_probe.py <tag>   （tag 串入 JSON 与截图名，如 before/after）"""
import subprocess, sys, os, json

proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "mtn_maze_log.txt")
jp = os.path.join(proj, "tools", "mtn_maze_data.json")
MARKER = 'ProbeMtnMaze="*res://tools/probe_mtn_maze.gd"'
TAG = sys.argv[1] if len(sys.argv) > 1 else "x"


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
        env = dict(os.environ)
        env["MTN_TAG"] = TAG
        proc = subprocess.Popen([exe, "--path", proj], cwd=proj, stdout=gf, stderr=subprocess.STDOUT, env=env)
        timed_out = False
        try:
            proc.communicate(timeout=300)
        except Exception:
            timed_out = True
            proc.kill()
        gf.close()
        if timed_out:
            print("FATAL: game run timed out (300s)")
            sys.exit(2)
    finally:
        with open(pg, encoding="utf-8") as f:
            cur = f.read()
        cur = cur.replace("\n" + MARKER, "").replace(MARKER, "")
        cur = cur.replace("[autoload]\n\n\n\n", "[autoload]\n\n").replace("[autoload]\n\n\n", "[autoload]\n\n")
        with open(pg, "w", encoding="utf-8") as f:
            f.write(cur)

    if not os.path.exists(jp):
        print("FATAL: no data json; log tail:")
        print("".join(open(gp, encoding="utf-8", errors="replace").readlines()[-15:]))
        sys.exit(2)
    data = json.load(open(jp, encoding="utf-8"))
    if "FATAL" in data:
        print("FATAL in probe:", data["FATAL"])
        sys.exit(2)

    g = data["global"]
    b = data["box"]
    print("=" * 60)
    print("MTN MAZE REPORT  tag=%s" % data["tag"])
    print("=" * 60)
    print("[global] walk=%d mtn_walk=%d" % (g["walk"], g["mtn_walk"]))
    print("  deg<=1 cells: all=%d mtn=%d" % (g["leaf1_all"], g["leaf1_mtn"]))
    print("  leaf-strip closure (mtn dead-end subtree): %d cells / %d rounds"
          % (g["strip_total"], g["strip_rounds"]))
    print("  depth-to-exit: max=%d mean=%.1f  %%<=8=%.1f%%  %%<=16=%.1f%%"
          % (g["depth_max"], g["depth_mean"], g["depth_le8_ratio"] * 100, g["depth_le16_ratio"] * 100))
    print("[box %d,%d..%d,%d] mtn=%d leaf1=%d strip=%d deep_mean=%.1f deepest=%s d=%d"
          % (b["x0"], b["y0"], b["x1"], b["y1"], b["mtn"], b["leaf1"], b["strip"],
             b["deep_mean"], tuple(b["deepest"]), b["deepest_d"]))
    with open(os.path.join(proj, "tools", "mtn_maze_map_%s.txt" % data["tag"]), "w", encoding="utf-8") as f:
        f.write("\n".join(data["map"]))
    print("map dump -> tools/mtn_maze_map_%s.txt" % data["tag"])


if __name__ == "__main__":
    main()
