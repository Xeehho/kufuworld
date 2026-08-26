import struct, zlib, colorsys

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

def avg_tile(rows, tx, ty, ts, channels):
    r=g=b=n=0
    for y in range(ty*ts,(ty+1)*ts):
        line=rows[y]
        for x in range(tx*ts,(tx+1)*ts):
            o=x*channels; r+=line[o]; g+=line[o+1]; b+=line[o+2]; n+=1
    return (r//n, g//n, b//n)

def name_color(c):
    r,g,b = c
    h,l,s = colorsys.rgb_to_hls(r/255,g/255,b/255)
    hd = h*360
    if s < 0.15:
        if l > 0.75: return "white"
        if l > 0.45: return "gray"
        return "dark"
    if hd < 25 or hd >= 340: return "red"
    if hd < 50: return "orange/brown"
    if hd < 70: return "yellow/tan"
    if hd < 160: return "green"
    if hd < 250: return "blue"
    return "purple"

base="downloaded_assets/Pixel Crawler - Free Pack/Environment/Tilesets/"
for fname, ts in [("Floors_Tiles.png",16),("Water_tiles.png",16),("Wall_Tiles.png",16)]:
    w,h,rows,ch = load_png(base+fname)
    cols=w//ts; rows_n=h//ts
    print("=== "+fname+" grid %dx%d ===" % (cols, rows_n))
    for ty in range(rows_n):
        line=""
        for tx in range(cols):
            c = avg_tile(rows,tx,ty,ts,ch)
            nm = name_color(c)
            ch1 = {"white":"W","gray":"G","dark":"D","red":"R","orange/brown":"B","yellow/tan":"T","green":"g","blue":"w","purple":"P"}[nm]
            line += ch1
        print("%2d %s" % (ty, line))
