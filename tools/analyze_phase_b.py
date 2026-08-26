# -*- coding: utf-8 -*-
"""Phase B 视觉验证：无视觉模型用调色板命中率代替肉眼
- shot 0-2 森林机位: 素材包树冠/树干命中 + 树底阴影带(草地变暗)统计
- shot 3 城镇机位: 黛青瓦顶/赭石茅草/米墙/冷灰山岩/木栅栏桥 命中统计
用法: python tools/analyze_phase_b.py
"""
import sys, os
sys.path.insert(0, "tools")
from import_pack_assets import load_png

def close(c, ref, tol):
    return all(abs(c[i] - ref[i]) <= tol for i in range(3))

TEAL_ROOF = [(0x44, 0x5b, 0x6b), (0x60, 0x7c, 0x8c), (0x2b, 0x3b, 0x47)]   # 黛青瓦三阶
THATCH    = [(0x93, 0x70, 0x47), (0xb2, 0x8e, 0x5e), (0x6b, 0x4f, 0x30)]   # 赭石茅草三阶
WALL      = [(0xef, 0xe0, 0xb7), (0xed, 0xea, 0xd8)]
ROCK      = [(0x96, 0xa0, 0xaa), (0x72, 0x7a, 0x84), (0x51, 0x59, 0x63)]
WOOD      = [(0x68, 0x4c, 0x30), (0x99, 0x72, 0x49), (0xa0, 0x77, 0x4c), (0x89, 0x66, 0x3f)]
CANOPY    = [(0x54, 0x68, 0x2c), (0x28, 0x1c, 0x0d), (0x84, 0x20, 0x20)]   # 树冠/树干/秋红

def scan(path, refs, tol=14, step=2):
    w, h, rows = load_png(path)
    hits = {i: 0 for i in range(len(refs))}
    total = 0
    for y in range(0, h, step):
        line = rows[y]
        for x in range(0, w * 4, 4 * step):
            r, g, b, a = line[x], line[x+1], line[x+2], line[x+3]
            if a < 200:
                continue
            total += 1
            for i, ref in enumerate(refs):
                if close((r, g, b), ref, tol):
                    hits[i] += 1
                    break
    return hits, total

if __name__ == "__main__":
    print("== 森林机位 (shot 0-2): 大树渲染 + 落地阴影 ==")
    for i in range(3):
        p = "tools/probe_shot_%d.png" % i
        if not os.path.exists(p):
            print(p, "missing"); continue
        hits, total = scan(p, CANOPY)
        # 阴影带: 素材包草地#337903被黑30%覆盖 -> 约#245a02附近，取暗绿窄带
        w, h, rows = load_png(p)
        shadow = 0
        for y in range(0, h, 2):
            line = rows[y]
            for x in range(0, w * 4, 8):
                r, g, b, a = line[x], line[x+1], line[x+2], line[x+3]
                if a > 200 and 18 <= r <= 46 and 74 <= g <= 108 and b <= 22:
                    shadow += 1
        print("shot%d canopy=%d trunk=%d red=%d shadow_band=%d (sampled %d)" %
              (i, hits[0], hits[1], hits[2], shadow, total))
    p3 = "tools/probe_shot_3.png"
    if os.path.exists(p3):
        print("== 城镇POI机位 (shot 3): 中式建筑新调色板 ==")
        for name, refs in [("黛青瓦顶", TEAL_ROOF), ("赭石茅草", THATCH),
                           ("米色墙", WALL), ("冷灰山岩", ROCK), ("暖木构", WOOD)]:
            hits, total = scan(p3, refs)
            print("%s: %d (sampled %d)" % (name, sum(hits.values()), total))
