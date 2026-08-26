# -*- coding: utf-8 -*-
"""Pixel Crawler 素材包 -> 江湖志 素材管线
从 downloaded_assets 裁切并生成 sprites/ 下的运行时贴图：
- 玩家: Body_A 全动画集 (64x64/帧, down/left/right/up) + Phase F1着装后处理(长衫/发型)
- NPC : Knight/Rogue/Wizzard/Peasant/Tavern (32x32, 内容bbox归一化高度29px, side+flip)
- Mob : Orc/Skeleton 各变体 idle/run/death (32x32, 原始朝向)
- 地形: 自动挑选均匀填充瓦片 (草地/泥土/水/沙石/山岩)
"""
import struct, zlib, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "downloaded_assets", "Pixel Crawler - Free Pack")
SPR = os.path.join(ROOT, "sprites")

# ---------------- PNG codec ----------------
def load_png(p):
    with open(p, "rb") as f: data = f.read()
    pos = 8; w=h=None; idat=b""; ch=4
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]; chunk = data[pos+8:pos+8+ln]
        if typ == b"IHDR":
            w,h,bd,ct = struct.unpack(">IIBB", chunk[:10]); ch={0:1,2:3,3:1,4:2,6:4}[ct]
        elif typ == b"IDAT": idat += chunk
        elif typ == b"IEND": break
        pos += 12+ln
    raw = zlib.decompress(idat); stride=w*ch
    rows=[]; prev=bytearray(stride); pp=0
    for y in range(h):
        ft=raw[pp]; line=bytearray(raw[pp+1:pp+1+stride]); pp+=1+stride
        if ft==1:
            for i in range(ch,stride): line[i]=(line[i]+line[i-ch])&255
        elif ft==2:
            for i in range(stride): line[i]=(line[i]+prev[i])&255
        elif ft==3:
            for i in range(stride):
                l=line[i-ch] if i>=ch else 0
                line[i]=(line[i]+(l+prev[i])//2)&255
        elif ft==4:
            for i in range(stride):
                a=line[i-ch] if i>=ch else 0; b=prev[i]; c=prev[i-ch] if i>=ch else 0
                p2=a+b-c; pa,pb,pc=abs(p2-a),abs(p2-b),abs(p2-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i]=(line[i]+pr)&255
        prev=line
        if ch==4: rows.append(bytes(line))
        else:
            ext=bytearray()
            for x in range(w):
                o=x*ch
                ext+=bytes([line[o], line[o+1] if ch>1 else 0, line[o+2] if ch>2 else 0, 255])
            rows.append(bytes(ext))
    return w,h,rows

def chunk_out(typ, data):
    return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ+data)&0xffffffff)

def save_png(path, w, h, rgba_rows):
    raw = b"".join(b"\x00"+r[:w*4] for r in rgba_rows)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path,"wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk_out(b"IHDR", ihdr))
        f.write(chunk_out(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk_out(b"IEND", b""))

def crop(rows, fw, fh, fi, mirror=False):
    out=[]
    for y in range(fh):
        line = rows[y][fi*fw*4:(fi+1)*fw*4]
        if mirror:
            px=[line[x*4:x*4+4] for x in range(fw)][::-1]
            line=b"".join(px)
        out.append(line)
    return out

def resize_nearest(rows, w, h, nw, nh):
    # Phase B-4/F3: nearest-neighbor缩放（NPC内容bbox归一化也用）
    out=[]
    for j in range(nh):
        sy = min(h - 1, j * h // nh)
        src = rows[sy]
        line = bytearray()
        for i in range(nw):
            sx = min(w - 1, i * w // nw)
            o = sx * 4
            line += src[o:o+4]
        out.append(bytes(line))
    return out

def darken(rows, factor):
    out=[]
    for line in rows:
        b2=bytearray(line)
        for i in range(0,len(b2),4):
            b2[i]=int(b2[i]*factor); b2[i+1]=int(b2[i+1]*factor); b2[i+2]=int(b2[i+2]*factor)
        out.append(bytes(b2))
    return out

def stats(rows, ts):
    """每瓦片: (均值RGB, 标准差, 平均alpha)"""
    h=len(rows); w=len(rows[0])//4
    res={}
    for ty in range(h//ts):
        for tx in range(w//ts):
            rs=gs=bs=als=n=0
            vals=[]
            for y in range(ty*ts,(ty+1)*ts):
                line=rows[y]
                for x in range(tx*ts,(tx+1)*ts):
                    o=x*4; r,g,b,a=line[o],line[o+1],line[o+2],line[o+3]
                    rs+=r; gs+=g; bs+=b; als+=a; n+=1; vals.append((r,g,b))
            mr,mg,mb=rs/n,gs/n,bs/n
            var=sum((vr-mr)**2+(vg-mg)**2+(vb-mb)**2 for vr,vg,vb in vals)/n
            res[(tx,ty)]=((mr,mg,mb),var**0.5,als/n)
    return res

P = lambda *p: os.path.join(PACK, *p)

# ================= Phase F1: 玩家着装引擎（外袍+发型，颜色域重绘不动描边） =================
SKIN_L = (0xd9, 0xa0, 0x66)   # 皮肤亮部
SKIN_D = (0xa2, 0x65, 0x43)   # 皮肤暗部
HAIR   = (38, 30, 44)         # 乌发主色
HAIR_H = (66, 55, 78)         # 乌发高光
RIBBON = (178, 52, 40)        # 朱红发带
ROBE   = (64, 76, 112)        # 黛蓝长衫亮部
ROBE_D = (48, 57, 88)         # 长衫暗部
SASH   = (140, 54, 36)        # 腰带赭红
SASH_D = (108, 41, 28)
PANTS  = (54, 50, 62)
PANTS_D= (42, 38, 48)
BOOT   = (30, 26, 32)
TRIM   = (216, 210, 192)      # 衣领米白镶边

def _dist2(c1, c2):
    return (c1[0]-c2[0])**2 + (c1[1]-c2[1])**2 + (c1[2]-c2[2])**2

def _is_skin(px):
    if px[3] < 10: return False
    c = (px[0], px[1], px[2])
    return _dist2(c, SKIN_L) <= 5600 or _dist2(c, SKIN_D) <= 4200

def _is_skin_dark(px):
    return px[3] >= 10 and _dist2((px[0], px[1], px[2]), SKIN_D) <= 4200

def _bbox_px(rows, w, h):
    minx,miny,maxx,maxy = w,h,-1,-1
    for y in range(h):
        row = rows[y]
        for x in range(w):
            if row[x*4+3] > 10:
                minx=min(minx,x); maxx=max(maxx,x); miny=min(miny,y); maxy=max(maxy,y)
    return minx,miny,maxx,maxy

def _skin_components(rows, w, h):
    labels = [[-1]*w for _ in range(h)]
    comps = []
    for y in range(h):
        row = rows[y]
        for x in range(w):
            o = x*4
            if row[o+3] > 10 and _is_skin(row[o:o+4]) and labels[y][x] < 0:
                cid = len(comps)
                cells = []
                stack = [(x,y)]
                labels[y][x] = cid
                minx=miny=10**9; maxx=maxy=-1
                while stack:
                    cx,cy = stack.pop()
                    cells.append((cx,cy))
                    minx=min(minx,cx); maxx=max(maxx,cx); miny=min(miny,cy); maxy=max(maxy,cy)
                    for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                        nx,ny = cx+dx, cy+dy
                        if 0<=nx<w and 0<=ny<h and labels[ny][nx]<0:
                            po = nx*4
                            prow = rows[ny]
                            if prow[po+3]>10 and _is_skin(prow[po:po+4]):
                                labels[ny][nx] = cid
                                stack.append((nx,ny))
                comps.append({"area":len(cells),"minx":minx,"miny":miny,"maxx":maxx,"maxy":maxy,"cells":cells})
    return labels, comps

def _face_window(dirn, bx0,by0,bx1,by1):
    hw = bx1-bx0+1; hh = by1-by0+1
    fy0 = by0 + int(hh*0.42); fy1 = by1 - 1
    if dirn == "down":
        return (bx0+2, fy0, bx1-2, fy1)
    if dirn == "right":
        return (bx0 + int(hw*0.42), fy0, bx1-1, fy1)
    if dirn == "left":
        return (bx0+1, fy0, bx0 + int(hw*0.58), fy1)
    return None  # up: 全后脑头发

def _dress_frame(rows, w, h, dirn):
    grid = [bytearray(r) for r in rows]
    bx0,by0,bx1,by1 = _bbox_px(rows,w,h)
    if bx1 < 0:
        return grid
    charH = by1-by0+1
    labels, comps = _skin_components(rows, w, h)
    head = None; head_cid = -1
    for c in sorted(comps, key=lambda c: c["miny"]):
        if c["area"] >= 12 and (c["maxy"]-c["miny"]+1) >= 7:
            head = c; break
    if head is not None:
        head_cid = comps.index(head)
    head_bottom = head["maxy"] if head is not None else by0 + int(charH*0.47)
    face_win = None
    if head is not None:
        face_win = _face_window(dirn, head["minx"],head["miny"],head["maxx"],head["maxy"])
        for (cx,cy) in head["cells"]:
            o = cx*4
            if face_win and face_win[0]<=cx<=face_win[2] and face_win[1]<=cy<=face_win[3]:
                continue
            dark = _is_skin_dark(grid[cy][o:o+4])
            grid[cy][o:o+4] = bytes([ *(HAIR_H if dark else HAIR), 255 ])
        if dirn in ("down","up"):
            cxm = (head["minx"]+head["maxx"])//2
            top = head["miny"]
            def _put(x,y,col):
                if 0<=x<w and 0<=y<h and grid[y][x*4+3] < 10:
                    grid[y][x*4:x*4+4] = bytes([*col,255])
            for dy in range(1,4):
                half = 2 if dy < 3 else 1
                for dx in range(-half, half+1):
                    _put(cxm+dx, top-dy, HAIR)
            for dx in range(-2, 3):
                _put(cxm+dx, top, RIBBON)
    waist = head_bottom + int(max(2,(by1-head_bottom)) * 0.52)
    for y in range(h):
        row = rows[y]; out = grid[y]
        for x in range(w):
            o = x*4
            if row[o+3] > 10 and _is_skin(row[o:o+4]):
                cid = labels[y][x]
                if head is not None and cid == head_cid:
                    continue
                dark = _is_skin_dark(row[o:o+4])
                if y >= by1 - 1:
                    col = BOOT
                elif y > waist:
                    col = PANTS_D if dark else PANTS
                elif waist <= y <= waist+1:
                    col = SASH_D if dark else SASH
                else:
                    col = ROBE_D if dark else ROBE
                out[o:o+4] = bytes([*col,255])
    if dirn == "down" and head is not None:
        cxm = (head["minx"]+head["maxx"])//2
        for i in range(3):
            yy = head_bottom + 1 + i
            for xx in (cxm-1-i, cxm+1+i):
                if 0<=xx<w and 0<=yy<h:
                    o = xx*4
                    c = tuple(grid[yy][o:o+3])
                    if _dist2(c, ROBE)<=400 or _dist2(c, ROBE_D)<=400:
                        grid[yy][o:o+4] = bytes([*TRIM,255])
    return grid

def dress_all_player_frames():
    out_dir = os.path.join(SPR,"player"); n=0
    for f in sorted(os.listdir(out_dir)):
        if not f.endswith(".png") or "." in f[:-4]: continue
        parts = f[:-4].split("_")
        dirn = parts[-2] if len(parts)>=2 else "down"
        if dirn not in ("down","left","right","up"): dirn="down"
        w,h,rows = load_png(os.path.join(out_dir,f))
        grid = _dress_frame(rows,w,h,dirn)
        save_png(os.path.join(out_dir,f), w,h, grid)
        n+=1
    print("[player-dress] %d frames dressed"%n)

# ================= 玩家 Body_A =================
CHAR_ANIMS = [
    ("idle",   "Idle_Base",   "Idle",   4, 6.0, True),
    ("walk",   "Walk_Base",   "Walk",   6, 10.0, True),
    ("run",    "Run_Base",    "Run",    6, 10.0, True),
    ("heavy",  "Pierce_Base", "Pierce", 8, 14.0, False),
    ("hurt",   "Hit_Base",    "Hit",    4, 8.0, False),
    ("death",  "Death_Base",  "Death",  8, 10.0, False),
    ("watering","Watering_Base","Watering",8, 12.0, False),
    ("collect","Collect_Base","Collect",8, 12.0, False),
]
DIRS = [("down","Down"), ("right","Side"), ("up","Up")]
# Phase G1: left=Side表镜像帧（先镜像裁切，再按dirn="left"着装，脸部窗口自动随bbox取左侧）
# 实测依据：Raw Side表眼睛/肤色质量一致右偏 -> 原生朝向为右，故right=原样、left=镜像
ALL_DIRS = [("down","Down"), ("right","Side"), ("left","Side"), ("up","Up")]
import re as _re

def _clean_stale_player_frames(out_dir):
    """删除全部 *_方向_N.png 旧产物，防止陈旧帧(旧程序画法)混入新导出（G1根因）"""
    pat = _re.compile(r"^[a-z]+_(down|up|left|right)_\d+\.png$")
    removed = 0
    for f in list(os.listdir(out_dir)):
        if pat.match(f):
            os.remove(os.path.join(out_dir, f)); removed += 1
    if removed:
        print("[player] cleaned %d stale frames" % removed)

def export_player():
    out_dir=os.path.join(SPR,"player"); count=0
    os.makedirs(out_dir, exist_ok=True)
    _clean_stale_player_frames(out_dir)
    def emit(prefix, base_dir, sheet_name, frames, suffix_map):
        nonlocal count
        for ddir, dsuf in ALL_DIRS:
            src = os.path.join(base_dir, "%s_%s-Sheet.png" % (sheet_name, suffix_map.get(ddir, dsuf)))
            if not os.path.exists(src):
                print("  MISS", os.path.relpath(src, PACK)); continue
            w,h,rows = load_png(src); fw=h
            fh_=64
            mirror = (ddir=="left")
            for i in range(frames):
                fr = crop(rows,fw,fh_,i,mirror)
                # Phase F1: 导出即着装（裸模Body_A -> 黛蓝长衫+乌发发髻）
                fr = _dress_frame(fr, fw, fh_, ddir)
                save_png(os.path.join(out_dir, "%s_%s_%d.png"%(prefix,ddir,i)), fw, fh_, fr)
                count+=1
    for prefix, folder, sheet, frames, spd, loop in CHAR_ANIMS:
        emit(prefix, P("Entities","Characters","Body_A","Animations",folder), sheet, frames,
             {"down":"Down","right":"Side","up":"Up"} if folder!="Pierce_Base" else {"down":"Down","right":"Side","up":"Top"})
    emit("attack", P("Entities","Characters","Body_A","Animations","Slice_Base"), "Slice", 8, {})
    emit("block", P("Entities","Characters","Body_A","Animations","Carry_Idle"), "Carry_Idle", 4, {})
    print("[player] %d frames"%count)
    return count

# ================= NPC（F3: 内容bbox归一化，修复merchant/elder模型过小） =================
NPC_MAP = {
    "warrior":    ("Npc's","Knight"),
    "scholar":    ("Npc's","Wizzard"),
    "mysterious": ("Npc's","Rogue"),
    "merchant":   ("Npc's","Citizen_F","Peasant_A"),
    "elder":      ("Npc's","Citizen_F","Tavern_B"),
}
TARGET_CHAR_H = 29.0   # 统一人物可见像素高（对齐warrior/mob基准）

def _paste_canvas(fr, tw, th, ts=32):
    canvas=[bytearray(ts*4) for _ in range(ts)]
    x0=(ts-tw)//2; y0=ts-th
    for j in range(th):
        canvas[y0+j][x0*4:(x0+tw)*4]=fr[j]
    return [bytes(r) for r in canvas]

def export_npcs():
    total=0
    TS=32
    out_dir=os.path.join(SPR,"npc")
    for ntype, parts in NPC_MAP.items():
        base = P("Entities", *parts)
        sheets=[]
        for dp,_,fs in os.walk(base):
            for f in fs:
                if f.endswith("-Sheet.png"):
                    rel=os.path.relpath(os.path.join(dp,f), base).replace("\\","/")
                    sheets.append((rel, f.lower()))
        def find_src(pref_folders, pref_names):
            for pf in pref_folders:
                for rel,nm in sorted(sheets):
                    if rel.lower().startswith(pf.lower()+"/") and any(pn in nm for pn in pref_names):
                        return os.path.join(base, rel)
            for rel,nm in sorted(sheets):
                if any(pn in nm for pn in pref_names):
                    return os.path.join(base, rel)
            return None
        idle_src = find_src(["Idle"],["idle-sheet","idle_side-sheet"])
        if idle_src is None:
            print("  [npc] MISS idle sheet:", ntype); continue
        w0,h0,rows0 = load_png(idle_src)
        bb = _bbox_px(rows0, w0, h0)
        src_h = max(1, bb[3]-bb[1]+1)
        scale = TARGET_CHAR_H / src_h
        for anim, prefs in [("idle", (["Idle"],["idle-sheet","idle_side-sheet"])),
                            ("walk", (["Walk","Run"],["walk-sheet","walk_side-sheet","run-sheet","run_side-sheet"]))]:
            src=find_src(*prefs)
            if src is None:
                print("  [npc] MISS sheet:", ntype, anim); continue
            w,h,rows=load_png(src); fw=h; n=w//fw
            f0 = crop(rows,fw,fw,0,False)
            b0 = _bbox_px(f0, fw, fw)
            ref_base = (fw-1-b0[3]) if b0[2] >= 0 else 0   # 本表frame0脚底基准
            def _norm_frame(fr):
                bx = _bbox_px(fr, fw, fw)
                if bx[2] < 0:
                    return None, None
                bw_ = bx[2]-bx[0]+1; bh_ = bx[3]-bx[1]+1
                rw_ = max(4, min(TS, int(round(bw_*scale))))
                rh_ = max(4, min(TS, int(round(bh_*scale))))
                sub=[fr[bx[1]+j][bx[0]*4:(bx[2]+1)*4] for j in range(bh_)]
                sr = resize_nearest(sub, bw_, bh_, rw_, rh_)
                sl=[bytes().join(sr[j][x*4:x*4+4] for x in reversed(range(rw_))) for j in range(rh_)]
                # 脚底锚定：以本表frame0为基准，帧间起伏按比例保留（walk bob不丢）
                delta = (fw-1-bx[3]) - ref_base
                feet_y = TS - 1 - int(round(delta*scale))
                y0 = min(TS-rh_, max(0, feet_y - rh_ + 1))
                x0 = max(0, (TS-rw_)//2)
                def canvas(lines):
                    cv=[bytearray(TS*4) for _ in range(TS)]
                    for j in range(len(lines)):
                        yy=y0+j
                        cv[yy][x0*4:x0*4+len(lines[j])]=lines[j][:TS*4-x0*4]
                    return [bytes(r) for r in cv]
                return canvas(sr), canvas(sl)
            for i in range(n):
                fr0 = crop(rows,fw,fw,i,False)
                cv_r, cv_l = _norm_frame(fr0)
                if cv_r is None:
                    continue
                save_png(os.path.join(out_dir,"%s_%s_right_%d.png"%(ntype,anim,i)),TS,TS,cv_r)
                save_png(os.path.join(out_dir,"%s_%s_left_%d.png"%(ntype,anim,i)),TS,TS,cv_l)
                save_png(os.path.join(out_dir,"%s_%s_down_%d.png"%(ntype,anim,i)),TS,TS,cv_r)
                save_png(os.path.join(out_dir,"%s_%s_up_%d.png"%(ntype,anim,i)),TS,TS,cv_r)
                total+=4
    print("[npc] %d frames"%total)
    return total

# ================= Mob =================
MOBS = ["Orc Crew/Orc","Orc Crew/Orc - Rogue","Orc Crew/Orc - Shaman","Orc Crew/Orc - Warrior",
        "Skeleton Crew/Skeleton - Base","Skeleton Crew/Skeleton - Mage","Skeleton Crew/Skeleton - Rogue","Skeleton Crew/Skeleton - Warrior"]
def slug(s): return s.split("/")[1].lower().replace(" ","_").replace("-","_")
def export_mobs():
    total=0
    for m in MOBS:
        name=slug(m)
        for anim in ["Idle","Run","Death"]:
            src=os.path.join(P("Entities","Mobs",m,anim),"%s-Sheet.png"%anim)
            if not os.path.exists(src):
                for cand in os.listdir(P("Entities","Mobs",m,anim)):
                    if cand.endswith("-Sheet.png"): src=os.path.join(P("Entities","Mobs",m,anim),cand); break
            w,h,rows=load_png(src); fw=h; n=w//fw
            for i in range(n):
                save_png(os.path.join(SPR,"mobs","%s_%s_%d.png"%(name,anim.lower(),i)),fw,fw,crop(rows,fw,fw,i,False))
                total+=1
    print("[mobs] %d frames"%total)

# ================= 地形自动选片 =================
def export_terrain():
    fl_w,fl_h,fl_rows = load_png(P("Environment","Tilesets","Floors_Tiles.png"))
    wt_w,wt_h,wt_rows = load_png(P("Environment","Tilesets","Water_tiles.png"))
    st_fl = stats(fl_rows,16); st_wt = stats(wt_rows,16)
    out=os.path.join(SPR,"tiles")
    def pick(st, cond, key=lambda s:(s[1])):
        cands=[(k,v) for k,v in st.items() if cond(k,v)]
        if not cands: return None,None
        k,v=min(cands,key=lambda kv: key(kv[1]))
        return k,v
    # 纯色草: 绿且均匀且全不透明
    def is_green(v): r,g,b=v[0]; return g>r+15 and g>b+25 and v[2]>250
    gk,gv = pick(st_fl, lambda k,v: k[0]<6 and k[1]>=10 and is_green(v))
    # 泥土: 棕红且均匀全不透明 (排除绿/蓝)
    def is_brown(v): r,g,b=v[0]; return r>g>b and r-b>20 and v[2]>250
    bk,bv = pick(st_fl, lambda k,v: is_brown(v) and k[1]>=12 and 5<=k[0]<=10)
    # 水: 蓝
    def is_blue(v): r,g,b=v[0]; return b>r+40 and b>g+20 and v[2]>250
    wk,wv = pick(st_wt, lambda k,v: is_blue(v) and 5<=k[1]<=14)
    print("[terrain] grass=%s%s dirt=%s%s water=%s%s" % (gk,gv[0],bk,bv[0],wk,wv[0]))
    def write(name, srcrows, tx, ty, mod=None):
        c=crop(srcrows,16,16,0)
        # 手动重定位到目标tile
        sub=[srcrows[ty*16+i][tx*16*4:(tx+1)*16*4] for i in range(16)]
        if mod: sub=mod(sub)
        save_png(os.path.join(out,name+".png"),16,16,sub)
    if gk: write("grass", fl_rows, gk[0], gk[1]); write("grass_dark", fl_rows, gk[0], gk[1], lambda rr: darken(rr,0.72))
    if bk: write("path", fl_rows, bk[0], bk[1]); write("farmland", fl_rows, bk[0], bk[1], lambda rr: darken(rr,0.62))
    if wk: write("water", wt_rows, wk[0], wk[1])

if __name__=="__main__":
    which = sys.argv[1] if len(sys.argv)>1 else "all"
    if which in ("all","player"): export_player()
    if which in ("all","npc"): export_npcs()
    if which in ("all","mobs"): export_mobs()
    if which in ("all","terrain"): export_terrain()
    print("DONE")