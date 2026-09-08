# -*- coding: utf-8 -*-
"""长安 E2E 探针 runner：temp-inject autoload -> run game -> restore project.godot。
按 city_visit.gd 的 CITY_VERSION 自动分发：2=v2剧情尺度新城灰盒（probe_changan_v2_e2e.gd）；
1=旧城108坊（probe_changan_e2e.gd，v1 验收归档用）。
headless 跑真实主场景全链路（/root/Main 绝对路径引用才生效，勿用探针场景包一层）。
用法: python tools/run_changan_e2e.py [windowed]"""
import subprocess, sys, os, re

proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "changan_e2e_log.txt")

with open(os.path.join(proj, "scripts", "city_visit.gd"), encoding="utf-8") as f:
    m = re.search(r"CITY_VERSION\s*:?=\s*(\d)", f.read())
CITY_VERSION = int(m.group(1)) if m else 1
if CITY_VERSION == 2:
    MARKER = 'ProbeChanganV2E2E="*res://tools/probe_changan_v2_e2e.gd"'
    DONE_TAG = "[ChangAnV2-E2E]"
else:
    MARKER = 'ProbeChanganE2E="*res://tools/probe_changan_e2e.gd"'
    DONE_TAG = "[ChangAn-M1-E2E]"
print("CITY_VERSION=%d -> %s" % (CITY_VERSION, MARKER.split("=")[0]))


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
        env = dict(os.environ)  # CHANGAN_SHOT 透传给定点截图模式
        proc = subprocess.Popen(args, cwd=proj, stdout=gf, stderr=subprocess.STDOUT, env=env)
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
        if DONE_TAG in line and ("[PASS]" in line or "[FAIL]" in line) and "全链路" in line:
            code = 0 if "[PASS]" in line else 1
            sys.exit(code)
    sys.exit(1)


if __name__ == "__main__":
    main()
