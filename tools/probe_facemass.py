# -*- coding: utf-8 -*-
"""头部区域内肤色像素质量偏移 -> 判定Side表原生朝向"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

BASE = os.path.join(ipa.PACK,"Entities","Characters","Body_A","Animations")

def analyze(path, fi):
    w,h,rows = ipa.load_png(path)
    fw=h
    fr = ipa.crop(rows,fw,h,fi,False)
    pts=[]
    for y in range(h):
        r=fr[y]
        for x in range(fw):
            o=x*4
            if o+3>=len(r) or r[o+3]<10: continue
            c=(r[o],r[o+1],r[o+2])
            if ipa._is_skin((c[0],c[1],c[2],r[o+3])): pts.append((x,y))
    if not pts: return None
    ys=[p[1] for p in pts]
    top=min(ys); bot=max(ys); charH=bot-top+1
    hy1=top+int(charH*0.45)
    head=[p for p in pts if p[1]<=hy1]
    if not head: return None
    hx0=min(p[0] for p in head); hx1=max(p[0] for p in head)
    hcx=(hx0+hx1)/2.0
    cx=sum(p[0] for p in head)/len(head)
    lm=sum(1 for p in head if p[0]<hcx); rm=sum(1 for p in head if p[0]>=hcx)
    off=cx-hcx
    return dict(f=fi, n=len(head), head_span=(hx0,hx1), centroid_off=round(off,2),
                L=lm, R=rm, verdict="RIGHT" if off>0.8 else ("LEFT" if off<-0.8 else "~sym"))

for name,sub,nf in [("Walk_Side","Walk_Base/Walk_Side-Sheet.png",6),
                    ("Idle_Side","Idle_Base/Idle_Side-Sheet.png",4),
                    ("Idle_Down","Idle_Base/Idle_Down-Sheet.png",2),
                    ("Run_Side","Run_Base/Run_Side-Sheet.png",6)]:
    print("==",name)
    for fi in range(nf):
        r=analyze(os.path.join(BASE,sub),fi)
        print("  ",r)
