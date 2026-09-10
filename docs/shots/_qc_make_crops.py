# -*- coding: utf-8 -*-
"""长安样张品控：关键部位放大裁片 + 墙带透缝实测扫描"""
from PIL import Image, ImageDraw
import os

BASE = r"C:\Learn\my-godot-project\docs\shots"
OUT = os.path.join(BASE, "_qc")
os.makedirs(OUT, exist_ok=True)

SHOTS = {
    "m1": "changan_m1_city_mingde.png",
    "fp": "changan_m1_world_footprint.png",
    "pal": "changan_v_palace.png",
    "xs": "changan_m1_city_xishi.png",
}
imgs = {k: Image.open(os.path.join(BASE, v)).convert("RGB") for k, v in SHOTS.items()}
for k, im in imgs.items():
    print(k, im.size)

# ---------- 放大裁片 ----------
CROPS = [
    # 明德门
    ("m1_gate_L",      "m1",  (770, 545, 1000, 820), 3),
    ("m1_gate_R",      "m1",  (940, 545, 1170, 820), 3),
    ("m1_wall_L",      "m1",  (0, 630, 420, 810), 3),
    ("m1_wall_R",      "m1",  (1500, 630, 1917, 810), 3),
    ("m1_bridge",      "m1",  (840, 660, 1060, 1040), 3),
    ("m1_houses_rowR", "m1",  (1480, 190, 1917, 430), 2),
    # 城郭轮廓
    ("fp_band_L",      "fp",  (0, 730, 500, 890), 3),
    ("fp_band_R",      "fp",  (1420, 730, 1917, 890), 3),
    ("fp_corner",      "fp",  (1760, 60, 1917, 890), 2),
    ("fp_player",      "fp",  (260, 790, 560, 1050), 3),
    # 宫城
    ("pal_topwall_L",  "pal", (0, 0, 500, 200), 2),
    ("pal_gate_top",   "pal", (700, 0, 1200, 180), 2),
    ("pal_hall_junc",  "pal", (740, 120, 1180, 430), 2),
    ("pal_wall_L",     "pal", (0, 120, 420, 460), 2),
    ("pal_columns_A",  "pal", (730, 290, 1160, 720), 2),
    ("pal_columns_B",  "pal", (730, 700, 1160, 1080), 2),
    ("pal_west_pav",   "pal", (60, 660, 360, 1060), 2),
    # 西市
    ("xs_roofhead",    "xs",  (960, 270, 1180, 430), 3),
    ("xs_shoprow",     "xs",  (860, 320, 1300, 620), 2),
    ("xs_toprow",      "xs",  (600, 20, 1030, 330), 2),
    ("xs_trees_R",     "xs",  (1470, 540, 1700, 750), 3),
    ("xs_bottom_wall", "xs",  (500, 840, 1370, 960), 2),
    ("xs_jiulou",      "xs",  (940, 530, 1210, 830), 2),
    ("xs_left_row",    "xs",  (500, 500, 880, 770), 2),
]
for name, key, box, sc in CROPS:
    im = imgs[key]
    c = im.crop(box)
    c = c.resize((c.width * sc, c.height * sc), Image.NEAREST)
    canvas = Image.new("RGB", (c.width, c.height + 22), (20, 20, 20))
    canvas.paste(c, (0, 22))
    d = ImageDraw.Draw(canvas)
    d.text((4, 4), "%s  box=%s x%d" % (name, box, sc), fill=(255, 255, 0))
    canvas.save(os.path.join(OUT, name + ".png"))
print("crops saved:", len(CROPS))

# ---------- 实测：墙带竖向范围 + 透缝扫描 ----------
def px(im, x, y):
    return im.getpixel((x, y))

def close(c, ref, tol=30):
    return abs(c[0]-ref[0]) <= tol and abs(c[1]-ref[1]) <= tol and abs(c[2]-ref[2]) <= tol

def vrun(im, x, y0, y1, ref, tol=30):
    """在 x 列、[y0,y1) 范围内找 ref 色的最长连续段"""
    best = (0, 0, 0); cur0 = None
    for y in range(y0, y1):
        if close(px(im, x, y), ref, tol):
            if cur0 is None: cur0 = y
        else:
            if cur0 is not None:
                if y - cur0 > best[0]: best = (y - cur0, cur0, y)
                cur0 = None
    if cur0 is not None and (y1 - cur0) > best[0]:
        best = (y1 - cur0, cur0, y1)
    return best

def seam_scan(im, box, refs, tol=30, frac=0.55, label=""):
    """扫描 box 内每一列，统计接近 refs 任一色的像素占比；占比>frac 的列=疑似透缝"""
    l, t, r, b = box
    h = b - t
    bad = []
    for x in range(l, r):
        n = 0
        for y in range(t, b):
            c = px(im, x, y)
            if any(close(c, rf, tol) for rf in refs):
                n += 1
        if n >= h * frac:
            bad.append(x)
    # 合并连续列
    rngs = []
    for x in bad:
        if rngs and x == rngs[-1][1] + 1:
            rngs[-1][1] = x
        else:
            rngs.append([x, x])
    print("[%s] box=%s 疑似透缝列: %s" % (label, box, rngs if rngs else "无"))

m1, fp, pal, xs = imgs["m1"], imgs["fp"], imgs["pal"], imgs["xs"]

print("\n--- 参考色采样 ---")
print("m1 dirt(300,120)=", px(m1, 300, 120), " m1 grass(100,838)=", px(m1, 100, 838), " m1 wallbody(400,730)=", px(m1, 400, 730))
print("fp grass(800,700)=", px(fp, 800, 700), " fp band(800,820)=", px(fp, 800, 820))
print("pal red(300,200)=", px(pal, 300, 200), " pal plaza(500,700)=", px(pal, 500, 700), " pal graywall(300,90)=", px(pal, 300, 90))
print("xs dirt(400,400)=", px(xs, 400, 400), " xs pave(700,500)=", px(xs, 700, 500))

print("\n--- 墙带竖向实测（最长连续段）---")
print("m1 墙身灰 @x=400 (y630-830):", vrun(m1, 400, 630, 830, px(m1, 400, 730), 34))
print("m1 墙身灰 @x=1300 (y630-830):", vrun(m1, 1300, 630, 830, px(m1, 400, 730), 34))
print("fp 墙带灰 @x=800 (y740-900):", vrun(fp, 800, 740, 900, px(fp, 800, 820), 34))
print("fp 墙带灰 @x=300 (y740-900):", vrun(fp, 300, 740, 900, px(fp, 300, 820), 34))
print("pal 宫墙红 @x=300 (y140-300):", vrun(pal, 300, 140, 300, px(pal, 300, 200), 40))
print("pal 宫墙红 @x=1500 (y140-300):", vrun(pal, 1500, 140, 300, px(pal, 1500, 200), 40))
print("pal 灰顶墙 @x=300 (y20-140):", vrun(pal, 300, 20, 140, px(pal, 300, 90), 34))

print("\n--- 透缝扫描 ---")
wb = px(m1, 400, 730)
dirt = px(m1, 300, 120)
grass = px(m1, 100, 838)
seam_scan(m1, (0, 692, 830, 788), [dirt, grass], label="m1左段墙身")
seam_scan(m1, (1040, 692, 1917, 788), [dirt, grass], label="m1右段墙身")
fpb = px(fp, 800, 820)
fpg = px(fp, 800, 700)
seam_scan(fp, (0, 788, 1850, 852), [fpg], label="fp横墙带")
seam_scan(fp, (1856, 140, 1917, 788), [fpg], label="fp竖墙")
pr = px(pal, 300, 200)
pg = px(pal, 500, 700)
seam_scan(pal, (120, 168, 770, 256), [pg], label="pal宫墙红(左)")
seam_scan(pal, (1140, 168, 1917, 256), [pg], label="pal宫墙红(右)")
print("done")
