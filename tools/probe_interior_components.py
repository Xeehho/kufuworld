# -*- coding: utf-8 -*-
"""内景家具源图连通分量分析（切片禁目测估框——血泪教训）：
对目标 sheet 跑透明底连通分量 → 合并近邻分量（格内部件互连失败的兜底）→ 输出精确 bbox 清单。
用法:
  python tools/probe_interior_components.py                 # 全部分析，输出带标注目检图
  python tools/probe_interior_components.py jingcheng/tile-B-07.png ...
"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "downloaded_assets", "comshadow_bundle")
OUT = os.path.join(ROOT, "docs", "shots", "pack_jingcheng")

SHEETS = [
    "jingcheng/tile-B-07.png",
    "jingcheng/tile-B-04.png",
    "jiangnan/tile-B-05.png",
    "jingcheng/tile-B-02.png",
    "jiangnan/tile-B-02.png",
]
if len(sys.argv) > 1:
    SHEETS = sys.argv[1:]


def components(im, min_px=24):
    """透明底 4 邻接连通分量，返回 [(count, l, t, r, b)]（像素 bbox）。"""
    w, h = im.size
    px = im.load()
    lab = [[0] * w for _ in range(h)]
    out = []
    nid = 0
    for sy in range(h):
        for sx in range(w):
            if lab[sy][sx] or px[sx, sy][3] <= 10:
                continue
            nid += 1
            stack = [(sx, sy)]
            lab[sy][sx] = nid
            cnt = 0
            l = r = sx
            t = b = sy
            while stack:
                x, y = stack.pop()
                cnt += 1
                l = min(l, x); r = max(r, x); t = min(t, y); b = max(b, y)
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not lab[ny][nx] and px[nx, ny][3] > 10:
                        lab[ny][nx] = nid
                        stack.append((nx, ny))
            if cnt >= min_px:
                out.append([cnt, l, t, r, b])
    return out, lab


def merge(boxes, gap=4):
    """bbox 间距 <=gap 的分量合并（灯笼穗/椅腿与座面断开类部件）。"""
    boxes = [list(b) for b in boxes]
    changed = True
    while changed:
        changed = False
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                a, b = boxes[i], boxes[j]
                if (a[1] - gap <= b[3] and b[1] - gap <= a[3] and
                        a[2] - gap <= b[4] and b[2] - gap <= a[4]):
                    boxes[i] = [a[0] + b[0], min(a[1], b[1]), min(a[2], b[2]), max(a[3], b[3]), max(a[4], b[4])]
                    boxes.pop(j)
                    changed = True
                    break
            if changed:
                break
    return boxes


def main():
    os.makedirs(OUT, exist_ok=True)
    for rel in SHEETS:
        im = Image.open(os.path.join(SRC, rel)).convert("RGBA")
        comp, _ = components(im)
        merged = merge(comp, gap=4)
        merged.sort(key=lambda b: (b[2] // 48, b[1]))
        print(f"==== {rel}  raw={len(comp)} merged={len(merged)} ====")
        for cnt, l, t, r, b in merged:
            print(f"  box=({l}, {t}, {r + 1}, {b + 1})  {r + 1 - l}x{b + 1 - t}  px={cnt}")
        vis = im.convert("RGB").copy()
        d = ImageDraw.Draw(vis)
        for i, (cnt, l, t, r, b) in enumerate(merged):
            d.rectangle([l, t, r, b], outline=(255, 40, 40), width=1)
            d.text((l + 1, t + 1), str(i), fill=(255, 255, 0))
        name = os.path.basename(rel).replace(".png", "_comp.png")
        vis.save(os.path.join(OUT, name))
        print(f"  vis -> docs/shots/pack_jingcheng/{name}")


if __name__ == "__main__":
    main()
