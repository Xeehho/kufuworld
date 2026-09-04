# -*- coding: utf-8 -*-
"""拼合诊断大图: 原始Side帧 / 现right帧 / 树表象限，供视觉核验"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_pack_assets as ipa

def blit(canvas, rows, x0, y0):
    for j,r in enumerate(rows):
        yy=y0+j
        if yy>=len(canvas): break
        line=canvas[yy]
        for i in range(0,len(r),4):
            xx=x0+i//4
            if xx>=CW: continue
            o=i
            if r[o+3]>10:
                line[xx*4:xx*4+4]=r[o:o+4]

def scale(rows,f):
    out=[]
    for r in rows:
        line=bytearray()
        for i in range(0,len(r),4):
            px=r[i:i+4]
            for _ in range(f): line+=px
        for _ in range(f): out.append(bytes(line))
    return out

CW,CH=1500,560
canvas=[bytearray(CW*4) for _ in range(CH)]

# 1) 原始Side walk frame0 (x3)
src=os.path.join(ipa.PACK,"Entities","Characters","Body_A","Animations")
walk_side=None
p=os.path.join(src,"Walk_Base","Walk_Side-Sheet.png")
if os.path.exists(p): walk_side=p
print("walk_side path:", walk_side)
if walk_side:
    w,h,rows=ipa.load_png(walk_side)
    fr=ipa.crop(rows,h,h,0,False)
    blit(canvas,scale(fr,3),10,10)
# 2) 现在的 walk_right_0 (x3) 与 walk_left_0 (x3)
for idx,name in [(0,"walk_right_0"),(1,"walk_left_0")]:
    w,h,rows=ipa.load_png(os.path.join(ipa.SPR,"player",name+".png"))
    blit(canvas,scale(rows,3),250+idx*260,10)

# 3) 三张树表的"声明region v0"(红框)与真实内容
sheets=[("pine",os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_03","Size_02.png"),64,80),
        ("oak", os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_01","Size_02.png"),128,64),
        ("bamboo",os.path.join(ROOT,"downloaded_assets","Pixel Crawler - Free Pack","Environment","Props","Static","Trees","Model_02","Size_03.png"),72,80)]
yoff=230
x=10
for name,p,dcw,dch in sheets:
    w,h,rows=ipa.load_png(p)
    reg=[r[:dcw*4] for r in rows[:dch]]
    s=scale(reg,1)
    blit(canvas,s,x,yoff)
    # 红框标出声明cell范围
    for i in range(dcw):
        canvas[yoff-1][ (x+i)*4:x*4+(i+1)*4 ] = bytes([255,0,0,255])
    x+=dcw+30
out=os.path.join(ROOT,"tools","diag_composite.png")
ipa.save_png(out,CW,CH,canvas)
print("saved",out)
