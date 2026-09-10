# -*- coding: utf-8 -*-
# QC analysis for tiled wall rebuild: measure crenellation rhythm, locate seams,
# check corner junction structure, export 4x nearest-neighbor crops as evidence.
from PIL import Image
import numpy as np
import os
import collections

BASE = r"C:\Learn\my-godot-project\docs\参考"
TW = os.path.join(BASE, "tiled_work")
OF = os.path.join(BASE, "sckr_official_demo")


def load(p):
    im = Image.open(p).convert("RGB")
    return im, np.asarray(im).astype(int)


def ranges(bool_arr):
    out = []
    s = None
    for i, v in enumerate(bool_arr):
        if v and s is None:
            s = i
        if not v and s is not None:
            out.append((s, i - 1))
            s = None
    if s is not None:
        out.append((s, len(bool_arr) - 1))
    return out


def save_crop(im, box, name, scale=4):
    c = im.crop(box)
    c = c.resize((c.width * scale, c.height * scale), Image.NEAREST)
    out = os.path.join(TW, name)
    c.save(out)
    print("saved", name, "box", box)


im, a = load(os.path.join(TW, "_parsed_rebuild.png"))
W, H = im.size
print("rebuild size", W, H)
bg = a[3, 3]
print("bg color", bg)
diff = np.abs(a - bg).sum(axis=2)
mask = diff > 30

ys = np.where(mask.any(axis=1))[0]
xs = np.where(mask.any(axis=0))[0]
print("content bbox x[%d..%d] y[%d..%d]" % (xs.min(), xs.max(), ys.min(), ys.max()))

# ---- per-column topmost wall pixel in lower half -> crenellation profile ----
half = int(H * 0.55)
top = np.full(W, 10 ** 9)
for x in range(W):
    col = np.where(mask[:, x])[0]
    col = col[col >= half]
    if len(col):
        top[x] = col[0]
band = top[top < 10 ** 8]
med = int(np.median(band))
p25 = int(np.percentile(band, 25))
p75 = int(np.percentile(band, 75))
print("wall-top y: median=%d p25(merlon top)=%d p75(valley)=%d merlon_height=%d" % (med, p25, p75, p75 - p25))

tall = (top < p25 - 60) & (top < 10 ** 8)
print("tall columns (vertical walls + gate column):", ranges(tall))

t_thresh = p25 + max(3, int(0.30 * (p75 - p25)))
tooth = (top < t_thresh) & (top < 10 ** 8) & ~tall
print("tooth threshold y =", t_thresh)
tr = ranges(tooth)
starts = [s for s, e in tr]
widths = [e - s + 1 for s, e in tr]
per = [starts[i + 1] - starts[i] for i in range(len(starts) - 1)]
print("teeth n =", len(tr))
print("period hist (px):", dict(collections.Counter(per)))
print("merlon width hist (px):", dict(collections.Counter(widths)))
nom = collections.Counter(per).most_common(1)[0][0]
outliers = [(p_, starts[i], starts[i + 1]) for i, p_ in enumerate(per) if abs(p_ - nom) > 3]
print("period outliers (nominal %d):" % nom, outliers)

# ---- horizontal wall band bottom near corners ----
print("columns with pixels above 0.55H:", ranges(tall))

# horizontal wall top/bottom at a clean spot
def wall_band(x):
    col = np.where(mask[:, x])[0]
    col = col[col >= half]
    if len(col) == 0:
        return None
    return col.min(), col.max()

probe_clean = int(W * 0.35)
print("wall band at clean x=%d:" % probe_clean, wall_band(probe_clean))

# left / right vertical wall ranges = tall ranges at far left / far right
talls = ranges(tall)
left_v = [r for r in talls if r[1] < W * 0.25]
right_v = [r for r in talls if r[0] > W * 0.75]
mid_v = [r for r in talls if W * 0.25 <= r[0] <= W * 0.75]
print("left vertical wall:", left_v, " right vertical wall:", right_v, " mid column:", mid_v)

lv0, lv1 = left_v[0]
rv0, rv1 = right_v[-1]
wb_clean = wall_band(probe_clean)

# does horizontal wall extend LEFT of left vertical wall outer edge?
outside_col = wall_band(max(lv0 - 12, 0))
print("band left of left vertical wall (x=%d):" % (lv0 - 12), outside_col)
# bottom line continuity: max y just inside vertical wall vs just right of it
inside_col = wall_band(lv1 + 4)
right_of_col = wall_band(lv1 + 40)
print("band inside-vertical x=%d:" % (lv1 + 4), inside_col, " right of it x=%d:" % (lv1 + 40), right_of_col)

# vertical wall top end y
vtops = []
for x in range(lv0, lv1 + 1):
    col = np.where(mask[:, x])[0]
    if len(col):
        vtops.append(col.min())
lv_top = min(vtops)
print("left vertical wall top y =", lv_top)

# ---- export evidence crops (4x nearest) ----
wb = wb_clean[1]
save_crop(im, (max(lv0 - 40, 0), med - 90, lv1 + 200, wb + 36), "_qc_corner_L.png")
save_crop(im, (max(rv0 - 200, 0), med - 90, min(rv1 + 40, W - 1), wb + 36), "_qc_corner_R.png")
if outliers:
    ox = outliers[0][1]
else:
    ox = int(W * 0.6)
save_crop(im, (ox - 120, med - 40, ox + 220, wb + 20), "_qc_seam.png")
save_crop(im, (probe_clean - 140, med - 40, probe_clean + 220, wb + 20), "_qc_clean.png")
save_crop(im, (max(lv0 - 24, 0), max(lv_top - 8, 0), lv1 + 24, lv_top + 170), "_qc_vend.png")
save_crop(im, (max(lv0 - 16, 0), lv_top + 240, lv1 + 16, lv_top + 400), "_qc_vmid.png")
# gate column base where it meets the wall
if mid_v:
    m0, m1 = mid_v[0]
    save_crop(im, (m0 - 90, med - 90, m1 + 90, wb + 30), "_qc_gatecol.png")

# ---- official reference rhythm ----
im2, a2 = load(os.path.join(OF, "_ana_wall_row.png"))
W2, H2 = im2.size
print("official size", W2, H2)
bg2 = a2[3, 3]
diff2 = np.abs(a2 - bg2).sum(axis=2)
mask2 = diff2 > 30
top2 = np.full(W2, 10 ** 9)
for x in range(int(W2 * 0.55), W2):
    col = np.where(mask2[:, x])[0]
    if len(col):
        top2[x] = col[0]
band2 = top2[top2 < 10 ** 8]
med2 = int(np.median(band2))
p25_2 = int(np.percentile(band2, 25))
p75_2 = int(np.percentile(band2, 75))
print("official wall-top y: median=%d p25=%d p75=%d merlon_height=%d" % (med2, p25_2, p75_2, p75_2 - p25_2))
tall2 = (top2 < p25_2 - 40) & (top2 < 10 ** 8)
tooth2 = (top2 < p25_2 + max(3, int(0.30 * (p75_2 - p25_2)))) & (top2 < 10 ** 8) & ~tall2
tr2 = ranges(tooth2)
starts2 = [s for s, e in tr2]
per2 = [starts2[i + 1] - starts2[i] for i in range(len(starts2) - 1)]
print("official wall-top med y =", med2, " teeth n =", len(tr2))
print("official period hist:", dict(collections.Counter(per2)))
print("official merlon width hist:", dict(collections.Counter([e - s + 1 for s, e in tr2])))
# official wall crop for visual compare
ox2 = starts2[2] if len(starts2) > 2 else int(W2 * 0.7)
c = im2.crop((ox2 - 60, med2 - 30, ox2 + 260, med2 + 130))
c = c.resize((c.width * 4, c.height * 4), Image.NEAREST)
c.save(os.path.join(TW, "_qc_official.png"))
print("saved _qc_official.png")
