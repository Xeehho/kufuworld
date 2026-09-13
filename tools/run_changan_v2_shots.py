# -*- coding: utf-8 -*-
"""长安v2 灰盒样张 runner：temp-inject ProbeChanganV2Shots autoload -> windowed 跑真实主场景 -> 还原 project.godot。
开机自动入城（city_visit CITY_VERSION=2）后定点截图 docs/shots/changan_v2_*.png。
用法: python tools/run_changan_v2_shots.py"""
import subprocess, sys, os

proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "changan_v2_shots_log.txt")
MARKER = 'ProbeChanganV2Shots="*res://tools/probe_changan_v2_shots.gd"'


def main():
    with open(pg, "rb") as f:
        original = f.read()
    try:
        marker_bytes = MARKER.encode("utf-8")
        if marker_bytes not in original:
            eol = b"\r\n" if b"[autoload]\r\n" in original else b"\n"
            header = b"[autoload]" + eol
            patched = original.replace(header, header + eol + marker_bytes + eol, 1)
            with open(pg, "wb") as f:
                f.write(patched)
        if os.path.exists(gp):
            os.remove(gp)
        gf = open(gp, "wb")   # 陷阱#34：stdout 落文件句柄
        args = [exe, "--path", proj]   # windowed：需要真实渲染出截图
        proc = subprocess.Popen(args, cwd=proj, stdout=gf, stderr=subprocess.STDOUT)
        timed_out = False
        try:
            proc.communicate(timeout=180)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
        gf.close()
    finally:
        # 字节级恢复：不得把用户当前 project.godot 的 LF/CRLF 或 BOM 顺手改写。
        with open(pg, "wb") as f:
            f.write(original)
    print("project.godot restored")
    with open(gp, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    print(text[-1500:])
    for line in text.splitlines():
        if "[ChangAnV2-Shots]" in line and ("[PASS]" in line or "[FAIL]" in line):
            sys.exit(0 if "[PASS]" in line else 1)
    sys.exit(1)


if __name__ == "__main__":
    main()
