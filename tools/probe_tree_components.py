# -*- coding: utf-8 -*-
"""对整张树表做连通分量分析，找出每棵树的真实bbox，验证声明cell是否错切"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

SHEETS = {
  "pine_M03_S02": (os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_03","Size_02.png"), 64, 80),
  "oak_M01_S02":  (os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_01","Size_02.png"), 128, 64),
  "bamboo_M02_S03":(os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_02","Size_03.png"), 72, 80),
}

for name,(p,cw,ch) in SHEETS.items():
    w,h,rows = ipa.load_png(p)
    seen=[[False]*w for _ in range(h)]
    comps=[]
    for yy in range(h):
        row=rows[yy]
        for xx in range(w):
            if row[xx*4+3]>10 and not seen[yy][xx]:
                stack=[(xx,yy)]; seen[yy][xx]=True
                minx=miny=10**9; maxx=maxy=-1; n=0
                while stack:
                    cx,cy=stack.pop(); n+=1
                    minx=min(minx,cx);maxx=max(maxx,cx);miny=min(miny,cy);maxy=max(maxy,cy)
                    for dx,dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)):
                        nx,ny=cx+dx,cy+dy
                        if 0<=nx<w and 0<=ny<h and not seen[ny][nx] and rows[ny][nx*4+3]>10:
                            seen[ny][nx]=True; stack.append((nx,ny))
                comps.append((n,minx,miny,maxx,maxy))
    comps.sort(reverse=True)
    print(f"== {name} sheet={w}x{h} declared_cell={cw}x{ch}")
    for n,a,b,c,d in comps[:8]:
        print(f"   comp opaque={n:6d} bbox=({a},{b})-({c},{d}) size={c-a+1}x{d-b+1}  crosses_declared_x={'YES' if (c-a+1)>cw else 'no'}")
