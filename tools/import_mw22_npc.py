# -*- coding: utf-8 -*-
"""Mystic Woods 付费版 player 底模 -> 江湖志 NPC 11类换装（整包换血 Slice C）
MW 无 NPC/村民素材——以 player.png 为底模逐帧重着装（与玩家唐装同源邻接判据）：
  男6: warrior(玄甲)/scholar(月白)/mysterious(深紫)/merchant(金棕)/elder(灰白)/guard(皂衣红缨)
  女5: tavern_f(石榴裙)/matron_f(绛紫)/peasant_f(靛蓝)/herbalist_f(青绿)/seamstress_f(藕荷)
       女式=长发披肩(鬓角延长)+裙装(裤位并裙色)+提高腰线
输出 sprites/npc/{type}_{idle,walk}_{dir}_{i}.png 32x32（画布/命名与旧管线一致，
MW素材gitignore本地生成；克隆缺失时 npc_character 走旧PNG或占位色块）。
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "downloaded_assets", "mystic_woods_2.2", "sprites", "characters", "player.png")
OUT = os.path.join(ROOT, "sprites", "npc")
os.makedirs(OUT, exist_ok=True)

TS = 48
# MW player 源色（同 specimen 实测）
SRC_HAIR = (87, 58, 35)
SRC_HAIR_D = (64, 39, 23)
SRC_SHIRT = (44, 101, 181)
SRC_SHIRT_L = (255, 255, 255)
SRC_PANTS = (29, 67, 138)
SRC_SHIRT_DK = (13, 32, 94)
SRC_SHADE = (120, 126, 151)
SRC_EDGE = (164, 168, 181)
SRC_BOOT = (33, 17, 13)
BODY_COLORS = {SRC_HAIR, SRC_HAIR_D, SRC_SHIRT, SRC_PANTS, SRC_BOOT,
               (0, 0, 0), (172, 123, 93), (193, 172, 143)}

# 11类配色: (发色, 袍/上衣, 裤或裙, 腰带, 女式, 头饰红缨)
TYPES = {
    "warrior":     ((30, 28, 30), (72, 78, 92), (48, 52, 60), (120, 40, 32), False, False),
    "scholar":     ((30, 28, 30), (226, 222, 208), (180, 176, 166), (58, 86, 106), False, False),
    "mysterious":  ((24, 22, 26), (54, 42, 70), (38, 30, 50), (120, 96, 44), False, False),
    "merchant":    ((87, 58, 35), (176, 132, 66), (110, 80, 40), (150, 56, 36), False, False),
    "elder":       ((168, 164, 156), (206, 202, 192), (160, 156, 148), (120, 116, 110), False, False),
    "guard":       ((30, 28, 30), (52, 50, 54), (40, 38, 42), (150, 56, 36), False, True),
    "tavern_f":    ((28, 24, 28), (216, 178, 120), (170, 54, 44), (196, 150, 74), True, False),
    "matron_f":    ((96, 74, 60), (170, 150, 160), (108, 60, 88), (150, 108, 50), True, False),
    "peasant_f":   ((74, 52, 34), (196, 188, 168), (70, 86, 120), (110, 96, 70), True, False),
    "herbalist_f": ((58, 60, 40), (216, 210, 190), (88, 120, 96), (110, 96, 70), True, False),
    "seamstress_f": ((30, 28, 30), (226, 200, 160), (168, 120, 150), (150, 108, 50), True, False),
}

MW_ROWS = {"down": (0, 3), "right": (1, 4), "up": (2, 5)}   # (idle行, walk行)


def shade(c, mul):
    return (min(255, int(c[0]*mul)), min(255, int(c[1]*mul)), min(255, int(c[2]*mul)))


def dress_type(fr, pal, dirn):
    """单帧类型重着装：pal=(发色,袍,裤/裙,腰带,女式,红缨)"""
    hair, robe, bottom, belt, female, plume = pal
    robe_l, robe_d = shade(robe, 1.25), shade(robe, 0.72)
    px = fr.load()
    xs, ys = [], []
    for y in range(TS):
        for x in range(TS):
            if px[x, y][3] > 200 and px[x, y][:3] in BODY_COLORS:
                xs.append(x); ys.append(y)
    if not xs:
        return fr
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    waist = y0 + int((y1 - y0 + 1) * (0.48 if female else 0.55))
    orig = [[px[x, y][:3] for x in range(TS)] for y in range(TS)]
    at_blue = lambda x, y: 0 <= x < TS and 0 <= y < TS and orig[y][x] in (SRC_SHIRT, SRC_PANTS)
    body_gray = lambda x, y: 0 <= x < TS and 0 <= y < TS and orig[y][x] in BODY_COLORS
    for y in range(TS):
        for x in range(TS):
            r, g, b, a = px[x, y]
            if a <= 10:
                continue
            src = (r, g, b)
            if src == SRC_SHIRT:
                px[x, y] = (*(robe if y >= waist else robe_l), 255)
            elif src in (SRC_PANTS, SRC_SHIRT_DK):
                px[x, y] = (*(bottom if y >= waist else robe_d), 255)
            elif src == SRC_SHIRT_L:
                if (at_blue(x-1, y) and at_blue(x+1, y)) or (at_blue(x, y-1) and at_blue(x, y+1)):
                    px[x, y] = (*robe_l, 255)
            elif src == SRC_SHADE:
                if body_gray(x-1, y) or body_gray(x+1, y) or body_gray(x, y-1) or body_gray(x, y+1):
                    px[x, y] = (*robe_d, 255)
            elif src == SRC_EDGE:
                if body_gray(x-1, y) or body_gray(x+1, y) or body_gray(x, y-1) or body_gray(x, y+1):
                    px[x, y] = (*robe_l, 255)
            elif src == SRC_HAIR and y < waist:
                px[x, y] = (*hair, 255)
            elif src == SRC_HAIR_D:
                px[x, y] = (*(shade(hair, 0.8) if y < waist else (28, 22, 20)), 255)
            elif src == SRC_BOOT:
                px[x, y] = (*(28, 22, 20), 255)
    # 腰带（男胸口束带/女高腰襦裙线）
    for y in (waist, waist + 1):
        for x in range(x0, x1 + 1):
            if px[x, y][:3] in (robe, robe_d):
                px[x, y] = (*(belt if y == waist else shade(belt, 0.8)), 255)
    # 发髻（与玩家同款，右向偏后）
    cx = (x0 + x1) // 2
    bx = cx - 2 if dirn == "right" else cx
    for dy, half in ((1, 2), (2, 2), (3, 1)):
        for dx in range(-half, half + 1):
            xx, yy = bx + dx, y0 - dy
            if 0 <= xx < TS and yy >= 0 and px[xx, yy][3] <= 10:
                px[xx, yy] = (*(hair if dy < 3 else shade(hair, 0.8)), 255)
    if plume and y0 - 2 >= 0:                      # 官差红缨
        px[bx, y0 - 2] = (170, 54, 44, 255)
        px[bx, y0 - 3] = (150, 40, 34, 255)
    if female:                                     # 长发披肩：头底两行向肩部延长
        hb = y0 + 9
        for yy in range(hb, hb + 4):
            for xx in (x0 + 1, x0 + 2, x1 - 2, x1 - 1):
                if 0 <= xx < TS and 0 <= yy < TS and px[xx, yy][3] <= 10:
                    px[xx, yy] = (*shade(hair, 0.9), 255)
    return fr


def main():
    im = Image.open(SRC).convert("RGBA")
    for tname, pal in TYPES.items():
        female = pal[4]
        for dirn in ["down", "left", "right", "up"]:
            src_dir = "right" if dirn == "left" else dirn
            idle_r, walk_r = MW_ROWS[src_dir]
            flip = (dirn == "left")
            for anim, row, n in (("idle", idle_r, 4), ("walk", walk_r, 6)):
                frames = []
                for c in range(n):
                    fr = im.crop((c*TS, row*TS, (c+1)*TS, (row+1)*TS)).convert("RGBA")
                    fr = dress_type(fr, pal, src_dir)
                    if female:                     # 女式去髻改披发：发髻区回填头发色
                        px = fr.load()
                        # 髻已在 dress_type 画出，保留（唐风女子也束髻）——无需处理
                    if flip:
                        fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
                    # 48x48 -> 32x32 画布: 取中带32宽, 脚线y43对齐画布y31
                    frames.append(fr.crop((8, 12, 40, 44)))
                for i, fr in enumerate(frames):
                    fr.save(os.path.join(OUT, "%s_%s_%s_%d.png" % (tname, anim, dirn, i)))
        print("[mw22-npc]", tname, "idle4+walk6 x4dir written")


if __name__ == "__main__":
    main()
