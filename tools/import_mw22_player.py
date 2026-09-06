# -*- coding: utf-8 -*-
"""Mystic Woods 付费版 player.png -> 江湖志 玩家帧管线（整包换血 Slice A）
生成两套外观（双外观系统地基）：
  sprites/player/         唐装（乌发髻+绯红圆领袍，穿越后）——当前游戏使用
  sprites/player_modern/  MW 原样（现代休闲装，穿越前）——备用，切换功能后接
⚠️ 授权：MW 禁止再分发（含修改版），两目录已 gitignore——素材本地生成，不入库。

帧布局（MW 48x48, 6列x10行）：
  行0-2 idle 下/右/上 各6帧 | 行3-5 walk 下/右/上 各6帧 | 行6-8 attack 下/右/上 各4帧 | 行9 受击/死亡 3帧
输出（引擎命名 {anim}_{dir}_{i}.png）：
  idle 6帧 / walk 6帧 / run 6帧(=walk) / attack 4帧 / block 4帧(程序化持盾)
  hurt 4帧 / death 8帧(末帧定格) / collect 8帧(attack回摆) / watering 8帧(同collect)
  左向 = 右向镜像；上向死亡/受击用下向帧
"""
import os, sys, importlib.util

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

# 复用样张工具里的唐装重着装 + 持盾提案（同一套色板/判据，保证样张=实机）
_spec = importlib.util.spec_from_file_location("mw22char", os.path.join(ROOT, "tools", "mw22_char_specimen.py"))
mw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mw)

from PIL import Image

SRC = mw.SRC
TS = 48
DIRS = ["down", "left", "right", "up"]

# MW 行号: {dir: (idle_row, walk_row, attack_row)}
MW_ROWS = {"down": (0, 3, 6), "right": (1, 4, 7), "up": (2, 5, 8)}


def mirror(img):
    return img.transpose(Image.FLIP_LEFT_RIGHT)


def get_frame(im, row, col):
    return im.crop((col*TS, row*TS, (col+1)*TS, (row+1)*TS)).convert("RGBA")


def save_set(out_dir, anim, dirn, frames):
    os.makedirs(out_dir, exist_ok=True)
    for i, fr in enumerate(frames):
        fr.save(os.path.join(out_dir, "%s_%s_%d.png" % (anim, dirn, i)))


def main():
    im = Image.open(SRC).convert("RGBA")
    death_frames = [get_frame(im, 9, c) for c in range(3)]  # 仅下向

    for outfit_dir, dressed in [("player", True), ("player_modern", False)]:
        out = os.path.join(ROOT, "sprites", outfit_dir)
        for dirn in DIRS:
            mirrored = (dirn == "left")
            src_dir = "right" if mirrored else dirn
            idle_r, walk_r, atk_r = MW_ROWS[src_dir]
            idle = [get_frame(im, idle_r, c) for c in range(6)]
            walk = [get_frame(im, walk_r, c) for c in range(6)]
            atk = [get_frame(im, atk_r, c) for c in range(4)]
            death = list(death_frames)
            if dressed:
                idle = [mw.tang_dress(f, src_dir) for f in idle]
                walk = [mw.tang_dress(f, src_dir) for f in walk]
                atk = [mw.tang_dress(f, src_dir) for f in atk]
                death = [mw.tang_dress(f, "down") for f in death_frames]
            if mirrored:
                idle = [mirror(f) for f in idle]
                walk = [mirror(f) for f in walk]
                atk = [mirror(f) for f in atk]
            save_set(out, "idle", dirn, idle)
            save_set(out, "walk", dirn, walk)
            save_set(out, "run", dirn, list(walk))                     # 疾跑=walk帧(靠speed提频)
            save_set(out, "attack", dirn, atk)
            save_set(out, "collect", dirn, atk + atk[::-1])            # 8帧回摆
            save_set(out, "watering", dirn, atk + atk[::-1])           # 8帧回摆(待PixelLab替换)
            save_set(out, "block", dirn, [mw.block_pose(f) for f in idle[:4]])
            save_set(out, "hurt", dirn, [death[0], death[1], death[1], death[0]])
            save_set(out, "death", dirn, death + [death[2]]*5)         # 8帧末态定格
        print("[mw22-player] %s: 9 anims x 4 dirs written" % outfit_dir)

    # 清理旧管线残留（64x64 attack 4..7 帧 / 旧 64x64 打坐帧，触发引擎重生成 48x48 打坐）
    removed = 0
    pdir = os.path.join(ROOT, "sprites", "player")
    for dirn in DIRS:
        for i in range(4, 8):
            for ext in (".png", ".png.import"):
                p = os.path.join(pdir, "attack_%s_%d%s" % (dirn, i, ext))
                if os.path.exists(p):
                    os.remove(p); removed += 1
    for i in (0, 1):
        for ext in (".png", ".png.import"):
            p = os.path.join(pdir, "meditate_down_%d%s" % (i, ext))
            if os.path.exists(p):
                os.remove(p); removed += 1
    print("[mw22-player] removed %d stale files" % removed)


if __name__ == "__main__":
    main()
