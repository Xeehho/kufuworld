import sys
sys.path.insert(0,"tools")
from import_pack_assets import load_png
from collections import deque

def comps(path):
    w,h,rows = load_png(path)
    # 步长4下采样alpha连通域
    step=4
    def a(x,y): return rows[y][x*4+3]
    seen=set(); out=[]
    for y in range(0,h,step):
        for x in range(0,w,step):
            if a(x,y)>40 and (x,y) not in seen:
                q=deque([(x,y)]); seen.add((x,y)); n=0
                minx=miny=10**9; maxx=maxy=-1
                while q:
                    cx,cy=q.popleft(); n+=1
                    minx=min(minx,cx);maxx=max(maxx,cx);miny=min(miny,cy);maxy=max(maxy,cy)
                    for dx,dy in ((step,0),(-step,0),(0,step),(0,-step)):
                        nx,ny=cx+dx,cy+dy
                        if 0<=nx<w and 0<=ny<h and a(nx,ny)>40 and (nx,ny) not in seen:
                            seen.add((nx,ny)); q.append((nx,ny))
                out.append((n,(minx,miny,maxx,maxy)))
    out.sort(reverse=True)
    return w,h,out

base="downloaded_assets/Pixel Crawler - Free Pack/Environment/Props/Static/Trees/"
for rel in ["Model_03/Size_02.png","Model_03/Size_03.png","Model_02/Size_03.png","Model_01/Size_02.png"]:
    w,h,cs = comps(base+rel)
    print(rel, "sheet=%dx%d"%(w,h), ["px=%d bbox=%s"%(c[0],c[1]) for c in cs[:3]])
