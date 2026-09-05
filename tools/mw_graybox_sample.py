# -*- coding: utf-8 -*-
"""Mystic Woods 免费包 -> 长安城灰盒样张（材质验证用，不入游戏管线）
合成两张对比图：MW 原色板 vs 唐风色板微调（锚=参考图17 Steam《长安》青瓦白墙红木）
布局示意：朱雀大街(9宽) x 主干街(5宽) 十字 + 两侧坊墙(石墙) + 坊门(木门) + 坊内栅栏院
输出: docs/shots/mw_graybox_original.png / mw_graybox_tang.png
"""
import os, sys, colorsys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_pack_assets import load_png, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MW = os.path.join(ROOT, "downloaded_assets", "mystic_woods_free_2.2", "sprites")
OUT = os.path.join(ROOT, "docs", "shots")
TS = 16          # MW 瓦片尺寸
SCALE = 2        # 输出放大倍数
COLS, ROWSN = 44, 26

def P(*p): return os.path.join(MW, *p)

def tile(src, tx, ty, ts=TS):
    """从 2D 表中取一个瓦片 -> rows 列表"""
    w = len(src[0]) // 4
    return [src[ty*ts+i][tx*ts*4:(tx+1)*ts*4] for i in range(ts)]

def paste(canvas, piece, cx, cy):
    """把瓦片贴到画布瓦片坐标（alpha 合成：透明像素保留底图）"""
    for i, line in enumerate(piece):
        y = cy*TS + i
        x0 = cx*TS*4
        dst = canvas[y]
        for j in range(0, len(line), 4):
            if line[j+3] >= 10:
                dst[x0+j:x0+j+4] = line[j:j+4]

def color_classify(piece):
    """返回 (绿占比, 棕占比, 灰占比, 透明占比)"""
    n = g = b = gr = a = 0
    for line in piece:
        for x in range(0, len(line), 4):
            r, gg, bb, al = line[x], line[x+1], line[x+2], line[x+3]
            n += 1
            if al < 10: a += 1
            elif gg > r+10 and gg > bb+10: g += 1
            elif r > gg > bb and r-bb > 15: b += 1
            elif abs(r-gg) < 14 and abs(gg-bb) < 14 and 50 < r < 210: gr += 1
    return g/n, b/n, gr/n, a/n

def tang_shift(rows):
    """唐风色板微调：绿->降饱和偏橄榄；棕->提暖偏土黄；灰石不动"""
    out = []
    for line in rows:
        nl = bytearray(line)
        for x in range(0, len(nl), 4):
            r, g, b, a = nl[x], nl[x+1], nl[x+2], nl[x+3]
            if a < 10: continue
            if g > r+10 and g > b+10:          # 绿系
                h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
                r2, g2, b2 = colorsys.hsv_to_rgb((h - 0.015) % 1.0, min(1.0, s*0.82), min(1.0, v*1.04))
                nl[x], nl[x+1], nl[x+2] = int(r2*255), int(g2*255), int(b2*255)
            elif r > g > b and r-b > 15:       # 棕土系
                nl[x] = min(255, int(r*1.06)); nl[x+1] = int(g*0.99); nl[x+2] = int(b*0.86)
        out.append(bytes(nl))
    return out

def main():
    grass  = load_png(P("tilesets", "grass.png"))
    plains = load_png(P("tilesets", "plains.png"))
    walls  = load_png(P("tilesets", "walls", "walls.png"))
    fences = load_png(P("tilesets", "fences.png"))
    door   = load_png(P("tilesets", "walls", "wooden_door.png"))
    decor  = load_png(P("tilesets", "decor_16x16.png"))
    player = load_png(P("characters", "player.png"))

    # ---- 自动选瓦片 ----
    def pt(t): return color_classify(tile(plains[2], t[0], t[1]))
    plains_tiles = {}
    for ty in range(plains[1]//TS):
        for tx in range(plains[0]//TS):
            plains_tiles[(tx, ty)] = color_classify(tile(plains[2], tx, ty))
    # 纯土路：棕>0.92 且几乎无绿草屑、避开最底行(水印行)
    dirt = next(((tx, ty) for ty in range(plains[1]//TS - 1) for tx in range(plains[0]//TS)
                 if plains_tiles[(tx, ty)][1] > 0.92 and plains_tiles[(tx, ty)][0] < 0.05), None)
    # 草->土 直线过渡沿：上边沿=上半全绿+下半全棕；下边沿反之
    def half_frac(piece, top, want):
        n = hit = 0
        rng = range(0, TS//2) if top else range(TS//2, TS)
        for y in rng:
            line = piece[y]
            for x in range(0, len(line), 4):
                r, g, bb, al = line[x], line[x+1], line[x+2], line[x+3]
                n += 1
                if al < 10: continue
                if want == "g" and g > r+10 and g > bb+10: hit += 1
                if want == "b" and r > g > bb and r-bb > 15: hit += 1
        return hit/n
    edge_top = edge_bot = None
    for ty in range(min(4, plains[1]//TS)):
        for tx in range(plains[0]//TS):
            if (tx, ty) == dirt: continue
            pc = tile(plains[2], tx, ty)
            if half_frac(pc, True, "g") > 0.9 and half_frac(pc, False, "b") > 0.9 and edge_top is None:
                edge_top = (tx, ty)
            if half_frac(pc, False, "g") > 0.9 and half_frac(pc, True, "b") > 0.9 and edge_bot is None:
                edge_bot = (tx, ty)
    print("[sample] dirt=%s edge_top=%s edge_bot=%s" % (dirt, edge_top, edge_bot))

    wall_cap, wall_face = (0, 4), (1, 4)   # walls.png 左下横条带上行=墙帽 下行=墙面
    fence_v = (2, 0)                        # fences.png 第3列竖段
    player_idle = tile(player[2], 1, 0, 48) # 48x48 idle 第一帧
    player_walk = tile(player[2], 0, 3, 48) # move 段第一帧

    # ---- 画布 ----
    def build(shift):
        cv = [[b"\x00"*TS*4]*(COLS*TS) for _ in range(ROWSN*TS)]
        cv = [bytearray(b"\x00"*COLS*TS*4) for _ in range(ROWSN*TS)]
        grass_t = tile(grass[2], 0, 0)
        dirt_t = tile(plains[2], *dirt) if dirt else grass_t
        et = tile(plains[2], *edge_top) if edge_top else dirt_t
        eb = tile(plains[2], *edge_bot) if edge_bot else dirt_t
        for y in range(ROWSN):
            for x in range(COLS):
                paste(cv, tang_shift(grass_t) if shift else grass_t, x, y)
        zq_x0, zq_x1 = 17, 25   # 朱雀大街 9 宽
        cross_y0, cross_y1 = 11, 15  # 主干街 5 宽
        # 路面
        for y in range(ROWSN):
            for x in range(zq_x0, zq_x1+1):
                if cross_y0 <= y <= cross_y1: continue
                paste(cv, tang_shift(dirt_t) if shift else dirt_t, x, y)
        for y in range(cross_y0, cross_y1+1):
            for x in range(COLS):
                paste(cv, tang_shift(dirt_t) if shift else dirt_t, x, y)
        # 路缘(草土过渡)
        for y in range(ROWSN):
            if cross_y0 <= y <= cross_y1: continue
            paste(cv, tang_shift(et) if shift else et, zq_x0-1, y)
            paste(cv, tang_shift(eb) if shift else eb, zq_x1+1, y)
        # 坊墙: 朱雀大街两侧 x=14 / x=28, 主干街处断开为坊门
        for wx in (14, 28):
            for y in range(ROWSN):
                if cross_y0 <= y <= cross_y1: continue
                paste(cv, tang_shift(tile(walls[2], *wall_face)) if shift else tile(walls[2], *wall_face), wx, y)
            # 门
            dt = tile(door[2], 0, 0)
            dt2 = tile(door[2], 1, 0)
            paste(cv, tang_shift(dt) if shift else dt, wx, cross_y0)
            paste(cv, tang_shift(dt2) if shift else dt2, wx, cross_y0)
        # 坊内栅栏院(西) + 陈设
        ft = tile(fences[2], *fence_v)
        for y in range(5, 10):
            paste(cv, tang_shift(ft) if shift else ft, 6, y)
        for x in range(6, 11):
            paste(cv, tang_shift(ft) if shift else ft, x, 5)
        for x in range(31, 37):
            paste(cv, tang_shift(ft) if shift else ft, x, 17)
        # 地面装饰(花/草丛)
        for (dx, dy, sx, sy) in [(8, 7, 0, 0), (33, 19, 1, 0), (36, 6, 0, 0)]:
            dp = tile(decor[2], sx, sy)
            paste(cv, tang_shift(dp) if shift else dp, dx, dy)
        # 玩家(体型/比例参照)
        pp = tang_shift(player_idle) if shift else player_idle
        pw = tang_shift(player_walk) if shift else player_walk
        paste(cv, pp, 20, 17)
        paste(cv, pw, 23, 19)
        # 放大 SCALE 倍
        big = []
        for y in range(ROWSN*TS):
            src = bytes(cv[y])
            for _ in range(SCALE):
                big.append(b"".join(src[x*4:x*4+4]*SCALE for x in range(COLS*TS)))
        return big

    for name, shift in [("mw_graybox_original", False), ("mw_graybox_tang", True)]:
        save_png(os.path.join(OUT, name + ".png"), COLS*TS*SCALE, ROWSN*TS*SCALE, build(shift))
        print("[sample] wrote", name)

if __name__ == "__main__":
    main()
