import subprocess, sys, os, time
exe = open(r"C:\Learn\my-godot-project\tools\godot_path.txt", "rb").read().decode("gbk")
proj = r"C:\Learn\my-godot-project"
for i in range(4):
    p = os.path.join(proj,"tools","probe_shot_%d.png"%i)
    if os.path.exists(p): os.remove(p)
lp = os.path.join(proj,"tools","probe_log.txt")
if os.path.exists(lp): os.remove(lp)
proc = subprocess.Popen([exe, "--path", proj],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
try:
    proc.communicate(timeout=50)
except Exception:
    proc.kill()
log = open(lp, encoding="utf-8").read() if os.path.exists(lp) else "(no log)"
sys.stdout.buffer.write(log[-400:].encode("utf-8"))