# -*- coding: utf-8 -*-
"""竹9 程序化 MW 调竹子表（美术重构 Slice E——PC 包最后一块遗留替换）
输出 sprites/tiles/bamboo_mw.png：144x160 = 48x80 cell x 3列x2行（6变体，与旧 PC 竹表同布局）
  变体序沿用 TREE_SEASONS[9]: 0/1/3/4/5 春  2 枯（枯=黄褐疏叶）
色板锚=import_mw22_tiles.py 松树表实测主色（108,166,80/73,127,60/描边深绿/干棕 91,66,43）
确定性的种子随机——重跑逐像素一致。MW 缺失无关（纯程序化，可入库，克隆免生成）
"""
import os, sys, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_pack_assets import save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sprites", "tiles", "bamboo_mw.png")
CW, CH = 48, 80          # cell 尺寸（与 TREE_SHEETS[9].cell 一致，勿改——world_generator 读此值）
COLS, ROWS = 3, 2

STALK_M = (108, 166, 80)   # 竿主绿（=MW 冠主绿实测）
STALK_L = (152, 202, 120)  # 竿受光列
STALK_D = (73, 127, 60)    # 竿暗缘/叶背
OUTLINE = (24, 64, 26)     # 描边（MW 树描边同族深绿；勿命名 OUT——遮蔽输出路径常量曾致 TypeError）
LEAF_L  = (134, 190, 96)   # 叶亮面
SOIL    = (91, 66, 43)     # 根部土（MW 干棕实测）
SOIL_D  = (58, 42, 28)
DRY_M   = (176, 160, 92)   # 枯竿黄褐
DRY_L   = (206, 192, 122)
DRY_D   = (124, 110, 60)


def draw_stalk(px, x0, y_bot, y_top, w, lean, pal, bent=0.0, rng=None):
    """一根竹竿：竖向渐细+节环+左亮右暗+双侧描边；lean=整竿横向漂移px；bent>0 时顶部再加弯"""
    h = y_bot - y_top
    for y in range(y_bot, y_top - 1, -1):
        t = (y_bot - y) / max(1, h)
        drift = lean * t + (bent * max(0.0, t - 0.75) / 0.25)
        cx = x0 + drift
        ww = w if t < 0.7 else max(4, w - 1)          # 顶部渐细1px
        xi = int(round(cx))
        for dx in range(-(ww // 2), ww // 2 + 1):
            x = xi + dx
            if dx == -(ww // 2) or dx == ww // 2:
                px(x, y, OUTLINE)                          # 描边
            elif dx == -(ww // 2) + 1:
                px(x, y, pal["L"])                     # 受光列
            elif dx == ww // 2 - 1:
                px(x, y, pal["D"])                     # 暗缘
            else:
                px(x, y, pal["M"])
        # 节环：每12~14px 一道暗环+微鼓描边
        if (y_bot - y) % 13 == 6 and y_top + 3 < y < y_bot - 2:
            for dx in range(-(ww // 2) - 1, ww // 2 + 2):
                px(xi + dx, y, pal["D"] if abs(dx) <= ww // 2 else OUTLINE)


def draw_leaf(px, x, y, direction, length, pal, droop=0):
    """柳叶：从(x,y)向 direction(±1) 斜向伸出，先扬后垂（droop>0 更垂）"""
    for i in range(length):
        lx = x + direction * (i + 1)
        rise = (2 if i < length // 3 else (0 if i < 2 * length // 3 else -1 - droop))
        ly = y - rise
        px(lx, ly, pal["M"] if i < length - 2 else pal.get("LL", pal["M"]))
        px(lx, ly + 1, pal["D"])
    px(x + direction * length, y - 1 - droop, pal.get("LL", pal["M"]))


def draw_leaf_up(px, x, y, pal, rng):
    """竿顶叶冠：2-4 片向上/斜出的小叶"""
    n = rng.randint(2, 4)
    for k in range(n):
        d = 1 if k % 2 == 0 else -1
        draw_leaf(px, x, y - k, d, rng.randint(4, 7), pal, droop=0 if k < 2 else 1)


def draw_base(px, cx, y_bot, rng, w=None):
    """根部土丘：贴地小土堆，保证 cell 底缘有内容（防悬空）"""
    ww = w or rng.randint(9, 13)
    for dx in range(-(ww // 2), ww // 2 + 1):
        hh = 2 if abs(dx) < ww // 3 else 1
        for dy in range(hh):
            px(cx + dx, y_bot + 1 - dy, SOIL if dy == 0 else SOIL_D)
    px(cx - ww // 2 - 1, y_bot + 1, OUTLINE)
    px(cx + ww // 2 + 1, y_bot + 1, OUTLINE)


def variant(px, vid, rng):
    if vid == 2:
        pal = {"M": DRY_M, "L": DRY_L, "D": DRY_D, "LL": DRY_L}
    else:
        pal = {"M": STALK_M, "L": STALK_L, "D": STALK_D, "LL": LEAF_L}
    DENS = {0: 5, 1: 4, 2: 2, 3: 4, 4: 6, 5: 4}[vid]   # 出叶节点密度（每竿）

    def stalk_set(specs):
        for (x0, y_top, w, lean, bent) in specs:
            draw_stalk(px, x0, 76, y_top, w, lean, pal, bent)
            draw_leaf_up(px, int(round(x0 + lean + bent)), y_top, pal, rng)
            # 中段出叶：按密度在节点处抽叶
            for y in range(76 - 10, y_top + 4, -13):
                if rng.random() < DENS / 6.0:
                    d = 1 if rng.random() < 0.5 else -1
                    draw_leaf(px, int(round(x0 + lean * (76 - y) / max(1, 76 - y_top))), y, d,
                              rng.randint(5, 8), pal, droop=rng.randint(0, 1))

    cx = CW // 2
    if vid == 0:
        stalk_set([(cx - 4, 12, 7, 1, 0), (cx + 7, 24, 6, -2, 0), (cx - 12, 30, 5, 2, 0)])
    elif vid == 1:
        stalk_set([(cx + 2, 10, 7, -1, 0), (cx - 8, 26, 6, 2, 0), (cx + 12, 48, 4, 0, 0)])
    elif vid == 2:
        stalk_set([(cx - 2, 14, 7, 1, 0), (cx + 9, 28, 5, -2, 0)])
    elif vid == 3:
        stalk_set([(cx - 1, 8, 7, -1, 3.0), (cx + 8, 26, 6, 2, 0), (cx - 11, 34, 5, -1, 0)])
    elif vid == 4:
        stalk_set([(cx - 7, 14, 6, 1, 0), (cx, 8, 7, 0, 0), (cx + 6, 18, 6, -1, 0), (cx + 13, 36, 4, 1, 0)])
    else:
        stalk_set([(cx, 6, 8, 0, 2.0), (cx - 10, 30, 5, 2, 0)])
    draw_base(px, cx + rng.randint(-2, 2), 77, rng)


def main():
    sheet_w, sheet_h = CW * COLS, CH * ROWS
    rows = [bytearray(b"\x00" * (sheet_w * 4)) for _ in range(sheet_h)]

    def factory(cx0, cy0):
        def px(x, y, c):
            if 0 <= x < CW and 0 <= y < CH:
                gx, gy = cx0 + x, cy0 + y
                o = gx * 4   # 行内偏移——曾误用整图扁平偏移(gy*sheet_w+gx)，写进单行全部越界散落成空表
                rows[gy][o:o + 4] = bytes(c) + b"\xff"
        return px

    for vid in range(COLS * ROWS):
        rng = random.Random(20260906 + vid)   # 固定种子：确定性重跑一致
        variant(factory((vid % COLS) * CW, (vid // COLS) * CH), vid, rng)

    def _count(rr):
        return sum(1 for r in rr for i in range(0, len(r), 4) if r[i + 3] > 0)
    n_px = _count(rows)
    if n_px == 0:
        raise SystemExit("[bamboo-mw] FATAL: 绘制结果为空表（px 写入未生效）")
    save_png(OUT, sheet_w, sheet_h, rows)
    print("[bamboo-mw] wrote %s (%dx%d, 6 variants, v2=枯, px=%d)" % (OUT, sheet_w, sheet_h, n_px))


if __name__ == "__main__":
    main()
