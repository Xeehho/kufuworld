# -*- coding: utf-8 -*-
"""对 TREE_SHEETS 三张树的每格变体做主导色分类（春绿/秋橙/枯木/雪白），输出季节映射表"""
import os, struct, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "downloaded_assets", "Pixel Crawler - Free Pack")

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

TREES = [
    ("松4", "Environment/Props/Static/Trees/Model_03/Size_02.png", 4, 2),
    ("橡8", "Environment/Props/Static/Trees/Model_01/Size_02.png", 4, 2),
    ("竹9", "Environment/Props/Static/Trees/Model_02/Size_03.png", 3, 2),
]
for tag, rel, gx, gy in TREES:
    w,h,rows = load_png(os.path.join(PACK, rel.replace("/", os.sep)))
    cw, chh = w//gx, h//gy
    print("== %s %s (%dx%d 格, 每格%dx%d) ==" % (tag, os.path.basename(rel), gx, gy, cw, chh))
    for vy in range(gy):
        for vx in range(gx):
            rg=ro=rt=rw=0   # 绿/橙/枯褐/白
            tot=0
            for y in range(chh):
                for x in range(cw):
                    o=((vx*cw+x)*4)+((vy*chh+y)*w*4)
                    r,g,b,a = rows[vy*chh+y][(vx*cw+x)*4], rows[vy*chh+y][(vx*cw+x)*4+1], rows[vy*chh+y][(vx*cw+x)*4+2], rows[vy*chh+y][(vx*cw+x)*4+3]
                    if a<128: continue
                    tot+=1
                    if g>95 and g>r+15 and g>b+15: rg+=1
                    elif r>120 and r>g+25 and r>b+25: ro+=1
                    elif r>140 and g>200 and b>200: rw+=1
                    elif r>90 and g>60 and b<80 and abs(r-g)<60: rt+=1
            if tot==0: cls="空"
            elif rw>tot*0.10: cls="雪"
            elif rt>tot*0.25 and rg<tot*0.15: cls="枯"
            elif ro>tot*0.20 and ro>=rg: cls="秋"
            else: cls="春"
            print("  变体%d (col%d,row%d): 绿=%d 橙=%d 枯=%d 白=%d 总=%d -> %s" % (vy*gx+vx, vx, vy, rg, ro, rt, rw, tot, cls))
