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
JC2 = "jingcheng/tile-B-02.png"
JC6 = "jingcheng/tile-B-06.png"
JC7 = "jingcheng/tile-B-07.png"
JC4 = "jingcheng/tile-B-04.png"
JC5 = "jingcheng/tile-B-05.png"
JN = "jiangnan/tile-B-04.png"
JN5 = "jiangnan/tile-B-05.png"
JN2 = "jiangnan/tile-B-02.png"
WA5 = "jingcheng/Auto-tile-A4-walls-5.png"
# ---- 内景换皮（2026-09-06）：wuxia_interior_dlc 内景包 + wuxia/wuxia_dlc 补充（同捆同源）----
WI1 = "wuxia_interior_dlc/tile-B-01.png"   # 挂轴/官帽椅/文案桌/条案/雕花屏/架子床
WI2 = "wuxia_interior_dlc/tile-B-02.png"   # 灶台/蒸笼/酒坛/厨柜/火盆/灯
WI4 = "wuxia_interior_dlc/tile-B-04.png"   # 墙画/红龙柜/药罐架/兵器架
WI5 = "wuxia_interior_dlc/tile-B-05.png"   # 内景墙板/金柱/灯笼/方砖地/书柜墙
WIA5 = "wuxia_interior_dlc/Auto-tile-A4-walls-5.png"  # 木板墙（内墙 83 源）
WD1 = "wuxia_dlc/tile-B-01.png"            # 柜台/仪仗幡
WD3 = "wuxia_dlc/tile-B-03.png"            # 折屏/妆台/酒架/药柜/书架/衣柜
WX3 = "wuxia/tile-B-03.png"                # 丹陛/横卷轴/蒲团垫/兵器架

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
    # ---- v3 密度重构（2026-09-06）：市井生活族（京城 B02 马车/轿子/雨棚摊）----
    ("cart_horse_a",     JC2, (0, 0, 192, 96)),       # 马车·客运
    ("carriage_blue",    JC2, (192, 0, 360, 96)),     # 马车·蓝棚
    ("sedan_gold",       JC2, (384, 0, 544, 96)),     # 轿子·金顶仪仗
    ("sedan_red",        JC2, (576, 96, 686, 192)),   # 轿子·红
    ("ox_cart_cover",    JC2, (384, 192, 544, 288)),  # 牛车·篷
    ("stall_awn_blue",   JC2, (576, 0, 672, 96)),     # 雨棚摊·蓝
    ("stall_awn_blue2",  JC2, (672, 0, 768, 96)),     # 雨棚摊·蓝乙
    ("stall_awn_green",  JC2, (672, 192, 768, 288)),  # 雨棚摊·绿
    ("stall_red_open",   JC2, (384, 384, 480, 480)),  # 开敞摊·红檐
    ("stall_goods_blue", JC2, (480, 384, 576, 486)),  # 杂货摊·蓝檐
    ("stall_white_awn",  JC2, (384, 480, 480, 576)),  # 布摊·白棚
    ("stall_green_awn",  JC2, (480, 480, 576, 576)),  # 果摊·绿棚
    ("stall_food_a",     JC2, (192, 672, 288, 768)),  # 食摊·红白
    ("stall_food_b",     JC2, (288, 672, 384, 768)),  # 食摊·蓝白
    # ---- v3：街道小件族（京城 B06 驴/柱/牌/灯）----
    ("donkey_post",      JC6, (384, 216, 480, 290)),  # 拴柱驴
    ("donkey_saddle",    JC6, (576, 216, 675, 292)),  # 驮驴
    ("pillar_red",       JC6, (714, 0, 768, 96)),     # 朱红廊柱
    ("board_notice",     JC6, (240, 576, 302, 682)),  # 告示牌
    ("banner_wine2",     JC6, (192, 576, 240, 672)),  # 酒旗·竖
    ("lamp_yellow",      JC6, (676, 572, 724, 768)),  # 黄灯柱
    # ---- v3：水乡族（江南 B05 船/码头/月洞门/拱桥/神龛/盆景）----
    # 船四条带烤入水底色，放置时与场景水瓦必出"色块矩形"——切片后统一 chroma-key 抠透明（BOAT_KEY）
    ("boat_row",         JN5, (382, 4, 532, 48)),     # 小船·row
    ("boat_cover",       JN5, (382, 50, 514, 98)),    # 客船·篷
    ("boat_small",       JN5, (382, 194, 482, 238)),  # 小船·乙
    ("boat_sampan",      JN5, (382, 238, 502, 280)),  # 舢板
    ("pier_wood",        JN5, (384, 96, 528, 192)),   # 木码头平台
    ("moongate_white",   JN5, (672, 0, 768, 96)),     # 月洞门（白墙）
    ("bridge_arch_stone", JN5, (480, 192, 576, 288)),  # 石拱桥·侧视（护城河）
    ("bench_wood",       JN5, (576, 96, 624, 144)),   # 条凳
    ("shrine_small",     JN5, (576, 384, 624, 480)),  # 神龛·灰瓦
    ("shrine_red",       JN5, (624, 384, 672, 480)),  # 神龛·红
    ("lantern_stone_s",  JN5, (384, 288, 432, 336)),  # 石灯·小
    ("bonsai_b",         JN5, (432, 288, 480, 336)),  # 盆景·乙
    ("stall_awn_bluew",  JN5, (480, 480, 576, 576)),  # 大棚摊·蓝白条
    # ---- 内景换皮（2026-09-06）：家具陈设族（坐标=measure_windows.py 连通分量实测）----
    # 挂轴墙画/屏风（WI1 屏画族 + WI4 墙画 + WD3 折屏 + WX3 横卷）
    ("scroll_pair_a",    WI1, (580, 386, 668, 478)),  # 挂画对·花鸟（中堂）
    ("scroll_pair_b",    WI1, (676, 386, 764, 478)),  # 挂画对·山水（中堂）
    ("scroll_h_a",       WX3, (0, 672, 128, 768)),    # 横卷轴·书法
    ("scroll_h_long",    WX3, (128, 672, 256, 768)),  # 横卷轴·长卷
    ("mural_scholar",    WI4, (192, 0, 288, 96)),     # 墙画·文士
    ("mural_elder",      WI4, (288, 0, 384, 96)),     # 墙画·长者
    ("mural_landscape",  WI4, (0, 192, 96, 288)),     # 墙画·山水
    ("mural_landscape_b", WI4, (96, 192, 192, 288)),  # 墙画·山水乙
    ("screen_carved_a",  WI1, (0, 288, 96, 384)),     # 雕花屏·龙纹
    ("screen_carved_b",  WI1, (96, 288, 192, 384)),   # 雕花屏·云纹
    ("screen_fold_land", WD3, (289, 392, 479, 479)),  # 折屏·山水四扇
    ("screen_fold_plum", WD3, (2, 488, 287, 575)),    # 折屏·花鸟宽扇
    # 桌案椅凳
    ("table_square",     JC7, (15, 17, 81, 96)),      # 方桌·原木
    ("table_square_red", JC7, (111, 17, 177, 96)),    # 方桌·朱漆
    ("tea_table_set",    WI1, (387, 192, 480, 288)),  # 茶桌连凳（带茶具）
    ("tea_table_a",      JC4, (98, 405, 190, 480)),   # 茶几·壶盏
    ("tea_table_b",      JC4, (195, 486, 285, 576)),  # 茶几·提壶
    ("altar_table",      WI1, (438, 396, 528, 480)),  # 条案·盆景烛台（供案/中堂）
    ("altar_table_b",    WI1, (480, 396, 570, 480)),  # 条案·乙
    ("sideboard",        JC7, (481, 192, 574, 288)),  # 抽屉条案
    ("chair_arm_a",      WI1, (384, 0, 432, 96)),     # 官帽椅·甲
    ("chair_arm_b",      WI1, (384, 96, 432, 192)),   # 官帽椅·乙
    ("stool_round_a",    JC4, (204, 597, 228, 624)),  # 圆凳·甲（单只，597~624；644~672 是第二只曾误连切）
    ("stool_round_b",    JC4, (252, 594, 276, 621)),  # 圆凳·乙（单只）
    ("desk_ink",         WI1, (480, 99, 576, 192)),   # 文案桌·文房
    ("desk_scroll",      WI1, (480, 290, 576, 384)),  # 文案桌·卷轴
    ("desk_open",        WI1, (576, 306, 672, 384)),  # 文案桌·摊卷
    ("stand_vase",       WI1, (681, 6, 711, 96)),      # 花几·瓶（wi1_scroll5 实测内容）
    ("stand_plant",      WI1, (726, 2, 763, 96)),      # 花几·盆景（wi1_scroll6 实测内容）
    ("dresser",          WD3, (194, 386, 286, 479)),  # 妆台·圆镜
    # 柜架
    ("cabinet_lattice",  JC7, (482, 0, 574, 96)),     # 顶箱柜·格扇
    ("cabinet_arch",     JC7, (578, 0, 670, 96)),     # 翘头柜·龛
    ("cabinet_tall",     JC7, (482, 96, 574, 192)),   # 高柜·抽屉
    ("cabinet_pair",     JC7, (488, 386, 570, 480)),  # 双门矮柜
    ("cabinet_red",      WI4, (390, 1, 474, 96)),     # 朱漆柜·素面
    ("cabinet_red_b",    WI4, (485, 0, 571, 96)),     # 朱漆柜·龙纹（御座背柜）
    ("shelf_curio",      JC7, (674, 0, 766, 96)),     # 多宝阁
    ("bookshelf_cab",    JC7, (385, 192, 479, 288)),  # 书柜·门扇
    ("bookshelf_books",  WD3, (295, 194, 377, 287)),  # 书架·卷册
    ("bookshelf_wall",   WI5, (288, 96, 384, 192)),   # 书柜墙（靠墙 96px）
    ("wall_screen_panel", WI5, (96, 96, 192, 192)),   # 花窗墙板（靠墙 96px）
    ("wardrobe",         WD3, (10, 194, 86, 287)),    # 衣柜
    ("counter_long",     JC7, (0, 431, 96, 480)),     # 长柜台·甲
    ("counter_long_b",   JC7, (96, 431, 192, 480)),   # 长柜台·乙
    ("counter_kitchen",  WI2, (481, 434, 575, 528)),  # 厨柜·碗碟
    ("counter_herb",     WD1, (480, 192, 576, 287)),  # 医馆柜台·药柜连体
    ("counter_doc",      WD1, (288, 288, 384, 384)),  # 柜台·文书
    # 店铺五皮肤专项
    ("shelf_cloth",      JC4, (0, 0, 95, 96)),        # 布架·彩帛
    ("shelf_cloth_b",    JC4, (97, 0, 191, 96)),       # 布架·悬帛
    ("shelf_cloth_tall", JC4, (1, 192, 95, 286)),      # 高布架·甲
    ("table_set_small",  JC4, (98, 192, 190, 287)),    # 小桌凳组（(98,192)实测为桌凳非货架）
    ("herb_drawer",      JC4, (192, 0, 288, 96)),      # 药柜·屉罐
    ("herb_drawer_b",    JC4, (290, 0, 382, 94)),      # 药柜·大屉
    ("herb_cabinet_a",   WD3, (386, 192, 478, 287)),   # 药柜·红罐葫芦
    ("herb_cabinet_b",   WD3, (482, 192, 574, 287)),   # 药柜·红罐乙
    ("jar_shelf",        WI4, (482, 290, 574, 384)),   # 药罐架·白青
    ("jar_shelf_b",      WI4, (578, 290, 670, 384)),   # 药罐架·朱封
    ("wine_rack",        WD3, (386, 290, 478, 383)),   # 菱格酒架
    ("wine_jars",        JC7, (386, 35, 478, 90)),     # 酒坛×2
    ("jars_cluster",     JC7, (193, 392, 285, 480)),   # 酒坛堆×4（酒封）
    ("jars_cluster_b",   JC7, (290, 396, 383, 480)),   # 酒坛堆·乙
    ("jar_white",        WI2, (6, 483, 43, 527)),      # 白酒坛
    # 床（架子床带幔）
    ("bed_canopy_red",   JC7, (482, 481, 574, 576)),   # 架子床·红幔
    ("bed_canopy_navy",  JC7, (578, 481, 670, 576)),   # 架子床·蓝幔
    ("bed_canopy_green", JC7, (674, 481, 766, 576)),   # 架子床·绿幔
    ("bed_canopy_blue",  WI1, (289, 0, 383, 96)),      # 架子床·青幔
    ("bed_canopy_tan",   WI1, (193, 0, 287, 96)),      # 架子床·素幔
    # 灯烛光源
    ("lantern_stand_a",  JC7, (582, 112, 618, 192)),   # 灯笼架·挑杆
    ("lantern_stand_b",  JC7, (634, 100, 662, 174)),   # 灯笼架·纸罩
    ("lantern_pole_pair", JC7, (580, 197, 668, 288)),  # 双灯宫灯架
    ("lantern_red_stand", JC7, (582, 387, 618, 450)),  # 红灯笼矮架
    ("lantern_std_red",  WI5, (600, 483, 648, 576)),   # 红灯笼高杆
    ("screen_panel_lacquer", WI5, (552, 480, 600, 576)), # 漆器屏板（(552,480)实测为青瓷屏板非灯，选窗误判已纠）
    ("lamp_small",       WI2, (730, 96, 768, 190)),    # 小灯檠
    ("firepit",          WI2, (656, 672, 704, 766)),   # 火盆
    # 厨房
    ("stove_brick",      WI2, (3, 9, 96, 96)),         # 灶·双眼砖
    ("stove_stone",      WI2, (192, 0, 285, 96)),      # 灶·石双锅
    ("stove_fire",       WI2, (0, 192, 96, 288)),      # 灶·蒸笼旺火
    ("steamer",          WI2, (480, 96, 523, 190)),    # 蒸笼·叠屉
    ("steamer_b",        WI2, (530, 96, 574, 185)),    # 蒸笼·单屉
    # 宫院/官署
    ("danbi_medallion",  WX3, (0, 384, 192, 528)),     # 丹陛·团龙浮雕方台
    ("danbi_platform",   WX3, (192, 384, 384, 528)),   # 丹陛·平台
    ("pillar_gold",      WI5, (384, 96, 432, 192)),    # 金柱·斗拱（(432,96)实为花窗板已改名）
    ("yizhang_fan_a",    WD1, (576, 0, 640, 96)),      # 仪仗幡·金红
    ("yizhang_fan_b",    WD1, (576, 576, 640, 672)),   # 仪仗幡·赤
    ("rack_spear",       WX3, (0, 320, 96, 384)),      # 兵器架·长兵
    ("rack_sword",       WX3, (192, 528, 288, 608)),   # 兵器架·剑
    ("rack_sword_b",     WX3, (288, 528, 384, 608)),   # 兵器架·矛
    ("rack_halberd",     WI4, (579, 577, 669, 672)),   # 兵器架·戟
    ("rack_sword_c",     WI4, (387, 597, 477, 672)),   # 兵器架·剑乙
    ("mat_cushion",      WX3, (384, 576, 480, 672)),   # 蒲团垫
]

# ---- tile 清单：16×16 整窗（TileMap 图集源，不修边）----
TILES = [
    # 街巷铺装（终案：街=夯土暖色、御道/宫市=石板、青灰砖=墙——三级语义清晰，修"街砖像城墙"）
    ("street_main",   JN, (400, 492, 416, 508)),  # 72 主干街：夯土（唐长安史实夯土路面）
    ("street_ward",   JN, (400, 492, 416, 508)),  # 73 坊内街：夯土
    ("street_lane",   JN, (400, 492, 416, 508)),  # 74 巷路：夯土
    ("street_zhuque", JC, (64, 176, 80, 192)),    # 71 御道石板：横排大板（地面感；仅朱雀中轴3宽铺装）
    ("pave_market",   JC, (96, 544, 112, 560)),   # 市内/宫内地面：宽版石板
    # 城墙（垛口+墙身同窗）
    ("wall_city",     JC, (568, 122, 584, 138)),  # 70 外郭城墙·垛口行（城齿+箭窗压顶）
    ("wall_city_body", JC, (568, 138, 584, 154)), # 106 外郭城墙·砖身行（横缝，N/S 走向段）
    # ---- v3 水系（江南 B05）：渠水蓝+岸石顶面 ----
    ("water_canal",   JN5, (240, 352, 256, 368)), # 112 渠水/护城河·江南蓝（(96,344)波浪纹平铺成块状，改纯水平铺窗）
    ("quay_stone",    JN5, (200, 260, 216, 276)), # 111 岸石·渠岸顶面（浅灰石板，(304,344)曾误切木栈道）
    # ---- 内景换皮（2026-09-06）：80~89 地面/墙体暖化替换 + 113 花砖 + 84~89 家具 16px 代表窗 ----
    ("interior_floor_wood", JN5, (400, 120, 416, 136)),   # 80 厅堂暖木地板（码头木板窗，150,118,93）
    ("interior_floor_brick", WI5, (48, 336, 64, 352)),    # 81 过道方砖（内景包砖+暖化，冷灰 147,147,157→暖褐）
    ("interior_wall_wood", WIA5, (400, 184, 416, 200)),   # 83 内墙·暖木板墙（压暗与地板区分）
    ("floor_medal",   WI5, (432, 336, 448, 352)),         # 113 厅心花砖（暖化，毯心点缀）
    ("interior_screen", WD3, (300, 400, 316, 416)),       # 84 屏风 16px 代表窗（M6 换肤/回退用）
    ("interior_lamp", JC7, (590, 396, 606, 412)),         # 85 灯烛 16px
    ("interior_desk", WI1, (500, 150, 516, 166)),         # 86 案面 16px
    ("interior_couch", JC7, (36, 436, 52, 452)),          # 87 榻 16px
    ("interior_cabinet", JC7, (520, 40, 536, 56)),        # 88 柜 16px
    ("interior_shelf", JC7, (710, 36, 726, 52)),          # 89 架 16px
]

# 足印瓦（ID 102）：16×16 全透明带碰撞（TileMap 物理管建筑占格，prop 只做视觉；
# 镂空 prop（摊贩/门楼）不再露出身后 tile-2 小屋画）。切片缺失时回退 house_town 可见版。
def make_foot_tile():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 0))

# ---- 合成 tile：竖向三段 vstack（顶盖/墙身/墙脚）→ 16×16 ----
# 条带=(box, 高px, rot)；rot=90 时墙身先旋转（横缝变竖缝，供 E/W 走向竖墙用），顶盖不转（垛口恒在顶）
# 坊墙 = 白灰墙身（江南院墙）+ 灰瓦顶 + 砖脚；宫墙 = 金瓦顶 + 红墙身 + 灰石基
COMPOSITES = [
    # 横竖同构：横段=顶檐压线4px+实心墙身10px+砖脚2px（墙身占比与竖段一致，修"细白线vs粗米黄柱"断裂）
    ("wall_ward",   JN,  [(496, 194, 512, 198), (496, 208, 512, 266), (496, 272, 512, 290)],
     [4, 10, 2]),   # 100 坊墙（瓦顶压线+白灰身+砖脚）
    ("wall_palace", JC3, [(0, 142, 16, 146), (0, 151, 16, 162), (0, 166, 16, 175)],
     [4, 10, 2]),   # 69 宫墙（金瓦压线+红身+石基）
    # 竖向墙段=侧立面（无檐无垛口，纯墙面+左右描边，檐口只落在转角/墙段北端）
    # 竖立面终案（夜色调制下素面会成"棕色光柱"）：低对比砖纹（±6% 缝，白天有材质、夜里不成光柱）
    ("wall_ward_v",   JN,  [(204, 36, 220, 52)],
     [16, "vedge", "solid", "brick"]),   # 105 坊墙·竖立面（白墙纯段solid平均=暖白灰；496,232实为木门框区，选窗误判已纠）
    ("wall_palace_v", JC3, [(0, 152, 16, 162)],
     [16, "vedge", "solid", "brick"]),   # 104 宫墙·竖立面（朱红纯段）
    ("wall_city_face_v", JC, [(568, 138, 584, 154)],
     [16, "vedge", "solid", "brick"]),   # 103 外郭墙·竖立面·内列（青灰低对比砖纹）
    ("wall_city_cap_w", JC, [(568, 122, 584, 138)],
     [16, "caprot", -90]),   # 108 外郭墙·垛口齿·西列（齿朝西，与横墙垛口转角衔接）
    ("wall_city_cap_e", JC, [(568, 122, 584, 138)],
     [16, "caprot", 90]),    # 109 外郭墙·垛口齿·东列（齿朝东）
]

def trim_alpha(im, pad=1):
    bbox = im.getbbox()
    if bbox is None:
        return im
    l, t, r, b = bbox
    l = max(0, l - pad); t = max(0, t - pad)
    r = min(im.width, r + pad); b = min(im.height, b + pad)
    return im.crop((l, t, r, b))

# 船类切片背景抠透明：源图水面为平色底，从四边界泛洪键出与边缘连通的水域（boat_cover 篷顶色近水色，
# 全图色键会吃掉篷内像素——泛洪只吃 hull 外水域，闭环区内同色不动）；再两轮邻接去晕
BOAT_KEY = {"boat_row", "boat_cover", "boat_small", "boat_sampan"}

def key_water_bg(im):
    px = im.load()
    kr, kg, kb = px[2, 2][:3]
    def dist(c):
        return abs(c[0] - kr) + abs(c[1] - kg) + abs(c[2] - kb)
    w, h = im.size
    seen = [[False] * w for _ in range(h)]
    stack = []
    for x in range(w):
        stack.append((x, 0)); stack.append((x, h - 1))
    for y in range(h):
        stack.append((0, y)); stack.append((w - 1, y))
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y][x]:
            continue
        seen[y][x] = True
        if dist(px[x, y]) >= 90:
            continue
        px[x, y] = (0, 0, 0, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    for _ in range(2):   # 去晕：紧邻透明的水色残边逐轮外扩
        halo = []
        for yy in range(h):
            for xx in range(w):
                c = px[xx, yy]
                if c[3] == 0:
                    continue
                if dist(c) < 150 and any(
                        0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0
                        for nx, ny in ((xx + 1, yy), (xx - 1, yy), (xx, yy + 1), (xx, yy - 1))):
                    halo.append((xx, yy))
        for xx, yy in halo:
            px[xx, yy] = (0, 0, 0, 0)
    im = keep_largest_component(im)
    return trim_alpha(im)

def keep_largest_component(im):
    """只保留最大不透明连通体（=目标物体），窗口带进的邻居碎片（灯笼/枯枝/水花点）全丢弃。
    前提：目标物体各部件互相连通（四船的桅/篷均连在船体上）。"""
    px = im.load()
    w, h = im.size
    lab = [[0] * w for _ in range(h)]
    best_id, best_cnt = 0, 0
    nid = 0
    for sy in range(h):
        for sx in range(w):
            if lab[sy][sx] or px[sx, sy][3] <= 10:
                continue
            nid += 1
            stack = [(sx, sy)]
            lab[sy][sx] = nid
            cnt = 0
            while stack:
                x, y = stack.pop()
                cnt += 1
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not lab[ny][nx] and px[nx, ny][3] > 10:
                        lab[ny][nx] = nid
                        stack.append((nx, ny))
            if cnt > best_cnt:
                best_cnt, best_id = cnt, nid
    for yy in range(h):
        for xx in range(w):
            if px[xx, yy][3] > 10 and lab[yy][xx] != best_id:
                px[xx, yy] = (0, 0, 0, 0)
    return im

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
        if name in BOAT_KEY:
            im = key_water_bg(im)
        im.save(os.path.join(OUT_PROPS, name + ".png"))
        made.append((name, im, "prop"))
    for name, rel, box in TILES:
        if only and name not in only:
            continue
        im = sheet(rel).crop(box)
        assert im.size == (16, 16), f"{name}: tile 窗必须16x16, got {im.size}"
        if name in ("street_main", "street_ward", "street_lane"):
            # 夯土暖化：压绿提红黄（SCKR 土路偏绿褐，与草地难分——史实夯土=暖黄土）
            pxs = im.load()
            for yy in range(16):
                for xx in range(16):
                    r, g, b, a = pxs[xx, yy]
                    if a > 0:
                        pxs[xx, yy] = (min(255, int(r * 1.10)), int(g * 0.84), int(b * 0.92), a)
        if name == "interior_floor_brick":
            # 内景方砖暖化：内景包原砖冷灰紫(147,147,157)→暖褐方砖（禁整屏冷灰纪律）
            pxs = im.load()
            for yy in range(16):
                for xx in range(16):
                    r, g, b, a = pxs[xx, yy]
                    if a > 0:
                        pxs[xx, yy] = (min(255, int(r * 1.14)), int(g * 0.94), int(b * 0.82), a)
        if name == "interior_wall_wood":
            # 内墙木板压暗：与暖木地板(80)拉开明度差，墙环读作实心墙裙（消"细线感"）
            pxs = im.load()
            for yy in range(16):
                for xx in range(16):
                    r, g, b, a = pxs[xx, yy]
                    if a > 0:
                        pxs[xx, yy] = (int(r * 0.88), int(g * 0.86), int(b * 0.88), a)
        if name == "floor_medal":
            # 花砖暖化（青瓷砖心提暖，与绛红毯同场不突兀）
            pxs = im.load()
            for yy in range(16):
                for xx in range(16):
                    r, g, b, a = pxs[xx, yy]
                    if a > 0:
                        pxs[xx, yy] = (min(255, int(r * 1.15)), int(g * 0.95), int(b * 0.85), a)
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
        # vedge 标记放在 weights 尾（zip 会因 strips 较短丢掉尾项，标记必须整表判断——踩坑：tag 永远读不到）
        vedge = "vedge" in weights
        hw = [w for w in weights if w != "vedge"]
        for (box, hpx) in zip(strips, hw):
            s = src.crop(box)
            parts.append(s.resize((16, hpx), Image.NEAREST))
        im = Image.new("RGBA", (16, 16))
        y = 0
        for p, hpx in zip(parts, hw):
            im.paste(p, (0, y))
            y += hpx
        solid = "solid" in weights
        if "caprot" in weights:
            # 垛口齿侧转：横墙垛口行整体旋转±90°（齿朝东西外侧，俯视正确），转角与横墙垛口自然衔接
            rot = [w for w in weights if w != "caprot"][0]
            im = src.crop(strips[0]).rotate(rot, expand=True)
            im.save(os.path.join(OUT_TILES, name + ".png"))
            made.append((name, im, "tile"))
            continue
        if solid:
            # 素面墙：源段平均色 + ±6% 行噪点（极轻，防绝对纯色）——竖排永不产生重复图案
            src_strip = src.crop(strips[0])
            px0 = src_strip.load()
            n = 0
            rs = gs = bs = 0
            for yy in range(src_strip.height):
                for xx in range(src_strip.width):
                    r, g, b, a = px0[xx, yy]
                    if a > 10:
                        rs += r; gs += g; bs += b; n += 1
            base = (rs // max(1, n), gs // max(1, n), bs // max(1, n))
            im = Image.new("RGBA", (16, 16))
            px = im.load()
            import random as _rnd
            _rnd.seed(hash(name) & 0xFFFF)
            for yy in range(16):
                f = 1.0 + _rnd.uniform(-0.06, 0.06)
                for xx in range(16):
                    px[xx, yy] = (min(255, int(base[0] * f)), min(255, int(base[1] * f)), min(255, int(base[2] * f)), 255)
            if "brick" in weights:
                # 低对比错缝砖纹（±7%）：给材质但不产生横档（高对比缝在夜色调制下成"梯"的教训）
                for row_i, yy in enumerate(range(0, 16, 5)):
                    for xx in range(16):
                        r, g, b, a = px[xx, yy]
                        px[xx, yy] = (int(r * 0.93), int(g * 0.93), int(b * 0.93), a)
                    jx = (3, 9, 14)[row_i % 3]
                    for yy2 in range(yy, min(16, yy + 5)):
                        r, g, b, a = px[jx, yy2]
                        px[jx, yy2] = (int(r * 0.93), int(g * 0.93), int(b * 0.93), a)
        if vedge:
            # 生成式描边（覆盖式，非乘法——源图残亮乘不没）：左3px 深影、2px 过渡、右2px 受光
            px = im.load()
            for _ in range(16):
                holes = [(x, y) for x in range(16) for y in range(16) if px[x, y][3] == 0]
                if not holes:
                    break
                for x, y in holes:
                    for nx, ny in ((x, y + 1), (x + 1, y), (x - 1, y), (x, y - 1)):
                        if 0 <= nx < 16 and 0 <= ny < 16 and px[nx, ny][3] > 0:
                            px[x, y] = px[nx, ny]
                            break
            # 竖立面加强（候选B实测最优）：左3px强阴影+2px过渡 → 受光面 → 右2px提亮，底部2px墙基线；
            # 连排读作连续竖高墙（与横墙垛口+亮墙身构成同一堵墙的两个视角）
            px = im.load()
            for yy in range(16):
                # 行基准色（当前行中位调）——覆盖式描边用它，避免源图残亮干扰
                row = [px[xx, yy] for xx in range(16)]
                med = sorted(row, key=lambda c: c[0] + c[1] + c[2])[8][:3]
                for xx in range(16):
                    f = 1.0
                    if xx < 3:
                        f = 0.58
                    elif xx < 5:
                        f = 0.76
                    elif xx >= 14:
                        f = 1.22
                    elif xx >= 12:
                        f = 1.1
                    px[xx, yy] = (min(255, int(med[0] * f)), min(255, int(med[1] * f)), min(255, int(med[2] * f)), 255)
        im.save(os.path.join(OUT_TILES, name + ".png"))
        made.append((name, im, "tile"))
        continue
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
    # ---- manifest（工程化解析数据库，范式v3）：生成器只能引用本清单语义名 ----
    if made and not only:
        import json
        CATS = [
            ("building", ("house_", "gable_", "compound_", "lou_", "hall_", "palace_", "gate_tower",
                          "gate_red", "gate_stone", "ting_", "pagoda_", "bell_", "drum_", "market_gate", "moongate_")),
            ("wall", ("wall_",)),
            ("ground", ("street_", "pave_", "quay_", "water_", "foot")),
            ("market", ("stall_", "market_counter", "cart_", "carriage_", "sedan_", "ox_cart")),
            ("water", ("boat_", "pier_")),
            ("plant", ("tree_", "willow_", "bonsai_")),
            ("street_furniture", ("lamp_", "lantern_", "banner_", "sign_", "board_")),
            ("decor", ("lion_", "paifang_", "pillar_", "shrine_", "incense_", "bench_", "donkey_", "bridge_")),
            # 内景陈设族（2026-09-06）——放在末尾，不抢既有分类前缀
            ("interior", ("bed_", "table_", "chair_", "desk_", "stool_", "dresser", "wardrobe",
                          "screen_", "scroll_", "mural_", "altar_", "stand_", "sideboard",
                          "bookshelf_", "herb_", "wine_", "jars_", "jar_white", "firepit",
                          "stove_", "steamer", "danbi_", "rack_", "mat_", "yizhang_", "floor_medal")),
        ]

        def cat_of(name: str) -> str:
            for cat, prefixes in CATS:
                for p in prefixes:
                    if name.startswith(p):
                        return cat
            return "misc"

        assets = []
        for name, rel, box in PROPS:
            assets.append({"name": name, "kind": "prop", "category": cat_of(name),
                           "sheet": rel, "box": list(box)})
        for name, rel, box in TILES:
            assets.append({"name": name, "kind": "tile", "category": cat_of(name),
                           "sheet": rel, "box": list(box)})
        for name, rel, strips, weights in COMPOSITES:
            assets.append({"name": name, "kind": "composite_tile", "category": "wall",
                           "sheet": rel, "strips": [list(s) for s in strips]})
        out_m = {
            "grid": {"texture_px": 16, "kit_block_px": 48},
            "source_root": "downloaded_assets/comshadow_bundle/",
            "note": "SCKR 中式包工程化解析清单（范式v3）。派生PNG已gitignore，克隆后重跑本脚本再生。",
            "assets": assets,
        }
        manifest_path = os.path.join(ROOT, "data", "sckr_manifest.json")
        with open(manifest_path, "w", encoding="utf-8") as mf:
            json.dump(out_m, mf, ensure_ascii=False, indent=1)
        print("[sckr-changan] manifest →", manifest_path, f"({len(assets)} 条)")
    print(f"[sckr-changan] 切片 {len(made)} 件 → props={OUT_PROPS} tiles={OUT_TILES}")

if __name__ == "__main__":
    main()
