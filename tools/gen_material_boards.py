# -*- coding: utf-8 -*-
"""生成长安v2素材库切件板：素材库/<类别>/board.tmx（16px 网格/infinite/base64/单图层 pieces）。
每类按 manifest category 预挂对应源表的 tsx（docs/参考/tiled_work/ts_XX.tsx），
用户开板即可盖章选件，AI 解析 gid→源表区域→按不透明像素精切成散件。
重跑覆盖：python tools/gen_material_boards.py
"""
import json
import os
import re
import glob

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
TSX_DIR = os.path.join(ROOT, "docs", "参考", "tiled_work")
LIB_DIR = os.path.join(ROOT, "素材库")
MANIFEST = os.path.join(ROOT, "data", "sckr_manifest.json")

# 文件夹 → manifest category（预挂源表依据；宁可多挂用户自查，不挂 interior=外城用不到）
FOLDER_CATS = {
    "00_地面": ["ground"],
    "01_民居坊": ["building"],
    "02_官宅清流": ["building"],
    "03_贵戚府": ["building", "decor"],
    "04_亲王公主府": ["building", "decor"],
    "05_官署": ["building", "decor"],
    "06_宫城": ["building", "decor"],
    "07_寺观": ["building", "decor"],
    "08_市铺": ["market", "street_furniture"],
    "09_风月楼": ["building", "street_furniture"],
    "10_军营": ["building"],
    "11_街饰过渡": ["decor", "street_furniture", "plant", "water", "misc"],
    "12_城防": ["wall"],
}

GID_STEP = 3000  # 每表预留 gid 段（最大 tilecount=2304，余量足）


def scan_tsx():
    """tsx 文件 → (sheet_key, name)。sheet_key 形如 jingcheng/tile-B-01.png。"""
    out = {}
    for f in sorted(glob.glob(os.path.join(TSX_DIR, "ts_*.tsx"))):
        txt = open(f, encoding="utf-8").read()
        m = re.search(r'image source="[^"]*?/comshadow_bundle/([^"]+)"', txt)
        if not m:
            continue
        sheet = m.group(1).replace("\\", "/")
        if sheet.startswith("wuxia_interior_dlc/"):
            continue  # 外城板不挂内景表（M4 内景阶段另建板）
        nm = re.search(r'name="([^"]+)"', txt).group(1)
        out[sheet] = {"file": os.path.basename(f), "name": nm}
    return out


def main():
    tsx = scan_tsx()
    man = json.load(open(MANIFEST, encoding="utf-8"))
    cat_sheets = {}
    for a in man["assets"]:
        cat_sheets.setdefault(a["category"], set()).add(a["sheet"])

    os.makedirs(LIB_DIR, exist_ok=True)
    for folder, cats in FOLDER_CATS.items():
        sheets = []
        for c in cats:
            for s in sorted(cat_sheets.get(c, [])):
                if s not in sheets and s in tsx:
                    sheets.append(s)
        if not sheets:
            print(f"[warn] {folder}: 无可挂源表")
        lines = ['<?xml version="1.0" encoding="UTF-8"?>',
                 '<map version="1.10" tiledversion="1.12.2" orientation="orthogonal" '
                 'renderorder="right-down" width="64" height="64" tilewidth="16" tileheight="16" '
                 'infinite="1" nextlayerid="2" nextobjectid="1">']
        for i, s in enumerate(sheets):
            lines.append(f'\t<tileset firstgid="{1 + i * GID_STEP}" '
                         f'source="../../docs/参考/tiled_work/{tsx[s]["file"]}"/>')
        lines += ['\t<layer id="1" name="pieces" width="64" height="64">',
                  '\t\t<data encoding="base64"/>',
                  '\t</layer>',
                  '</map>']
        path = os.path.join(LIB_DIR, folder, "board.tmx")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
        names = ", ".join(tsx[s]["name"] for s in sheets)
        print(f"{folder}: {len(sheets)} 表 [{names}]")
    print("done")


if __name__ == "__main__":
    main()
