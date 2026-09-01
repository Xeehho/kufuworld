# -*- coding: utf-8 -*-
"""Water_tiles.png 精确分析：
1. 全格分类（水填充/岸环含草或棕边/空）
2. 检测填充区动画帧（相邻列同格图案微差=波纹位移帧）
3. 首岛(0..3,0..3)环块的内容分布（草/棕/泡沫占比→方向映射）"""
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

w,h,rows = load_png(os.path.join(PACK, "Environment", "Tilesets", "Water_tiles.png"))
TS=16
def cell_img(tx,ty):
    return [rows[ty*TS+y][tx*TS*4:(tx+1)*TS*4] for y in range(TS)]

def classify(tx,ty):
    img=cell_img(tx,ty)
    blue=green=brown=foam=0
    for y in range(TS):
        row=img[y]
        for x in range(TS):
            o=x*4; r,g,b,a=row[o],row[o+1],row[o+2],row[o+3]
            if a<10: continue
            if b>140 and b>r+30 and g>110: blue+=1
            elif g>90 and g>r+20 and g>b+20: green+=1
            elif r>110 and r>b+40 and g<b+60: brown+=1
            elif r>180 and g>200 and b>220: foam+=1
    tot=blue+green+brown+foam
    if tot<40: return None  # 空
    return {"blue":blue,"green":green,"brown":brown,"foam":foam}

# 1) 全表地图
print("== 全表分类 (列0-24 x 行0-24) G=含草 B=含棕 f=含泡沫 .=纯水 x=空 ==")
for ty in range(h//TS):
    line=""
    for tx in range(w//TS):
        c=classify(tx,ty)
        if c is None: line+="x"
        elif c["green"]>30: line+="G"
        elif c["brown"]>30: line+="B"
        elif c["foam"]>10: line+="f"
        else: line+="."
    print("%2d %s" % (ty,line))

# 2) 填充区动画帧检测：取纯水格，比较 (6,7) 与右侧同行各列的像素差
def diff(c1,c2):
    d=0
    for y in range(TS):
        for x in range(TS):
            o=x*4
            d+=abs(c1[y][o]-c2[y][o])+abs(c1[y][o+1]-c2[y][o+1])+abs(c1[y][o+2]-c2[y][o+2])
    return d//(TS*TS)

print("\n== 纯水填充格与 (6,7) 的平均差（找动画帧列）==")
base=cell_img(6,7)
for ty in [5,6,7,8,9,10,11]:
    rowtxt=[]
    for tx in range(0,12):
        c=classify(tx,ty)
        if c is None or c["green"]>30 or c["brown"]>30: rowtxt.append("  --")
        else:
            rowtxt.append("%4d"%diff(base,cell_img(tx,ty)))
    print("row %2d: %s" % (ty, " ".join(rowtxt)))

# 3) 首岛 4x4 环块象限内容（草在哪个角/边）
print("\n== 首岛(0..3,0..3) 每格草像素分布（上下左右四象限计数）==")
for ty in range(4):
    for tx in range(4):
        img=cell_img(tx,ty)
        q={"N":0,"S":0,"E":0,"W":0}
        for y in range(TS):
            for x in range(TS):
                o=x*4; r,g,b,a=img[y][o],img[y][o+1],img[y][o+2],img[y][o+3]
                if g>90 and g>r+20 and g>b+20:
                    if y<8: q["N"]+=1
                    else: q["S"]+=1
                    if x<8: q["W"]+=1
                    else: q["E"]+=1
        print("(%d,%d) N=%3d S=%3d W=%3d E=%3d" % (tx,ty,q["N"],q["S"],q["W"],q["E"]))
