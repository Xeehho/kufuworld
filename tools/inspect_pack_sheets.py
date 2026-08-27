# -*- coding: utf-8 -*-
"""放大关键材质包sheet并画16px网格线，输出到 .trae/sheet_preview/ 供视觉确认"""
import os, struct, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "downloaded_assets", "Pixel Crawler - Free Pack")
OUT = os.path.join(ROOT, ".trae", "sheet_preview")

def load_png(p):
    with open(p, "rb") as f: data = f.read()
    pos = 8; w=h=None; idat=b""; ch=4
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]; chunk = data[pos+8:pos+8+ln]
        if typ == b"IHDR":
            w,h,bd,ct = struct.unpack(">IIBB", chunk[:10]); ch={0:1,2:3,3:1,4:2,6:4}[ct]
        elif typ == b"IDAT": idat += chunk
        elif typ == b"IEND": break
        pos += 12+ln
    raw = zlib.decompress(idat); stride=w*ch
    rows=[]; prev=bytearray(stride); pp=0
    for y in range(h):
        ft=raw[pp]; line=bytearray(raw[pp+1:pp+1+stride]); pp+=1+stride
        if ft==1:
            for i in range(ch,stride): line[i]=(line[i]+line[i-ch])&255
        elif ft==2:
            for i in range(stride): line[i]=(line[i]+prev[i])&255
        elif ft==3:
            for i in range(stride):
                l=line[i-ch] if i>=ch else 0
                line[i]=(line[i]+(l+prev[i])//2)&255
        elif ft==4:
            for i in range(stride):
                a=line[i-ch] if i>=ch else 0; b=prev[i]; c=prev[i-ch] if i>=ch else 0
                p2=a+b-c; pa,pb,pc=abs(p2-a),abs(p2-b),abs(p2-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i]=(line[i]+pr)&255
        prev=line
        if ch==4: rows.append(bytes(line))
        else:
            ext=bytearray()
            for x in range(w):
                o=x*ch
                ext+=bytes([line[o], line[o+1] if ch>1 else 0, line[o+2] if ch>2 else 0, 255])
            rows.append(bytes(ext))
    return w,h,rows

def chunk_out(typ, data):
    return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ+data)&0xffffffff)

def save_png(path, w, h, rgba_rows):
    raw = b"".join(b"\x00"+bytes(r[:w*4]) for r in rgba_rows)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path,"wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk_out(b"IHDR", ihdr))
        f.write(chunk_out(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk_out(b"IEND", b""))

def magnify(rows, w, h, scale, ts):
    ow, oh = w*scale, h*scale
    out=[]
    for y in range(oh):
        sy = y//scale
        line = bytearray()
        for x in range(ow):
            sx = x//scale
            if sx < w:
                o = sx*4
                line += rows[sy][o:o+4]
            else:
                line += b"\x00\x00\x00\x00"
        # 网格线：每 ts*scale 像素画红色半透明线
        if y % (ts*scale) == 0:
            for i in range(0, len(line), 4):
                line[i] = 255; line[i+1] = 0; line[i+2] = 0; line[i+3] = 255
        # 每256px(即16格)用黄色粗线
        elif y % (ts*scale*16) == 0:
            for i in range(0, len(line), 4):
                line[i] = 255; line[i+1] = 255; line[i+2] = 0; line[i+3] = 255
        out.append(bytearray(line))
    # 竖线
    for ty in range(0, w//ts+1):
        x0 = ty*ts*scale
        for line in out:
            for dx in range(scale if ty%16 else scale+1):
                xx = x0+dx
                if xx < ow:
                    o = xx*4
                    line[o] = 255; line[o+1] = 0 if ty%16 else 255; line[o+2] = 0 if ty%16 else 255; line[o+3] = 255
    return out, ow, oh

SHEETS = [
    ("Environment/Tilesets/Floors_Tiles.png", 4),
    ("Environment/Tilesets/Water_tiles.png", 4),
    ("Environment/Tilesets/Wall_Tiles.png", 4),
    ("Environment/Tilesets/Wall_Variations.png", 4),
    ("Environment/Structures/Buildings/Walls.png", 4),
    ("Environment/Structures/Buildings/Roofs.png", 4),
    ("Environment/Structures/Buildings/Props.png", 4),
    ("Environment/Props/Static/Farm.png", 4),
    ("Environment/Props/Static/Vegetation.png", 4),
    ("Environment/Props/Static/Rocks.png", 4),
]

for rel, sc in SHEETS:
    p = os.path.join(PACK, rel.replace("/", os.sep))
    if not os.path.exists(p):
        print("MISS", rel); continue
    w,h,rows = load_png(p)
    out, ow, oh = magnify(rows, w, h, sc, 16)
    name = os.path.basename(rel).replace(".png", "_x%d.png"%sc)
    save_png(os.path.join(OUT, name), ow, oh, out)
    print("OK %s %dx%d -> %dx%d" % (name, w, h, ow, oh))
print("DONE")
