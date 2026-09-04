import struct, zlib

def load_png(p):
    with open(p, "rb") as f: data = f.read()
    pos = 8; w=h=None; idat=b""; channels=4
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]; chunk = data[pos+8:pos+8+ln]
        if typ == b"IHDR":
            w,h,bd,ct = struct.unpack(">IIBB", chunk[:10])
            channels = {0:1,2:3,3:1,4:2,6:4}[ct]
        elif typ == b"IDAT": idat += chunk
        elif typ == b"IEND": break
        pos += 12+ln
    raw = zlib.decompress(idat); stride = w*channels
    rows=[]; prev=bytearray(stride); ppos=0
    for y in range(h):
        ft = raw[ppos]; line = bytearray(raw[ppos+1:ppos+1+stride]); ppos += 1+stride
        if ft==1:
            for i in range(channels,stride): line[i]=(line[i]+line[i-channels])&255
        elif ft==2:
            for i in range(stride): line[i]=(line[i]+prev[i])&255
        elif ft==3:
            for i in range(stride):
                l=line[i-channels] if i>=channels else 0
                line[i]=(line[i]+(l+prev[i])//2)&255
        elif ft==4:
            for i in range(stride):
                a=line[i-channels] if i>=channels else 0; b=prev[i]; c=prev[i-channels] if i>=channels else 0
                pp=a+b-c; pa,pb,pc=abs(pp-a),abs(pp-b),abs(pp-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i]=(line[i]+pr)&255
        prev=line
        rows.append(line)
    return w,h,rows,channels

def tile_rgba(rows, tx, ty, ts, ch):
    r=g=b=n=al=0
    for y in range(ty*ts,(ty+1)*ts):
        line=rows[y]
        for x in range(tx*ts,(tx+1)*ts):
            o=x*ch; r+=line[o]; g+=line[o+1]; b+=line[o+2]; al+=line[o+3]; n+=1
    return "#%02x%02x%02x a%d" % (r//n, g//n, b//n, al//n)

base="downloaded_assets/Pixel Crawler - Free Pack/Environment/Tilesets/"
w,hh,rows,ch = load_png(base+"Floors_Tiles.png")
print("--- FLOORS key tiles (tx,ty): color ---")
for tx,ty in [(1,1),(2,1),(3,1),(1,2),(2,2),(3,2),(1,3),(2,3),(3,3),
              (7,1),(8,1),(7,2),(8,2),(7,3),(8,3),
              (1,6),(2,6),(1,7),(2,7),
              (1,11),(2,11),(1,12),(2,12),(1,13),(2,13),(1,14),(2,14)]:
    print("floors(%d,%d) %s" % (tx,ty,tile_rgba(rows,tx,ty,16,ch)))
w2,h2,r2,c2 = load_png(base+"Water_tiles.png")
print("--- WATER key tiles ---")
for tx,ty in [(1,1),(2,1),(6,1),(7,1),(1,2),(6,2),
              (1,6),(2,6),(3,6),(1,7),(2,7),
              (1,11),(2,11),(3,11),(1,12),(2,12),
              (6,6),(7,6),(6,11),(7,11)]:
    print("water(%d,%d) %s" % (tx,ty,tile_rgba(r2,tx,ty,16,c2)))
