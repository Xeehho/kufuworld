# -*- coding: utf-8 -*-
"""SCKR 样板间数字拼装 v2（2026-09-08）：按 vision 评审四类问题修正坐标 + 自动验收断言

v2 修正（对照 vision FAIL 项）：
A 城墙：①wall_run 改干净段 (577,98,645,192)——底边单值 185 无门楼斜脚残影（垂舌根治）；
        ②gate_big 框扩 (467,98,577,192) 尾=垛口起相位 / gate_mid 框扩 (620,98,720,192) 尾含隙
        ——所有对接缝落在垛口起点相位上（4px 透缝根治）；③官方层次：门楼脚 191 / 墙脚 185（两档为官方设计）
B 宫墙：①宫门框扩 (0,96,145,192) 含 144 列使段接缝瓦垄相位连续（6px 垄周期）；②太极殿底缘
        压墙帽线以下（后排被前排遮挡锚定）；③画布加高带间隔离
C 连排：①door_a 截尾 (295,0,384,92) 去 7px 矮帽（顶部透缝根治）；②马头墙底对齐 oy-4；
        ③画布加高 row2 完整呈现
自动断言：逐缝背景竖线扫描 + 底边分组校验 + 重叠区同源校验
"""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "downloaded_assets", "comshadow_bundle")
OUT = os.path.join(ROOT, "docs", "参考", "sckr_official_demo")

JC1 = Image.open(os.path.join(SRC, "jingcheng", "tile-B-01.png")).convert("RGBA")
JC3 = Image.open(os.path.join(SRC, "jingcheng", "tile-B-03.png")).convert("RGBA")
JN4 = Image.open(os.path.join(SRC, "jiangnan", "tile-B-04.png")).convert("RGBA")
FONT = ImageFont.load_default()
BG = (52, 52, 56)

def paste(canvas, src, box, dx, dy):
    canvas.alpha_composite(src.crop(box), (dx, dy))

def label(canvas, x, y, text):
    ImageDraw.Draw(canvas).text((x, y), text, fill=(255, 220, 120, 255), font=FONT)

def _is_bg(px):
    r, g, b = px[0], px[1], px[2]
    return abs(r - 52) < 14 and abs(g - 52) < 14 and abs(b - 56) < 14

def assert_no_bg_seams(canvas, x0, y0, x1, y1, min_h=30, min_w=2, tag=""):
    """验收1：背景色竖缝（宽>=min_w 高>=min_h）——按颜色匹配而非 alpha（画布不透明）"""
    rgb = canvas.convert("RGB").load()
    fails = []
    for x in range(x0, x1 - min_w + 1):
        run = 0; best = 0
        for y in range(y0, y1):
            if _is_bg(rgb[x, y]):
                run += 1; best = max(best, run)
            else:
                run = 0
        if best >= min_h and all(
            max((1 if _is_bg(rgb[xx, yy]) else 0) for yy in range(y0, y1)) for xx in range(x, x + min_w)
        ):
            fails.append((x, best))
    if fails:
        print(f"[FAIL] {tag} 背景色竖缝：{fails[:8]}")
        return False
    print(f"[PASS] {tag} 无背景色竖缝（宽>= {min_w}px 高>= {min_h}px）")
    return True

def assert_bottom_groups(canvas, y_line, tol, items, tag=""):
    """验收2：件底边=区域内最下方非背景像素行（容差 tol）"""
    rgb = canvas.convert("RGB").load()
    ok = True
    for name, (bx0, bx1, expect) in items.items():
        bot = -1
        for y in range(min(y_line + 6, canvas.height - 1), y_line - 100, -1):
            if any(not _is_bg(rgb[x, y]) for x in range(bx0, bx1, 3)):
                bot = y; break
        if bot < 0:
            print(f"[WARN] {tag}/{name} 无内容"); continue
        if abs(bot - expect) > tol:
            print(f"[FAIL] {tag}/{name} 底边 y={bot} 期望 {expect}±{tol}")
            ok = False
    if ok: print(f"[PASS] {tag} 底边分组校验")
    return ok

# ============ 样板 A v2：城墙 + 城门 ============
W, H = 640, 330
c = Image.new("RGBA", (W, H), BG + (255,))
label(c, 10, 6, "A/1 OFFICIAL BAND (x430-720)")
paste(c, JC1, (430, 98, 720, 192), 10, 24)
oy = 150
label(c, 10, oy - 18, "A/2 v2: wall(577..645 clean,base185) pitch-aligned gates")
# 部件（源带坐标系 -> 画布 x = 10 + (sx - 473)，渲染顺序：墙先、门楼盖）
paste(c, JC1, (577, 98, 645, 192), 10 + 104, oy)   # wall_run @114 (带577~645)
paste(c, JC1, (577, 98, 645, 192), 10 + 172, oy)   # @182 (带645~713)
paste(c, JC1, (577, 98, 645, 192), 10 + 240, oy)   # @254 (带717~785? 240+473=713→713? 修正: 240+473-10=703...) 见下方布局说明
paste(c, JC1, (577, 98, 645, 192), 10 + 308, oy)   # @318
paste(c, JC1, (467, 98, 577, 192), 10, oy)         # gate_big @10 (框扩467~577, 尾=垛起相位)
paste(c, JC1, (620, 98, 720, 192), 10 + 147, oy)   # gate_mid @157 (框扩620~720, 尾含隙, 盖墙上)
paste(c, JC1, (473, 194, 568, 288), 10 + 376, oy)  # gate_big_o @376: 实内容左缘源483->画布386=wall尾零间隙
okA = assert_no_bg_seams(c, 10, oy + 20, 471, oy + 94, tag="A/2 墙区")
okA &= assert_bottom_groups(c, oy + 92, 2, {
    "wall_run": (114, 182, oy + 87), "gate_big": (10, 120, oy + 93), "gate_mid": (157, 257, oy + 93),
}, tag="A/2")
d = ImageDraw.Draw(c)
d.line([(10, oy + 94), (630, oy + 94)], fill=(255, 120, 120, 255))
label(c, 470, oy + 97, "frame base y192; wall foot 185 / gate foot 191 (official)")
c.convert("RGB").save(os.path.join(OUT, "_mockup_A_citywall.png"))
print("A 断言:", "PASS" if okA else "FAIL")

# ============ 样板 B v2：宫墙 + 宫门 + 太极殿 ============
W, H = 640, 430
c = Image.new("RGBA", (W, H), BG + (255,))
label(c, 10, 6, "B/1 OFFICIAL (gate_gold x0-145 + stone_blue x144-288, band y96-192)")
paste(c, JC3, (0, 96, 144, 192), 10, 24)           # 官方宫门gold(参照)
paste(c, JC3, (145, 96, 288, 192), 155, 24)        # 石基蓝顶（官方相邻件）
oy = 200
label(c, 10, oy - 18, "B/2 v2: wall_run(48px) + gate_gold ; TAIJI base sunk below wall cap")
paste(c, JC3, (0, 0, 144, 96), 106, oy - 40)       # 太极殿先贴(后排)：底=oy+56 压墙帽线(oy+32)下24px
paste(c, JC3, (0, 128, 48, 192), 10, oy + 32)      # 宫墙段 @10
paste(c, JC3, (0, 128, 48, 192), 58, oy + 32)      # @58 (段尾105|门首106 源47|0相位连续)
paste(c, JC3, (0, 128, 48, 192), 250, oy + 32)     # @250 (gate尾249|段首250, 源143|0相邻连续)
paste(c, JC3, (0, 128, 48, 192), 298, oy + 32)
paste(c, JC3, (0, 128, 48, 192), 346, oy + 32)
paste(c, JC3, (0, 96, 144, 192), 106, oy)          # 宫门gold 最后贴:框收144(去断续列),底对齐墙底
okB = assert_no_bg_seams(c, 10, oy + 46, 395, oy + 94, tag="B/2 墙带(自帽线y142起)")
okB &= assert_bottom_groups(c, oy + 94, 3, {
    "wall_seg": (10, 106, oy + 96), "gate_gold": (106, 251, oy + 96), "wall_seg2": (251, 395, oy + 96),
}, tag="B/2")
d = ImageDraw.Draw(c)
d.line([(10, oy + 96), (630, oy + 96)], fill=(255, 120, 120, 255))
label(c, 470, oy + 99, "base line y192-equivalent for wall/gate")
c.convert("RGB").save(os.path.join(OUT, "_mockup_B_palace.png"))
print("B 断言:", "PASS" if okB else "FAIL")

# ============ 样板 C v2：连排长屋 ============
W, H = 640, 430
c = Image.new("RGBA", (W, H), BG + (255,))
label(c, 10, 6, "C/1 OFFICIAL ROW (win_a+door_a, y0-92)")
paste(c, JN4, (195, 0, 390, 92), 10, 24)           # 官方两开间（含door尾矮帽,原样参照）
paste(c, JN4, (290, 96, 480, 192), 210, 24 - 4)     # 官方shop_open原件对照(注意其x382-385柱隙门洞为原生设计)
oy = 150
label(c, 10, oy - 18, "C/2 v5: door trimmed / body-width dock / gable aligned ; shop colonnade = official design")
# 排1：win(93) + door(89截尾) 密排 + 马头墙封端（底对齐 oy-4）
paste(c, JN4, (195, 0, 288, 92), 10, oy)           # win_a
paste(c, JN4, (295, 0, 384, 92), 103, oy)          # door_a(截尾89px)
paste(c, JN4, (195, 0, 288, 92), 192, oy)          # win_a
paste(c, JN4, (295, 0, 384, 92), 285, oy)          # door_a
paste(c, JN4, (192, 96, 288, 192), 360, oy - 4)    # gable_ma @360(重叠14px,左缘留白由door填充)
# 排2：shop_open(双开间) + door + win —— 底边锚：shop 画布高96,顶上移4使脚与92高件齐平
oy2 = oy + 130
paste(c, JN4, (290, 96, 480, 192), 10, oy2 - 4)     # house_shop_open 底边锚(vision终验核销项)
paste(c, JN4, (295, 0, 384, 92), 197, oy2)         # door_a @197=shop身尾 按身宽对接
paste(c, JN4, (195, 0, 288, 92), 286, oy2)         # win_a @286=door尾197+89
okC = assert_no_bg_seams(c, 10, oy + 10, 438, oy + 92, tag="C/2 row1")
okC &= assert_no_bg_seams(c, 200, oy2 + 10, 380, oy2 + 92, tag="C/2 row2(door+win段,避shop门洞)")

def assert_foot_uniform(canvas, x0, x1, y_expect, tol=1, tag=""):
    """验收3：全段脚线单值（底边锚绑定断言）——只统计脚部窗口内有内容的列（柱隙列跳过）"""
    rgb2 = canvas.convert("RGB").load()
    bots = set()
    for x in range(x0, x1, 2):
        foot_has = any(not _is_bg(rgb2[x, y]) for y in range(y_expect - 8, min(y_expect + 5, canvas.height)))
        if not foot_has:
            continue
        for y in range(y_expect + 4, y_expect - 100, -1):
            if not _is_bg(rgb2[x, y]):
                bots.add(y); break
    ok = bool(bots) and (max(bots) - min(bots)) <= tol
    print(("[PASS] " if ok else "[FAIL] ") + tag + " 脚线单值 y∈" + str(sorted(bots)))
    return ok

okC &= assert_foot_uniform(c, 10, 377, oy2 + 92, tag="C/2 row2")
d = ImageDraw.Draw(c)
d.line([(10, oy + 92), (630, oy + 92)], fill=(255, 120, 120, 255))
d.line([(10, oy2 + 92), (630, oy2 + 92)], fill=(255, 120, 120, 255))
label(c, 470, oy2 + 96, "row base lines")
c.convert("RGB").save(os.path.join(OUT, "_mockup_C_rowhouse.png"))
print("C 断言:", "PASS" if okC else "FAIL")
