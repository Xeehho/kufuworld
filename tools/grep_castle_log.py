# -*- coding: utf-8 -*-
"""从游戏stdout日志过滤古堡相关行"""
log = open(r'C:\Learn\my-godot-project\tools\probe_style_stdout.txt', encoding='utf-8', errors='replace').read()
for line in log.splitlines():
    if ('Castle' in line) or ('Placed POI' in line) or ('古堡' in line) or ('force spawn' in line) or ('POIs scattered' in line):
        print(line)
