# -*- coding: utf-8 -*-
"""素材库进件：board.tmx 盖章 → 切件 PNG + manifest + 一览图 + Tiled 切件表。
流程（docs/长安v2-材质库映射.md §四）：板解析 → 连通域分件（盖章簇）→ 不透明像素精裁
→ 自动编号 <类别>_<NN> → manifest（类别 tag+源表溯源）→ 一览图 → 每类 collection 切件表。

尺度结论（2026-09-09 实测，进件不缩放）：全部源表共享 ≈96px 单体建筑模块
（04/06/08 基准件 94-96 高；01/02/03 的大件是 2×2 模块合院或多栋拼板，内部建筑仍 ≈90px，
÷2 会把它们砍成 45px、比所有类小一半）。拼板（scene_board 类）单列待拍板，不擅自切。

重跑覆盖：python tools/ingest_material_boards.py
产物：素材库/<类别>/pieces/*.png、切件.tsx、_一览图.png；素材库/_总览.png；
     data/material_library.json；docs/参考/tiled_work/_material_ingest_report.md
"""
import os
import io
import re
import glob
import json
import base64
import zlib
import collections
import xml.etree.ElementTree as ET
from datetime import datetime

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
LIB = os.path.join(ROOT, "素材库")
MANIFEST = os.path.join(ROOT, "data", "material_library.json")
REPORT = os.path.join(ROOT, "docs", "参考", "tiled_work", "_material_ingest_report.md")

FOLDER_KIND = {  # 类别 → kind（映射文档 §二）
    "00_地面": "ground", "01_民居坊": "residential", "02_官宅清流": "residential_noble",
    "03_贵戚府": "noble", "04_亲王公主府": "noble", "05_官署": "office",
    "06_宫城": "palace", "07_寺观": "temple", "08_市铺": "market",
    "09_风月楼": "venue", "10_军营": "military", "11_街饰过渡": "transition",
    "12_城防": "citywall",
}
PENDING_CATS = ["09_风月楼", "10_军营", "12_城防"]  # 名字占位：材质包待用户推进

FLIP_H, FLIP_V, FLIP_D = 0x40000000, 0x80000000, 0x20000000
GID_MASK = 0x1FFFFFFF

# 字体（一览图标签/占位牌）：Windows 雅黑；缺失退回默认
def _font(size):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return ImageFont.load_default()

_img_cache = {}
def load_img(rel):
    if rel not in _img_cache:
        _img_cache[rel] = Image.open(os.path.join(ROOT, rel)).convert("RGBA")
    return _img_cache[rel]

_tsx_cache = {}
def load_tsx(tsx_abs):
    if tsx_abs not in _tsx_cache:
        t = ET.parse(tsx_abs).getroot()
        _tsx_cache[tsx_abs] = (int(t.get("columns")),
                               t.find("image").get("source").replace("../../../", ""))
    return _tsx_cache[tsx_abs]


def parse_board(path):
    """board.tmx → (cells[(x,y,gid,flip)], [(firstgid, tsx绝对路径)])"""
    root = ET.parse(path).getroot()
    tables = [(int(ts.get("firstgid")), os.path.normpath(os.path.join(os.path.dirname(path), ts.get("source"))))
              for ts in root.findall("tileset")]
    tables.sort()
    cells = []
    for lay in root.findall("layer"):
        data = lay.find("data")
        if data is None:
            continue
        for ch in data.findall("chunk"):
            raw = base64.b64decode((ch.text or "").strip())
            comp = data.get("compression")
            if comp == "zlib":
                raw = zlib.decompress(raw)
            elif comp == "gzip":
                raw = zlib.decompress(raw, 16 + zlib.MAX_WBITS)
            cw, chh = int(ch.get("width")), int(ch.get("height"))
            cx, cy = int(ch.get("x")), int(ch.get("y"))
            for i in range(len(raw) // 4):
                g = int.from_bytes(raw[i * 4:i * 4 + 4], "little")
                if g == 0:
                    continue
                cells.append((cx + i % cw, cy + i // cw, g & GID_MASK, g & (FLIP_H | FLIP_V | FLIP_D)))
    return cells, tables


def clusters(cells):
    """盖章簇 = 8 连通格群（用户规则：件间距≥1 格全空）。"""
    grid = {(x, y): (g, f) for x, y, g, f in cells}
    seen, out = set(), []
    for p in grid:
        if p in seen:
            continue
        stack, comp = [p], []
        seen.add(p)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (cur[0] + dx, cur[1] + dy)
                    if q in grid and q not in seen:
                        seen.add(q)
                        stack.append(q)
        out.append(comp)
    return out, grid


def classify(w, h, opacity):
    """件类别（启发式，一览图人工核对）：ground/prop/unit/estate/scene_board"""
    if opacity > 0.995 and w % 16 == 0 and h % 16 == 0:
        return "ground"          # 平铺地面/墙面纹理条
    if w > 270 or h > 200:
        return "scene_board"     # 多栋拼板（整块场景，待拍板怎么用）
    if w >= 144 and h >= 144:
        return "estate"          # 2×2 模块合院/府邸整块
    if max(w, h) <= 64:
        return "prop"            # 街饰散件（树/摊/灯…）
    return "unit"                # ≈96px 单体建筑基准件


def checks(w, h, cls, crop):
    a = crop.split()[3].load()
    bottom = sum(1 for x in range(w) if a[x, h - 1] > 0) / w if h else 0
    return {
        "w16": w % 16 == 0, "h16": h % 16 == 0,
        "bottom_anchor": round(bottom, 2),
        "bottom_ok": True if cls in ("ground", "prop") else bottom >= 0.5,
    }


def placeholder_piece(cat):
    """空类占位牌：名字展位（材质待补）。"""
    f = _font(18)
    label = f"{cat[3:]} · 材质待补"
    tmp = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    box = tmp.textbbox((0, 0), label, font=f)
    w = box[2] + 28
    h = box[3] + 24
    img = Image.new("RGBA", (w, h), (38, 34, 30, 255))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=(212, 175, 55, 255), width=2)
    d.text((14, 10), label, font=f, fill=(235, 220, 180, 255))
    return img


def build_sheet(cat, pieces):
    """一览图：件按高降序流式，标签=编号 尺寸 类别（占位按字体宽参与排版防截断）；顶部 96px 基准标尺。"""
    W = 920
    header = 30
    f11 = _font(12)
    items = [(p["id"], p["img"], p["w"], p["h"], p["class"]) for p in pieces]
    items.sort(key=lambda t: (-t[3], -t[2]))
    items = [(pid, im, w, h, c, lbl, int(f11.getlength(lbl) + 0.5))
             for pid, im, w, h, c in items
             for lbl in [f"{pid} {w}x{h} {c}"]]
    def adv(it):
        return max(it[2], it[6] + 6) + 12
    x, y, rowh = 6, header + 22, 0
    for it in items:
        if x + adv(it) > W:
            x = 6; y += rowh + 20; rowh = 0
        rowh = max(rowh, it[3]); x += adv(it)
    sheet = Image.new("RGBA", (W, y + rowh + 10), (54, 54, 58, 255))
    d = ImageDraw.Draw(sheet)
    f12 = _font(14)
    d.text((6, 4), f"{cat}（{len(pieces)} 件）", font=f12, fill=(140, 220, 255, 255))
    # 96px 基准标尺
    d.rectangle((6, header, 6 + 96, header + 8), fill=(255, 210, 90, 255))
    d.text((108, header - 4), "96px = 单体建筑基准（6 格）· 全类共用", font=f11, fill=(255, 210, 90, 255))
    x, y, rowh = 6, header + 22, 0
    for pid, im, w, h, c, lbl, lw in items:
        if x + adv((pid, im, w, h, c, lbl, lw)) > W:
            x = 6; y += rowh + 20; rowh = 0
        sheet.paste(im, (x, y), im)
        d.text((x, y - 14), lbl, font=f11, fill=(255, 255, 120, 255))
        rowh = max(rowh, h); x += adv((pid, im, w, h, c, lbl, lw))
    return sheet


def main():
    manifest = {
        "version": 1,
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "note": "素材库进件清单：board.tmx 盖章→精切件。尺度实测全表共用 ≈96px 单体基准，"
                "进件 1:1 不缩放；01/02/03 大件=多模块合院/拼板（见 report）。"
                "派生 PNG 受 license 约束已 gitignore，重跑本脚本再生。",
        "scale_baseline_px": 96,
        "categories": {},
    }
    report = ["# 素材库进件报告 v1", "",
              f"> 生成：{manifest['generated']}　工具：`tools/ingest_material_boards.py`（重跑覆盖产物）",
              "> 尺度实测：**全部源表共用 ≈96px 单体建筑模块**（04/06/08 基准件 94~96 高；01/02/03 大件内部建筑同 ≈90px）",
              "> ——为满足比例一致性，进件一律 1:1 不缩放；大件是多模块整块，不是倍率偏差。", ""]
    for cat in sorted(os.listdir(LIB)):
        bdir = os.path.join(LIB, cat)
        board = os.path.join(bdir, "board.tmx")
        if not os.path.isdir(bdir) or not os.path.exists(board):
            continue
        os.makedirs(os.path.join(bdir, "pieces"), exist_ok=True)
        for old in glob.glob(os.path.join(bdir, "pieces", "*.png")):
            os.remove(old)  # 重跑清理旧件（编号可能变）

        entry = {"kind": FOLDER_KIND.get(cat, ""), "status": "ok", "pieces": [], "issues": []}
        cells, tables = parse_board(board)
        pieces = []
        if not cells and cat in PENDING_CATS:
            # 名字占位（材质包待用户推进）
            ph = placeholder_piece(cat)
            pid = f"{cat}_01"
            ph.save(os.path.join(bdir, "pieces", pid + ".png"))
            entry["status"] = "pending_material"
            entry["pieces"].append({
                "id": pid, "file": f"pieces/{pid}.png", "w": ph.width, "h": ph.height,
                "class": "name_placeholder", "source": None, "flip": None,
                "opacity": None, "checks": None})
            pieces.append({"id": pid, "img": ph, "w": ph.width, "h": ph.height, "class": "占位"})
            report.append(f"## {cat}\n- 状态：**材质待补（名字占位）**——包不满意，等用户推进后重新盖章跑进件。")
        elif not cells:
            entry["status"] = "empty"
            report.append(f"## {cat}\n- ⚠️ 空板且不在占位名单，请确认。")
        else:
            tsx_map = dict(tables)
            comps, grid = clusters(cells)

            def table_of(g):
                fg = max(f for f in [t[0] for t in tables] if g >= f)
                return fg, g - fg

            # 簇内可能贴着不同表的件（用户混搭贴放）→ 按表分裂成子簇逐件出
            subcomps = []
            for comp in comps:
                by_tbl = collections.defaultdict(list)
                for p in comp:
                    by_tbl[table_of(grid[p][0])[0]].append(p)
                if len(by_tbl) > 1:
                    entry["issues"].append(
                        f"盖章簇含 {len(by_tbl)} 张表的贴邻件（板 {min(p[0] for p in comp)},{min(p[1] for p in comp)} 附近），已按表分件")
                for fg, pts in by_tbl.items():
                    sub_grid = {p: grid[p] for p in pts}
                    seen, out = set(), []
                    for p in pts:
                        if p in seen:
                            continue
                        stack, one = [p], []
                        seen.add(p)
                        while stack:
                            cur = stack.pop()
                            one.append(cur)
                            for dx in (-1, 0, 1):
                                for dy in (-1, 0, 1):
                                    q = (cur[0] + dx, cur[1] + dy)
                                    if q in sub_grid and q not in seen:
                                        seen.add(q)
                                        stack.append(q)
                        out.append(one)
                    subcomps += out
            subcomps.sort(key=lambda c: (min(p[1] for p in c), min(p[0] for p in c)))
            n = 0
            for comp in subcomps:
                fg0, _ = table_of(grid[comp[0]][0])
                cols, imgrel = load_tsx(tsx_map[fg0])
                xs, ys = [], []
                for p in comp:
                    _, tidx = table_of(grid[p][0])
                    xs += [tidx % cols * 16, tidx % cols * 16 + 15]
                    ys += [tidx // cols * 16, tidx // cols * 16 + 15]
                region = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
                img = load_img(imgrel)
                bbox = img.crop(region).split()[3].getbbox()
                if not bbox:
                    entry["issues"].append(
                        f"盖章区域全透明（源表 {imgrel} box {list(region)}）——疑误盖，未出件")
                    continue
                real = (region[0] + bbox[0], region[1] + bbox[1],
                        region[0] + bbox[2], region[1] + bbox[3])
                crop = img.crop(real)
                # 统一翻转位 → 套用（保持用户在 Tiled 看到的样子）
                flips = {grid[p][1] for p in comp}
                flip = None
                if len(flips) == 1 and flips != {0}:
                    flip = flips.pop()
                    if flip & FLIP_D:
                        crop = crop.transpose(Image.TRANSPOSE)
                    if flip & FLIP_H:
                        crop = crop.transpose(Image.FLIP_LEFT_RIGHT)
                    if flip & FLIP_V:
                        crop = crop.transpose(Image.FLIP_TOP_BOTTOM)
                elif len(flips) > 1:
                    entry["issues"].append(f"件 {region} 翻转位不一致，按原始方向出件")
                w, h = crop.size
                alpha = crop.split()[3]
                opacity = sum(alpha.histogram()[128:]) / (w * h)
                cls = classify(w, h, opacity)
                n += 1
                pid = f"{cat}_{n:02d}"
                crop.save(os.path.join(bdir, "pieces", pid + ".png"))
                entry["pieces"].append({
                    "id": pid, "file": f"pieces/{pid}.png", "w": w, "h": h, "class": cls,
                    "source": {"sheet": imgrel, "box": list(real)},
                    "board_cells": {"x0": min(p[0] for p in comp), "y0": min(p[1] for p in comp),
                                    "x1": max(p[0] for p in comp), "y1": max(p[1] for p in comp)},
                    "flip": hex(flip) if flip else None,
                    "opacity": round(opacity, 3), "checks": checks(w, h, cls, crop)})
                pieces.append({"id": pid.split("_", 1)[1], "img": crop, "w": w, "h": h, "class": cls})
            # 类别统计
            cnt = collections.Counter(p["class"] for p in entry["pieces"])
            stat = "、".join(f"{k}×{v}" for k, v in cnt.most_common())
            report.append(f"## {cat}（{len(entry['pieces'])} 件：{stat}）")
            heights = sorted(p["h"] for p in entry["pieces"] if p["class"] in ("unit", "estate"))
            if heights:
                report.append(f"- 单体/合院高度分布：{heights}")
            boards = [p for p in entry["pieces"] if p["class"] == "scene_board"]
            for p in boards:
                report.append(f"- 🟠 拼板待拍板：`{p['id']}` {p['w']}x{p['h']} ← {p['source']['sheet']} "
                              f"box{p['source']['box']}（多栋建筑共地整块，无透明切缝，不能自动拆）")
            for iss in entry["issues"]:
                report.append(f"- ⚠️ {iss}")
        manifest["categories"][cat] = entry

        # 一览图
        if pieces:
            build_sheet(cat, pieces).save(os.path.join(bdir, "_一览图.png"))
        # Tiled 切件表（collection，与 v2_props.tsx 同构：tilecount/columns=0/属性 slice；
        # 配套起步图为 1px 网格——collection 大件正常左上锚）
        tsx = ['<?xml version="1.0" encoding="UTF-8"?>',
               f'<tileset version="1.10" tiledversion="1.12.2" name="切件-{cat}" '
               f'tilewidth="16" tileheight="16" tilecount="{len(entry["pieces"])}" columns="0">']
        for i, p in enumerate(entry["pieces"]):
            tsx.append(f'\t<tile id="{i}">')
            tsx.append(f'\t\t<properties><property name="slice" value="{p["id"]}"/></properties>')
            tsx.append(f'\t\t<image width="{p["w"]}" height="{p["h"]}" source="pieces/{p["id"]}.png"/>')
            tsx.append('\t</tile>')
        tsx.append("</tileset>")
        open(os.path.join(bdir, "切件.tsx"), "w", encoding="utf-8", newline="\n").write("\n".join(tsx) + "\n")

    # 总览
    cats = [c for c in manifest["categories"]]
    CW = 4
    cellw, cellh = 230, 260
    rows = (len(cats) + CW - 1) // CW
    total = Image.new("RGBA", (CW * cellw + 20, rows * cellh + 20), (44, 44, 48, 255))
    d = ImageDraw.Draw(total)
    f14, f12 = _font(15), _font(12)
    for i, cat in enumerate(cats):
        cx, cy = 10 + (i % CW) * cellw, 10 + (i // CW) * cellh
        d.rectangle((cx, cy, cx + cellw - 8, cy + cellh - 8), outline=(90, 90, 96, 255))
        e = manifest["categories"][cat]
        st = {"ok": f"{len(e['pieces'])}件", "pending_material": "待补·占位", "empty": "空"}[e["status"]]
        d.text((cx + 8, cy + 6), cat, font=f14, fill=(140, 220, 255, 255))
        d.text((cx + 8, cy + 26), st, font=f12, fill=(200, 200, 200, 255))
        sheet_path = os.path.join(LIB, cat, "_一览图.png")
        if os.path.exists(sheet_path):
            th = Image.open(sheet_path).convert("RGBA")
            scale = min((cellw - 20) / th.width, (cellh - 50) / th.height)
            th = th.resize((max(1, int(th.width * scale)), max(1, int(th.height * scale))), Image.NEAREST)
            total.paste(th, (cx + 8, cy + 46), th)
    total.save(os.path.join(LIB, "_总览.png"))

    # manifest + 报告
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    report += ["", "## 待拍板项",
               "1. **拼板（scene_board）怎么用**：整块铺进坊（当现成样板）/ 换小件重新盖章 / 授权按建筑间隙切（地面边缘会有直切痕）。",
               "2. **01/02/03 大件**：实测非倍率偏差（内部建筑 ≈90px 与全类一致）。若仍要缩小为 96 级，需拍板 ÷2（建筑将变 45px，与全部类别失衡）或换盖单体件。",
               "3. 各板『盖章区域全透明』疑点（03/06/11 共 6 处，见上）：疑误盖，可顺手清掉。"
               "另：现代都市表在 11 类的盖章均落在透明区未出件（仅 00 类混入一根 48x16 现代表地面窄条，纹理无害）。", ""]
    open(REPORT, "w", encoding="utf-8", newline="\n").write("\n".join(report) + "\n")

    # 控制台摘要
    n_piece = sum(len(e["pieces"]) for e in manifest["categories"].values())
    n_board = sum(1 for e in manifest["categories"].values()
                  for p in e["pieces"] if p["class"] == "scene_board")
    print(f"进件完成：{n_piece} 件入 13 类（拼板 {n_board} 块待拍板）")
    print(f"manifest：{os.path.relpath(MANIFEST, ROOT)}　报告：{os.path.relpath(REPORT, ROOT)}")
    print(f"一览图：素材库/<类别>/_一览图.png　总览：素材库/_总览.png　切件表：素材库/<类别>/切件.tsx")


if __name__ == "__main__":
    main()
