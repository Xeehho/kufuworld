# -*- coding: utf-8 -*-
"""审计三张树表的2x2象限内容是否被声明的cell裁切（bbox触边=被切半）"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

SHEETS = {
  "pine_M03_S02 (cell 64x80)": (os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_03","Size_02.png"), 64, 80),
  "oak_M01_S02 (cell 128x64)": (os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_01","Size_02.png"), 128, 64),
  "bamboo_M02_S03 (cell 72x80)": (os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_02","Size_03.png"), 72, 80),
}

for name,(p,cw,ch) in SHEETS.items():
    w,h,rows = ipa.load_png(p)
    print(f"== {name} sheet={w}x{h} grid={w//cw}x{h//ch}")
    for vy in range(h//ch):
        for vx in range(w//cw):
            minx,miny,maxx,maxy = cw,ch,-1,-1
            n=0
            for y in range(vy*ch,(vy+1)*ch):
                row=rows[y]
                for x in range(vx*cw,(vx+1)*cw):
                    if row[x*4+3]>10:
                        n+=1
                        lx=x-vx*cw
                        minx=min(minx,lx);maxx=max(maxx,lx);miny=min(miny,y-vy*ch);maxy=max(maxy,y-vy*ch)
            if maxx<0:
                print(f"   v({vx},{vy}): EMPTY"); continue
            touch=[]
            if minx==0: touch.append("L")
            if maxx==cw-1: touch.append("R")
            if miny==0: touch.append("T")
            if maxy==ch-1: touch.append("B")
            print(f"   v({vx},{vy}) opaque={n:6d} bbox=({minx},{miny})-({maxx},{maxy}) {'CLIPPED:'+','.join(touch) if touch else 'ok'}")
