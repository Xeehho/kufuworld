# -*- coding: utf-8 -*-
"""内景切片候选窗测量 + 裁片联络表（切片禁目测估框——先测后切）。
用法: python tools/measure_windows.py            # 测量全部候选窗并出联络表 docs/shots/pack_jingcheng/interior_slice_preview.png
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "downloaded_assets", "comshadow_bundle")
OUT = os.path.join(ROOT, "docs", "shots", "pack_jingcheng")

# (label, sheet, l, t, r, b) —— 候选窗=96px 单元格，输出窗内内容 bbox
CANDS = [
    ("wi1_scroll1", "wuxia_interior_dlc/tile-B-01.png", 480, 0, 528, 96),
    ("wi1_scroll2", "wuxia_interior_dlc/tile-B-01.png", 528, 0, 576, 96),
    ("wi1_scroll3", "wuxia_interior_dlc/tile-B-01.png", 576, 0, 624, 96),
    ("wi1_scroll4", "wuxia_interior_dlc/tile-B-01.png", 624, 0, 672, 96),
    ("wi1_scroll5", "wuxia_interior_dlc/tile-B-01.png", 672, 0, 720, 96),
    ("wi1_scroll6", "wuxia_interior_dlc/tile-B-01.png", 720, 0, 768, 96),
    ("wi1_chair_top", "wuxia_interior_dlc/tile-B-01.png", 384, 0, 432, 96),
    ("wi1_chair_mid", "wuxia_interior_dlc/tile-B-01.png", 384, 96, 432, 192),
    ("wi1_bed_blue", "wuxia_interior_dlc/tile-B-01.png", 288, 0, 384, 96),
    ("wi1_bed_top", "wuxia_interior_dlc/tile-B-01.png", 192, 0, 288, 96),
    ("wi1_tea_row2", "wuxia_interior_dlc/tile-B-01.png", 384, 192, 480, 288),
    ("wi1_desk_ink", "wuxia_interior_dlc/tile-B-01.png", 480, 96, 576, 192),
    ("wi1_desk_scroll1", "wuxia_interior_dlc/tile-B-01.png", 480, 288, 576, 384),
    ("wi1_desk_scroll2", "wuxia_interior_dlc/tile-B-01.png", 576, 288, 672, 384),
    ("wi1_altar", "wuxia_interior_dlc/tile-B-01.png", 432, 384, 528, 480),
    ("wi1_desk_a", "wuxia_interior_dlc/tile-B-01.png", 480, 384, 576, 480),
    ("wi1_desk_b", "wuxia_interior_dlc/tile-B-01.png", 576, 384, 672, 480),
    ("wi1_desk_c", "wuxia_interior_dlc/tile-B-01.png", 672, 384, 768, 480),
    ("wi1_desk_d", "wuxia_interior_dlc/tile-B-01.png", 480, 576, 576, 672),
    ("wi1_desk_e", "wuxia_interior_dlc/tile-B-01.png", 576, 576, 672, 672),
    ("wi1_desk_f", "wuxia_interior_dlc/tile-B-01.png", 672, 576, 768, 672),
    ("wi1_bed_y1", "wuxia_interior_dlc/tile-B-01.png", 192, 96, 288, 192),
    ("wi1_bed_g1", "wuxia_interior_dlc/tile-B-01.png", 192, 192, 288, 288),
    ("wi1_bed_p1", "wuxia_interior_dlc/tile-B-01.png", 192, 288, 288, 384),
    ("wi1_screen_lo", "wuxia_interior_dlc/tile-B-01.png", 0, 288, 96, 384),
    ("wi1_screen_hi", "wuxia_interior_dlc/tile-B-01.png", 96, 288, 192, 384),
    ("jc7_table_a", "jingcheng/tile-B-07.png", 0, 0, 96, 96),
    ("jc7_table_red", "jingcheng/tile-B-07.png", 96, 0, 192, 96),
    ("jc7_jars2", "jingcheng/tile-B-07.png", 384, 0, 480, 96),
    ("jc7_cab_lattice", "jingcheng/tile-B-07.png", 480, 0, 576, 96),
    ("jc7_cab_arch", "jingcheng/tile-B-07.png", 576, 0, 672, 96),
    ("jc7_shelf_curio", "jingcheng/tile-B-07.png", 672, 0, 768, 96),
    ("jc7_cab_tall2", "jingcheng/tile-B-07.png", 480, 96, 576, 192),
    ("jc7_lantern_std", "jingcheng/tile-B-07.png", 576, 96, 624, 192),
    ("jc7_lantern_std2", "jingcheng/tile-B-07.png", 624, 96, 672, 192),
    ("jc7_counter_a", "jingcheng/tile-B-07.png", 96, 288, 192, 384),
    ("jc7_bookshelf", "jingcheng/tile-B-07.png", 384, 192, 480, 288),
    ("jc7_lantern_pole", "jingcheng/tile-B-07.png", 576, 192, 672, 288),
    ("jc7_lantern_hang", "jingcheng/tile-B-07.png", 672, 192, 768, 288),
    ("jc7_jars_cluster", "jingcheng/tile-B-07.png", 192, 384, 288, 480),
    ("jc7_jars_cluster2", "jingcheng/tile-B-07.png", 288, 384, 384, 480),
    ("jc7_lantern_floor", "jingcheng/tile-B-07.png", 576, 384, 624, 480),
    ("jc7_cab_pair", "jingcheng/tile-B-07.png", 480, 384, 576, 480),
    ("jc7_bed_r1", "jingcheng/tile-B-07.png", 480, 480, 576, 576),
    ("jc7_bed_b1", "jingcheng/tile-B-07.png", 576, 480, 672, 576),
    ("jc7_bed_g1", "jingcheng/tile-B-07.png", 672, 480, 768, 576),
    ("jc7_bed_p1", "jingcheng/tile-B-07.png", 480, 576, 576, 672),
    ("jc7_lowcab_a", "jingcheng/tile-B-07.png", 0, 384, 96, 480),
    ("jc7_lowcab_b", "jingcheng/tile-B-07.png", 96, 384, 192, 480),
    ("jc7_sideboard", "jingcheng/tile-B-07.png", 480, 192, 576, 288),
    ("jc4_silk_shelf1", "jingcheng/tile-B-04.png", 0, 0, 96, 96),
    ("jc4_silk_shelf2", "jingcheng/tile-B-04.png", 96, 0, 192, 96),
    ("jc4_herbdrawer", "jingcheng/tile-B-04.png", 192, 0, 288, 96),
    ("jc4_herbdrawer2", "jingcheng/tile-B-04.png", 288, 0, 384, 96),
    ("jc4_silk_tall", "jingcheng/tile-B-04.png", 0, 192, 96, 288),
    ("jc4_silk_tall2", "jingcheng/tile-B-04.png", 96, 192, 192, 288),
    ("jc4_tea_a", "jingcheng/tile-B-04.png", 96, 384, 192, 480),
    ("jc4_tea_b", "jingcheng/tile-B-04.png", 192, 480, 288, 576),
    ("jc4_stool1", "jingcheng/tile-B-04.png", 192, 576, 240, 672),
    ("jc4_stool2", "jingcheng/tile-B-04.png", 240, 576, 288, 672),
    ("wd3_screen_land", "wuxia_dlc/tile-B-03.png", 288, 384, 480, 480),
    ("wd3_screen_plum", "wuxia_dlc/tile-B-03.png", 0, 480, 288, 576),
    ("wd3_dresser", "wuxia_dlc/tile-B-03.png", 192, 384, 288, 480),
    ("wd3_wine_rack", "wuxia_dlc/tile-B-03.png", 384, 288, 480, 384),
    ("wd3_herb_jar1", "wuxia_dlc/tile-B-03.png", 384, 192, 480, 288),
    ("wd3_herb_jar2", "wuxia_dlc/tile-B-03.png", 480, 192, 576, 288),
    ("wd3_bookshelf", "wuxia_dlc/tile-B-03.png", 288, 192, 384, 288),
    ("wd3_wardrobe", "wuxia_dlc/tile-B-03.png", 0, 192, 96, 288),
    ("wd3_chair1", "wuxia_dlc/tile-B-03.png", 0, 288, 48, 384),
    ("wd3_chair2", "wuxia_dlc/tile-B-03.png", 48, 288, 96, 384),
    ("wx3_danbi_a", "wuxia/tile-B-03.png", 0, 384, 192, 528),
    ("wx3_danbi_b", "wuxia/tile-B-03.png", 192, 384, 384, 528),
    ("wx3_scroll_h1", "wuxia/tile-B-03.png", 0, 672, 128, 768),
    ("wx3_scroll_h2", "wuxia/tile-B-03.png", 128, 672, 256, 768),
    ("wx3_scroll_h3", "wuxia/tile-B-03.png", 256, 672, 384, 768),
    ("wx3_scroll_h4", "wuxia/tile-B-03.png", 384, 672, 512, 768),
    ("wx3_mat", "wuxia/tile-B-03.png", 384, 576, 480, 672),
    ("wx3_rack_spear", "wuxia/tile-B-03.png", 0, 320, 96, 384),
    ("wx3_rack_sword", "wuxia/tile-B-03.png", 192, 528, 288, 608),
    ("wx3_rack_sword2", "wuxia/tile-B-03.png", 288, 528, 384, 608),
    ("wi4_mural1", "wuxia_interior_dlc/tile-B-04.png", 0, 0, 96, 96),
    ("wi4_mural2", "wuxia_interior_dlc/tile-B-04.png", 96, 0, 192, 96),
    ("wi4_mural3", "wuxia_interior_dlc/tile-B-04.png", 192, 0, 288, 96),
    ("wi4_mural4", "wuxia_interior_dlc/tile-B-04.png", 288, 0, 384, 96),
    ("wi4_mural_l1", "wuxia_interior_dlc/tile-B-04.png", 0, 192, 96, 288),
    ("wi4_mural_l2", "wuxia_interior_dlc/tile-B-04.png", 96, 192, 192, 288),
    ("wi4_rack1", "wuxia_interior_dlc/tile-B-04.png", 384, 576, 480, 672),
    ("wi4_rack2", "wuxia_interior_dlc/tile-B-04.png", 480, 576, 576, 672),
    ("wi4_rack3", "wuxia_interior_dlc/tile-B-04.png", 576, 576, 672, 672),
    ("wi4_rack4", "wuxia_interior_dlc/tile-B-04.png", 672, 576, 768, 672),
    ("wi4_cab_red", "wuxia_interior_dlc/tile-B-04.png", 384, 0, 480, 96),
    ("wi4_cab_red2", "wuxia_interior_dlc/tile-B-04.png", 480, 0, 576, 96),
    ("wi4_jarshelf", "wuxia_interior_dlc/tile-B-04.png", 480, 288, 576, 384),
    ("wi4_jarshelf2", "wuxia_interior_dlc/tile-B-04.png", 576, 288, 672, 384),
    ("wi2_stove1", "wuxia_interior_dlc/tile-B-02.png", 0, 0, 96, 96),
    ("wi2_stove2", "wuxia_interior_dlc/tile-B-02.png", 192, 0, 288, 96),
    ("wi2_stove_big", "wuxia_interior_dlc/tile-B-02.png", 0, 192, 96, 288),
    ("wi2_steamer1", "wuxia_interior_dlc/tile-B-02.png", 480, 96, 528, 192),
    ("wi2_steamer2", "wuxia_interior_dlc/tile-B-02.png", 528, 96, 576, 192),
    ("wi2_jars_row", "wuxia_interior_dlc/tile-B-02.png", 0, 384, 48, 480),
    ("wi2_jar_white", "wuxia_interior_dlc/tile-B-02.png", 0, 480, 48, 528),
    ("wi2_counter", "wuxia_interior_dlc/tile-B-02.png", 480, 432, 576, 528),
    ("wi2_shelf_dish", "wuxia_interior_dlc/tile-B-02.png", 288, 432, 384, 528),
    ("wi2_lantern", "wuxia_interior_dlc/tile-B-02.png", 720, 96, 768, 192),
    ("wi2_firepit", "wuxia_interior_dlc/tile-B-02.png", 656, 672, 704, 768),
    ("wi5_wall_lattice", "wuxia_interior_dlc/tile-B-05.png", 96, 96, 192, 192),
    ("wi5_bookwall", "wuxia_interior_dlc/tile-B-05.png", 288, 96, 384, 192),
    ("wi5_pillar1", "wuxia_interior_dlc/tile-B-05.png", 384, 96, 432, 192),
    ("wi5_pillar2", "wuxia_interior_dlc/tile-B-05.png", 432, 96, 480, 192),
    ("wi5_lantern_h1", "wuxia_interior_dlc/tile-B-05.png", 432, 192, 480, 288),
    ("wi5_lantern_h2", "wuxia_interior_dlc/tile-B-05.png", 528, 192, 576, 288),
    ("wi5_lantern_std1", "wuxia_interior_dlc/tile-B-05.png", 552, 480, 600, 576),
    ("wi5_lantern_std2", "wuxia_interior_dlc/tile-B-05.png", 600, 480, 648, 576),
    ("wi5_floor_plain", "wuxia_interior_dlc/tile-B-05.png", 48, 336, 64, 352),
    ("wi5_floor_medal", "wuxia_interior_dlc/tile-B-05.png", 432, 336, 448, 352),
    ("wd1_counter_a", "wuxia_dlc/tile-B-01.png", 0, 0, 96, 72),
    ("wd1_counter_herb", "wuxia_dlc/tile-B-01.png", 480, 192, 576, 288),
    ("wd1_counter_doc", "wuxia_dlc/tile-B-01.png", 288, 288, 384, 384),
    ("wd1_banner1", "wuxia_dlc/tile-B-01.png", 576, 0, 640, 96),
    ("wd1_banner2", "wuxia_dlc/tile-B-01.png", 576, 384, 640, 480),
    ("wd1_banner3", "wuxia_dlc/tile-B-01.png", 576, 576, 640, 672),
]


def cellbox(im, l, t, r, b):
    px = im.load()
    minx = miny = 10 ** 9
    maxx = maxy = -1
    n = 0
    for y in range(t, min(b, im.height)):
        for x in range(l, min(r, im.width)):
            if px[x, y][3] > 10:
                n += 1
                minx = min(minx, x); maxx = max(maxx, x)
                miny = min(miny, y); maxy = max(maxy, y)
    return (minx, miny, maxx + 1, maxy + 1, n) if n else None


def main():
    os.makedirs(OUT, exist_ok=True)
    sheets = {}
    def S(rel):
        if rel not in sheets:
            sheets[rel] = Image.open(os.path.join(SRC, rel)).convert("RGBA")
        return sheets[rel]
    crops = []
    for label, rel, l, t, r, b in CANDS:
        im = S(rel)
        cb = cellbox(im, l, t, r, b)
        if cb is None:
            print(f"{label}: EMPTY")
            continue
        x0, y0, x1, y1, n = cb
        print(f"{label}: box=({x0},{y0},{x1},{y1}) {x1-x0}x{y1-y0} n={n}")
        crops.append((label, im.crop((x0, y0, x1, y1))))
    # 联络表：每格 220x220，NEAREST 放大
    cols, cw, ch = 10, 220, 240
    rows = (len(crops) + cols - 1) // cols
    out = Image.new("RGBA", (cols * cw, rows * ch), (44, 44, 52, 255))
    d = ImageDraw.Draw(out)
    for i, (label, im) in enumerate(crops):
        cx, cy = (i % cols) * cw, (i // cols) * ch
        s = min((cw - 16) / im.width, (ch - 34) / im.height, 3.0)
        s = max(s, 0.5)
        im2 = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.NEAREST)
        out.paste(im2, (cx + 8, cy + 26), im2)
        d.text((cx + 6, cy + 4), f"{label} {im.width}x{im.height}", fill=(255, 255, 120))
        d.rectangle([cx, cy, cx + cw - 1, cy + ch - 1], outline=(90, 90, 100))
    out.convert("RGB").save(os.path.join(OUT, "interior_slice_preview.png"))
    print("preview ->", os.path.join(OUT, "interior_slice_preview.png"))


if __name__ == "__main__":
    main()
