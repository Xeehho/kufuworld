import struct, zlib, sys, os
sys.path.insert(0, "tools")
from import_pack_assets import load_png

img = "tools/probe_shot_0.png"
w,h,rows = load_png(img)
print("size", w, h)

# 象限色块统计 + 中央角色检测
def classify(r,g,b,a):
    if a < 40: return "transparent"
    if g > r+20 and g > b+20 and g > 60: return "green"
    if b > r+30 and b > g+10: return "blue"
    if r > 140 and g > 100 and b < 120 and r > b+60: return "tan/brown"
    if r < 90 and g < 90 and b < 110: return "dark"
    if abs(r-g)<25 and abs(g-b)<25:
        if r > 180: return "white/gray"
        return "midgray"
    return "other"

buckets = {}
cx0,cy0,cx1,cy1 = w//4, h//4, 3*w//4, 3*h//4
center_other = []
for y in range(0,h,3):
    line = rows[y]
    for x in range(0,w,3):
        o=x*4; c=classify(line[o],line[o+1],line[o+2],line[o+3])
        buckets[c]=buckets.get(c,0)+1
        if cx0<=x<cx1 and cy0<=y<cy1 and c=="other":
            center_other.append((x,y,line[o],line[o+1],line[o+2]))

tot=sum(buckets.values())
for k,v in sorted(buckets.items(), key=lambda kv:-kv[1]):
    print("%-10s %5.1f%%" % (k, v*100.0/tot))
print("center 'other' px:", len(center_other))
if center_other:
    xs=[p[0] for p in center_other]; ys=[p[1] for p in center_other]
    print("center-other bbox x[%d,%d] y[%d,%d]"%(min(xs),max(xs),min(ys),max(ys)))
    sample = center_other[:8]
    print("sample colors:", ["#%02x%02x%02x"%(p[2],p[3],p[4]) for p in sample])
