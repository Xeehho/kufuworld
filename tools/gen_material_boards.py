# -*- coding: utf-8 -*-
"""生成长安v2素材库切件板：素材库/<类别>/board.tmx（16px 网格/infinite/base64/单图层 pieces）。
2026-09-09 用户拍板：**所有源表全挂到每块板**（不按类别过滤），用户混搭选件——
类别=盖章所在的文件夹（在哪块板上盖的就归哪类）。
重跑覆盖：python tools/gen_material_boards.py
"""
import os
import re
import glob

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
TSX_DIR = os.path.join(ROOT, "docs", "参考", "tiled_work")
LIB_DIR = os.path.join(ROOT, "素材库")

FOLDERS = [
    "00_地面", "01_民居坊", "02_官宅清流", "03_贵戚府", "04_亲王公主府",
    "05_官署", "06_宫城", "07_寺观", "08_市铺", "09_风月楼",
    "10_军营", "11_街饰过渡", "12_城防",
]

GID_STEP = 3000  # 每表预留 gid 段（最大 tilecount=2304，余量足）


def scan_tsx():
    """全部 tsx 表（按文件名序）→ [(文件名, 显示名)]。"""
    out = []
    for f in sorted(glob.glob(os.path.join(TSX_DIR, "ts_*.tsx"))):
        txt = open(f, encoding="utf-8").read()
        nm = re.search(r'name="([^"]+)"', txt)
        out.append((os.path.basename(f), nm.group(1) if nm else os.path.basename(f)))
    return out


def main():
    tables = scan_tsx()
    os.makedirs(LIB_DIR, exist_ok=True)
    for folder in FOLDERS:
        lines = ['<?xml version="1.0" encoding="UTF-8"?>',
                 '<map version="1.10" tiledversion="1.12.2" orientation="orthogonal" '
                 'renderorder="right-down" width="64" height="64" tilewidth="16" tileheight="16" '
                 'infinite="1" nextlayerid="2" nextobjectid="1">']
        for i, (fname, _nm) in enumerate(tables):
            lines.append(f'\t<tileset firstgid="{1 + i * GID_STEP}" '
                         f'source="../../docs/参考/tiled_work/{fname}"/>')
        lines += ['\t<layer id="1" name="pieces" width="64" height="64">',
                  '\t\t<data encoding="base64"/>',
                  '\t</layer>',
                  '</map>']
        path = os.path.join(LIB_DIR, folder, "board.tmx")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    names = ", ".join(nm for _f, nm in tables)
    print(f"{len(FOLDERS)} 板 × {len(tables)} 表全挂 [{names}]")


if __name__ == "__main__":
    main()
