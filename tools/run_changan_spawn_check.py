# -*- coding: utf-8 -*-
"""出生点自动入城检查 runner：无探针注入直接启动游戏（真实用户路径），15s 后杀进程查日志。
预期：日志出现 [CityVisit] 出生点=长安明德门内（自动入城） 与 入城 S（明德门）。
用法: python tools/run_changan_spawn_check.py"""
import subprocess, sys, os, time

proj = r"C:\Learn\my-godot-project"
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
log = os.path.join(proj, "tools", "changan_spawn_check_log.txt")

def main():
    if os.path.exists(log):
        os.remove(log)
    gf = open(log, "wb")
    # --quit-after 1200 帧 ≈ 20s：优雅退出保证 stdout 缓冲完整落盘（杀进程会丢尾部日志，陷阱#34同款）
    proc = subprocess.Popen([exe, "--path", proj, "--quit-after", "1200"], cwd=proj, stdout=gf, stderr=subprocess.STDOUT)
    try:
        proc.communicate(timeout=90)
        ended = True
    except subprocess.TimeoutExpired:
        ended = False
        proc.kill()
        proc.communicate()
    gf.close()
    with open(log, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    hit1 = "出生点=长安明德门内" in text
    hit2 = "入城 S（明德门）" in text
    print("auto_enter_log=%s enter_city_log=%s (ended=%s)" % (hit1, hit2, ended))
    if hit1 and hit2:
        print("[SpawnCheck][PASS] 开机自动入城生效")
        sys.exit(0)
    print("[SpawnCheck][FAIL] 自动入城未触发，日志尾部：")
    print(text[-2000:])
    sys.exit(1)

if __name__ == "__main__":
    main()
