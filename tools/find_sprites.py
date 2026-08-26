import struct, sys
sys.path.insert(0,"tools")
from import_pack_assets import load_png

w,h,rows = load_png("tools/probe_shot_1.png")
# 找"非地形"像素: 与草地绿/水蓝/雾棕差异大的
def is_terrain(r,g,b):
    if g > r+15 and g > b+15: return True          # 绿
    if b > r+25 and b > g+5: return True            # 蓝水
    if r>200 and g>160 and b>110 and r>b+60: return True  # 雾化亮地
    return False

mask = [[False]*w for _ in range(h)]
for y in range(0,h,2):
    line=rows[y]
    for x in range(0,w,2):
        o=x*4; r,g,b,a=line[o],line[o+1],line[o+2],line[o+3]
        if a>60 and not is_terrain(r,g,b): mask[y][x]=True

# BFS连通域 (步长2网格)
seen=[[False]*w for _ in range(h)]
comps=[]
from collections import deque
for y in range(0,h,2):
    for x in range(0,w,2):
        if mask[y][x] and not seen[y][x]:
            q=deque([(x,y)]); seen[y][x]=True
            n=0; xs=[]; ys=[]; cols=[]
            while q:
                cx,cy=q.popleft(); n+=1
                xs.append(cx); ys.append(cy)
                if len(cols)<3:
                    o=cx*4; cols.append("#%02x%02x%02x"%(rows[cy][o],rows[cy][o+1],rows[cy][o+2]))
                for dx,dy in ((2,0),(-2,0),(0,2),(0,-2)):
                    nx,ny=cx+dx,cy+dy
                    if 0<=nx<w and 0<=ny<h and mask[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx]=True; q.append((nx,ny))
            comps.append((n,min(xs),min(ys),max(xs),max(ys),cols))
comps.sort(reverse=True)
print("top components (size, bbox, colors):")
for c in comps[:10]:
    n,x0,y0,x1,y1,cols=c
    print("  px=%6d bbox=(%4d,%4d)-(%4d,%4d) wh=%dx%d %s" % (n,x0,y0,x1,y1,x1-x0,y1-y0,cols))
