# -*- coding: utf-8 -*-
"""用下半头轮廓凸出量(鼻/ chin)判定Side表原生朝向"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

BASE = os.path.join(ipa.PACK,"Entities","Characters","Body_A","Animations")

def analyze(path, fi):
    w,h,rows = ipa.load_png(path)
    fw=h
    fr = ipa.crop(rows,fw,h,fi,False)
    op=[]
    for y in range(h):
        r=fr[y]
        xs=[x for x in range(fw) if r[x*4+3]>10]
        op.append((y,xs))
    ys=[y for y,xs in op if xs]
    top=min(ys); bot=max(ys)
    charH=bot-top+1
    # 头部区域: 顶部到45%身高
    hy1=top+int(charH*0.45)
    def edges(y):
        for yy,xs in op:
            if yy==y: return (min(xs),max(xs)) if xs else None
        return None
    # 上半头基线(20%~32%身高处边缘中位数)
    import statistics
    upL=[]; upR=[]
    for frac in [0.18,0.22,0.26,0.30]:
        e=edges(top+int(charH*frac))
        if e: upL.append(e[0]); upR.append(e[1])
    Lb=statistics.median(upL); Rb=statistics.median(upR)
    # 下半头(33%~44%)最大外凸
    pL=0; pR=0
    for frac in [0.33,0.36,0.39,0.42]:
        e=edges(top+int(charH*frac))
        if not e: continue
        pL=max(pL, Lb-e[0])   # 向左凸出
        pR=max(pR, e[1]-Rb)   # 向右凸出
    return dict(frame=fi, base=(Lb,Rb), protL=pL, protR=pR,
                verdict="RIGHT" if pR>pL else ("LEFT" if pL>pR else "TIE"))

for name,sub in [("Walk_Side","Walk_Base/Walk_Side-Sheet.png"),
                 ("Idle_Side","Idle_Base/Idle_Side-Sheet.png")]:
    print("==",name)
    for fi in range(6):
        print(analyze(os.path.join(BASE,sub), fi))
