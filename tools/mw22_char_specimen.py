# -*- coding: utf-8 -*-
"""Mystic Woods 付费版 player.png 角色样张（P0b 验证用，不入游戏管线）
验证三件事：
  1) 唐装重着装（乌发髻+绯红圆领袍+金束带+乌皮靴）在 48x48 帧上的全动画效果
  2) MW 原生外观作"现代装"的对比条（双外观路线：穿越前=MW原样/穿越后=唐装重着装）
  3) block 补帧提案（包内无防御帧 -> idle 帧+程序化持盾叠加+身体下坐1px）
布局（scale 4）：
  唐装: idle 下/右/上, walk 下/右/上, attack 下/右/上, 死亡
  现代: idle 下, walk 下, block提案x2
输出: docs/shots/mw22_char_specimen.png
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "downloaded_assets", "mystic_woods_2.2", "sprites", "characters", "player.png")
OUT = os.path.join(ROOT, "docs", "shots", "mw22_char_specimen.png")
TS = 48  # 帧尺寸
SCALE = 4

# ---- 唐装映射（源RGB -> 目标RGB），按帧内上下半身分区处理 ----
HAIR = (38, 32, 38)        # 乌发主
HAIR_D = (28, 24, 26)      # 乌发暗
ROBE = (150, 56, 36)       # 绯红袍主（锚=坊墙小样 RED_M，唐风红木色板）
ROBE_L = (206, 106, 72)    # 袍亮（衫高光位）
ROBE_D = (110, 40, 26)     # 袍暗（裤位并入袍摆）
BELT = (196, 150, 74)      # 金束带（锚=GOLD）
BELT_D = (150, 108, 50)
BOOT = (52, 38, 30)        # 乌皮靴帮（原发影棕复用位）
BOOT_D = (28, 22, 20)      # 靴面深

SRC_HAIR = (87, 58, 35)
SRC_HAIR_D = (64, 39, 23)
SRC_SHIRT = (44, 101, 181)
SRC_SHIRT_L = (255, 255, 255)
SRC_PANTS = (29, 67, 138)
SRC_BOOT_D = (33, 17, 13)


def frame(im, c, r):
    return im.crop((c*TS, r*TS, (c+1)*TS, (r+1)*TS)).convert("RGBA")


CORE = {SRC_HAIR, SRC_HAIR_D, SRC_SHIRT, SRC_PANTS, SRC_BOOT_D,
        (0, 0, 0), (172, 123, 93), (193, 172, 143)}   # 身体本色(弧光/白刃不在内)
SHADE_GRAY = (120, 126, 151)                            # 衫影/弧光灰 双用色
SHIRT_DK = (13, 32, 94)                                 # 衫最暗档


def tang_dress(fr, dirn):
    """单帧唐装重着装：乌发髻 + 绯红圆领袍 + 金束带 + 乌皮靴
    双用色分离规则：白=衫高光/眼白/弧光高光三用，仅当被蓝色衣物十字夹住才染；
    蓝灰=衫影/弧光灰双用，仅当紧贴蓝色衣物才染（贴白刃/弧光的保留灰）"""
    px = fr.load()
    xs, ys = [], []
    for y in range(TS):
        for x in range(TS):
            if px[x, y][3] > 200 and px[x, y][:3] in CORE:   # 身体bbox, 排除弧光
                xs.append(x); ys.append(y)
    if not xs:
        return fr
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    ch = y1 - y0 + 1
    waist = y0 + int(ch * 0.55)
    cx = (x0 + x1) // 2
    orig = [[px[x, y][:3] for x in range(TS)] for y in range(TS)]   # 快照, 防同帧改色污染邻接判断
    # 衣饰灰判据：贴身体本色(衫蓝/黑描边/皮肤/发棕) -> 衣物；悬浮于白/灰之间 -> 弧光
    BODY_COLORS = {SRC_SHIRT, SRC_PANTS, (0, 0, 0), (172, 123, 93), (193, 172, 143), SRC_HAIR, SRC_HAIR_D}
    body_gray = lambda x, y: 0 <= x < TS and 0 <= y < TS and orig[y][x] in BODY_COLORS
    at_blue = lambda x, y: 0 <= x < TS and 0 <= y < TS and orig[y][x] in (SRC_SHIRT, SRC_PANTS)
    for y in range(TS):
        for x in range(TS):
            r, g, b, a = px[x, y]
            if a <= 10:
                continue
            src = (r, g, b)
            if src == SRC_SHIRT:
                px[x, y] = (*(ROBE if y >= waist else ROBE_L), 255)
            elif src in (SRC_PANTS, SHIRT_DK):
                px[x, y] = (*ROBE_D, 255)
            elif src == SRC_SHIRT_L:
                if (at_blue(x-1, y) and at_blue(x+1, y)) or (at_blue(x, y-1) and at_blue(x, y+1)):
                    px[x, y] = (*ROBE_L, 255)          # 衫高光(被蓝十字夹住) -> 袍亮
            elif src == SHADE_GRAY:
                if body_gray(x-1, y) or body_gray(x+1, y) or body_gray(x, y-1) or body_gray(x, y+1):
                    px[x, y] = (*ROBE_D, 255)          # 衫影(贴衣/贴描边) -> 袍影
            elif src == (164, 168, 181):
                if body_gray(x-1, y) or body_gray(x+1, y) or body_gray(x, y-1) or body_gray(x, y+1):
                    px[x, y] = (*ROBE_L, 255)          # 衫缘高光 -> 袍亮
            elif src == SRC_HAIR and y < waist:
                px[x, y] = (*HAIR, 255)
            elif src == SRC_HAIR_D:
                px[x, y] = (*(HAIR_D if y < waist else BOOT), 255)
            elif src == SRC_BOOT_D:
                px[x, y] = (*BOOT_D, 255)
    # 金束带: 腰线两行, 袍色像素改金
    for y in (waist, waist + 1):
        for x in range(x0, x1 + 1):
            if px[x, y][:3] in (ROBE, ROBE_D):
                px[x, y] = (*(BELT if y == waist else BELT_D), 255)
    # 发髻: 头顶堆 3 行乌发 + 金簪一点（右向偏后）
    bx = cx - 2 if dirn == "right" else cx
    for dy, half in ((1, 2), (2, 2), (3, 1)):
        for dx in range(-half, half + 1):
            xx, yy = bx + dx, y0 - dy
            if 0 <= xx < TS and yy >= 0 and px[xx, yy][3] <= 10:
                px[xx, yy] = (*(HAIR if dy < 3 else HAIR_D), 255)
    if 0 <= bx + 3 < TS and y0 - 2 >= 0:
        px[bx + 3, y0 - 2] = (*BELT, 255)       # 发簪
    return fr


def block_pose(fr):
    """block 补帧提案: 身体下坐1px + 体侧程序化小圆木盾（不遮脸）"""
    canvas = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    canvas.alpha_composite(fr, (0, 1))
    d = ImageDraw.Draw(canvas)
    px = fr.load()
    xs = [x for y in range(TS) for x in range(TS) if fr.getpixel((x, y))[3] > 200]
    cx = (min(xs) + max(xs)) // 2
    sx0, sy0 = cx + 2, 30                       # 右手侧前方
    d.ellipse([sx0, sy0, sx0 + 7, sy0 + 9], fill=(116, 84, 54, 255), outline=(52, 36, 26, 255))
    d.ellipse([sx0 + 2, sy0 + 3, sx0 + 4, sy0 + 5], fill=(150, 150, 158, 255))
    return canvas


def main():
    im = Image.open(SRC).convert("RGBA")
    ROWS = {  # 行号 -> (帧数, 方向)
        0: (6, "down"), 1: (6, "right"), 2: (6, "up"),
        3: (6, "down"), 4: (6, "right"), 5: (6, "up"),
        6: (4, "down"), 7: (4, "right"), 8: (4, "up"), 9: (3, "down"),
    }
    bands = []  # (标签, [帧PIL])
    # 唐装段
    for r, label in [(0, "唐装 idle·下"), (1, "唐装 idle·右"), (2, "唐装 idle·上"),
                     (3, "唐装 walk·下"), (4, "唐装 walk·右"), (5, "唐装 walk·上"),
                     (6, "唐装 attack·下"), (7, "唐装 attack·右"), (8, "唐装 attack·上"),
                     (9, "唐装 受击/死亡")]:
        n, dirn = ROWS[r]
        bands.append((label, [tang_dress(frame(im, c, r), dirn) for c in range(n)]))
    # 现代段（MW 原样即"穿越前"外观）
    bands.append(("现代 idle·下（MW原样）", [frame(im, c, 0) for c in range(6)]))
    bands.append(("现代 walk·下（MW原样）", [frame(im, c, 3) for c in range(6)]))
    bands.append(("block补帧提案: idle原帧 | 下坐+持盾", [frame(im, 0, 0), block_pose(frame(im, 0, 0))]))

    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
    except OSError:
        font = ImageFont.load_default()

    pad, label_h, cell = 10, 22, TS*SCALE
    max_cells = max(len(f) for _, f in bands)
    W = pad*2 + max_cells*(cell+8) - 8
    H = pad*2 + sum(label_h + cell + 14 for _ in bands) - 14
    sheet = Image.new("RGBA", (W, H), (40, 40, 48, 255))
    d = ImageDraw.Draw(sheet)
    y = pad
    for label, frames in bands:
        d.text((pad, y+2), label, fill=(255, 220, 120, 255), font=font)
        y += label_h
        for i, fr in enumerate(frames):
            big = fr.resize((cell, cell), Image.NEAREST)
            sheet.alpha_composite(big, (pad + i*(cell+8), y))
        y += cell + 14
    sheet.save(OUT)
    print("[char-specimen] wrote", OUT, sheet.size)


if __name__ == "__main__":
    main()
