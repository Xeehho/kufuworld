# -*- coding: utf-8 -*-
"""Phase G 探针: 玩家帧着装采样 + 树表尺寸审计 (只读, 不改任何产物)"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

SPR_P = os.path.join(ipa.SPR, "player")
ROBE=(64,76,112); ROBE_D=(48,57,88); SASH=(140,54,36); HAIR=(38,30,44)

def cloth_stats(path):
    w,h,rows = ipa.load_png(path)
    robe=sash=hair=skin=n=0
    minx,miny,maxx,maxy = w,h,-1,-1
    for y in range(h):
        row=rows[y]
        for x in range(w):
            o=x*4
            if row[o+3]<10: continue
            n+=1
            c=(row[o],row[o+1],row[o+2])
            minx=min(minx,x);maxx=max(maxx,x);miny=min(miny,y);maxy=max(maxy,y)
            if ipa._dist2(c,ROBE)<=900 or ipa._dist2(c,ROBE_D)<=900: robe+=1
            elif ipa._dist2(c,SASH)<=900: sash+=1
            elif ipa._dist2(c,HAIR)<=700: hair+=1
            elif ipa._is_skin((c[0],c[1],c[2],row[o+3])): skin+=1
    return dict(file=os.path.basename(path), opaque=n, robe=robe, sash=sash,
                hair=hair, bare_skin=skin, bbox=(minx,miny,maxx,maxy))

print("== PLAYER FRAMES on disk ==")
names=["idle_down_0","idle_up_0","walk_down_0","run_down_0",
       "walk_right_0","walk_right_1","walk_right_2","walk_right_3","walk_right_4","walk_right_5",
       "walk_left_0","walk_left_1","walk_left_2","walk_left_3","walk_left_4","walk_left_5",
       "idle_right_0","idle_right_1","idle_left_0","attack_right_0","attack_left_0",
       "hurt_right_0","hurt_left_0","death_right_0"]
for name in names:
    p=os.path.join(SPR_P,name+".png")
    if not os.path.exists(p):
        print(name,"MISSING"); continue
    print(cloth_stats(p))

print()
print("== TREE SHEETS ==")
sheets = {
 "pine_M03_S02":  os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_03","Size_02.png"),
 "oak_M01_S02":   os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_01","Size_02.png"),
 "bamboo_M02_S03":os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_02","Size_03.png"),
}
for k,v in sheets.items():
    print(k, "exists=", os.path.exists(v), end=" ")
    if os.path.exists(v):
        w,h,rows=ipa.load_png(v)
        print("size=%dx%d"%(w,h))
    else:
        print()
