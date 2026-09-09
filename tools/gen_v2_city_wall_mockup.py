# -*- coding: utf-8 -*-
"""生成 v2 长安外郭城墙环 Tiled 图（用户模板单元拼装版）

用户拍板（2026-09-08 晚）：
- 不用文档计划的 E/W 豁口城门（先不放东西门，渲染验收时用户定）
- 以用户 Outer_city_wall.tmx 模板为唯一单元：横墙带/门楼/竖墙/马道
- 北墙=南墙整体水平镜像（"对折过去"）
- 宽度按 v2 文档：W=168 H=142 格（16px 网格），墙环 margin=8 wall=2

单元提取（全部从模板 gid 抄，不手造坐标）：
- wall_rows: 横墙带 5 行 = 源B01(29, 7..11) 平铺
- gate_pkg:  门楼包 = 建筑(门楼 x41..56 × y44..49) + 地面(马道+门前路 x21..52 × y18..49)
- vwall:     竖墙 3 列 × 29 行（左右两侧序列，纵向 6 行自周期循环平铺）
"""
import base64
import os
import struct
import xml.etree.ElementTree as ET
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'docs', '参考', 'tiled_work')

FLIP_H, FLIP_V, FLIP_D = 0x80000000, 0x40000000, 0x20000000
FLIP_MASK = FLIP_H | FLIP_V | FLIP_D

# v2 城参数（抄自 changan_v2_generator.gd 同源公式）
MARGIN, WALL, RING, BW, BH, MAIN_S, ZQ_S, COLS, ROWS, AXIS = 8, 2, 3, 20, 20, 4, 6, 6, 5, 3
W = MARGIN * 2 + WALL * 2 + RING * 2 + COLS * BW + (COLS - 1) * MAIN_S + (ZQ_S - MAIN_S)   # 168
H = MARGIN * 2 + WALL * 2 + RING * 2 + ROWS * BH + (ROWS - 1) * MAIN_S                      # 142


def col_x(c):
    return MARGIN + WALL + RING + c * (BW + MAIN_S) + (ZQ_S - MAIN_S if c >= AXIS else 0)


def row_y(r):
    return MARGIN + WALL + RING + r * (BH + MAIN_S)


def seam_x(i):
    return col_x(i) - (ZQ_S if i == AXIS else MAIN_S)


S_CX = seam_x(AXIS) + ZQ_S // 2          # 明德门心 = 84
N_CX = seam_x(COLS - 1) + MAIN_S // 2    # 玄武门心 = 133

VW_W, VW_E = MARGIN - 1, W - MARGIN - 2  # 竖墙 3 列左缘：西 x7..9 东 x158..160（对称：各以墙格外缘向城外探 1 列）


def parse(path, want_layers):
    m = ET.parse(path).getroot()
    w = int(m.get('width'))
    tss = []
    for ts in m.findall('tileset'):
        root = ET.parse(os.path.join(os.path.dirname(path), ts.get('source'))).getroot()
        tss.append((int(ts.get('firstgid')), root.get('name'), int(root.get('columns')),
                    int(root.get('tilecount')), ts.get('source')))
    tss.sort()
    layers = {}
    for layer in m.findall('layer'):
        if layer.get('name') not in want_layers:
            continue
        data = layer.find('data')
        raw = zlib.decompress(base64.b64decode(''.join(data.itertext())))
        layers[layer.get('name')] = [raw[i] | raw[i + 1] << 8 | raw[i + 2] << 16 | raw[i + 3] << 24
                                     for i in range(0, len(raw), 4)]
    return w, tss, layers


def remap_gid(g, tss, keep):
    if not g:
        return 0
    base, flip = g & ~FLIP_MASK, g & FLIP_MASK
    for old_fg, new_fg, cnt in keep:
        if old_fg <= base < old_fg + cnt:
            return new_fg + (base - old_fg) | flip
    raise AssertionError('gid %d 无表' % g)


def main():
    # ── 模板解析 ──
    tw, ttss, tlayers = parse(os.path.join(WORK, 'Outer_city_wall.tmx'), ['地面', '建筑'])
    b01 = next(t for t in ttss if t[1] == '京城-B01')
    old_fg, b01_cols, b01_cnt = b01[0], b01[2], b01[3]
    build, ground = tlayers['建筑'], tlayers['地面']
    TG = lambda x, y: build[y * tw + x]   # 模板建筑层取格
    DG = lambda x, y: ground[y * tw + x]  # 模板地面层取格

    # 新图只引一张 B01 表（firstgid=1）
    keep = [(old_fg, 1, b01_cnt)]
    N = lambda g: remap_gid(g, ttss, keep)

    # 单元①门楼包（建筑 x41..56 y44..49；地面 x21..52 y18..49，空格照抄 0）
    gate_build = [[TG(x, y) for x in range(41, 57)] for y in range(44, 50)]
    gate_ground = [[DG(x, y) for x in range(21, 53)] for y in range(18, 50)]
    # 单元②竖墙序列（左右各 3 列 × 30 行——含 y45 嵌入行：竖墙件嵌进墙带垛口行补透明豁口，
    # 模板"三线齐平零露缝"的关键细节，序列底=col24 位）
    vwl = [[TG(x, y) for y in range(16, 46)] for x in range(14, 17)]
    vwr = [[TG(x, y) for y in range(16, 46)] for x in range(84, 87)]
    # 单元③横墙带 5 行墙身 gid（源 col29 row7..11，从模板 y45 x38 直接取）
    wall_row_gid = [TG(38, y) for y in range(45, 50)]

    # ── 拼装画布 ──
    gnd = [0] * (W * H)
    bld = [0] * (W * H)

    def put(layer, x, y, g):
        layer[y * W + x] = g

    def hmirror(g):
        return g ^ FLIP_H if g else 0

    def stamp_build_pkg(cx, top_y, mirrored):
        """门楼包（16 格宽）以门心 cx 落位：镜像时 x 顺序翻转 + tile 翻转"""
        ox = cx - 8
        for dy, row in enumerate(gate_build):
            for dx, g in enumerate(row):
                px = ox + (15 - dx if mirrored else dx)
                put(bld, px, top_y + dy, N(hmirror(g) if mirrored else g))

    # 地面包偏移重算：模板墙带顶 y45，地面包 y18..49（底行 y49=墙带底下一行? 模板墙带 y45..49 同高——
    # 地面包底 y49 与墙带底同行）。v2 南墙带 y129..133 → 偏移 = 133-49 = +84；北墙带 y8..12 → 偏移 = 8-49 = -41
    def stamp_ground_pkg(cx, off, mirrored):
        gox = cx - 28  # 地面包 x21..52（32 格宽）左缘 = 门楼左缘 - 20
        for dy, row in enumerate(gate_ground):
            y = dy + 18 + off
            if y < 0 or y >= H:
                continue
            for dx, g in enumerate(row):
                if g:
                    px = gox + (31 - dx if mirrored else dx)
                    put(gnd, px, y, N(hmirror(g) if mirrored else g))

    # 南墙带（y129..133）+北墙带（y8..12），x7..160 墙身平铺
    for x in range(7, 161):
        for r, gid in enumerate(wall_row_gid):
            put(bld, x, 129 + r, N(gid))
            put(bld, x, 8 + r, N(hmirror(gid)))
    # 门楼包：南=原版（y128..133），北=镜像（y7..12）
    stamp_ground_pkg(S_CX, 133 - 49, False)
    stamp_build_pkg(S_CX, 128, False)
    stamp_ground_pkg(N_CX, 8 - 49, True)
    stamp_build_pkg(N_CX, 7, True)

    # 东西竖墙：y12..129（118 行）两端嵌入行——
    # 南底行 y129=序列位29（col24）嵌进墙带垛口行（补 13px 透明豁口，模板 y45 同款）；
    # 北顶行 y12=序列位2（col27）嵌进北墙带墙基行（源29,11 下部 6px 固有透明，嵌满格竖墙件补缝）
    # 东墙=模板右竖墙原样（模板左右竖墙翻转位 f6=rot90 / fA=rot270 已互为镜像，用户手拼对称；
    #   再 hmirror 会还原成西墙同款导致东西不对称——2026-09-08 用户反馈修正）
    for y in range(12, 130):
        sy = (y - 12 + 2) % 30
        for c in range(3):
            put(bld, VW_W + c, y, N(vwl[c][sy]))   # 西墙=模板左竖墙原序列
            put(bld, VW_E + c, y, N(vwr[c][sy]))   # 东墙=模板右竖墙原序列（天然镜像）

    # ── 写 tmx ──
    def layer_xml(idx, name, data):
        raw = b''.join(struct.pack('<I', g) for g in data)
        return (' <layer id="%d" name="%s" width="%d" height="%d">\n'
                '  <data encoding="base64" compression="zlib">%s</data>\n </layer>\n'
                % (idx, name, W, H, base64.b64encode(zlib.compress(raw, 9)).decode()))

    notes = [
        ('南墙·明德门（你的模板原版，宽 168 格按文档）', 20, 136, '#e0b040'),
        ('北墙·玄武门（模板镜像对折）', 20, 18, '#e0b040'),
        ('东西墙=你的竖墙序列纵贯；E/W 门暂未放（等你拍板）', 12, 70, '#a0a0a0'),
    ]
    objs = [' <objectgroup id="10" name="标注">']
    for i, (txt, ox, oy, color) in enumerate(notes):
        objs.append('  <object id="%d" x="%d" y="%d" width="1" height="1">'
                    '   <text fontfamily="sans-serif" pixelssize="14" color="%s">%s</text>  </object>'
                    % (i + 1, ox * 16, oy * 16, color, txt))
    objs.append(' </objectgroup>')

    tmx = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<map version="1.10" tiledversion="1.12.2" orientation="orthogonal" renderorder="right-down" '
           'width="%d" height="%d" tilewidth="16" tileheight="16" infinite="0" nextlayerid="11" nextobjectid="%d">\n'
           ' <tileset firstgid="1" source="ts_02.tsx"/>\n' % (W, H, len(notes) + 1))
    tmx += layer_xml(1, '地面', gnd)
    tmx += layer_xml(2, '建筑', bld)
    tmx += layer_xml(3, '道具', [0] * (W * H))
    tmx += '\n'.join(objs) + '\n</map>\n'
    out = os.path.join(WORK, 'v2_city_wall_mockup.tmx')
    open(out, 'w', encoding='utf-8', newline='\n').write(tmx)
    print('[v2-wall] 画布 %d×%d 格；S门x=%d N门x=%d 竖墙西%d..%d 东%d..%d'
          % (W, H, S_CX, N_CX, VW_W, VW_W + 2, VW_E, VW_E + 2))
    print('[v2-wall] 建筑格=%d 地面格=%d → %s (%.1f KB)'
          % (len([g for g in bld if g]), len([g for g in gnd if g]), out, os.path.getsize(out) / 1024))


if __name__ == '__main__':
    main()
