# -*- coding: utf-8 -*-
"""解析用户 Tiled 工程 Outer_city_wall.tmx：GID→源图集16px网格→复现渲染+拼装语法分析"""
import base64, zlib, os, re
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "docs", "参考", "tiled_work")
SRC = os.path.join(ROOT, "downloaded_assets", "comshadow_bundle")

tree = ET.parse(os.path.join(WORK, "Outer_city_wall.tmx"))
m = tree.getroot()
W, H = int(m.get("width")), int(m.get("height"))

# tileset firstgid -> (name, image_path, columns)
tilesets = []
for ts in m.findall("tileset"):
    fg = int(ts.get("firstgid"))
    root = ET.parse(os.path.join(WORK, ts.get("source"))).getroot()
    tilesets.append((fg, root.get("name"), root.find("image").get("source"),
                     int(root.get("columns")), int(root.get("tilecount"))))
tilesets.sort()

def gid_to_source(gid):
    """GID(去翻转位) -> (图名, 图路径, 源图16px格col,row)"""
    for i in range(len(tilesets) - 1, -1, -1):
        fg, name, img, cols, cnt = tilesets[i]
        if gid >= fg:
            idx = gid - fg
            if idx >= cnt:
                return None
            return (name, img, idx % cols, idx // cols)
    return None

FLIP_H, FLIP_V, FLIP_D = 0x80000000, 0x40000000, 0x20000000

layers = {}
for layer in m.findall("layer"):
    data = layer.find("data")
    raw = zlib.decompress(base64.b64decode(data.text))
    gids = []
    for i in range(0, len(raw), 4):
        g = raw[i] | raw[i+1] << 8 | raw[i+2] << 16 | raw[i+3] << 24
        gids.append(g)
    layers[layer.get("name")] = gids

# 图缓存
imgs = {}
def get_img(rel):
    if rel not in imgs:
        imgs[rel] = Image.open(os.path.normpath(os.path.join(WORK, rel))).convert("RGBA")
    return imgs[rel]

# 复现渲染
scale = 2
canvas = Image.new("RGBA", (W * 16 * scale, H * 16 * scale), (60, 60, 64, 255))
stats = {}
flips_seen = []
for lname in ("地面", "建筑", "道具"):
    if lname not in layers: continue
    gids = layers[lname]
    for i, g in enumerate(gids):
        if g == 0: continue
        fh, fv, fd = bool(g & FLIP_H), bool(g & FLIP_V), bool(g & FLIP_D)
        base = g & ~(FLIP_H | FLIP_V | FLIP_D)
        info = gid_to_source(base)
        if not info: continue
        name, rel, col, row = info
        x, y = (i % W) * 16, (i // W) * 16
        tile = get_img(rel).crop((col * 16, row * 16, col * 16 + 16, row * 16 + 16))
        # Tiled 翻转顺序: diagonal -> h -> v
        if fd: tile = tile.transpose(Image.TRANSPOSE)
        if fh: tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
        if fv: tile = tile.transpose(Image.FLIP_TOP_BOTTOM)
        if fh or fv or fd:
            flips_seen.append((lname, x // 16, y // 16, name, col, row, fh, fv, fd))
        canvas.alpha_composite(tile.resize((16 * scale, 16 * scale), Image.NEAREST), (x * scale, y * scale))
        key = (lname, name, row)  # 按图集行统计（B01 城墙带在 row 6~11 附近）
        stats[key] = stats.get(key, 0) + 1

canvas.convert("RGB").save(os.path.join(WORK, "_parsed_rebuild.png"))

print("=== 图层 tile 统计（图/行 → 数量, 前 25）===")
for k, v in sorted(stats.items(), key=lambda kv: -kv[1])[:25]:
    print(f"  {k[0]:3s} {k[1]:10s} 行{k[2]:3d}: {v}")
print()
print(f"=== 翻转 tile 数: {len(flips_seen)}（前 20）===")
for f in flips_seen[:20]:
    print(f"  {f[0]} @({f[1]},{f[2]}) {f[3]} 16格({f[4]},{f[5]}) H={f[6]} V={f[7]} D={f[8]}")

# 建筑层 tile 的源坐标聚类（识别城墙带/门楼/竖墙块来源）
print()
print("=== 建筑层 tile 源分布（源16格坐标 -> 使用次数, 只列 B01）===")
bstat = {}
gids = layers.get("建筑", [])
for i, g in enumerate(gids):
    if g == 0: continue
    base = g & ~(FLIP_H | FLIP_V | FLIP_D)
    info = gid_to_source(base)
    if not info or "京城-B01" not in info[0]: continue
    name, rel, col, row = info
    bstat[(col, row)] = bstat.get((col, row), 0) + 1
for k, v in sorted(bstat.items(), key=lambda kv: -kv[1])[:30]:
    print(f"  源16格({k[0]:2d},{k[1]:2d}) = 像素({k[0]*16},{k[1]*16}): {v} 次")
