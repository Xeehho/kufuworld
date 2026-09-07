# -*- coding: utf-8 -*-
"""SCKR 考古实证：48px 货架格对齐度 + A4 墙布局 + 切片底边基线分析"""
import json, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "downloaded_assets", "comshadow_bundle")

m = json.load(open(os.path.join(ROOT, "data", "sckr_manifest.json"), encoding="utf-8"))
assets = m["assets"]

def off(v):
    """距最近 48px 格线的偏移量"""
    r = v % 48
    return min(r, 48 - r)

print("=" * 70)
print("一、prop 框选与 48px 货架格对齐统计（阈值 ≤4px 视为对齐）")
print("=" * 70)
props = [a for a in assets if a["kind"] == "prop"]
stats = {"l": 0, "t": 0, "r": 0, "b": 0}
for a in props:
    l, t, r, b = a["box"]
    if off(l) <= 4: stats["l"] += 1
    if off(t) <= 4: stats["t"] += 1
    if off(r) <= 4: stats["r"] += 1
    if off(b) <= 4: stats["b"] += 1
n = len(props)
print(f"prop 总数 {n}")
for k, c in stats.items():
    print(f"  {k}: {c}/{n} 对齐 ({100*c//n}%)")

print()
print("偏离最大的 12 条（框没落在货架格上）：")
scored = []
for a in props:
    l, t, r, b = a["box"]
    s = off(l) + off(t) + off(r) + off(b)
    scored.append((s, a))
scored.sort(key=lambda x: -x[0])
for s, a in scored[:12]:
    print(f"  {a['name']:22s} box={a['box']} 总偏移={s}px  ({a['sheet']})")

print()
print("=" * 70)
print("二、A4 外墙 autotile 布局分析（jingcheng/Auto-tile-A4-Walls-1.png）")
print("=" * 70)
im = Image.open(os.path.join(SRC, "jingcheng", "Auto-tile-A4-Walls-1.png")).convert("RGBA")
w, h = im.size
alpha = im.getchannel("A")
px = alpha.load()
# 每行非透明像素计数 → 找空行带（段分隔）
rows = []
for y in range(h):
    cnt = sum(1 for x in range(0, w, 2) if px[x, y] > 16)  # 隔列采样提速
    rows.append(cnt)
# 找连续空带（cnt==0 的行段）
bands = []
in_band = False
for y, c in enumerate(rows):
    if c == 0 and not in_band:
        start = y; in_band = True
    elif c != 0 and in_band:
        bands.append((start, y)); in_band = False
if in_band: bands.append((start, h))
print(f"尺寸 {w}x{h}；空行带（素材段分隔）: {bands if bands else '无——满铺 autotile 表（符合 RM A4 规格）'}")
# 检查 16px 子块级连续性：A4 autotile 内部以 16px 子块拼接
col_alpha = im.getchannel("A")
# 看几个关键 16px 边界处的列空隙
gaps_x = []
for x in range(w):
    cnt = sum(1 for y in range(0, h, 3) if col_alpha.getpixel((x, y)) > 16)
    if cnt == 0: gaps_x.append(x)
print(f"全空列数: {len(gaps_x)} (样例: {gaps_x[:20]})")

print()
print("=" * 70)
print("三、关键族切片的底边基线与实际像素框（切后 trim 实测）")
print("=" * 70)
def real_box(sheet, box):
    im = Image.open(os.path.join(SRC, sheet)).convert("RGBA")
    l, t, r, b = box
    crop = im.crop((l, t, r, b))
    bbox = crop.getchannel("A").getbbox()  # 非空 alpha 的实框
    if bbox is None: return None, None
    return (l + bbox[0], t + bbox[1], l + bbox[2], t + bbox[3]), (bbox[2]-bbox[0], bbox[3]-bbox[1])

# 城墙族 + 民居族 + 店铺：底边基线是否一致
families = {
    "城墙族": ["gate_tower_big", "gate_tower_mid", "wall_seg"],
    "民居族(江南)": ["house_win_a", "house_door_a", "house_win_small", "house_shop_open", "house_small_win", "house_small_door"],
    "小宅排": ["house_small_win", "gable_white", "house_small_door", "compound_gate"],
}
cache = {}
for fam, names in families.items():
    print(f"\n[{fam}]")
    for nm in names:
        a = next((x for x in assets if x["name"] == nm), None)
        if not a:
            print(f"  {nm:22s} 不在 manifest"); continue
        rb, size = real_box(a["sheet"], a["box"])
        if rb is None:
            print(f"  {nm:22s} 空框!"); continue
        l, t, r, b = rb
        print(f"  {nm:22s} 实框={rb}  尺寸={size[0]}x{size[1]}  底边y={b} (对48线偏移{off(b)}px) 顶边y={t} (偏移{off(t)}px)")
