# -*- coding: utf-8 -*-
import subprocess, sys
exe = open('tools/godot_path.txt','rb').read().decode('gbk','ignore').strip()
scripts = sys.argv[1:]
for s in scripts:
    p = subprocess.run([exe, "--headless", "--path", ".", "--check-only", "--script", "res://"+s], capture_output=True, timeout=120)
    out=(p.stdout+p.stderr).decode('utf-8','ignore')
    bad=[l.strip()[:150] for l in out.splitlines() if ('ERROR' in l)]
    print("==", s, "rc", p.returncode)
    for l in bad[:6]:
        print("   ", l)
