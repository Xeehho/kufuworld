# -*- coding: utf-8 -*-
import sys, io
_out = open(r"C:\Learn\my-godot-project\tools\probe_run_d_out.txt", "wb")
sys.stdout = io.TextIOWrapper(_out, encoding="utf-8")
sys.stderr = sys.stdout
exec(compile(open(r"C:\Learn\my-godot-project\tools\run_probe_d.py", encoding="utf-8").read(), "run_probe_d.py", "exec"))
_out.flush()