# -*- coding: utf-8 -*-
"""扫描 Floors_Tiles.png 每格统计：找出均匀填充瓦片候选（低std+高alpha），按色系分组输出
一次性分析工具，供画面改造 P1.0 选格用"""
import os, struct, zlib, math

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

w,h,rows = load_png(os.path.join(PACK, "Environment", "Tilesets", "Floors_Tiles.png"))
TS=16
print("sheet %dx%d = %d cols x %d rows" % (w,h,w//TS,h//TS))

def cell_stats(tx,ty):
    rs=gs=bs=0; n=0; vals=[]
    for y in range(ty*TS,(ty+1)*TS):
        row=rows[y]
        for x in range(tx*TS,(tx+1)*TS):
            o=x*4
            r,g,b,a=row[o],row[o+1],row[o+2],row[o+3]
            if a<128: return None  # 有透明→非填充格
            rs+=r; gs+=g; bs+=b; n+=1
            vals.append((r,g,b))
    mr,mg,mb=rs/n,gs/n,bs/n
    var=sum((r-mr)**2+(g-mg)**2+(b-mb)**2 for r,g,b in vals)/n
    return (round(mr),round(mg),round(mb),round(math.sqrt(var),1))

def classify(c):
    r,g,b,_=c
    if r>200 and g>200 and b>200: return "snow/white"
    if g>r and g>b and g>60: return "green"
    if r>g>b and r>140: return "sand/tan"
    if r>100 and g>70 and b<80: return "brown/dirt"
    if abs(r-g)<18 and abs(g-b)<18: return "gray/stone"
    if b>r and b>g: return "blue"
    return "other"

groups={}
for ty in range(h//TS):
    for tx in range(w//TS):
        s=cell_stats(tx,ty)
        if s is None: continue
        mr,mg,mb,std=s
        if std>14: continue  # 只要均匀填充
        k=classify(s)
        groups.setdefault(k,[]).append((tx,ty,mr,mg,mb,std))

for k in ["green","sand/tan","brown/dirt","snow/white","gray/stone"]:
    lst=groups.get(k,[])
    print("\n== %s (%d格) ==" % (k,len(lst)))
    # 按均值颜色聚合输出（相邻近色合并展示）
    for tx,ty,r,g,b,std in sorted(lst,key=lambda t:(t[4],t[1],t[0])):
        print("  (%2d,%2d) rgb=%3d,%3d,%3d std=%.1f" % (tx,ty,r,g,b,std))

# 当前在用的基格参考
print("\n== 当前基格 ==")
for name,(tx,ty) in {"grass":(2,10),"grass_dark":(1,11),"path":(6,10),"sand":(6,23),"snow":(2,24)}.items():
    s=cell_stats(tx,ty)
    print("  %s (%d,%d) -> %s" % (name,tx,ty,s))
