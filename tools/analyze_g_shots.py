# -*- coding: utf-8 -*-
"""Phase G 截图审计：Y-sort遮挡差分(长袍像素) + 海岸/城镇调色板 sanity"""
import os, sys, zlib, struct
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

ROBE=(64,76,112); ROBE_D=(48,57,88)

def count_robe(path, cx=None, cy=None, half=160):
    w,h,rows = ipa.load_png(path)
    x0 = max(0,(w//2-half)) if cx is None else max(0,cx-half)
    x1 = min(w,(w//2+half)) if cx is None else min(w,cx+half)
    y0 = max(0,(h//2-half)) if cy is None else max(0,cy-half)
    y1 = min(h,(h//2+half)) if cy is None else min(h,cy+half)
    n=0
    for y in range(y0,y1):
        r=rows[y]
        for x in range(x0,x1):
            o=x*4
            if r[o+3]<10: continue
            c=(r[o],r[o+1],r[o+2])
            if ipa._dist2(c,ROBE)<=1400 or ipa._dist2(c,ROBE_D)<=1400:
                n+=1
    return n

T=os.path.join(ROOT,"tools")
s0=count_robe(os.path.join(T,"probe_g_shot_0.png"))
s1=count_robe(os.path.join(T,"probe_g_shot_1.png"))
print(f"robe px SOUTH(front)={s0}  NORTH(behind)={s1}")
print("Y-SORT OCCLUSION:", "WORKING" if s1 < s0*0.6 else ("WEAK" if s1<s0 else "BROKEN"))

def dominant(path):
    w,h,rows=ipa.load_png(path)
    from collections import Counter
    cnt=Counter()
    for y in range(0,h,3):
        r=rows[y]
        for x in range(0,w,3):
            o=x*4
            if r[o+3]<10: continue
            cnt[(r[o]//32,r[o+1]//32,r[o+2]//32)]+=1
    return [(tuple(v*32 for v in k),n) for k,n in cnt.most_common(6)]

for i,name in [(2,"coast"),(3,"town")]:
    p=os.path.join(T,f"probe_g_shot_{i}.png")
    print(f"shot{i}({name}) dominant:", dominant(p))

# 海岸图：树冠绿是否出现在水面蓝区域(粗检)：绿色系(g>r+15,g>b+15)与蓝色系(b>r+30,b>g+20)像素的水平相邻混合计数
w,h,rows=ipa.load_png(os.path.join(T,"probe_g_shot_2.png"))
def cls(px):
    r,g,b=px
    if g>r+15 and g>b+15: return "G"
    if b>r+30 and b>g+20: return "B"
    return "."
mix=0
for y in range(0,h,2):
    prev="."
    row=rows[y]
    for x in range(w):
        c=cls(tuple(row[x*4:x*4+3]))
        if c!="." and prev!="." and c!=prev:
            mix+=1
        if c!=".": prev=c
print(f"coast G/B adjacency transitions={mix} (小值≈水岸无树冠悬伸)")
