# 生成 Tiled 底图：15 个 .tsx 图块集 + changan_mockup.tmx（SCKR 京城/江南包，16px 网格）
# 纯数据工作文件，不属于项目代码。重跑即可重建。
import os
import re
import struct
import xml.etree.ElementTree as ET

NL = chr(10)  # 避免任何转义歧义

ROOT = os.path.dirname(os.path.abspath(__file__))
for _ in range(3):  # tiled_work → 参考 → docs → 项目根
    ROOT = os.path.dirname(ROOT)
WORK = os.path.join(ROOT, 'docs', '参考', 'tiled_work')
os.makedirs(WORK, exist_ok=True)


def png_size(path):
    with open(path, 'rb') as f:
        head = f.read(24)
    w, h = struct.unpack('>II', head[16:24])
    return w, h


PACK = {'jingcheng': '京城', 'jiangnan': '江南', 'jiangnan_dlc': '江南DLC',
        'modern_city': '现代都市', 'modern_residential': '现代住宅',
        'wuxia': '武侠', 'wuxia_dlc': '武侠DLC', 'wuxia_interior_dlc': '武侠内景'}


def sheet_name(sub, fn):
    m = re.search(r'[Ww]alls-(\d+)', fn)
    if m:
        return '%s-墙%s' % (PACK[sub], m.group(1))
    m = re.match(r'Tile_A2(?:-(\d))?', fn)
    if m:
        return '%s-A2%s' % (PACK[sub], ('-' + m.group(1)) if m.group(1) else '')
    return '%s-B%s' % (PACK[sub], fn[7:9])


# 前 15 张保持原始顺序（保证 GID 编号与历史文件一致），其余全包扫描追加
old = ([('jingcheng', 'Auto-tile-A4-Walls-1.png'), ('jingcheng', 'Auto-tile-A4-walls-5.png')]
       + [('jingcheng', 'tile-B-0%d.png' % i) for i in range(1, 8)]
       + [('jiangnan', 'Auto-tile-A4-walls-5.png')]
       + [('jiangnan', 'tile-B-0%d.png' % i) for i in range(1, 6)])
registered = set(old)
ordered = list(old)
for sub in sorted(os.listdir(os.path.join(ROOT, 'downloaded_assets', 'comshadow_bundle'))):
    base = os.path.join(ROOT, 'downloaded_assets', 'comshadow_bundle', sub)
    if not os.path.isdir(base):
        continue
    for f in sorted(os.listdir(base)):
        if f.lower().endswith('.png') and (sub, f) not in registered:
            ordered.append((sub, f))

sheets = []
for sub, f in ordered:
    rel = 'downloaded_assets/comshadow_bundle/%s/%s' % (sub, f)
    w, h = png_size(os.path.join(ROOT, rel))
    tw, th = w // 16, h // 16
    assert w % 16 == 0 and h % 16 == 0, rel
    sheets.append((sheet_name(sub, f), rel, tw, th, tw * th))

# --- .tsx 图块集 ---
tsx_names = []
for i, (name, rel, tw, th, cnt) in enumerate(sheets):
    tsx = 'ts_%02d.tsx' % i
    xml_lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<tileset version="1.10" tiledversion="1.12.2" name="%s" '
        'tilewidth="16" tileheight="16" tilecount="%d" columns="%d">' % (name, cnt, tw),
        ' <image source="../../../%s" width="%d" height="%d"/>' % (rel, tw * 16, th * 16),
        '</tileset>',
    ]
    with open(os.path.join(WORK, tsx), 'w', encoding='utf-8') as fh:
        fh.write(NL.join(xml_lines) + NL)
    tsx_names.append(tsx)

# --- .tmx 地图（100x60 固定，三层 + 标注对象层）---
W, H = 100, 60
tilesets_xml = []
firstgids = []
gid = 1
for (name, rel, tw, th, cnt), tsx in zip(sheets, tsx_names):
    tilesets_xml.append(' <tileset firstgid="%d" source="%s"/>' % (gid, tsx))
    firstgids.append((name, gid, cnt))
    gid += cnt

rows = [','.join(['0'] * W) for _ in range(H)]
# 图层数据用 base64+zlib（实测本机 Tiled 1.12.2 渲染器对 csv 编码会失败，base64 正常）
import base64
import zlib as _zlib
layers_xml = []
for lid, lname in [(1, '地面'), (2, '建筑'), (3, '道具')]:
    raw = b''.join((0).to_bytes(4, 'little') for _ in range(W * H))
    b64 = base64.b64encode(_zlib.compress(raw)).decode('ascii')
    layers_xml.append(
        ' <layer id="%d" name="%s" width="%d" height="%d">' % (lid, lname, W, H)
        + NL + '  <data encoding="base64" compression="zlib">' + NL
        + b64 + NL + '  </data>' + NL + ' </layer>')

tmx_lines = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<map version="1.10" tiledversion="1.12.2" orientation="orthogonal" renderorder="right-down" '
    'width="%d" height="%d" tilewidth="16" tileheight="16" infinite="0" '
    'nextlayerid="5" nextobjectid="1">' % (W, H),
] + tilesets_xml + layers_xml + [
    ' <objectgroup id="4" name="标注" color="#ff0000"/>',
    '</map>',
]
with open(os.path.join(WORK, 'changan_mockup.tmx'), 'w', encoding='utf-8') as fh:
    fh.write(NL.join(tmx_lines) + NL)

# --- 自校验 ---
m = ET.parse(os.path.join(WORK, 'changan_mockup.tmx')).getroot()
for layer in m.findall('layer'):
    data = layer.find('data')
    assert data.get('encoding') == 'base64'
    raw = _zlib.decompress(base64.b64decode(''.join(data.text.split())))
    cells = [int.from_bytes(raw[i:i+4], 'little') for i in range(0, len(raw), 4)]
    assert len(cells) == W * H and set(cells) == {0}, layer.get('name')
for ts in m.findall('tileset'):
    assert os.path.isfile(os.path.join(WORK, ts.get('source')))
    t = ET.parse(os.path.join(WORK, ts.get('source'))).getroot()
    img = os.path.normpath(os.path.join(WORK, t.find('image').get('source')))
    assert os.path.isfile(img), img

print('生成并自校验通过：%d 个图块集 + changan_mockup.tmx（%dx%d 瓦，3 图块层 + 标注层）' % (len(sheets), W, H))
for name, g, c in firstgids:
    print('  GID %6d 起  %s（%d 块）' % (g, name, c))
