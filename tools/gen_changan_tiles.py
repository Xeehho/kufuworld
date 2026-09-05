# -*- coding: utf-8 -*-
"""长安城新瓦片 PNG 生成（M0 灰盒）：坊门·开 / 坊门·闭
色系锚定 sprites/tiles/ward_wall.png（白灰暖砖）——门框色直接采样复用
配色参照: 参考14号(红门气派) + 唐风微调色板
输出: sprites/tiles/ward_gate_open.png / ward_gate_closed.png
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_pack_assets import load_png, save_png
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILES = os.path.join(ROOT, "sprites", "tiles")
TS = 16

# ---- 从 ward_wall.png 采样砖面/灰缝色，保证坊门门框与坊墙同色系 ----
_w, _h, _rows = load_png(os.path.join(TILES, "ward_wall.png"))
cnt = Counter()
for line in _rows:
    for x in range(0, len(line), 4):
        if line[x+3] >= 10:
            cnt[(line[x], line[x+1], line[x+2])] += 1
BRICK = cnt.most_common(1)[0][0]                      # 砖面主色
BRICK_DARK = min(cnt, key=lambda c: sum(c))          # 灰缝/暗色

WOOD_D = (90, 58, 38)     # 门楣深木
WOOD_M = (146, 92, 56)    # 门扇木中
WOOD_L = (178, 120, 78)   # 木高光
RED_M  = (156, 58, 38)    # 红漆门扇（唐风锚点色）
RED_D  = (112, 38, 24)
GOLD   = (216, 178, 90)
HOLE   = (44, 38, 34)     # 门洞内暗
HOLE_L = (58, 50, 44)

def px(t, x, y, c):
    if 0 <= x < TS and 0 <= y < TS:
        o = (y*TS + x)*4
        t[o:o+4] = bytes(c) + b"\xff"

def rect(t, x0, y0, x1, y1, c):
    for y in range(y0, y1+1):
        for x in range(x0, x1+1):
            px(t, x, y, c)

def brick_rect(t, x0, y0, x1, y1):
    """与 ward_wall 同款的大砖缝砌法"""
    rect(t, x0, y0, x1, y1, BRICK)
    for y in range(y0, y1+1, 4):
        rect(t, x0, min(y1, y+3), x1, min(y1, y+3), BRICK_DARK)
    for band, y in enumerate(range(y0, y1+1, 4)):
        jx = x0 + (2 if band % 2 == 0 else 1)
        if jx <= x1:
            for yy in range(y, min(y1, y+3)+1):
                px(t, jx, yy, BRICK_DARK)

def gate_common(t):
    """门框+门楣（开闭共用）"""
    brick_rect(t, 0, 0, 2, 15)            # 西柱
    brick_rect(t, 13, 0, 15, 15)          # 东柱
    rect(t, 0, 0, 15, 2, WOOD_D)          # 楣
    rect(t, 1, 1, 14, 1, WOOD_M)
    rect(t, 0, 3, 15, 3, BRICK_DARK)      # 楣下压边

def draw_gate(open_state):
    t = bytearray(b"\x00"*(TS*TS*4))
    gate_common(t)
    if open_state:
        rect(t, 3, 4, 12, 14, HOLE)       # 门洞
        for i, x in enumerate(range(3, 13, 3)):   # 洞内微光梯度
            rect(t, x, 6, x, 13, HOLE_L if i % 2 == 0 else HOLE)
        rect(t, 3, 15, 12, 15, BRICK_DARK)        # 门槛石
    else:
        rect(t, 3, 4, 12, 15, WOOD_D)     # 门框底
        rect(t, 4, 5, 11, 15, RED_M)      # 双扇红漆
        rect(t, 7, 5, 8, 15, RED_D)       # 门缝
        rect(t, 4, 5, 4, 15, RED_D)
        rect(t, 11, 5, 11, 15, RED_D)
        for yy in (7, 11):                # 金钉 2x2 阵
            for xx in (5, 10):
                rect(t, xx, yy, xx+1, yy+1, GOLD)
        rect(t, 4, 12, 11, 12, RED_D)     # 门下横枨
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

if __name__ == "__main__":
    save_png(os.path.join(TILES, "ward_gate_closed.png"), TS, TS, draw_gate(False))
    save_png(os.path.join(TILES, "ward_gate_open.png"), TS, TS, draw_gate(True))
    print("[changan-tiles] BRICK=", BRICK, "DARK=", BRICK_DARK, "wrote ward_gate_open/closed.png")
