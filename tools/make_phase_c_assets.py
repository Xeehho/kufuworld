# -*- coding: utf-8 -*-
"""Phase C 资产烘焙：从素材包Stations裁剪站台 + 程序绘制作物/浆果丛 + 湿润农田变体。
输出 sprites/stations/*.png, sprites/farm/*.png, sprites/tiles/farmland_wet.png
可重复运行（幂等覆盖）。运行: python tools/make_phase_c_assets.py
"""
from PIL import Image, ImageDraw
import os, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PK = os.path.join(ROOT, "downloaded_assets", "Pixel Crawler - Free Pack",
                  "Environment", "Structures", "Stations")

def ensure(d):
    os.makedirs(d, exist_ok=True); return d

ST = ensure(os.path.join(ROOT, "sprites", "stations"))
FM = ensure(os.path.join(ROOT, "sprites", "farm"))

def tight(img):
    bb = img.getchannel("A").getbbox()
    return img.crop(bb) if bb else img

def save_scaled(img, path, target_h, nearest=True):
    w, h = img.size
    s = target_h / h
    out = img.resize((max(1,int(round(w*s))), target_h), Image.NEAREST if nearest else Image.LANCZOS)
    out.save(path)
    print("baked", os.path.relpath(path, ROOT), out.size)

# ---------- Stations ----------
# Workbench.png 192x352：横向整幅、纵向6段构建动画带；取顶带（成品工作台）
wb = Image.open(os.path.join(PK, "Workbench", "Workbench.png")).convert("RGBA")
save_scaled(tight(wb.crop((0, 1, 192, 61))), os.path.join(ST, "workbench.png"), 30)

# Furnace.png 192x384：取顶部 192x64 带（完整熔炉）
fu = Image.open(os.path.join(PK, "Furnace", "Furnace.png")).convert("RGBA")
save_scaled(tight(fu.crop((0, 2, 192, 64))), os.path.join(ST, "furnace.png"), 40)

# Alchemy_Table_01-Sheet 192x704：11条~32px动画带；取第1带（y31..63）
al = Image.open(os.path.join(PK, "Alchemy", "Alchemy_Table_01-Sheet.png")).convert("RGBA")
save_scaled(tight(al.crop((0, 31, 192, 63))), os.path.join(ST, "alchemy_table.png"), 32)

# Bonfire_01-Sheet 128x32：4帧火焰动画，逐帧导出 bonfire_f0..3.png
bf = Image.open(os.path.join(PK, "Bonfire", "Bonfire_01-Sheet.png")).convert("RGBA")
for i in range(4):
    fr = tight(bf.crop((i*32, 0, i*32+32, 32)))
    fr.save(os.path.join(ST, "bonfire_f%d.png" % i))
    print("baked bonfire_f%d.png" % i, fr.size)

# ---------- 作物 4 阶段 (16x16) ----------
def crop_stage(stage):
    im = Image.new("RGBA", (16, 16), (0,0,0,0))
    dr = ImageDraw.Draw(im)
    g1=(74,124,58,255); g2=(96,152,70,255); st=(122,94,60,255)
    if stage == 0:      # 破土芽
        dr.line([(8,15),(8,12)], fill=g1); dr.ellipse([7,10,9,13], fill=g2)
    elif stage == 1:    # 幼苗两叶
        dr.line([(8,15),(8,9)], fill=st)
        dr.ellipse([4,8,8,11], fill=g1); dr.ellipse([8,8,12,11], fill=g1)
        dr.ellipse([6,6,10,9], fill=g2)
    elif stage == 2:    # 旺长丛叶
        dr.line([(8,15),(8,6)], fill=st)
        dr.ellipse([3,7,9,12], fill=g1); dr.ellipse([7,7,13,12], fill=g1)
        dr.ellipse([5,4,11,10], fill=g2); dr.ellipse([7,9,9,12], fill=g2)
    else:               # 成熟结果(青菜头+淡黄心)
        dr.polygon([(4,15),(12,15),(10,9),(6,9)], fill=g1)
        dr.polygon([(6,15),(10,15),(9,11),(7,11)], fill=g2)
        dr.ellipse([6,7,10,11], fill=(228,214,140,255))
    return im
for s in range(4):
    crop_stage(s).save(os.path.join(FM, "crop_%d.png" % s))
print("baked crop_0..3.png (16x16)")

# ---------- 浆果丛 有果/无果 (22x18) ----------
def bush(with_fruit):
    im = Image.new("RGBA", (22, 18), (0,0,0,0))
    dr = ImageDraw.Draw(im)
    d1=(52,96,50,255); d2=(72,124,62,255)
    dr.ellipse([2,6,12,16], fill=d1); dr.ellipse([8,4,20,15], fill=d1)
    dr.ellipse([4,4,14,12], fill=d2); dr.ellipse([10,7,19,15], fill=d2)
    if with_fruit:
        for (bx,by) in [(6,8),(12,6),(15,11),(9,12)]:
            dr.ellipse([bx,by,bx+3,by+3], fill=(196,52,66,255))
            dr.point((bx+1,by+1), fill=(236,120,120,255))
    return im
bush(True).save(os.path.join(FM, "berry_bush.png"))
bush(False).save(os.path.join(FM, "berry_bush_empty.png"))
print("baked berry_bush(_empty).png (22x18)")

# ---------- 湿润农田：farmland.png 压暗偏蓝 ----------
fl = Image.open(os.path.join(ROOT, "sprites", "tiles", "farmland.png")).convert("RGBA")
px = fl.load()
W,H = fl.size
for y in range(H):
    for x in range(W):
        r,g,b,a = px[x,y]
        if a == 0: continue
        px[x,y] = (int(r*0.55), int(g*0.60), int(b*0.78), a)
fl.save(os.path.join(ROOT, "sprites", "tiles", "farmland_wet.png"))
print("baked farmland_wet.png", fl.size)
print("ALL DONE");
