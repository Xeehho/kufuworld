import subprocess, sys
raw = subprocess.run(
    ["powershell", "-Command", "(Get-Process -Id 208460 -ErrorAction SilentlyContinue).Path"],
    capture_output=True).stdout
# Windows 控制台默认 GBK/CP936 输出中文
for enc in ("gbk", "utf-8"):
    try:
        p = raw.decode(enc).strip()
        if p and "\\x" not in repr(p):
            break
    except Exception:
        continue
with open(r"C:\Learn\my-godot-project\tools\godot_path.txt", "wb") as f:
    f.write(raw.strip())
sys.stdout.buffer.write(("saved_bytes=%d" % len(raw.strip())).encode())
