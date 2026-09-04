import struct, zlib

def load_png_alpha(p):
    with open(p, "rb") as f:
        data = f.read()
    pos = 8
    w = h = None
    idat = b""
    channels = 4
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]
        if typ == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", chunk[:10])
            channels = {0:1, 2:3, 3:1, 4:2, 6:4}[ct]
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * channels
    rows = []
    prev = bytearray(stride)
    ppos = 0
    for y in range(h):
        ft = raw[ppos]
        line = bytearray(raw[ppos+1:ppos+1+stride])
        ppos += 1 + stride
        if ft == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i-channels]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i-channels] if i >= channels else 0
                line[i] = (line[i] + (left + prev[i]) // 2) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i-channels] if i >= channels else 0
                b = prev[i]
                c = prev[i-channels] if i >= channels else 0
                pp = a + b - c
                pa, pb, pc = abs(pp-a), abs(pp-b), abs(pp-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        prev = line
        if channels == 4:
            rows.append(line[3::4])
        else:
            rows.append(bytearray([255]) * w)
    return w, h, rows

def frame_bbox(rows, x0, x1, thresh=40):
    minx, miny, maxx, maxy = x1, len(rows), -1, -1
    for y in range(len(rows)):
        for x in range(x0, x1):
            if rows[y][x] > thresh:
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
    return minx, miny, maxx, maxy

base = "downloaded_assets/Pixel Crawler - Free Pack/"
tests = [
    ("Entities/Characters/Body_A/Animations/Idle_Base/Idle_Down-Sheet.png", "player_idle_down"),
    ("Entities/Characters/Body_A/Animations/Run_Base/Run_Side-Sheet.png", "player_run_side"),
    ("Entities/Npc's/Knight/Idle/Idle-Sheet.png", "knight_idle"),
    ("Entities/Mobs/Orc Crew/Orc - Warrior/Idle/Idle-Sheet.png", "orc_warrior_idle"),
    ("Environment/Structures/Stations/Bonfire/Bonfire_01-Sheet.png", "bonfire01"),
    ("Environment/Structures/Stations/Workbench/Workbench.png", "workbench"),
]
for rel, name in tests:
    try:
        w, h, rows = load_png_alpha(base + rel)
        fw = h
        n = w // fw
        info = []
        for i in range(min(n, 3)):
            bx = frame_bbox(rows, i*fw, (i+1)*fw)
            info.append("f%d:x[%d,%d]y[%d,%d]" % (i, bx[0]-i*fw, bx[2]-i*fw, bx[1], bx[3]))
        print("%s: sheet=%dx%d frame=%dx%d count=%d | %s" % (name, w, h, fw, fw, n, " | ".join(info)))
    except Exception as e:
        print(name, "ERR", e)
