# -*- coding: utf-8 -*-
"""放大首岛5x5+相邻水格，标注格坐标，供岸环方向映射目检"""
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

w,h,rows = load_png(os.path.join(PACK, "Environment", "Tilesets", "Water_tiles.png"))
# 首岛 7x7 区域（含外圈水）放大12x，格坐标标签
X0,Y0,X1,Y1 = 0,0,7,7
SC=12; TS=16
pw=(X1-X0)*TS*SC; ph=(Y1-Y0)*TS*SC
out=[bytearray(pw*4) for _ in range(ph)]
for sy in range(ph):
    srcy=Y0*TS+sy//SC
    src=rows[srcy]
    line=out[sy]
    for sx in range(pw):
        srcx=X0*TS+sx//SC
        o=srcx*4; d=sx*4
        line[d:d+4]=src[o:o+4]
for gy in range(ph):
    if gy%(TS*SC)==0:
        line=out[gy]
        for xx in range(pw):
            o=xx*4; line[o]=255;line[o+1]=0;line[o+2]=0;line[o+3]=255
for gx in range(pw):
    if gx%(TS*SC)==0:
        for line in out:
            o=gx*4; line[o]=255;line[o+1]=0;line[o+2]=0;line[o+3]=255
save_png(os.path.join(OUT,"water_island1_x12.png"), pw, ph, out)
print("OK water_island1_x12.png %dx%d (格子=(0,0)-(6,6))" % (pw,ph))
