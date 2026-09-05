# -*- coding: utf-8 -*-
"""长安M1 E2E 探针 runner：temp-inject ProbeChanganE2E autoload -> run game -> restore project.godot。
headless 跑真实主场景全链路（/root/Main 绝对路径引用才生效，勿用探针场景包一层）。
用法: python tools/run_changan_e2e.py"""
import subprocess, sys, os

proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "changan_e2e_log.txt")
MARKER = 'ProbeChanganE2E="*res://tools/probe_changan_e2e.gd"'


def main():
    with open(pg, encoding="utf-8") as f:
        original = f.read()
    try:
        if MARKER not in original:
            patched = original.replace("[autoload]\n", "[autoload]\n\n" + MARKER + "\n", 1)
            with open(pg, "w", encoding="utf-8") as f:
                f.write(patched)
        if os.path.exists(gp):
            os.remove(gp)
        # 陷阱#34：stdout 落文件句柄，勿用 PIPE；加 windowed 参数跑窗口模式出截图样张
        gf = open(gp, "wb")
        args = [exe] + ([] if "windowed" in sys.argv else ["--headless"]) + ["--path", proj]
        proc = subprocess.Popen(args, cwd=proj, stdout=gf, stderr=subprocess.STDOUT)
        timed_out = False
        try:
            proc.communicate(timeout=180)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
        gf.close()
        if timed_out:
            print("FATAL: E2E probe timed out (180s)")
            sys.exit(2)
    finally:
        with open(pg, "w", encoding="utf-8") as f:
            f.write(original)
    print("project.godot restored")
    with open(gp, "r", encoding="utf-8", errors="replace") as f:
        tail = f.read()
    print(tail[-3000:])
    for line in tail.splitlines():
        if "[ChangAn-M1-E2E]" in line:
            code = 0 if "[PASS]" in line else 1
            sys.exit(code)
    sys.exit(1)


if __name__ == "__main__":
    main()
