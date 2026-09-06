# -*- coding: utf-8 -*-
"""SCKR 中式包 → 长安城素材切片管线（京城包 jingcheng + 江南包 jiangnan）

license 纪律：downloaded_assets/comshadow_bundle/ 已 gitignore（禁转发）；
本脚本产物 sprites/changan_props_sckr/ 与 sprites/tiles_changan_sckr/ 为派生贴图，
同样 gitignore——克隆仓库后自购材质包重跑本脚本即可再生。

用法：
  python tools/import_sckr_changan.py            # 全量切片 + 输出联络表
  python tools/import_sckr_changan.py 名字 [名字…] # 只切指定条目（调试框选）

清单坐标 = 源图集原生像素 (l, t, r, b)；prop 条目切后自动 alpha 修边（trim_pad 留边）；
tile_* 条目 16×16 整窗不修边（进 TileMap 图集）。
"""
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "downloaded_assets", "comshadow_bundle")
OUT_PROPS = os.path.join(ROOT, "sprites", "changan_props_sckr")
OUT_TILES = os.path.join(ROOT, "sprites", "tiles_changan_sckr")
CONTACT = os.path.join(ROOT, "docs", "shots", "pack_jingcheng", "slice_contact.png")

JC = "jingcheng/tile-B-01.png"
JC3 = "jingcheng/tile-B-03.png"
JN = "jiangnan/tile-B-04.png"
JN5 = "jiangnan/tile-B-05.png"
JN2 = "jiangnan/tile-B-02.png"
WA5 = "jingcheng/Auto-tile-A4-walls-5.png"

# ---- prop 清单：大件（Sprite2D 用，自动修边）----
PROPS = [
    # 城墙族（京城包 B01 城墙带）
    ("gate_tower_big",   JC,  (473, 98, 568, 192)),   # 城门楼·大（蓝顶骑楼+拱门）明德门
    ("gate_tower_mid",   JC,  (620, 98, 706, 192)),   # 城门楼·中（蓝顶）玄武/春明/开远
    ("gate_tower_big_o", JC,  (473, 194, 568, 288)),  # 城门楼·大（橙顶变体）
    ("wall_seg",         JC,  (568, 116, 634, 192)),  # 城墙直段（垛口+墙身）
    ("paifang_stone",    JC,  (290, 98, 384, 192)),   # 石牌坊（灰）
    ("paifang_stone_g",  JC,  (290, 196, 384, 288)),  # 石牌坊（金顶）
    # 宫殿族（京城包 B03）
    ("hall_taiji",       JC3, (0, 0, 144, 96)),       # 太极殿·重檐金顶+白石台基
    ("palace_gate_red",  JC3, (144, 0, 288, 96)),     # 宫城正门·红墙金顶（承天门）
    ("gate_stone_gold",  JC3, (288, 0, 384, 96)),     # 石基城门楼·金顶
    ("palace_gate_gold", JC3, (0, 96, 144, 192)),     # 宫门·金顶红墙+石狮
    ("gate_stone_blue",  JC3, (144, 96, 288, 192)),   # 石基城门楼·蓝顶带墙
    ("pagoda_blue",      JC3, (390, 0, 478, 99)),     # 大雁塔·青瓦五级（底缘99，防混入下方楼脊）
    ("pagoda_gold",      JC3, (483, 96, 575, 192)),   # 宝塔·金顶五级
    ("pagoda_green",     JC3, (490, 0, 566, 106)),    # 宝塔·绿瓦八 kind
    ("lou_blue",         JC3, (676, 0, 763, 96)),     # 二层楼·蓝顶（天香阁门面）
    ("lou_brown",        JC3, (576, 0, 667, 96)),     # 二层楼·棕（酒楼门面）
    ("lou_dark",         JC3, (386, 104, 478, 192)),  # 二层楼·深色
    ("hall_grey",        JC3, (0, 578, 96, 673)),     # 大殿·灰瓦（官署）
    ("hall_gold2",       JC3, (386, 584, 478, 672)),  # 大殿·金顶乙
    ("hall_gold3",       JC3, (578, 584, 670, 672)),  # 大殿·金顶丙
    ("hall_red",         JC3, (290, 674, 382, 768)),  # 大殿·红墙
    ("ting_gold",        JC3, (200, 389, 280, 479)),  # 金顶亭
    ("paifang_big_gold", JC3, (674, 295, 768, 383)),  # 大牌坊·金
    ("paifang_red",      JC3, (482, 389, 575, 480)),  # 牌坊·红
    ("gate_red_gold",    JC3, (482, 485, 575, 576)),  # 朱金大门
    ("lion_white_a",     JC3, (676, 483, 713, 529)),  # 白石狮甲
    ("lion_white_b",     JC3, (727, 483, 764, 529)),  # 白石狮乙
    ("pagoda_small",     JC3, (627, 495, 669, 576)),  # 小石塔
    # 市井族（京城包 B01）
    ("lamp_red",         JC,  (585, 507, 615, 559)),  # 红灯笼街灯（双灯挑杆）
    ("lamp_red2",        JC,  (670, 507, 700, 559)),  # 街灯乙（橙灯挑杆）
    ("lamp_stone",       JC,  (630, 501, 660, 562)),  # 石灯柱
    ("lion_stone_a",     JC,  (588, 5, 612, 51)),     # 石狮柱甲
    ("lion_stone_b",     JC,  (635, 5, 661, 51)),     # 石狮柱乙
    ("incense_bronze",   JC,  (584, 57, 616, 98)),    # 铜香炉
    ("stall_red",        JC,  (709, 509, 767, 563)),  # 市摊·蓝棚挂灯
    ("stall_wood",       JC,  (723, 576, 767, 623)),  # 市摊·紫棚
    ("stall_red2",       JC,  (673, 623, 720, 673)),  # 市摊·红白棚
    ("stall_banner",     JC,  (720, 627, 767, 670)),  # 市摊·挂架
    ("bell_tower",       JC,  (394, 290, 468, 386)),  # 钟楼（市楼）
    ("drum_tower",       JC,  (490, 290, 564, 386)),  # 鼓楼（市楼乙）
    ("market_gate",      JC,  (487, 390, 569, 474)),  # 市门楼（带榜墙门）
    # 民居族（江南包 JN）
    ("house_win_a",      JN,  (195, 0, 288, 92)),     # 民居·窗
    ("house_door_a",     JN,  (295, 0, 390, 92)),     # 民居·门
    ("house_win_small",  JN,  (395, 0, 480, 92)),     # 民居·双窗小
    ("house_shop_open",  JN,  (290, 96, 480, 192)),   # 店铺·开敞门面
    ("gable_ma",         JN,  (192, 96, 288, 192)),   # 马头墙
    ("house_small_win",  JN,  (0, 194, 96, 290)),     # 小宅·窗
    ("gable_white",      JN,  (96, 194, 190, 290)),   # 白影壁
    ("house_small_door", JN,  (285, 194, 386, 290)),  # 小宅·门
    ("compound_gate",    JN,  (434, 194, 532, 290)),  # 院墙门楼（白墙）
    ("tree_big",         JN,  (672, 0, 768, 96)),     # 大树
    ("tree_lush_a",      JN,  (578, 672, 668, 768)),  # 树·茂甲
    ("tree_lush_b",      JN,  (670, 672, 764, 768)),  # 树·茂乙
    ("gate_wood",        JN,  (385, 672, 473, 766)),  # 木牌坊
    ("gate_stone_small", JN,  (481, 672, 576, 768)),  # 石门楼（小）
    ("sign_tea",         JN,  (488, 578, 522, 622)),  # 茶楼幌
    ("sign_inn",         JN,  (577, 582, 620, 615)),  # 客栈牌匾
    ("sign_wine",        JN,  (727, 144, 761, 193)),  # 酒幌
    ("banner_purple",    JN,  (632, 580, 652, 617)),  # 紫幌
    # 江南 B05：柳树/红白大棚/市案
    ("willow_a",         JN5, (575, 575, 670, 678)),  # 柳树甲
    ("willow_b",         JN5, (677, 572, 767, 678)),  # 柳树乙
    ("stall_rw",         JN5, (580, 485, 665, 572)),  # 大棚摊·红白
    ("market_counter",   JN5, (668, 495, 742, 568)),  # 市案·酒缸
]

# ---- tile 清单：16×16 整窗（TileMap 图集源，不修边）----
TILES = [
    # 街巷铺装（京城包 B01 左侧砖铺区）
    ("street_main",   JC, (32, 48, 48, 64)),      # 72 主干街：顺砖
    ("street_ward",   JC, (32, 416, 48, 432)),    # 73 坊内街：竖砖
    ("street_lane",   JC, (480, 64, 496, 80)),    # 74 巷路：人字纹
    ("street_zhuque", JC, (208, 500, 224, 516)),  # 71 御道：大石板
    ("pave_market",   JC, (96, 544, 112, 560)),   # 市内/宫内地面：宽版石板
    # 城墙（垛口+墙身同窗）
    ("wall_city",     JC, (568, 122, 584, 138)),  # 70 外郭城墙·垛口行（城齿+箭窗压顶）
    ("wall_city_body", JC, (568, 138, 584, 154)), # 106 外郭城墙·砖身行（横缝，N/S 走向段）
]

# 足印瓦（ID 102）：16×16 全透明带碰撞（TileMap 物理管建筑占格，prop 只做视觉；
# 镂空 prop（摊贩/门楼）不再露出身后 tile-2 小屋画）。切片缺失时回退 house_town 可见版。
def make_foot_tile():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 0))

# ---- 合成 tile：竖向三段 vstack（顶盖/墙身/墙脚）→ 16×16 ----
# 条带=(box, 高px, rot)；rot=90 时墙身先旋转（横缝变竖缝，供 E/W 走向竖墙用），顶盖不转（垛口恒在顶）
# 坊墙 = 白灰墙身（江南院墙）+ 灰瓦顶 + 砖脚；宫墙 = 金瓦顶 + 红墙身 + 灰石基
COMPOSITES = [
    ("wall_ward",   JN,  [(496, 194, 512, 200), (496, 208, 512, 266), (496, 272, 512, 290)],
     [5, 8, 3]),   # 100 坊墙（白灰+瓦顶+砖脚）
    ("wall_palace", JC3, [(0, 142, 16, 150), (0, 151, 16, 164), (0, 166, 16, 175)],
     [5, 9, 2]),   # 69 宫墙（金瓦顶+红身+石基）
    ("wall_ward_v",   JN,  [(496, 194, 512, 200), (496, 208, 512, 266), (496, 272, 512, 290)],
     [5, 8, 3, 90]),   # 105 坊墙·竖（墙身转90°）
    ("wall_palace_v", JC3, [(0, 142, 16, 150), (0, 151, 16, 164), (0, 166, 16, 175)],
     [5, 9, 2, 90]),   # 104 宫墙·竖
    ("wall_city_body_v", JC, [(568, 138, 584, 154)], [16, 90]),   # 107 外郭墙·砖身行·竖（E/W 走向段）
]

def trim_alpha(im, pad=1):
    bbox = im.getbbox()
    if bbox is None:
        return im
    l, t, r, b = bbox
    l = max(0, l - pad); t = max(0, t - pad)
    r = min(im.width, r + pad); b = min(im.height, b + pad)
    return im.crop((l, t, r, b))

def main():
    only = set(sys.argv[1:])
    os.makedirs(OUT_PROPS, exist_ok=True)
    os.makedirs(OUT_TILES, exist_ok=True)
    sheets = {}
    def sheet(rel):
        if rel not in sheets:
            sheets[rel] = Image.open(os.path.join(SRC, rel)).convert("RGBA")
        return sheets[rel]
    made = []
    for name, rel, box in PROPS:
        if only and name not in only:
            continue
        im = trim_alpha(sheet(rel).crop(box))
        im.save(os.path.join(OUT_PROPS, name + ".png"))
        made.append((name, im, "prop"))
    for name, rel, box in TILES:
        if only and name not in only:
            continue
        im = sheet(rel).crop(box)
        assert im.size == (16, 16), f"{name}: tile 窗必须16x16, got {im.size}"
        if name == "street_lane":
            # 人字纹石间勾缝在源图为透明，直接铺会漏草——焙一层深灰蓝底色
            px = im.load()
            for yy in range(16):
                for xx in range(16):
                    if px[xx, yy][3] < 128:
                        px[xx, yy] = (74, 88, 112, 255)
        im.save(os.path.join(OUT_TILES, name + ".png"))
        made.append((name, im, "tile"))
    if not only or "foot" in only:
        make_foot_tile().save(os.path.join(OUT_TILES, "foot.png"))
        made.append(("foot", make_foot_tile(), "tile"))
    for name, rel, strips, weights in COMPOSITES:
        if only and name not in only:
            continue
        src = sheet(rel)
        parts = []
        for item in zip(strips, weights):
            box, hpx = item[0], item[1]
            rot = item[2] if len(item) > 2 else 0
            s = src.crop(box)
            if rot:
                s = s.rotate(rot, expand=True)
            parts.append(s.resize((16, hpx), Image.NEAREST))
        im = Image.new("RGBA", (16, 16))
        y = 0
        for p, hpx in zip(parts, weights):
            im.paste(p, (0, y))
            y += hpx
        im.save(os.path.join(OUT_TILES, name + ".png"))
        made.append((name, im, "tile"))
    # 联络表（2x，便于目检修框）
    if made and not only:
        cols = 8
        cw, ch = 200, 210
        rows = (len(made) + cols - 1) // cols
        from PIL import ImageDraw
        out = Image.new("RGBA", (cols * cw, rows * ch), (40, 40, 48, 255))
        d = ImageDraw.Draw(out)
        for i, (name, im, kind) in enumerate(made):
            cx, cy = (i % cols) * cw, (i // cols) * ch
            s = min((cw - 16) / im.width, (ch - 30) / im.height, 3.0)
            s = max(s, 0.5)
            im2 = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.NEAREST)
            out.paste(im2, (cx + 8, cy + 24), im2)
            d.text((cx + 6, cy + 4), f"{name} {im.width}x{im.height}", fill=(255, 255, 120))
            d.rectangle([cx, cy, cx + cw - 1, cy + ch - 1], outline=(90, 90, 100))
        out.convert("RGB").save(CONTACT)
        print("[sckr-changan] 联络表 →", CONTACT)
    print(f"[sckr-changan] 切片 {len(made)} 件 → props={OUT_PROPS} tiles={OUT_TILES}")

if __name__ == "__main__":
    main()
