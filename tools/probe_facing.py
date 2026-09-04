# -*- coding: utf-8 -*-
"""判断Body_A的Side表原生朝向：裸皮(脸/手)质心相对身体bbox中心的偏移"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

def skin_centroid(path):
    w,h,rows = ipa.load_png(path)
    sx=sy=n=0; minx,miny,maxx,maxy = w,h,-1,-1
    for y in range(h):
        row=rows[y]
        for x in range(w):
            o=x*4
            if row[o+3]<10: continue
            minx=min(minx,x);maxx=max(maxx,x);miny=min(miny,y);maxy=max(maxy,y)
            c=(row[o],row[o+1],row[o+2])
            if ipa._is_skin((c[0],c[1],c[2],row[o+3])):
                sx+=x; sy+=y; n+=1
    if n==0: return None
    cx = sx/n
    bcx = (minx+maxx)/2.0
    return dict(file=os.path.basename(path), skin_n=n, skin_cx=round(cx,1),
                body_bbox=(minx,maxx), body_cx=round(bcx,1),
                offset=round(cx-bcx,1))

P=os.path.join(ipa.SPR,"player")
for f in ["idle_right_0","idle_right_1","walk_right_0","walk_right_2",
          "idle_left_0","walk_left_0","idle_down_0"]:
    p=os.path.join(P,f+".png")
    print(skin_centroid(p) if os.path.exists(p) else f+" MISSING")

# 同时看原始Side表frame0（未着装、未镜像）
src=os.path.join(ipa.PACK,"Entities","Characters","Body_A","Animations","Walk_Base","Walk_Base_Side-Sheet.png")
if os.path.exists(src):
    w,h,rows=ipa.load_png(src)
    fr=ipa.crop(rows,h,h,0,False)
    tmp=os.path.join(ROOT,"tools","_raw_side_f0.png")
    ipa.save_png(tmp,h,h,fr)
    print("RAW Side frame0:", skin_centroid(tmp))
