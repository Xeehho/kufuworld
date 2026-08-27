# -*- coding: utf-8 -*-
"""逐瓦片分类图 + 候选瓦片montage，用于精确选材坐标"""
import os, struct, zlib, sys

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

def classify(rows, tx, ty, ts=16):
    """返回 (类别字母, 均匀度0-9)"""
    h = len(rows); w = len(rows[0])//4
    if (ty+1)*ts > h or (tx+1)*ts > w: return ("-", 0)
    rs=gs=bs=n=0; als=0; vals=[]
    for y in range(ty*ts,(ty+1)*ts):
        line=rows[y]
        for x in range(tx*ts,(tx+1)*ts):
            o=x*4; r,g,b,a=line[o],line[o+1],line[o+2],line[o+3]
            rs+=r; gs+=g; bs+=b; als+=a; n+=1; vals.append((r,g,b))
    if als/n < 30: return ("K", 0)  # 空
    mr,mg,mb = rs/n,gs/n,bs/n
    var = sum((a1-mr)**2+(a2-mg)**2+(a3-mb)**2 for a1,a2,a3 in vals)/n
    std = var**0.5
    uni = max(0, 9-int(std/12))
    r,g,b = mr,mg,mb
    if g>r+12 and g>b+12: return ("D" if g<110 else "G", uni)
    if b>r+25 and b>g+10: return ("U", uni)
    if r>g+15 and g>b+10: return ("B" if r<150 else "O", uni)  # 棕/橙
    if r>200 and g>180 and b<160: return ("O", uni)
    if abs(r-g)<18 and abs(g-b)<18:
        if r>200: return ("W", uni)
        if r>120: return ("S", uni)
        return ("s", uni)  # 深灰
    if r>140 and b>120 and g<r-20 and g<b-10: return ("P", uni)
    if r>g>b and r-b<25: return ("t", uni)  # 棕木/土淡
    return ("?", uni)

def cmap(rel, ts=16):
    w,h,rows = load_png(os.path.join(PACK, rel.replace("/", os.sep)))
    print("=== %s %dx%d (%dx%d tiles) ===" % (rel, w, h, w//ts, h//ts))
    for ty in range(h//ts):
        line=""
        for tx in range(w//ts):
            c,u = classify(rows, tx, ty, ts)
            line += c if u>=6 else c.lower()
        print("%2d %s" % (ty, line))
    print("    " + "".join(str(i%10) for i in range(w//ts)))

def crop_tile(rows, tx, ty, ts=16):
    return [rows[ty*ts+i][tx*ts*4:(tx+1)*ts*4] for i in range(ts)]

def montage(rel, coords, out_name, mag=8, ts=16):
    """候选瓦片montage：每瓦片上放一行，左侧留8px写不了字就靠顺序"""
    w,h,rows = load_png(os.path.join(PACK, rel.replace("/", os.sep)))
    mw = 10 + ts*mag + 10
    mh = len(coords)*(10 + ts*mag + 6)
    out=[bytearray(b"\x18\x14\x10\xff"*mw) for _ in range(mh)]
    for i,(tx,ty) in enumerate(coords):
        tile = crop_tile(rows, tx, ty, ts)
        y0 = i*(10+ts*mag+6)+10
        for dy in range(ts*mag):
            line = out[y0+dy]
            src = tile[dy//mag]
            for dx in range(ts*mag):
                o=(10+dx)*4; s=dx//mag*4
                line[o:o+4]=src[s:s+4]
    save_png(os.path.join(OUT,out_name), mw, mh, out)
    print("montage %s: %s" % (out_name, coords))

if __name__=="__main__":
    which = sys.argv[1] if len(sys.argv)>1 else "maps"
    if which in ("maps","all"):
        cmap("Environment/Tilesets/Floors_Tiles.png")
        cmap("Environment/Tilesets/Water_tiles.png")
        cmap("Environment/Tilesets/Wall_Tiles.png")
        cmap("Environment/Props/Static/Vegetation.png")
        cmap("Environment/Structures/Buildings/Props.png")
        cmap("Environment/Structures/Buildings/Walls.png")
        cmap("Environment/Structures/Buildings/Roofs.png")
        cmap("Environment/Props/Static/Rocks.png")
    if which in ("mont","all"):
        montage("Environment/Structures/Buildings/Walls.png",
                [(21,12),(22,12),(23,12),(24,12),(26,12),(27,12),(2,2),(3,2),(6,2),(7,2),(2,28),(3,28)], "cand_walls.png", mag=5)
        montage("Environment/Structures/Buildings/Roofs.png",
                [(10,12),(11,12),(12,12),(13,12),(11,3),(12,3),(13,3),(12,2),(13,2),(11,13),(12,13)], "cand_roofs.png", mag=5)
        montage("Environment/Structures/Buildings/Props.png",
                [(6,2),(7,2),(6,3),(7,3),(6,4),(7,4),(6,5),(7,5),(3,2),(3,3),(10,4),(11,4),(12,4),(13,4),(1,9),(2,9),(1,10),(2,10),(3,11),(4,11)], "cand_props.png", mag=5)
        montage("Environment/Props/Static/Vegetation.png",
                [(12,10),(13,10),(12,11),(13,11),(14,10),(3,21),(7,21),(3,23),(3,24),(6,23),(7,23),(5,9),(6,9),(6,10),(7,10)], "cand_veg.png", mag=5)
        montage("Environment/Props/Static/Rocks.png",
                [(4,2),(5,2),(8,2),(9,2),(4,3),(7,3),(8,3),(9,3),(10,2),(11,2),(4,5),(5,5)], "cand_rocks.png", mag=5)
        montage("Environment/Tilesets/Floors_Tiles.png",
                [(1,10),(2,10),(1,11),(6,10),(7,10),(1,12),(2,12),(17,1),(18,1),(17,2),(2,22),(6,22),(2,24)], "cand_floors.png", mag=5)
        montage("Environment/Tilesets/Wall_Tiles.png",
                [(1,1),(2,2),(8,2),(9,3),(1,16),(2,16),(1,17),(7,16),(8,16),(7,17),(13,16),(14,16),(0,8),(6,8),(1,21),(7,21)], "cand_wallsheet.png", mag=5)

