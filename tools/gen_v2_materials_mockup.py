# -*- coding: utf-8 -*-
"""生成 v2 材质起步 Tiled 工程（长安 v2 材质阶段·第 0 步）

产物（docs/参考/tiled_work/）：
  v2_tile16.tsx        — 16px 地面/墙带切片 collection 表（manifest tile 类）
  v2_props.tsx         — prop 大件 collection 表（起步批：城门楼/排屋/山墙/店面/杂件）
  v2_materials_mockup.tmx — 1px 网格起步图（1440×1000，base64+zlib）：
    只含用户 Outer_city_wall.tmx 城墙段原拼法整段拷贝（零损耗 ground truth）。
    ⚠️ 2026-09-08 用户拍板：不预摆任何 AI 模板（排屋/店面/地面段已删）——
    除城墙段外全部留白，拼法由用户手拼探索，AI 只供切片+验收。
纯数据工作文件，重跑即可重建。切片纪律：全部引用 manifest 条目，无临时像素窗口。
"""
import base64
import json
import os
import struct
import xml.etree.ElementTree as ET
import zlib

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'docs', '参考', 'tiled_work')
TILES_DIR = os.path.join(ROOT, 'sprites', 'tiles_changan_sckr')
PROPS_DIR = os.path.join(ROOT, 'sprites', 'changan_props_sckr')
MANIFEST = json.load(open(os.path.join(ROOT, 'data', 'sckr_manifest.json'), encoding='utf-8'))

CANVAS_W, CANVAS_H = 1440, 1000         # 1px 网格画布（容纳城墙示范段 1168×544 + 续拼留白）

# ── 起步批注册表（语义名 → manifest name）─────────────────────────
TILE16 = ['street_zhuque', 'street_main', 'street_ward', 'street_lane',
          'pave_market', 'wall_band_crest', 'wall_band_body_a', 'wall_band_body_b',
          'wall_band_body_c', 'wall_band_base', 'wall_band_v_w0', 'wall_band_v_w1',
          'wall_band_v_w2', 'foot']
PROPS = ['gate_tower_big', 'gate_tower_mid', 'house_win_a', 'house_door_a',
         'house_win_small', 'house_small_win', 'house_small_door', 'gable_ma',
         'gable_white', 'house_shop_open', 'gate_wood', 'bench_wood',
         'lamp_red', 'lamp_stone', 'market_gate', 'pagoda_gold', 'lou_blue',
         'compound_gate']

FLIP_MASK = 0xF0000000


def png_size(path):
    with open(path, 'rb') as f:
        head = f.read(24)
    return struct.unpack('>II', head[16:24])


def rel(path):
    return os.path.relpath(path, WORK).replace('\\', '/')


def write_tileset_tsx(fname, names, src_dir, tile_w):
    """collection 式 tsx：每件一个 <tile id><image/></tile>"""
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<tileset version="1.10" tiledversion="1.12.2" name="%s" tilewidth="%d" tileheight="%d" tilecount="%d" columns="0">'
             % (fname[:-4], tile_w, tile_w, len(names))]
    for i, n in enumerate(names):
        w, h = png_size(os.path.join(src_dir, n + '.png'))
        lines.append(' <tile id="%d">' % i)
        lines.append('  <properties><property name="slice" value="%s"/></properties>' % n)
        lines.append('  <image width="%d" height="%d" source="%s"/>' % (w, h, rel(os.path.join(src_dir, n + '.png'))))
        lines.append(' </tile>')
    lines.append('</tileset>')
    open(os.path.join(WORK, fname), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    return len(names)


def parse_user_wall_tmx():
    """解析用户 Outer_city_wall.tmx → {层名: [gid...]} + 表信息"""
    m = ET.parse(os.path.join(WORK, 'Outer_city_wall.tmx')).getroot()
    W, H = int(m.get('width')), int(m.get('height'))
    tss = []
    for ts in m.findall('tileset'):
        root = ET.parse(os.path.join(WORK, ts.get('source'))).getroot()
        tss.append({'old_fg': int(ts.get('firstgid')), 'src': ts.get('source'),
                    'name': root.get('name'), 'count': int(root.get('tilecount'))})
    layers = {}
    for layer in m.findall('layer'):
        data = layer.find('data')
        raw = zlib.decompress(base64.b64decode(''.join(data.itertext())))
        gids = [raw[i] | raw[i + 1] << 8 | raw[i + 2] << 16 | raw[i + 3] << 24
                for i in range(0, len(raw), 4)]
        layers[layer.get('name')] = {'w': W, 'h': H, 'gids': gids}
    return tss, layers


def main():
    # ①两张 collection 表
    n_tiles = write_tileset_tsx('v2_tile16.tsx', TILE16, TILES_DIR, 16)
    n_props = write_tileset_tsx('v2_props.tsx', PROPS, PROPS_DIR, 16)

    # ②用户城墙段 → gid 重映射（ts_02 京城-B01 / ts_14 江南-B05 续接新体系）
    tss, user_layers = parse_user_wall_tmx()
    new_bases = []  # (old_fg, new_fg, count) — 按旧 fg 排序后顺序分配
    next_fg = 1 + n_tiles + n_props
    kept = []
    for ts in sorted(tss, key=lambda t: t['old_fg']):
        pass  # 先扫一遍确定引用了哪些表
    used = set()
    for L in user_layers.values():
        for g in L['gids']:
            if g:
                used.add(g & ~FLIP_MASK)
    for ts in sorted(tss, key=lambda t: t['old_fg']):
        if any(ts['old_fg'] <= u < ts['old_fg'] + ts['count'] for u in used):
            kept.append((ts, next_fg))
            next_fg += ts['count']
    remap = {ts['old_fg']: nf for ts, nf in kept}

    def remap_gid(g):
        if not g:
            return 0
        base, flip = g & ~FLIP_MASK, g & FLIP_MASK
        for ts, nf in kept:
            if ts['old_fg'] <= base < ts['old_fg'] + ts['count']:
                return nf + (base - ts['old_fg']) | flip
        raise AssertionError('gid %d 无表可映射' % g)

    # ③三层画布
    ground = [0] * (CANVAS_W * CANVAS_H)
    build = [0] * (CANVAS_W * CANVAS_H)

    def put(layer, x, y, gid):
        if x < 0 or y < 0 or x >= CANVAS_W or y >= CANVAS_H:
            raise AssertionError('越界 (%d,%d)' % (x, y))
        layer[y * CANVAS_W + x] = gid

    def copy_user_layer(dst, src_layer, ox, oy):
        L = user_layers[src_layer]
        for i, g in enumerate(L['gids']):
            if g:
                put(dst, ox + (i % L['w']) * 16, oy + (i // L['w']) * 16, remap_gid(g))

    # 段 A：城墙示范段整段拷贝（用户原拼法，bbox 73×34 格 = 1168×544px）
    copy_user_layer(ground, '地面', 16, 16)
    copy_user_layer(build, '建筑', 16, 16)

    # 2026-09-08 用户拍板：不预摆 AI 模板——排屋/店面/地面段全删，
    # 城墙段以外留白，拼法由用户手拼探索（AI 只供切片+验收）。

    # ④tmx
    def layer_xml(idx, name, data):
        raw = b''.join(struct.pack('<I', g) for g in data)
        b64 = base64.b64encode(zlib.compress(raw, 9)).decode()
        return (' <layer id="%d" name="%s" width="%d" height="%d">\n'
                '  <properties><property name="v2阶段" value="骨架样板段"/></properties>\n'
                '  <data encoding="base64" compression="zlib">%s</data>\n'
                ' </layer>\n' % (idx, name, CANVAS_W, CANVAS_H, b64))

    ts_lines = [' <tileset firstgid="1" source="v2_tile16.tsx"/>',
                ' <tileset firstgid="%d" source="v2_props.tsx"/>' % (1 + n_tiles)]
    for ts, nf in kept:
        ts_lines.append(' <tileset firstgid="%d" source="%s"/>' % (nf, ts['src']))

    notes = [
        ('城墙模板（你的原拼法·已保留）', 16, 620, '#e0b040'),
        ('↓ 下方全部留白：排屋/店面/地面由你自己拼，拼完发回验收', 16, 700, '#a0a0a0'),
    ]
    obj_lines = [' <objectgroup id="10" name="标注">']
    for i, (txt, ox, oy, color) in enumerate(notes):
        obj_lines.append('  <object id="%d" type="note" x="%d" y="%d" width="1" height="1">'
                         '   <text fontfamily="sans-serif" fontsize="14" pixelssize="14" color="%s">%s</text>'
                         '  </object>' % (i + 1, ox, oy, color, txt))
    obj_lines.append(' </objectgroup>')

    tmx = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<map version="1.10" tiledversion="1.12.2" orientation="orthogonal" renderorder="right-down" '
           'width="%d" height="%d" tilewidth="1" tileheight="1" infinite="0" nextlayerid="11" nextobjectid="%d">\n'
           % (CANVAS_W, CANVAS_H, len(notes) + 1))
    tmx += '\n'.join(ts_lines) + '\n'
    tmx += layer_xml(1, '地面', ground)
    tmx += layer_xml(2, '建筑', build)
    tmx += (' <layer id="3" name="道具" width="%d" height="%d">\n'
            '  <data encoding="base64" compression="zlib">%s</data>\n </layer>\n'
            % (CANVAS_W, CANVAS_H, base64.b64encode(zlib.compress(b'\0\0\0\0' * CANVAS_W * CANVAS_H)).decode()))
    tmx += '\n'.join(obj_lines) + '\n</map>\n'
    out = os.path.join(WORK, 'v2_materials_mockup.tmx')
    open(out, 'w', encoding='utf-8', newline='\n').write(tmx)

    print('[v2-mockup] tile16=%d props=%d 续用表=%s' % (
        n_tiles, n_props, [(ts['name'], nf) for ts, nf in kept]))
    print('[v2-mockup] 预摆=仅城墙段（用户拍板：不留 AI 模板）')
    print('[v2-mockup] → %s (%.1f KB)' % (out, os.path.getsize(out) / 1024))


if __name__ == '__main__':
    main()
