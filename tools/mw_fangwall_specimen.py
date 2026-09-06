# -*- coding: utf-8 -*-
"""长安坊墙/宅门小样 —— Mystic Woods 画风的自产中式瓦片首件样品
形制参照: docs/参考图-长安城/12(屋顶形制)/14(宅门气派)/17(青瓦白墙红红色板)
画风约束: MW 式柔和二阶明暗+低饱和, 16x16 瓦片
输出: docs/shots/mw_fangwall_specimen.png (4x 放大)
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_pack_assets import load_png, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MW = os.path.join(ROOT, "downloaded_assets", "mystic_woods_2.2", "sprites")
OUT = os.path.join(ROOT, "docs", "shots")
TS = 16
SCALE = 4

# 色板（锚=参考图17 青瓦白墙红木 + MW 低饱和调子）
ROOF_D  = (86, 94, 106)     # 瓦面暗
ROOF_M  = (112, 121, 134)   # 瓦面中（青灰）
ROOF_L  = (148, 157, 170)   # 瓦楞高光
EAVE    = (64, 71, 82)      # 檐口阴影
BRICK_L = (162, 168, 176)   # 砖面亮
BRICK_M = (138, 145, 155)   # 砖面中
MORTAR  = (108, 115, 126)   # 灰缝
WOOD_D  = (74, 58, 46)      # 木深（门楣）
RED_D   = (110, 36, 23)     # 红漆暗
RED_M   = (150, 56, 36)     # 红漆中
GOLD    = (216, 178, 90)    # 金钉/匾额
WHITE_W = (226, 222, 208)   # 白灰墙（门垛）

def px(t, x, y, c):
    if 0 <= x < TS and 0 <= y < TS:
        o = (y*TS + x)*4
        t[o:o+4] = bytes(c) + b"\xff"

def rect(t, x0, y0, x1, y1, c):
    for y in range(y0, y1+1):
        for x in range(x0, x1+1):
            px(t, x, y, c)

def new_tile():
    return bytearray(b"\x00" * (TS*TS*4))

def draw_roof(t, y0=0, y1=7):
    """瓦顶: 筒瓦楞(4px组: 亮楞+瓦沟) + 实心檐影, 8px 高"""
    rect(t, 0, y0, 15, y1-1, ROOF_M)
    for x in range(0, 16, 4):
        for y in range(y0+1, y1-1):
            px(t, x, y, ROOF_L)                       # 瓦楞高光
            c = ROOF_D if (x + y) % 5 == 0 else ROOF_D if x == 0 else ROOF_M
            px(t, x+1, y, ROOF_M)                     # 瓦面
            px(t, x+2, y, ROOF_D if (x*3+y) % 7 == 0 else ROOF_M)
            px(t, x+3, y, ROOF_D)                     # 瓦沟阴影
    rect(t, 0, y0, 15, y0, ROOF_D)                    # 顶脊压边
    rect(t, 0, y1-1, 15, y1-1, ROOF_L)                # 檐口亮边
    rect(t, 0, y1, 15, y1, EAVE)                      # 檐影(实心)

def draw_bricks(t, y0=0, y1=15):
    """顺砖砌法: 每4行一层, 竖缝错位"""
    rect(t, 0, y0, 15, y1, BRICK_M)
    for band_i, y in enumerate(range(y0, y1+1, 4)):
        y_end = min(y+3, y1)
        rect(t, 0, y_end, 15, y_end, MORTAR)         # 横缝
        jx = 4 if band_i % 2 == 0 else 12             # 竖缝错位
        for yy in range(y, y_end):
            px(t, jx, yy, MORTAR)
        # 砖面随机二阶（确定性 hash，避免真随机）
        for yy in range(y, y_end):
            if yy == y_end: continue
            for x in range(16):
                if ((x*7 + yy*13) % 11) == 0:
                    px(t, x, yy, BRICK_L)

def tile_wall():
    """墙身直段: 上8px瓦顶 + 下8px砖身"""
    t = new_tile()
    draw_roof(t, 0, 7)
    draw_bricks(t, 8, 15)
    return t

def tile_gate():
    """宅门(1瓦宽): 门垛白灰 + 红门扇 + 金钉, 全高16px"""
    t = new_tile()
    draw_roof(t, 0, 5)                       # 门楣小顶(比墙顶略矮=门在墙前)
    rect(t, 0, 6, 15, 6, EAVE)
    # 白灰门垛两侧
    rect(t, 0, 7, 2, 15, WHITE_W)
    rect(t, 13, 7, 15, 15, WHITE_W)
    px(t, 2, 8, (200, 196, 182)); px(t, 13, 8, (200, 196, 182))
    # 红门扇
    rect(t, 3, 7, 12, 15, RED_M)
    rect(t, 3, 7, 3, 15, RED_D); rect(t, 12, 7, 12, 15, RED_D)
    rect(t, 7, 7, 8, 15, RED_D)              # 门缝
    # 金钉 2x2 阵
    for yy in (9, 12):
        for xx in (5, 10):
            rect(t, xx, yy, xx+1, yy+1, GOLD)
    return t

def tile_lantern():
    """挂灯墙段: 墙身 + 檐下红灯笼(14号图元素)"""
    t = tile_wall()
    rect(t, 7, 8, 8, 9, WOOD_D)              # 灯杆
    rect(t, 6, 10, 9, 13, (184, 59, 42))     # 灯笼红
    rect(t, 6, 10, 9, 10, (203, 79, 58))
    rect(t, 7, 14, 8, 14, GOLD)
    px(t, 6, 10, GOLD); px(t, 9, 10, GOLD)
    return t

def tile_end(left=True):
    """墙端头: 瓦顶收头 + 端柱"""
    t = tile_wall()
    x0, x1 = (0, 3) if left else (12, 15)
    rect(t, x0, 8, x1, 15, WHITE_W)
    rect(t, x0, 8, x0, 15, (200, 196, 182)) if left else rect(t, x1, 8, x1, 15, (200, 196, 182))
    return t

def main():
    grass = load_png(os.path.join(MW, "tilesets", "grass.png"))[2][0]  # 单行=整块16x16
    gt = [grass] * TS

    seq = [
        tile_end(True), tile_wall(), tile_lantern(), tile_wall(),
        tile_gate(), tile_wall(), tile_wall(), tile_end(False),
    ]
    cols = len(seq)
    rows_n = 2   # 两排: 上排样张, 下排留白写无字说明位(仅重复一遍便于看平铺)
    W = cols*TS*SCALE
    H = (rows_n*TS + 2)*SCALE
    cv = [bytearray(b"\x00"*(cols*TS*4)) for _ in range(rows_n*TS + 2)]
    for rep in range(rows_n):
        base_y = rep*(TS+2)
        for x in range(cols):
            for gy in range(cols):   # 草地打底
                pass
        for x in range(cols):
            # 每列先铺草地, 再贴样片
            for row_i in range(TS):
                y = base_y + row_i
                gline = gt[row_i]
                cv[y][x*TS*4:(x+1)*TS*4] = gline
        for x, t in enumerate(seq):
            for row_i in range(TS):
                y = base_y + row_i
                line = t[row_i*TS*4:(row_i+1)*TS*4]
                dst = cv[y]
                for j in range(0, len(line), 4):
                    if line[j+3] >= 10:
                        dst[x*TS*4+j:x*TS*4+j+4] = line[j:j+4]
    big = []
    for y in range(rows_n*TS + 2):
        src = bytes(cv[y])
        if len(src) != cols*TS*4:
            print('SHORT cv row', y, len(src))
        for _ in range(SCALE):
            big.append(b"".join(src[x*4:x*4+4]*SCALE for x in range(cols*TS)))
    save_png(os.path.join(OUT, "mw_fangwall_specimen.png"), W, H, big)
    print("[specimen] wrote mw_fangwall_specimen.png", W, "x", H)

if __name__ == "__main__":
    main()
