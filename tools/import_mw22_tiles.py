# -*- coding: utf-8 -*-
"""Mystic Woods 付费版 -> 长安志 地形瓦片管线（整包换血 Slice B）
全部 MW 派生瓦片输出到 sprites/tiles_mw22/（gitignore，本地生成）：
  地面: grass(+a/b/patch/dark) path farmland(+wet) sand(+a/b) dirt_patch stone
  装饰: flower daisy flower_white/yellow tuft_a/b/c mushroom rock fence bridge
  水系: water_anim.png 96x16 六帧动画条 + shore.png 80x80 岸环八向(MW池塘边块)
  山崖: mountain(+b/c) —— MW 石簇
  树表: tree_oak.png / tree_pine.png 4x2=8变体(春/秋/枯/雪程序化调色)，竹保留PC包
唐风色板烘焙（tang_shift 与灰盒样张同源：绿->橄榄 / 棕->暖土）。
⚠️ 授权：MW 禁再分发，tiles_mw22/ 已 gitignore——克隆后本地重跑本工具。
"""
import os, sys, colorsys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MW = os.path.join(ROOT, "downloaded_assets", "mystic_woods_2.2", "sprites")
OUT = os.path.join(ROOT, "sprites", "tiles_mw22")
os.makedirs(OUT, exist_ok=True)

T = 16


def P(*p):
    return os.path.join(MW, *p)


def tang(im):
    """唐风色板微调（绿->降饱和偏橄榄；棕->提暖偏土黄），与 tools/mw_graybox_sample.py 同源"""
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 10:
                continue
            if g > r + 10 and g > b + 10:
                h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
                r2, g2, b2 = colorsys.hsv_to_rgb((h - 0.015) % 1.0, min(1.0, s*0.82), min(1.0, v*1.04))
                px[x, y] = (int(r2*255), int(g2*255), int(b2*255), a)
            elif r > g > b and r - b > 15:
                px[x, y] = (min(255, int(r*1.06)), int(g*0.99), int(b*0.86), a)
    return im


def crop(im, tx, ty, ts=T):
    return im.crop((tx*ts, ty*ts, (tx+1)*ts, (ty+1)*ts))


def val_mul(im, mul):
    """整图明度乘法（草地变体/暗草/雪景压暗用）"""
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a >= 10:
                px[x, y] = (min(255, int(r*mul)), min(255, int(g*mul)), min(255, int(b*mul)), a)
    return im


def recolor_green(im, fn):
    """仅对绿色系像素做 fn(r,g,b)->(r,g,b)（树冠秋色/枯色/雪覆，不动树干/地面）"""
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 10 or not (g > r + 10 and g > b + 10):
                continue
            nr, ng, nb = fn(r, g, b)
            px[x, y] = (nr, ng, nb, a)
    return im


def autumn(im):
    return recolor_green(im, lambda r, g, b: (min(255, int(g*1.35)+30), int(g*0.85), int(b*0.45)))


def bare(im):
    return recolor_green(im, lambda r, g, b: (int(g*0.72), int(g*0.52), int(g*0.34)))


def snowy(im):
    return recolor_green(im, lambda r, g, b: (int(r*0.35+160), int(g*0.35+175), int(b*0.30+195)))


def save(im, name):
    im.save(os.path.join(OUT, name))
    print("  ", name, im.size)


def main():
    plains = Image.open(P("tilesets", "plains.png")).convert("RGBA")
    grass_t = Image.open(P("tilesets", "grass.png")).convert("RGBA")
    decor = Image.open(P("tilesets", "decor_16x16.png")).convert("RGBA")
    fences = Image.open(P("tilesets", "fences.png")).convert("RGBA")
    walls = Image.open(P("tilesets", "walls", "walls.png")).convert("RGBA")
    wooden = Image.open(P("tilesets", "floors", "wooden.png")).convert("RGBA")
    water1 = Image.open(P("tilesets", "water1.png")).convert("RGBA")
    objects = Image.open(P("objects", "objects.png")).convert("RGBA")

    print("[mw22-tiles] ground:")
    g0 = crop(plains, 2, 5)                       # 纯草
    save(tang(g0), "grass.png")
    save(tang(crop(plains, 0, 3)), "grass_a.png")
    save(tang(val_mul(g0, 1.06)), "grass_b.png")  # 微亮纯草（避免土斑过多的旧选(3,3)）
    save(tang(val_mul(g0, 0.88)), "grass_patch.png")
    save(tang(val_mul(g0, 0.80)), "grass_dark.png")
    save(tang(crop(plains, 2, 1)), "path.png")    # 纯土
    save(tang(val_mul(crop(plains, 2, 1), 0.78)), "farmland.png")
    save(tang(val_mul(crop(plains, 2, 1), 0.72)), "farmland_wet.png")
    save(val_mul(tang(crop(plains, 4, 1)), 1.28), "sand.png")
    save(val_mul(tang(crop(plains, 5, 1)), 1.24), "sand_a.png")
    save(val_mul(tang(crop(plains, 5, 2)), 1.32), "sand_b.png")
    save(tang(crop(plains, 4, 1)), "dirt_patch.png")
    save(crop(plains, 2, 9), "stone.png")         # 纯石板（无tang，石色不动）

    print("[mw22-tiles] decor:")
    # decor_16x16 4x5 实测: (0,0)草丛 (1,0)双叶 (2,0)黄花丛 (0,2)红白花 (1,2)白花细碎 (2,2)花簇 (3,2)雏菊 (0,3)红蘑菇
    save(tang(crop(decor, 0, 0)), "tuft_a.png")
    save(tang(crop(decor, 1, 0)), "tuft_b.png")
    save(tang(crop(decor, 2, 0)), "tuft_c.png")
    save(tang(crop(decor, 1, 2)), "flower_white.png")
    save(tang(crop(decor, 2, 2)), "flower_yellow.png")
    save(tang(crop(decor, 0, 2)), "flower.png")
    save(tang(crop(decor, 3, 2)), "daisy.png")
    save(tang(crop(decor, 0, 3)), "mushroom.png")
    save(tang(crop(plains, 0, 8)), "rock.png")    # 带草石簇（碰撞瓦）
    save(tang(crop(fences, 2, 0)), "fence.png")
    save(wooden, "bridge.png")                    # MW 木地板=桥面（无tang，木色原样）

    print("[mw22-tiles] water:")
    # MW 六帧只动画池塘边线、中心纯静止（实测帧差=None）-> 大水域以 MW 水色为底
    # 程序化对角微光波纹（沿用旧"双帧波纹"思路，6帧相位推移）
    base = crop(water1, 2, 1)
    strip = Image.new("RGBA", (96, 16), (0, 0, 0, 0))
    for i in range(6):
        fr = base.copy()
        px = fr.load()
        for y in range(16):
            for x in range(16):
                if (x + y + i * 3) % 16 < 3:      # 对角亮带，逐帧推移3px
                    r, g, b, a = px[x, y]
                    px[x, y] = (min(255, int(r*1.10)+8), min(255, int(g*1.10)+8), min(255, int(b*1.12)+10), a)
        strip.paste(fr, (i*16, 0))
    save(strip, "water_anim.png")

    print("[mw22-tiles] shore(岸环八向, 草沿朝向):")
    shore = Image.new("RGBA", (80, 80), (0, 0, 0, 0))
    sm = tang(water1)
    # 既有 shore_cells 布局: N(2,0) E(4,2) S(2,4) W(0,2) SW(1,4) SE(3,4) NW(1,0) NE(3,0)
    for dst, src in [((2, 0), (2, 0)), ((4, 2), (3, 1)), ((2, 4), (2, 2)), ((0, 2), (1, 1)),
                     ((1, 4), (1, 2)), ((3, 4), (3, 2)), ((1, 0), (1, 0)), ((3, 0), (3, 0))]:
        shore.paste(crop(sm, *src), (dst[0]*16, dst[1]*16))
    save(shore, "shore.png")

    print("[mw22-tiles] mountain:")
    save(crop(plains, 2, 9), "mountain.png")
    save(crop(plains, 4, 9), "mountain_b.png")
    save(val_mul(crop(plains, 2, 9).transpose(Image.FLIP_LEFT_RIGHT), 0.88), "mountain_c.png")

    print("[mw22-tiles] trees(4x2=8变体, 春/秋/枯/雪):")
    boxes = [(1, 80, 46, 144), (49, 80, 94, 144), (3, 147, 46, 208), (51, 147, 94, 208)]
    trees = []
    for (x0, y0, x1, y1) in boxes:
        t = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        t.paste(objects.crop((x0, y0, x1, y1)), ((64-(x1-x0))//2, 64-(y1-y0)))  # 底对齐=脚踩地
        trees.append(tang(t))
    t1, t2, t3, t4 = trees
    oak = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
    for i, v in enumerate([t1, t2, autumn(t1), autumn(t2), t3, t4, bare(t1), snowy(t1)]):
        oak.paste(v, ((i % 4)*64, (i//4)*64))
    save(oak, "tree_oak.png")
    pine = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
    for i, v in enumerate([t3, t4, autumn(t3), bare(t3), t4, autumn(t4), bare(t4), snowy(t3)]):
        pine.paste(v, ((i % 4)*64, (i//4)*64))
    save(pine, "tree_pine.png")
    print("[mw22-tiles] done ->", OUT)


if __name__ == "__main__":
    main()
