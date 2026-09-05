# -*- coding: utf-8 -*-
"""长安城瓦片 PNG 生成（M0 坊门 + M2 宅门品级/宫墙/外郭墙/御道）
色系锚定 sprites/tiles/ward_wall.png（白灰暖砖）——门框色直接采样复用
配色参照: 参考14号(红门气派) + 唐风微调色板
输出:
  M0: ward_gate_open.png / ward_gate_closed.png
  M2: changan_gate_a/b/c.png（宅门品级75~77）changan_palace_wall.png（69宫墙）
      changan_outer_wall.png（70外郭城墙）changan_zhuque.png（71御道）
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

# ---- M2 宅门品级（设计稿§5.1 75~77）：A 朱门金钉五路（亲王/公主/国寺）
#      B 朱门素铜钉（国公/郡王/士族）  C 黑漆木门（官署/曲坊小宅）----
def draw_mansion_gate(grade: str):
    t = bytearray(b"\x00"*(TS*TS*4))
    # 两侧墙垛（与坊墙同砌法）
    brick_rect(t, 0, 0, 2, 15)
    brick_rect(t, 13, 0, 15, 15)
    # 门楣+屋顶压边：A/B 出挑檐口（灰瓦），C 素木楣
    if grade in ("A", "B"):
        rect(t, 0, 0, 15, 1, (70, 70, 76))    # 檐口灰瓦
        rect(t, 1, 2, 14, 2, WOOD_D)          # 门楣
        rect(t, 1, 3, 14, 3, WOOD_M)
        if grade == "A":
            for xx in (2, 7, 12):             # 檐下金钉门簪三路
                rect(t, xx, 2, xx+1, 2, GOLD)
    else:
        rect(t, 0, 0, 15, 1, WOOD_D)
        rect(t, 1, 1, 14, 3, WOOD_D)          # 黑漆素楣
        rect(t, 1, 3, 14, 3, (60, 40, 28))
    # 门扇
    if grade == "C":
        rect(t, 3, 4, 12, 15, (52, 44, 40))   # 黑漆门扇
        rect(t, 7, 4, 8, 15, (38, 32, 30))    # 门缝
        rect(t, 3, 12, 12, 12, (38, 32, 30))  # 横枨
    else:
        rect(t, 3, 4, 12, 15, RED_M)
        rect(t, 7, 4, 8, 15, RED_D)
        rect(t, 3, 4, 3, 15, RED_D)
        rect(t, 12, 4, 12, 15, RED_D)
        if grade == "A":                       # 五路门钉（行×列）
            for yy in (5, 8, 11, 13):
                for xx in (4, 6, 9, 11):
                    rect(t, xx, yy, xx, yy, GOLD)
            rect(t, 5, 7, 10, 7, GOLD)         # 门环横钹
        else:                                  # 素铜钉四角
            for yy in (5, 13):
                for xx in (4, 11):
                    rect(t, xx, yy, xx+1, yy+1, (176, 148, 96))
        rect(t, 3, 14, 12, 14, RED_D)          # 下横枨
    rect(t, 3, 15, 12, 15, BRICK_DARK)         # 门槛石
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

# ---- M2 宫墙 69：朱红墙身+顶部灰瓦压顶（大明宫红墙意象）----
def draw_palace_wall():
    t = bytearray(b"\x00"*(TS*TS*4))
    REDD = (146, 56, 40)     # 墙身朱红
    REDD_D = (112, 40, 28)   # 红暗缝
    REDD_L = (172, 74, 52)   # 受光
    TILE_G = (84, 84, 92)    # 灰瓦
    TILE_GD = (62, 62, 70)
    rect(t, 0, 0, 15, 1, TILE_G)       # 顶部灰瓦压顶
    rect(t, 0, 2, 15, 2, TILE_GD)
    for x in (3, 8, 13):
        rect(t, x, 0, x, 1, TILE_GD)   # 瓦垄
    rect(t, 0, 3, 15, 15, REDD)
    for y in (7, 12):
        rect(t, 0, y, 15, y, REDD_D)   # 砖层缝
    for band, y in enumerate((3, 8, 13)):
        jx = 4 if band % 2 == 0 else 10
        rect(t, jx, y, jx, min(15, y+3), REDD_D)   # 竖向错缝
    rect(t, 0, 3, 15, 3, REDD_L)       # 檐下受光
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

# ---- M2 外郭城墙 70：夯土大砖（黄土墙身+深缝+根部的黑土线）----
def draw_outer_wall():
    t = bytearray(b"\x00"*(TS*TS*4))
    EARTH = (168, 138, 96)
    EARTH_D = (128, 102, 70)
    EARTH_L = (190, 162, 118)
    rect(t, 0, 0, 15, 0, (86, 82, 78))         # 墙顶压边
    rect(t, 0, 1, 15, 13, EARTH)
    for y in (4, 9):                            # 大块夯土层缝
        rect(t, 0, y, 15, y, EARTH_D)
    for band, y in enumerate((1, 5, 10)):       # 竖向错缝
        jx = 3 if band % 2 == 0 else 10
        rect(t, jx, y, jx, y+2, EARTH_D)
        rect(t, (12 if band % 2 == 0 else 6), y, (12 if band % 2 == 0 else 6), y+2, EARTH_D)
    rect(t, 0, 1, 15, 1, EARTH_L)               # 顶部受光
    rect(t, 0, 14, 15, 15, (96, 78, 56))        # 根部
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

# ---- M2 朱雀御道 71：大块石板+纵列对缝（比石板更整饬，中轴气势）----
def draw_zhuque():
    t = bytearray(b"\x00"*(TS*TS*4))
    ST = (172, 164, 150)
    ST_D = (138, 130, 118)
    ST_L = (196, 189, 176)
    rect(t, 0, 0, 15, 15, ST)
    for y in (0, 8):                            # 两排大石板
        rect(t, 0, y, 15, y, ST_D)
    off = 0                                     # 纵缝上下错位
    for x in (5, 11):
        rect(t, x, 1, x, 7, ST_D)
    for x in (2, 8, 14):
        rect(t, x, 9, x, 15, ST_D)
    rect(t, 1, 1, 4, 1, ST_L)                   # 板面受光
    rect(t, 9, 9, 13, 9, ST_L)
    rect(t, 0, 15, 15, 15, ST_D)
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

if __name__ == "__main__":
    save_png(os.path.join(TILES, "ward_gate_closed.png"), TS, TS, draw_gate(False))
    save_png(os.path.join(TILES, "ward_gate_open.png"), TS, TS, draw_gate(True))
    save_png(os.path.join(TILES, "changan_gate_a.png"), TS, TS, draw_mansion_gate("A"))
    save_png(os.path.join(TILES, "changan_gate_b.png"), TS, TS, draw_mansion_gate("B"))
    save_png(os.path.join(TILES, "changan_gate_c.png"), TS, TS, draw_mansion_gate("C"))
    save_png(os.path.join(TILES, "changan_palace_wall.png"), TS, TS, draw_palace_wall())
    save_png(os.path.join(TILES, "changan_outer_wall.png"), TS, TS, draw_outer_wall())
    save_png(os.path.join(TILES, "changan_zhuque.png"), TS, TS, draw_zhuque())
    print("[changan-tiles] BRICK=", BRICK, "DARK=", BRICK_DARK,
          "wrote ward_gate×2 + mansion_gate a/b/c + palace/outer wall + zhuque")
