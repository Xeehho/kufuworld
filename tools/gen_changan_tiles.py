# -*- coding: utf-8 -*-
"""长安城瓦片 PNG 生成（M0 坊门 + M2 宅门品级/宫墙/外郭墙/御道）
色系锚定 sprites/tiles/ward_wall.png（白灰暖砖）——门框色直接采样复用
配色参照: 参考14号(红门气派) + 唐风微调色板
Slice D(2026-09-06): 全族校色对齐 MW 调子——石作=蓝灰(walls.png实测103,117,152)、木作=暖棕(117,83,56)、毯=绛红(158,46,70)
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

WOOD_D = (80, 54, 37)     # 门楣深木（MW wooden_door 暗棕实测）
WOOD_M = (117, 83, 56)    # 门扇木中（MW wooden 地板面实测）
WOOD_L = (142, 104, 72)   # 木高光
RED_M  = (164, 52, 42)    # 红漆门扇（唐风锚点色相+MW饱和度）
RED_D  = (118, 36, 28)
GOLD   = (216, 178, 90)
HOLE   = (36, 30, 28)     # 门洞内暗
HOLE_L = (50, 42, 38)

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
        rect(t, 0, 0, 15, 1, (86, 92, 114))   # 檐口青瓦（MW蓝灰调）
        rect(t, 1, 2, 14, 2, WOOD_D)          # 门楣
        rect(t, 1, 3, 14, 3, WOOD_M)
        if grade == "A":
            for xx in (2, 7, 12):             # 檐下金钉门簪三路
                rect(t, xx, 2, xx+1, 2, GOLD)
    else:
        rect(t, 0, 0, 15, 1, WOOD_D)
        rect(t, 1, 1, 14, 3, WOOD_D)          # 黑漆素楣
        rect(t, 1, 3, 14, 3, (52, 35, 25))
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
    REDD = (164, 52, 44)     # 墙身朱红（唐朱相+MW饱和）
    REDD_D = (118, 38, 32)   # 红暗缝
    REDD_L = (186, 74, 56)   # 受光
    TILE_G = (88, 94, 118)   # 青瓦（MW蓝灰调）
    TILE_GD = (62, 66, 88)
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
    EARTH = (174, 138, 90)
    EARTH_D = (132, 100, 64)
    EARTH_L = (196, 160, 110)
    rect(t, 0, 0, 15, 0, (76, 64, 50))         # 墙顶压边
    rect(t, 0, 1, 15, 13, EARTH)
    for y in (4, 9):                            # 大块夯土层缝
        rect(t, 0, y, 15, y, EARTH_D)
    for band, y in enumerate((1, 5, 10)):       # 竖向错缝
        jx = 3 if band % 2 == 0 else 10
        rect(t, jx, y, jx, y+2, EARTH_D)
        rect(t, (12 if band % 2 == 0 else 6), y, (12 if band % 2 == 0 else 6), y+2, EARTH_D)
    rect(t, 0, 1, 15, 1, EARTH_L)               # 顶部受光
    rect(t, 0, 14, 15, 15, (102, 80, 56))        # 根部
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

# ---- M2 朱雀御道 71：大块石板+纵列对缝（比石板更整饬，中轴气势）----
def draw_zhuque():
    t = bytearray(b"\x00"*(TS*TS*4))
    ST = (150, 156, 172)
    ST_D = (116, 122, 142)
    ST_L = (176, 182, 196)
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


# ==================== M4 内景瓦片族 80~89（§5.3 interior_tiles） ====================
# 木/砖/毯地板 + 内墙/屏风/灯烛 + 家具案/榻/柜/架；便利店等现代场景 M6 仅换皮肤复用

WOOD_F  = (143, 103, 66)   # 木地板面（MW wooden 实测调）
WOOD_FD = (100, 70, 44)    # 板缝
CARPET  = (158, 46, 70)    # 毯面绛红（MW carpet 实测）
CARPET_D= (113, 25, 60)
IWALL   = (104, 74, 50)     # 内墙木框（MW木族）
IWALL_D = (72, 50, 34)
IWALL_P = (206, 192, 168)  # 墙面粉白（纸面）
LAMP_F  = (238, 196, 110)  # 灯焰
def draw_floor_wood():
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 0, 0, 15, 15, WOOD_F)
    for y in (0, 5, 10, 15):                    # 横向板缝
        rect(t, 0, y, 15, y, WOOD_FD)
    for band, y0 in enumerate((1, 6, 11)):      # 竖向错缝
        jx = (4, 11)[band % 2]
        rect(t, jx, y0, jx, y0+3, WOOD_FD)
    rect(t, 0, 1, 15, 1, (168, 126, 80))        # 板面受光
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_floor_brick():
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 0, 0, 15, 15, (140, 148, 168))
    for y in (0, 7, 15):
        rect(t, 0, y, 15, y, (108, 116, 138))
    for x in (0, 7, 15):
        rect(t, x, 0, x, 6, (108, 116, 138))
        rect(t, x+4 if x+4 <= 15 else 4, 8, x+4 if x+4 <= 15 else 4, 14, (108, 116, 138))
    rect(t, 1, 1, 5, 1, (164, 170, 188))
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_carpet():
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 0, 0, 15, 15, CARPET)
    rect(t, 0, 0, 15, 1, CARPET_D)
    rect(t, 0, 14, 15, 15, CARPET_D)
    rect(t, 0, 0, 1, 15, CARPET_D)
    rect(t, 14, 0, 15, 15, CARPET_D)
    for cx, cy in ((4, 4), (11, 4), (4, 11), (11, 11)):
        px(t, cx, cy, GOLD); px(t, cx, cy-1, GOLD_D := (180, 148, 80))
    px(t, 7, 7, GOLD); px(t, 8, 8, GOLD)
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_interior_wall():
    # 下半木护壁+上半粉白纸面，顶部深木压条
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 0, 0, 15, 15, IWALL_P)
    rect(t, 0, 8, 15, 15, IWALL)
    for x in (2, 6, 10, 14):
        rect(t, x, 9, x, 14, IWALL_D)
    rect(t, 0, 7, 15, 7, IWALL_D)
    rect(t, 0, 0, 15, 0, IWALL_D)
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_screen():
    # 屏风：木框+中间山水淡彩（底透，占格下沿）
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 1, 2, 14, 14, IWALL_D)              # 框
    rect(t, 2, 3, 13, 13, IWALL_P)              # 面
    rect(t, 3, 9, 12, 12, (120, 140, 150))      # 远山
    rect(t, 4, 7, 8, 8, (150, 160, 156))
    rect(t, 9, 6, 12, 7, (150, 160, 156))
    rect(t, 2, 13, 13, 13, IWALL_D)
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_lamp():
    # 灯烛：铜灯座+暖焰（底透）
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 6, 13, 9, 15, (96, 68, 44))        # 座
    rect(t, 5, 9, 10, 12, (124, 90, 58))       # 灯身
    rect(t, 6, 10, 9, 11, (150, 112, 72))
    rect(t, 7, 5, 8, 8, LAMP_F)                 # 焰
    px(t, 7, 4, (255, 232, 160)); px(t, 8, 4, (255, 232, 160))
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_desk():
    # 案：深木案面+四足（占格下沿）
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 1, 6, 14, 9, WOOD_M)                # 案面
    rect(t, 1, 6, 14, 6, WOOD_L)
    rect(t, 2, 10, 3, 15, WOOD_D)               # 足
    rect(t, 12, 10, 13, 15, WOOD_D)
    rect(t, 1, 9, 14, 9, WOOD_D)
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_couch():
    # 榻：矮榻+软垫（可行走）
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 1, 8, 14, 13, WOOD_M)
    rect(t, 2, 5, 13, 9, CARPET)                # 垫
    rect(t, 2, 5, 13, 6, (188, 73, 82))
    rect(t, 1, 13, 14, 13, WOOD_D)
    rect(t, 1, 8, 1, 12, WOOD_L)
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_cabinet():
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 2, 1, 13, 15, WOOD_D)               # 柜体
    rect(t, 3, 2, 12, 7, WOOD_M)                # 上屉
    rect(t, 3, 9, 12, 14, WOOD_M)               # 下门
    rect(t, 7, 9, 8, 14, WOOD_D)                # 门缝
    px(t, 6, 11, GOLD); px(t, 9, 11, GOLD)      # 铜扣
    rect(t, 2, 1, 13, 1, WOOD_L)
    return [t[y*TS*4:(y+1)*TS*4] for y in range(TS)]

def draw_shelf():
    # 架：多格木架+卷轴瓶罐
    t = bytearray(b"\x00"*(TS*TS*4))
    rect(t, 2, 0, 13, 15, WOOD_D)
    for y in (5, 10):
        rect(t, 2, y, 13, y, IWALL_D)
    rect(t, 3, 1, 5, 4, (196, 180, 150))        # 卷轴
    rect(t, 7, 2, 8, 4, (110, 130, 120))        # 瓶
    rect(t, 10, 2, 12, 4, (150, 96, 60))        # 罐
    rect(t, 3, 6, 4, 9, (170, 140, 100))
    rect(t, 6, 7, 9, 9, (120, 120, 140))
    rect(t, 11, 6, 12, 9, (150, 96, 60))
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
    save_png(os.path.join(TILES, "interior_floor_wood.png"), TS, TS, draw_floor_wood())
    save_png(os.path.join(TILES, "interior_floor_brick.png"), TS, TS, draw_floor_brick())
    save_png(os.path.join(TILES, "interior_carpet.png"), TS, TS, draw_carpet())
    save_png(os.path.join(TILES, "interior_wall.png"), TS, TS, draw_interior_wall())
    save_png(os.path.join(TILES, "interior_screen.png"), TS, TS, draw_screen())
    save_png(os.path.join(TILES, "interior_lamp.png"), TS, TS, draw_lamp())
    save_png(os.path.join(TILES, "interior_desk.png"), TS, TS, draw_desk())
    save_png(os.path.join(TILES, "interior_couch.png"), TS, TS, draw_couch())
    save_png(os.path.join(TILES, "interior_cabinet.png"), TS, TS, draw_cabinet())
    save_png(os.path.join(TILES, "interior_shelf.png"), TS, TS, draw_shelf())
    print("[changan-tiles] BRICK=", BRICK, "DARK=", BRICK_DARK,
          "wrote ward_gate×2 + mansion_gate a/b/c + palace/outer wall + zhuque + interior×10")
