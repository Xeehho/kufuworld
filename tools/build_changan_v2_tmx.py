# -*- coding: utf-8 -*-
"""长安v2 全城 → Tiled tmx 构建器（一次性导出，供用户在 Tiled 手动编辑）。

输入: docs/参考/tiled_work/_changan_v2_city_dump.json（tools/export_changan_v2_dump.gd 实机生成）
输出: docs/参考/tiled_work/changan_v2_city.tmx（16px 网格，tileset 全内嵌，自包含）
      docs/参考/tiled_work/_changan_v2_city_preview.png（校验预览，gitignore）

约定:
- 地面/城墙装饰 = 瓦片层（base64+zlib；Tiled 1.12.2 对 csv 有静默失败坑，必须 base64）
- 材质件 = 对象层，objectalignment="bottom" → 对象(x,y)=件底边中心，与 Godot 底边锚一致
- 材质件分 4 层: 城墙立面/城外林带/城门/坊内建筑道具，层内按 foot_y 升序（近似 y-sort）
- 参考层: 城内人口(点)/出城触发(矩形)/街区(矩形+kind配色)
- 翻转位按 TMX 规范: bit31(0x80000000)=水平翻转
用法: python tools/build_changan_v2_tmx.py [仅校验已有tmx: verify]
"""
import os
import sys
import json
import base64
import zlib
import struct
import itertools
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
WORK = os.path.join(ROOT, "docs", "参考", "tiled_work")
DUMP = os.path.join(WORK, "_changan_v2_city_dump.json")
TMX = os.path.join(WORK, "changan_v2_city.tmx")
PREVIEW = os.path.join(WORK, "_changan_v2_city_preview.png")

FLIP_H = 0x80000000          # TMX 规范：bit31=水平翻转（注意与 ingest_material_boards.py 常量命名相反）
GID_MASK = 0x1FFFFFFF

# 街区 kind → 轮廓色（取自生成器 KIND_COLORS 的近似色，仅编辑参考用）
KIND_COLORS = {
    "palace": "#f4d166", "palace_east": "#f2b859", "royal_reserve": "#999999",
    "military": "#d97a6b", "taoist": "#c9a1d9", "temple": "#c9a1d9",
    "office": "#e8c26b", "yamen": "#e8c26b", "noble": "#8ab8e8",
    "venue": "#f2a1bf", "market": "#80d989", "residential": "#f5f5f5",
    "reserve_empty": "#999999",
}

_objid = itertools.count(1)
_layerid = itertools.count(1)


def res_to_rel(res_path, from_dir=WORK):
    """res://xxx → 相对 tmx 目录的路径（tmx 内引用图片/清单用）"""
    assert res_path.startswith("res://"), res_path
    rel = os.path.relpath(os.path.join(ROOT, res_path[len("res://"):]), from_dir)
    return rel.replace("\\", "/")


def fmt(v):
    s = ("%.2f" % float(v)).rstrip("0").rstrip(".")
    return s if s else "0"


class GidMap:
    """tileset gid 分配 + 反查（校验用）"""

    def __init__(self):
        self.next_gid = 1
        self.sets = []   # [(firstgid, kind, name, meta)]  kind: single|atlas|lib|prop

    def add_single(self, name, tiles):          # tiles: {godot_sid: file}
        first = self.next_gid
        max_id = max(tiles)
        self.next_gid = first + max_id + 1
        self.sets.append((first, "single", name, {"tiles": tiles, "count": max_id + 1}))
        return first

    def add_atlas(self, name, file, tw, th):
        first = self.next_gid
        self.next_gid = first + tw * th
        self.sets.append((first, "atlas", name, {"file": file, "tw": tw, "th": th}))
        return first

    def add_collection(self, name, items, alignment=None):
        """items: [(id, file, w, h, slice)]"""
        first = self.next_gid
        max_id = max(i[0] for i in items)
        self.next_gid = first + max_id + 1
        self.sets.append((first, "collection", name,
                          {"items": items, "count": max_id + 1, "alignment": alignment}))
        return first

    def reverse(self):
        """gid(去翻转位) → (kind, name, payload, local_id)"""
        out = {}
        for first, kind, name, meta in self.sets:
            if kind == "single":
                for sid, file in meta["tiles"].items():
                    out[first + sid] = ("single", name, file, sid)
            elif kind == "atlas":
                for i in range(meta["tw"] * meta["th"]):
                    out[first + i] = ("atlas", name, (meta["file"], meta["tw"], i), i)
            else:
                for lid, file, w, h, sl in meta["items"]:
                    out[first + lid] = ("collection", name, (file, w, h, sl), lid)
        return out


def tileset_xml(gm):
    lines = []
    for first, kind, name, meta in gm.sets:
        if kind == "single":
            lines.append('\t<tileset firstgid="%d" name=%s tilewidth="16" tileheight="16" tilecount="%d" columns="0">'
                         % (first, quoteattr(name), meta["count"]))
            for sid in sorted(meta["tiles"]):
                lines.append('\t\t<tile id="%d"><image width="16" height="16" source=%s/></tile>'
                             % (sid, quoteattr(res_to_rel(meta["tiles"][sid]))))
            lines.append("\t</tileset>")
        elif kind == "atlas":
            lines.append('\t<tileset firstgid="%d" name=%s tilewidth="16" tileheight="16" '
                         'tilecount="%d" columns="%d">'
                         % (first, quoteattr(name), meta["tw"] * meta["th"], meta["tw"]))
            lines.append('\t\t<image width="%d" height="%d" source=%s/>'
                         % (meta["tw"] * 16, meta["th"] * 16, quoteattr(res_to_rel(meta["file"]))))
            lines.append("\t</tileset>")
        else:
            align = ' objectalignment="%s"' % meta["alignment"] if meta.get("alignment") else ""
            lines.append('\t<tileset firstgid="%d" name=%s tilewidth="16" tileheight="16" '
                         'tilecount="%d" columns="0"%s>'
                         % (first, quoteattr(name), meta["count"], align))
            for lid, file, w, h, sl in meta["items"]:
                lines.append('\t\t<tile id="%d">'
                             '\n\t\t\t<properties><property name="slice" value=%s/></properties>'
                             '\n\t\t\t<image width="%d" height="%d" source=%s/>'
                             '\n\t\t</tile>'
                             % (lid, quoteattr(sl), w, h, quoteattr(res_to_rel(file))))
            lines.append("\t</tileset>")
    return lines


def layer_data_xml(gids):
    raw = struct.pack("<%dI" % len(gids), *gids)
    b64 = base64.b64encode(zlib.compress(raw, 9)).decode("ascii")
    lid = next(_layerid)
    return ['\t<layer id="%d" name="PLACEHOLDER" width="W" height="H">'
            '\n\t\t<data encoding="base64" compression="zlib">%s</data>'
            '\n\t</layer>' % (lid, b64)]


def build(dump):
    from PIL import Image
    W, H = dump["meta"]["W"], dump["meta"]["H"]
    gm = GidMap()

    # ---- 单格瓦片：PNG 实测尺寸；≠16 的（如垛口齿列 20×20，Godot 只取左上 16×16）
    # 生成 16×16 裁片到 _changan_single_16/（派生件，gitignore），保证 Tiled 渲染与游戏同区域 ----
    single_dir = os.path.join(WORK, "_changan_single_16")
    os.makedirs(single_dir, exist_ok=True)
    single_files = {}
    for sid_s, rec in dump["single_tiles"].items():
        src = os.path.join(ROOT, rec["file"][len("res://"):])
        with Image.open(src) as im:
            im = im.convert("RGBA")
            if im.size == (16, 16):
                single_files[int(sid_s)] = rec["file"]
            else:
                stem = os.path.splitext(os.path.basename(rec["file"]))[0]
                out = os.path.join(single_dir, "%s_16.png" % stem)
                im.crop((0, 0, 16, 16)).save(out)
                single_files[int(sid_s)] = "res://docs/参考/tiled_work/_changan_single_16/%s_16.png" % stem
    single_first = gm.add_single("长安瓦片（单格）", single_files)

    # ---- SCKR 道具：manifest box 是切片框，PNG 已裁透明边——以实机件贴图尺寸为准 ----
    actual_wh = {}
    for p in dump["pieces"]:
        if p["piece"] not in actual_wh:
            actual_wh[p["piece"]] = (p["w"], p["h"])
    atlas_first = {}
    for sid_s in sorted(dump["zone_tiles"], key=int):
        zt = dump["zone_tiles"][sid_s]
        atlas_first[int(sid_s)] = gm.add_atlas(
            "地面区带Z%d_%s" % (zt["zone"], zt["swatch"]), zt["file"], zt["tw"], zt["th"])
    lib_first = {}
    lib_index = {}   # cat -> {piece_id: tile_local_id}
    for cat in dump["lib_cats"]:
        items = [(i, "res://素材库/%s/%s" % (cat, p["file"]), p["w"], p["h"], p["id"])
                 for i, p in enumerate(dump["lib_cats"][cat])]
        lib_first[cat] = gm.add_collection("素材件-%s" % cat, items, alignment="bottom")
        lib_index[cat] = {p["id"]: i for i, p in enumerate(dump["lib_cats"][cat])}
    prop_items = [(i, p["file"]) + actual_wh.get(p["name"], (p["w"], p["h"])) + (p["name"],)
                  for i, p in enumerate(dump["pack_props"])]
    prop_first = gm.add_collection("SCKR道具", prop_items, alignment="bottom")
    prop_index = {p["name"]: i for i, p in enumerate(dump["pack_props"])}

    # ---- 瓦片层 gid ----
    def cell_gid(sid, ax, ay):
        if sid < 0:
            return 0
        if sid in atlas_first:
            zt = dump["zone_tiles"][str(sid)]
            g = atlas_first[sid] + ay * zt["tw"] + ax
            assert 0 <= ax < zt["tw"] and 0 <= ay < zt["th"], (sid, ax, ay)
            return g
        assert str(sid) in dump["single_tiles"], sid
        return single_first + sid

    ground_gids = [cell_gid(s, a, b) for s, a, b in
                   zip(dump["ground"]["sids"], dump["ground"]["ax"], dump["ground"]["ay"])]
    decor_gids = [cell_gid(s, a, b) for s, a, b in
                  zip(dump["decor"]["sids"], dump["decor"]["ax"], dump["decor"]["ay"])]

    # ---- 材质件对象 ----
    def piece_gid(p):
        if p["cat"] == "sckr":
            return prop_first + prop_index[p["piece"]]
        return lib_first[p["cat"]] + lib_index[p["cat"]][p["piece"]]

    grp_layer = {"wall_facade": "城墙立面", "outskirts": "城外林带",
                 "city_gate": "城门", "block": "坊内建筑道具"}
    grp_pieces = {"wall_facade": [], "outskirts": [], "city_gate": [], "block": []}
    for i, p in enumerate(dump["pieces"]):
        g = piece_gid(p) | (FLIP_H if p["flip"] else 0)
        # 对象名：有语义名（OuterWall_*/CityGate_*）保留，匿名件用件id+序号
        nm = p["name"] if not p["name"].startswith("@") and p["name"] != "Sprite2D" \
            else "%s#%02d" % (p["piece"], i)
        grp_pieces[p["group"]].append({"id": next(_objid), "gid": g, "x": p["x"], "y": p["y"],
                                       "name": nm, "piece": p["piece"]})
    for grp in grp_pieces:
        grp_pieces[grp].sort(key=lambda o: (o["y"], o["x"]))

    def objgroup_xml(name, objs, extra=""):
        lid = next(_layerid)
        lines = ['\t<objectgroup id="%d" name=%s%s>' % (lid, quoteattr(name), extra)]
        for o in objs:
            lines.append('\t\t<object id="%d" name=%s gid="%d" x="%s" y="%s"/>' %
                         (o["id"], quoteattr(str(o["name"])), o["gid"], fmt(o["x"]), fmt(o["y"])))
        lines.append("\t</objectgroup>")
        return lines

    npc_objs = [{"id": next(_objid), "name": n["name"], "x": n["x"], "y": n["y"]}
                for n in dump["npcs"]]
    lid = next(_layerid)
    npc_lines = ['\t<objectgroup id="%d" name="城内人口">' % lid]
    for o in npc_objs:
        npc_lines.append('\t\t<object id="%d" name=%s x="%s" y="%s"><point/></object>'
                         % (o["id"], quoteattr(str(o["name"])), fmt(o["x"]), fmt(o["y"])))
    npc_lines.append("\t</objectgroup>")

    lid = next(_layerid)
    portal_lines = ['\t<objectgroup id="%d" name="出城触发" color="#e07040">' % lid]
    for pt in dump["portals"]:
        portal_lines.append('\t\t<object id="%d" name=%s x="%s" y="%s" width="%s" height="%s"/>'
                            % (next(_objid), quoteattr("%s(%s)" % (pt["name"], pt["side"])),
                               fmt(pt["x"]), fmt(pt["y"]), fmt(pt["w"]), fmt(pt["h"])))
    portal_lines.append("\t</objectgroup>")

    lid = next(_layerid)
    block_lines = ['\t<objectgroup id="%d" name="街区轮廓（参考）">' % lid]
    for b in dump["blocks"]:
        color = KIND_COLORS.get(b["kind"], "#cccccc")
        block_lines.append(
            '\t\t<object id="%d" name=%s type="block" x="%d" y="%d" width="%d" height="%d" color="%s">'
            '\n\t\t\t<properties><property name="id" value=%s/><property name="kind" value=%s/></properties>'
            '\n\t\t</object>'
            % (next(_objid), quoteattr(b["name"]), b["x"] * 16, b["y"] * 16,
               b["w"] * 16, b["h"] * 16, color, quoteattr(b["id"]), quoteattr(b["kind"])))
    block_lines.append("\t</objectgroup>")

    # ---- 组装 ----
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<map version="1.10" tiledversion="1.12.2" orientation="orthogonal" '
             'renderorder="right-down" width="%d" height="%d" tilewidth="16" tileheight="16" '
             'infinite="0" nextlayerid="%d" nextobjectid="%d">' % (W, H, next(_layerid), next(_objid)),
             '\t<properties>'
             '\n\t\t<property name="来源" value="长安v2实机生成导出（tools/export_changan_v2_dump.gd → tools/build_changan_v2_tmx.py）"/>'
             '\n\t\t<property name="导出时间" value=%s/>' % quoteattr(str(dump["meta"]["dump_time"])) +
             '\n\t\t<property name="编辑约定" value="物件=底边中心锚(objectalignment=bottom)；16px网格；翻转=水平翻转位"/>'
             '\n\t</properties>']
    lines += tileset_xml(gm)
    for gids, name in [(ground_gids, "地面"), (decor_gids, "城墙装饰")]:
        lay = layer_data_xml(gids)
        lay[0] = lay[0].replace('name="PLACEHOLDER"', 'name=%s' % quoteattr(name)) \
                       .replace('width="W"', 'width="%d"' % W).replace('height="H"', 'height="%d"' % H)
        lines += lay
    lines += objgroup_xml(grp_layer["wall_facade"], grp_pieces["wall_facade"])
    lines += objgroup_xml(grp_layer["outskirts"], grp_pieces["outskirts"])
    lines += objgroup_xml(grp_layer["city_gate"], grp_pieces["city_gate"])
    lines += objgroup_xml(grp_layer["block"], grp_pieces["block"])
    lines += npc_lines
    lines += portal_lines
    lines += block_lines
    lines.append("</map>")
    with open(TMX, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return gm


# ---------------- 校验：解析回读，逐格/逐件与 dump 对账 ----------------

def verify(dump):
    from PIL import Image
    fails = []
    root = ET.parse(TMX).getroot()
    W, H = int(root.get("width")), int(root.get("height"))
    if (W, H) != (dump["meta"]["W"], dump["meta"]["H"]):
        fails.append("尺寸 %dx%d ≠ dump" % (W, H))

    # 重建 tileset 反查表
    gm = GidMap()
    for ts in root.findall("tileset"):
        first = int(ts.get("firstgid"))
        name = ts.get("name")
        if ts.find("image") is not None:      # 图集 tileset
            img = ts.find("image")
            tw = int(ts.get("columns"))
            src = img.get("source")
            p = os.path.normpath(os.path.join(WORK, src))
            if not os.path.exists(p):
                fails.append("图集缺失 %s" % src)
                continue
            with Image.open(p) as im:
                if im.size != (tw * 16, int(ts.get("tilecount")) // tw * 16):
                    fails.append("图集尺寸不符 %s" % src)
            gm.sets.append((first, "atlas", name, {"file": None, "tw": tw, "src": src}))
        else:                                  # collection tileset
            items = []
            for t in ts.findall("tile"):
                img = t.find("image")
                w, h = int(img.get("width")), int(img.get("height"))
                src = img.get("source")
                p = os.path.normpath(os.path.join(WORK, src))
                if not os.path.exists(p):
                    fails.append("贴图缺失 %s" % src)
                else:
                    with Image.open(p) as im:
                        if im.size != (w, h):
                            fails.append("贴图尺寸不符 %s: tmx=%dx%d 实际=%s" % (src, w, h, im.size))
                sl = ""
                props = t.find("properties")
                if props is not None:
                    for pr in props.findall("property"):
                        if pr.get("name") == "slice":
                            sl = pr.get("value")
                items.append((int(t.get("id")), src, w, h, sl))
            if name == "长安瓦片（单格）":
                gm.sets.append((first, "single", name, {"tiles": {
                    lid: "res://" + os.path.relpath(
                        os.path.normpath(os.path.join(WORK, src)), ROOT).replace("\\", "/")
                    for lid, src, _w, _h, _sl in items}, "count": 1}))
                single_first_here = first
            else:
                gm.sets.append((first, "collection", name, {"items": items,
                                                            "alignment": ts.get("objectalignment")}))
    gmap = {}
    single_ts_first = int([e for e in root.findall("tileset")
                           if e.get("name") == "长安瓦片（单格）"][0].get("firstgid"))
    ts_counts = {e.get("name"): int(e.get("tilecount")) for e in root.findall("tileset")}
    # "长安瓦片（单格）" 在解析侧按 single 类型登记，其余 collection 正常登记
    single_first_here = None
    for first, kind, name, meta in gm.sets:
        if kind == "atlas":
            for i in range(ts_counts[name]):
                gmap[first + i] = ("atlas", name, meta["src"], meta["tw"], i)
        elif kind == "single":
            for sid, file in meta["tiles"].items():
                gmap[first + sid] = ("single", name, file, sid)
        else:
            for lid, src, w, h, sl in meta["items"]:
                gmap[first + lid] = ("collection", name, src, w, h, sl)

    # 瓦片层逐格
    def expect_gid(sid, ax, ay):
        if sid < 0:
            return None
        return ("cell", sid, ax, ay)

    layers = {l.get("name"): l for l in root.findall("layer")}
    for lname, cells in [("地面", dump["ground"]), ("城墙装饰", dump["decor"])]:
        if lname not in layers:
            fails.append("缺瓦片层 %s" % lname)
            continue
        data = layers[lname].find("data")
        raw = zlib.decompress(base64.b64decode(data.text))
        gids = struct.unpack("<%dI" % (len(raw) // 4), raw)
        if len(gids) != W * H:
            fails.append("%s 格数 %d ≠ %d" % (lname, len(gids), W * H))
            continue
        bad = 0
        for i, (sid, ax, ay) in enumerate(zip(cells["sids"], cells["ax"], cells["ay"])):
            g = gids[i] & GID_MASK
            if sid < 0:
                if g != 0:
                    bad += 1
                continue
            if g not in gmap:
                bad += 1
                continue
            kind, *_ = gmap[g]
            if kind == "single":
                # 反查该 gid 是否落在"长安瓦片"表且 local id == sid
                if g - single_ts_first != sid:
                    bad += 1
            else:   # atlas: local = ay*tw+ax
                src, tw, _li = gmap[g][2], gmap[g][3], gmap[g][4]
                zt = dump["zone_tiles"].get(str(sid))
                if zt is None or gmap[g][1] != "地面区带Z%d_%s" % (zt["zone"], zt["swatch"]) \
                        or _li != ay * tw + ax:
                    bad += 1
        if bad:
            fails.append("%s 逐格不符 %d 处" % (lname, bad))

    # 对象层逐件（按 gid+坐标+翻转 多重集比对）
    grp_layer = {"wall_facade": "城墙立面", "outskirts": "城外林带",
                 "city_gate": "城门", "block": "坊内建筑道具"}
    for grp, lname in grp_layer.items():
        og = [o for o in root.findall("objectgroup") if o.get("name") == lname]
        if not og:
            fails.append("缺对象层 %s" % lname)
            continue
        got = []
        for o in og[0].findall("object"):
            gid = int(o.get("gid"))
            got.append((gid & GID_MASK, round(float(o.get("x")), 2), round(float(o.get("y")), 2),
                         bool(gid & FLIP_H)))
        exp_list = []
        for p in dump["pieces"]:
            if p["group"] != grp:
                continue
            # 期望 gid 反查：collection 表中 slice==piece 且 w/h 匹配
            cand = [g for g, v in gmap.items() if v[0] == "collection" and v[5] == p["piece"]]
            if not cand:
                fails.append("件 %s 找不到对应 tileset 条目" % p["piece"])
                continue
            g = cand[0]
            exp_list.append((g, round(float(p["x"]), 2), round(float(p["y"]), 2), bool(p["flip"])))
        if sorted(got) != sorted(exp_list):
            only_got = [t for t in got if t not in exp_list]
            only_exp = [t for t in exp_list if t not in got]
            fails.append("%s 对象不符：tmx多%d件/dump多%d件（首例 got=%s exp=%s）"
                         % (lname, len(only_got), len(only_exp),
                            only_got[:1], only_exp[:1]))

    # 人口/触发/街区计数
    for lname, want in [("城内人口", len(dump["npcs"])), ("出城触发", len(dump["portals"])),
                        ("街区轮廓（参考）", len(dump["blocks"]))]:
        og = [o for o in root.findall("objectgroup") if o.get("name") == lname]
        n = len(og[0].findall("object")) if og else -1
        if n != want:
            fails.append("%s 对象数 %d ≠ %d" % (lname, n, want))

    return fails


# ---------------- 预览图（从解析后的 tmx 渲染，独立目检锚点/gid） ----------------

def preview(dump):
    from PIL import Image
    root = ET.parse(TMX).getroot()
    W, H = int(root.get("width")), int(root.get("height"))
    canvas = Image.new("RGBA", (W * 16, H * 16), (20, 24, 20, 255))

    # tileset: gid → 16px 图（单格=整图；图集=裁 16x16）
    tiles = {}
    for ts in root.findall("tileset"):
        first = int(ts.get("firstgid"))
        if ts.find("image") is not None:
            img_el = ts.find("image")
            tw = int(ts.get("columns"))
            sheet = Image.open(os.path.normpath(os.path.join(WORK, img_el.get("source")))).convert("RGBA")
            for i in range(int(ts.get("tilecount"))):
                tiles[first + i] = sheet.crop(((i % tw) * 16, (i // tw) * 16,
                                               (i % tw) * 16 + 16, (i // tw) * 16 + 16))
        else:
            for t in ts.findall("tile"):
                img = t.find("image")
                tiles[first + int(t.get("id"))] = Image.open(
                    os.path.normpath(os.path.join(WORK, img.get("source")))).convert("RGBA")

    for lay in root.findall("layer"):
        data = lay.find("data")
        raw = zlib.decompress(base64.b64decode(data.text))
        gids = struct.unpack("<%dI" % (len(raw) // 4), raw)
        for i, g in enumerate(gids):
            g &= GID_MASK
            if g == 0 or g not in tiles:
                continue
            canvas.paste(tiles[g], (i % W * 16, i // W * 16), tiles[g])

    # 对象层：y-sort 合并（近似游戏内遮挡），底边中心锚
    objs = []
    for og in root.findall("objectgroup"):
        if og.get("name") in ("城内人口", "出城触发", "街区轮廓（参考）"):
            continue
        for o in og.findall("object"):
            if o.get("gid") is None:
                continue
            objs.append(o)
    objs.sort(key=lambda o: (float(o.get("y")), float(o.get("x"))))
    for o in objs:
        g = int(o.get("gid"))
        img = tiles.get(g & GID_MASK)
        if img is None:
            continue
        if g & FLIP_H:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        cx, by = float(o.get("x")), float(o.get("y"))
        canvas.paste(img, (int(round(cx - img.width / 2.0)), int(round(by - img.height))), img)

    canvas.save(PREVIEW)
    print("[preview] %s (%dx%d)" % (os.path.relpath(PREVIEW, ROOT), canvas.width, canvas.height))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "build"
    with open(DUMP, encoding="utf-8") as f:
        dump = json.load(f)
    if mode != "verify":
        build(dump)
        print("[build] %s" % os.path.relpath(TMX, ROOT))
    fails = verify(dump)
    if fails:
        for e in fails:
            print("[verify][FAIL] %s" % e)
        sys.exit(1)
    preview(dump)
    print("[verify] OK：逐格瓦片/逐件对象/贴图尺寸/参考层计数 全部对账通过")


if __name__ == "__main__":
    main()
