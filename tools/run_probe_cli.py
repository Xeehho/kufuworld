# -*- coding: utf-8 -*-
"""临时：CLI 运行 Godot 回归探针（捕获输出到文件，避免 GUI/PowerShell stdout 坑）"""
import subprocess, sys, time, os

ROOT = r"c:\Learn\my-godot-project"

def godot_exe():
    # 优先 godot_path.txt（GBK）；否则用本机已知安装位置
    p = os.path.join(ROOT, "godot_path.txt")
    if os.path.exists(p):
        with open(p, "rb") as f:
            raw = f.read().decode("gbk", errors="ignore").strip()
        cand = raw.splitlines()[0].strip() if raw else ""
        if cand and os.path.exists(cand):
            return cand
    fallback = r"C:\迅雷下载\Godot_v4.6.2-stable_win64.exe"
    return fallback if os.path.exists(fallback) else ""

def main():
    exe = godot_exe()
    if not exe or not os.path.exists(exe):
        print("godot not found:", exe)
        sys.exit(1)
    # 清理上轮日志/截图，避免残留"探针结束"导致误判提前退出
    for f in ["probe_reg_log.txt"]:
        fp = os.path.join(ROOT, "tools", f)
        if os.path.exists(fp):
            os.remove(fp)
    out = open(os.path.join(ROOT, "tools", "cli_run_out.txt"), "w", encoding="utf-8", errors="ignore")
    # 以探针场景启动（内部自行实例化主场景），不依赖project.godot autoload注入
    p = subprocess.Popen([exe, "--path", ROOT, "res://tools/probe_main.tscn"], cwd=ROOT,
                         stdout=out, stderr=subprocess.STDOUT)
    print("started pid=", p.pid)
    deadline = time.time() + 120
    log = os.path.join(ROOT, "tools", "probe_reg_log.txt")
    while time.time() < deadline:
        if os.path.exists(log):
            with open(log, "r", encoding="utf-8", errors="ignore") as f:
                txt = f.read()
            if "探针结束" in txt:
                print("probe finished")
                break
        time.sleep(1)
    time.sleep(2)
    try:
        p.terminate()
        p.wait(timeout=10)
    except Exception:
        p.kill()
    out.close()
    print("done")

if __name__ == "__main__":
    main()
