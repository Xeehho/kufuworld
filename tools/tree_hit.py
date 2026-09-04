import sys, collections
sys.path.insert(0,"tools")
from import_pack_assets import load_png
# 从三张树表收集显著色 (出现>=200次的RGB)
palette=set()
for rel,cell in [("Model_03/Size_02.png",(64,80)),("Model_01/Size_02.png",(128,64)),("Model_02/Size_03.png",(72,80))]:
    w,h,rows = load_png("downloaded_assets/Pixel Crawler - Free Pack/Environment/Props/Static/Trees/"+rel)
    cnt=collections.Counter()
    for y in range(h):
        line=rows[y]
        for x in range(w):
            o=x*4
            if line[o+3]>200: cnt[(line[o],line[o+1],line[o+2])]+=1
    for c,n in cnt.most_common(30):
        if n>300: palette.add(c)
print("tree palette size:", len(palette))
w,h,rows = load_png("tools/probe_shot_0.png")
hit=collections.Counter()
for y in range(0,h,2):
    line=rows[y]
    for x in range(0,w,2):
        o=x*4; c=(line[o],line[o+1],line[o+2])
        if c in palette: hit[c]+=1
tot=sum(hit.values())
print("tree-palette px hits:", tot)
print("top:", [(("#%02x%02x%02x"%c), n) for c,n in hit.most_common(6)])
