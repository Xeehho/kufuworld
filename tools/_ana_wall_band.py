# -*- coding: utf-8 -*-
"""城墙带重切前置分析（2026-09-08 重切落地阶段）
①源 B01 col29 竖条(x464..480, y96..192)逐行内容/垛口相位——用户 Tiled 横墙平铺的源
②垛口带(y96..128)横向相位扫描：垛齿起止 x 坐标（找完整周期窗）
③用户 tmx 城墙段布局还原：行结构（垛口/墙身行号）、竖墙翻转用法、拐角拼法
"""
import base64, zlib, os
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "docs", "参考", "tiled_work")
B01 = Image.open(os.path.join(ROOT, "downloaded_assets", "comshadow_bundle",
                              "jingcheng", "tile-B-01.png")).convert("RGBA")

print("=" * 70)
print("① col29 竖条 (464..480, 96..192) 行带分析（用户横墙平铺源）")
px = B01.load()
for row in range(6, 12):
    y0 = row * 16
    # 每行 16px 高：统计非透明像素 + 最亮行（垛齿顶亮线）
    alpha_cnt = sum(1 for yy in range(y0, y0 + 16) for xx in range(464, 480)
                    if px[xx, yy][3] > 10)
    # 行内每列的最高不透明 y（垛齿轮廓）
    tops = []
    for xx in range(464, 480):
        top = next((yy for yy in range(y0, y0 + 16) if px[xx, yy][3] > 10), None)
        tops.append(top - y0 if top is not None else None)
    print(f"  row{row} y{y0}~{y0+16}: 不透明px={alpha_cnt}/256  列顶轮廓={tops}")

print()
print("=" * 70)
print("② 垛口带相位扫描 y96..128（x384..576 官方城墙带区间）：逐列最高不透明 y")
# 垛齿=垛口带内更高的列；豁口=矮列。扫描垛齿起止
cols = []
for xx in range(384, 576):
    top = next((yy for yy in range(96, 128) if px[xx, yy][3] > 10), None)
    cols.append((xx, top))
# 按 top 分组：高齿（top<=98 附近）vs 豁口（top 更深）
runs = []
cur_h = None
start = None
for xx, top in cols:
    h = "齿" if (top is not None and top <= 101) else "豁"
    if h != cur_h:
        if cur_h is not None:
            runs.append((cur_h, start, xx - 1))
        cur_h, start = h, xx
runs.append((cur_h, start, 575))
for h, a, b in runs:
    print(f"  x{a}..{b} ({b-a+1}px): {h}")

print()
print("=" * 70)
print("③ 用户 tmx 布局还原：建筑层逐格（源16格+翻转），前 40 行 × 100 列抽样")
tree = ET.parse(os.path.join(WORK, "Outer_city_wall.tmx"))
m = tree.getroot()
W, H = int(m.get("width")), int(m.get("height"))
tilesets = []
for ts in m.findall("tileset"):
    fg = int(ts.get("firstgid"))
    root = ET.parse(os.path.join(WORK, ts.get("source"))).getroot()
    tilesets.append((fg, root.get("name"), int(root.get("columns")), int(root.get("tilecount"))))
tilesets.sort()

def gid_to_src(gid):
    for i in range(len(tilesets) - 1, -1, -1):
        fg, name, cols_, cnt = tilesets[i]
        if gid >= fg:
            idx = gid - fg
            if idx >= cnt:
                return None
            return (name, idx % cols_, idx // cols_)
    return None

FLIP_H, FLIP_V, FLIP_D = 0x80000000, 0x40000000, 0x20000000
gids = None
for layer in m.findall("layer"):
    if layer.get("name") != "建筑":
        continue
    data = layer.find("data")
    raw = zlib.decompress(base64.b64decode(data.text))
    gids = [raw[i] | raw[i+1] << 8 | raw[i+2] << 16 | raw[i+3] << 24
            for i in range(0, len(raw), 4)]
assert gids is not None

# 行结构统计：每地图行的 (源row 分布, 翻转数)
print("  -- 地图行 -> 源行分布（只列城墙行）--")
for yy in range(H):
    rowstat = {}
    for xx in range(W):
        g = gids[yy * W + xx]
        if g == 0:
            continue
        base = g & ~(FLIP_H | FLIP_V | FLIP_D)
        info = gid_to_src(base)
        if not info or "B01" not in info[0]:
            continue
        rot = bool(g & FLIP_D)
        rowstat.setdefault((info[1], rot), set()).add(info[2])
    if rowstat:
        desc = "; ".join(f"srcrow{r}{'(rot)' if k else ''}:cols{sorted(v)[:6]}"
                         for (r, k), v in sorted(rowstat.items()))
        print(f"  y={yy:3d}: {desc}")

# 拐角区（横墙端 x0..3 与竖墙相接处）：细看 x80..99, y12..24
print()
print("  -- 东拐角区 x80..99 × y12..24 逐格（src col,row + 翻转标记）--")
for yy in range(12, 25):
    line = []
    for xx in range(80, 100):
        g = gids[yy * W + xx]
        if g == 0:
            line.append("    .    ")
            continue
        fh, fv, fd = bool(g & FLIP_H), bool(g & FLIP_V), bool(g & FLIP_D)
        info = gid_to_src(g & ~(FLIP_H | FLIP_V | FLIP_D))
        if not info:
            line.append("    ?    ")
            continue
        c, r = info[1], info[2]
        tag = ("D" if fd else "") + ("H" if fh else "") + ("V" if fv else "")
        line.append(f"{c:2d},{r:2d}{tag:<3s}")
    print(f"  y={yy:2d} " + " ".join(line))
