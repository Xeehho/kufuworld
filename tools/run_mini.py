import subprocess, sys, os, time
exe = open(r"C:\Learn\my-godot-project\tools\godot_path.txt", "rb").read().decode("gbk")
proj = r"C:\Learn\my-godot-project"
for i in range(3):
    p = os.path.join(proj,"tools","probe_shot_%d.png"%i)
    if os.path.exists(p): os.remove(p)
if os.path.exists(proj+"\\tools\\probe_log.txt"): os.remove(proj+"\\tools\\probe_log.txt")
t0=time.time()
proc = subprocess.Popen([exe, "--path", proj, "res://tools/screenshot_probe.tscn"],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
try:
    out = proc.communicate(timeout=50)[0]
except Exception:
    proc.kill(); out = proc.stdout.read()
sys.stdout.buffer.write(("rc=%s elapsed=%.1f\n" % (proc.poll(), time.time()-t0)).encode()
    + out.decode("utf-8","replace").split("godot_ai")[1].splitlines()[1:].__str__()[:200].encode() + "\n---PROBE LOG---\n".encode())
log = ""
lp = os.path.join(proj,"tools","probe_log.txt")
if os.path.exists(lp):
    log = open(lp, encoding="utf-8").read()
sys.stdout.buffer.write(log.encode("utf-8"))
