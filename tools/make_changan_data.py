# -*- coding: utf-8 -*-
"""长安城数据生成（M0）：docs/长安城地图设计.md §4.1 JSON Schema
12列×9排=108坊 + 宫皇区(4×2) + 东西两市；三阶段 stage_unlock；剧情坊史实近似定位（M2 按01图校正）
输出: data/changan_city.json（运行时 changan_generator.gd 读取）
坐标约定: 全部 0-based；col=坊列(西→东)，row=坊排(北→南)
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GRID = {
    "cols": 12, "rows": 9, "block": [26, 26],
    "street": {"zhunque": 9, "main": 5, "ring": 4},
    "wall": 1, "margin": 10,                      # 外郭城墙厚1；城外荒地带10
    "palace_zone": {"cols": [4, 7], "rows": [0, 1], "interiors": [
        {"ref": "liangyi_dian", "name": "两仪殿", "gate": "E"},
        {"ref": "donggong", "name": "东宫", "gate": "W"},
    ]},
    "markets": [
        {"col": 3, "row": 2, "name": "西市", "shops": [
            {"ref": "sizhuang_w", "name": "西市绸缎庄", "skin": "silk", "at": [3, 17]},
            {"ref": "yaoshi_w", "name": "西市药铺", "skin": "herb", "at": [3, 10]},
            {"ref": "shushi_w", "name": "西市书肆", "skin": "book", "at": [14, 10]},
            {"ref": "huguguang", "name": "琥珀光", "skin": "wine", "at": [14, 17]},
            {"ref": "dangpu_w", "name": "西市当铺", "skin": "pawn", "at": [3, 3]},
        ]},
        {"col": 8, "row": 2, "name": "东市", "shops": [
            {"ref": "sizhuang_e", "name": "东市绸缎庄", "skin": "silk", "at": [3, 17]},
            {"ref": "yaoshi_e", "name": "东市药铺", "skin": "herb", "at": [3, 10]},
            {"ref": "shushi_e", "name": "东市书肆", "skin": "book", "at": [14, 17]},
            {"ref": "jiushi_e", "name": "东市酒肆", "skin": "wine", "at": [14, 10]},
        ]},
    ],
}

# 剧情坊（14+2）：史实方位近似，M2 对照 docs/参考图-长安城/01 古今叠合图校正
STORY_WARDS = {
    # (col, row): (name, landmark)
    (8, 0): ("崇仁坊", "长孙府/礼会院"),
    (9, 0): ("胜业坊", "吴王府"),
    (8, 1): ("宣阳坊", "长乐公主府"),
    (4, 2): ("务本坊", "房府/国子监"),
    (4, 3): ("延康坊", "魏王府"),
    (8, 3): ("平康坊", "天香阁"),
    (9, 3): ("亲仁坊", "功臣府群入口"),
    (3, 3): ("长寿坊", "怀化郡王府/西市畔"),
    (3, 4): ("宣义坊", "范阳卢府"),
    (3, 6): ("崇义坊", "清河崔府"),
    (6, 4): ("昌乐坊", "博陵崔府"),
    (2, 5): ("崇贤坊", "兰陵萧府"),
    (4, 7): ("靖善坊", "大兴善寺"),
    (4, 8): ("安义坊", "晋王府"),
    (10, 8): ("晋昌坊", "大慈恩寺"),      # 极盛期
    (0, 0): ("修德坊", "弘福寺"),
    # M5 官署坊（皇城外围）
    (2, 0): ("颁政坊", "京兆府"),
    (2, 1): ("辅兴坊", "鸿胪寺"),
    (10, 1): ("光宅坊", "大理寺"),
    (10, 2): ("安兴坊", "礼部院"),
    (10, 0): ("来庭坊", "御史台"),
    (2, 2): ("布政坊", "司农寺"),
}

# ---- M2 剧情坊 lots（§4.1 Schema：kind/ref/grade + 象限→at/size/gate 换算）----
# 象限盒（坊26×26，十字街在12~13，坊墙0/25）：北象限门朝S接横街，南象限门朝N；W/E大盒门朝纵街
QUAD_BOX = {
    "NW": ([2, 2],  [9, 8], "S"), "NE": ([15, 2], [9, 8], "S"),
    "SW": ([2, 16], [9, 8], "N"), "SE": ([15, 16], [9, 8], "N"),
    "W":  ([2, 2],  [9, 21], "E"), "E": ([15, 2], [9, 21], "W"),
}
# grade→宅门瓦片：A=75 朱门金钉(亲王/公主/国寺) B=76 朱门铜钉(国公/郡王/士族) C=77 黑漆门(官署/曲坊)
STORY_LOTS = {
    "崇仁坊": [("mansion", "zhangsun_fu", "A", "NE", "长孙府"), ("office", "lihui_yuan", "C", "SW", "礼会院")],
    "胜业坊": [("mansion", "wu_wangfu", "A", "NW", "吴王府")],
    "宣阳坊": [("mansion", "changle_gongzhu_fu", "A", "NE", "长乐公主府")],
    "务本坊": [("mansion", "fang_fu", "B", "NE", "房玄龄府"), ("office", "guozijian", "C", "NW", "国子监")],
    "延康坊": [("mansion", "wei_wangfu", "A", "NE", "魏王府")],
    "平康坊": [("venue", "tianxiang_ge", "A", "NE", "天香阁"), ("house", "pingkang_zhai_1", "C", "SW", "平康小宅一"), ("house", "pingkang_zhai_2", "C", "NW", "平康小宅二")],
    "亲仁坊": [("mansion", "gongchen_fu_1", "B", "NE", "功臣府一"), ("mansion", "gongchen_fu_2", "B", "NW", "功臣府二"), ("mansion", "gongchen_fu_3", "C", "SE", "功臣府三")],
    "长寿坊": [("mansion", "huaihua_junwang_fu", "B", "NE", "怀化郡王府")],
    "宣义坊": [("mansion", "fanyang_lu_fu", "B", "NE", "范阳卢府")],
    "昌乐坊": [("mansion", "boling_cui_fu", "B", "NE", "博陵崔府")],
    "崇贤坊": [("mansion", "lanling_xiao_fu", "B", "NE", "兰陵萧府")],
    "崇义坊": [("mansion", "qinghe_cui_fu", "B", "NE", "清河崔府")],
    "靖善坊": [("temple", "daxingshan_si", "A", "W", "大兴善寺")],
    "安义坊": [("mansion", "jin_wangfu", "A", "NE", "晋王府")],
    "晋昌坊": [("temple", "daciensi", "A", "W", "大慈恩寺")],
    "修德坊": [("temple", "hongfu_si", "B", "NE", "弘福寺")],
    # M5 官署四座（§8.1 衙署：堂+廊二段式，C档黑漆门，皇城外围史实近似）
    "颁政坊": [("office", "jingzhao_fu", "C", "E", "京兆府")],
    "辅兴坊": [("office", "honglu_si", "C", "E", "鸿胪寺")],
    "光宅坊": [("office", "dali_si", "C", "W", "大理寺")],
    "安兴坊": [("office", "libu_yuan", "C", "W", "礼部院")],
    "来庭坊": [("office", "yushi_tai", "C", "E", "御史台")],
    "布政坊": [("office", "sinong_si", "C", "W", "司农寺")],
}

def build_lots(ward_name: str):
    lots, interiors = [], []
    for kind, ref, grade, q, disp in STORY_LOTS.get(ward_name, []):
        at, size, gate = QUAD_BOX[q]
        lots.append({"kind": kind, "ref": ref, "grade": grade, "name": disp,
                     "at": at, "size": size, "gate": gate})
        interiors.append(ref)   # M4 传送门登记：门面 ref 与 interiors 一致（M2 验收断言）
    return lots, interiors

# 其余坊名池（唐长安史实坊名，M2 校正）
NAME_POOL = [
    "光德坊", "通济坊", "丰安坊", "安化坊", "崇德坊", "怀远坊", "长兴坊", "太平坊",
    "永平坊", "通轨坊", "大安坊", "义宁坊", "普宁坊", "辅兴坊", "颁政坊", "布政坊",
    "延寿坊", "光行坊", "延祚坊", "丰乐坊", "安业坊", "修道坊", "敦义坊", "大通坊",
    "昌明坊", "丰邑坊", "群贤坊", "怀贞坊", "宣风坊", "昭行坊", "永兴坊", "永昌坊",
    "翊善坊", "光宅坊", "来庭坊", "安兴坊", "长乐坊", "大宁坊", "兴宁坊", "新昌坊",
    "升道坊", "广德坊", "立政坊", "敦化坊", "青龙坊", "曲江坊", "通善坊", "通济北坊",
    "乐游原坊", "升平坊", "修政坊", "保宁坊", "安义东坊", "兰陵坊", "开化坊", "光福坊",
    "安宁坊", "道德坊", "敦厚坊", "惠和坊", "永崇坊", "兴化坊", "昭国坊", "新宁坊",
    "化度坊", "丰泉坊", "福祥坊", "嘉会坊", "永达坊", "延福坊", "宗仁坊", "保义坊",
    "宣平坊", "丰宜坊", "安昌坊", "昌明东坊", "归义坊", "通闰坊", "常乐坊", "崇业坊",
    "恭安坊", "兴宁西坊", "资敬坊", "长庆坊", "履信坊", "永丰坊", "安平坊", "敦化北坊",
]

def main():
    story_used = set()
    name_i = 0
    blocks = []
    for row in range(GRID["rows"]):
        for col in range(GRID["cols"]):
            if (col, row) in story_used:
                continue
            if (col, row) in STORY_WARDS:
                name, landmark = STORY_WARDS[(col, row)]
                story_used.add((col, row))
            else:
                name = NAME_POOL[name_i % len(NAME_POOL)] if name_i < len(NAME_POOL) else f"别坊{name_i + 1}"
                name_i += 1
                landmark = ""
            # 三阶段：stage0=北部4排(rows0-3) + 宫区两市；stage1=rows4-6；stage2=南两排
            stage = 0 if row <= 3 else (1 if row <= 6 else 2)
            if (col, row) == (10, 8):
                stage = 1                             # 晋昌坊=曲江一带，治世即开
            fill = "residential_high" if row <= 3 else "residential_low"
            gates = ["N", "S"]
            if col == 4:
                gates.append("E")                     # 邻朱雀街西坊开东门
            if col == 5:
                gates.append("W")
            b = {
                "id": f"ward_{col}_{row}", "col": col, "row": row, "name": name,
                "type": "ward", "gates": gates, "stage_unlock": stage,
                "fill": fill, "lots": [], "interiors": [],
                "npc_config": "", "canals": row in (2, 5), "trees": "locust",
            }
            if landmark:
                b["landmark"] = landmark
                b["lots"], b["interiors"] = build_lots(name)   # M2：剧情坊宅邸布点
            blocks.append(b)

    data = {"grid": GRID, "version": "M0", "blocks": blocks}
    out = os.path.join(ROOT, "data", "changan_city.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    n_story = sum(1 for b in blocks if "landmark" in b)
    print(f"[changan-data] wrote {out}: {len(blocks)} blocks, story={n_story}, "
          f"stage0={sum(1 for b in blocks if b['stage_unlock']==0)}")

if __name__ == "__main__":
    main()
