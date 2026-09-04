# -*- coding: utf-8 -*-
"""把 Vegetation.png 的候选装饰区域放大拼接输出，标注16px格坐标，供P1.3选格"""
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

w,h,rows = load_png(os.path.join(PACK, "Environment", "Props", "Static", "Vegetation.png"))

# 候选区: (标签, x0cell,y0cell, x1cell,y1cell)  cell坐标含头不含尾
REGIONS = [
    ("A_twigs",    16,0, 25,2),    # 顶部枯枝/落叶排
    ("B_plants",    0,9, 14,17),   # 小植物4色调区
    ("C_bottom",    0,20, 14,27),  # 蘑菇/小花/点状花区
]
SC=8; TS=16
for tag,cx0,cy0,cx1,cy1 in REGIONS:
    pw=(cx1-cx0)*TS*SC; ph=(cy1-cy0)*TS*SC
    out=[bytearray(pw*4) for _ in range(ph)]
    for sy in range(ph):
        srcy=cy0*TS + sy//SC
        if srcy>=h: continue
        src=rows[srcy]
        line=out[sy]
        for sx in range(pw):
            srcx=cx0*TS + sx//SC
            if srcx>=w: continue
            o=srcx*4; d=sx*4
            line[d:d+4]=src[o:o+4]
    # 网格线红，每5格黄粗
    for gy in range(0, ph):
        cell_y=gy//(TS*SC)
        if gy % (TS*SC) == 0:
            for xx in range(pw):
                o=xx*4
                if cell_y % 5 == 0: line=out[gy]; line[o]=255;line[o+1]=255;line[o+2]=0;line[o+3]=255
                else: line=out[gy]; line[o]=255;line[o+1]=0;line[o+2]=0;line[o+3]=255
    for gx in range(0, pw):
        cell_x=gx//(TS*SC)
        if gx % (TS*SC) == 0:
            for line in out:
                o=gx*4
                if cell_x % 5 == 0: line[o]=255;line[o+1]=255;line[o+2]=0;line[o+3]=255
                else: line[o]=255;line[o+1]=0;line[o+2]=0;line[o+3]=255
    save_png(os.path.join(OUT, "veg_%s_x8.png"%tag), pw, ph, out)
    print("OK veg_%s_x8.png cells=(%d,%d)-(%d,%d) %dx%d" % (tag,cx0,cy0,cx1,cy1,pw,ph))
print("DONE")
