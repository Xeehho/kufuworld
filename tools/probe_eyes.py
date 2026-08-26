# -*- coding: utf-8 -*-
"""用眼睛像素(头部肤色区内的暗点)判定Side表原生朝向"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

BASE = os.path.join(ipa.PACK,"Entities","Characters","Body_A","Animations")

def analyze(path, fi):
    w,h,rows = ipa.load_png(path)
    fw = h  # 帧宽=表高(方形帧)
    fr = ipa.crop(rows,fw,h,fi,False)
    # 收集肤像素与暗像素
    skins=[]; darks=[]
    for y in range(h):
        r=fr[y]
        for x in range(fw):
            o=x*4
            if o+3>=len(r): continue
            if r[o+3]<10: continue
            c=(r[o],r[o+1],r[o+2])
            if ipa._is_skin((c[0],c[1],c[2],r[o+3])): skins.append((x,y))
            elif c[0]<75 and c[1]<75 and c[2]<75: darks.append((x,y,c))
    if not skins: return "no skin"
    ys=[s[1] for s in skins]
    hy0=min(ys); hy1=hy0+int((max(ys)-hy0)*0.55)  # 头部区域=肤像素上部55%
    heads=[s for s in skins if s[1]<=hy1]
    hx0=min(s[0] for s in heads); hx1=max(s[0] for s in heads)
    hcx=(hx0+hx1)/2.0
    eyes=[d for d in darks if hx0<=d[0]<=hx1 and min(ys)<=d[1]<=hy1+3]
    eye_cx = sum(d[0] for d in eyes)/len(eyes) if eyes else -1
    return dict(frame=fi, head_bbox=(hx0,hx1), head_cx=hcx,
                eye_n=len(eyes), eye_cx=None if eye_cx<0 else round(eye_cx,1),
                facing="RIGHT" if eye_cx>hcx else ("LEFT" if eye_cx>=0 else "?"),
                offset=None if eye_cx<0 else round(eye_cx-hcx,1))

print("== Walk_Side (原生) ==")
for fi in range(6):
    print(analyze(os.path.join(BASE,"Walk_Base","Walk_Side-Sheet.png"), fi))
print("== Idle_Down (对称基准) ==")
print(analyze(os.path.join(BASE,"Idle_Base","Idle_Down-Sheet.png"), 0))
