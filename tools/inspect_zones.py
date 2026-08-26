import sys
sys.path.insert(0,"tools")
from import_pack_assets import load_png
w,h,rows = load_png("tools/probe_shot_1.png")
# 横向扫描 y=500 行 x∈[900,1200] 找硬边界
line=rows[500]
prev=None; edges=[]
for x in range(900,1300):
    o=x*4; c=(line[o]//8, line[o+1]//8, line[o+2]//8)
    if prev and c!=prev: edges.append((x,"#%02x%02x%02x"%(line[o],line[o+1],line[o+2])))
    prev=c
print("y=500 edges:", edges[:10])
# 该灰区内部有变化吗?
import collections
cnt=collections.Counter()
for y in range(100,h-100,17):
    l=rows[y]
    for x in range(1050,w-50,17):
        o=x*4; cnt["#%02x%02x%02x"%(l[o],l[o+1],l[o+2])]+=1
print("gray zone colors:", cnt.most_common(6))
# 橙色328区域内部结构
cnt2=collections.Counter()
for y in range(560,880,7):
    l=rows[y]
    for x in range(452,772,7):
        o=x*4; cnt2["#%02x%02x%02x"%(l[o],l[o+1],l[o+2])]+=1
print("orange zone:", cnt2.most_common(6))
