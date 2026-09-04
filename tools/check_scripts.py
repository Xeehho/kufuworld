# -*- coding: utf-8 -*-
import subprocess, os, sys
proj = r"C:\Learn\my-godot-project"
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
files = sys.argv[1:]
for f in files:
    p = subprocess.run([exe, "--headless", "--path", proj, "--check-only", "--script", "res://" + f],
                       capture_output=True, timeout=40)
    out = (p.stdout + p.stderr).decode("utf-8", errors="replace")
    tag = "OK" if p.returncode == 0 and "Parse Error" not in out else "ERR"
    print(f, "=>", tag)
    if tag == "ERR":
        print(out[:1500])