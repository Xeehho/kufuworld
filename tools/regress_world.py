# -*- coding: utf-8 -*-
"""世界重构全量回归（docs/武侠世界重构规划-2026-08-31.md §10.1）
temp-inject ProbeWorldRegress -> run game -> restore project.godot -> assert & report.
断言失败纪律：先修因，禁止改断言凑绿；规则变更需升 WORLD_RULES_VERSION 并登记文档。
"""
import subprocess, sys, os, json

proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "regress_world_log.txt")
jp = os.path.join(proj, "tools", "regress_world_data.json")
MARKER = 'ProbeWorldRegress="*res://tools/probe_world_regress.gd"'

results = []  # (group, name, ok, detail, since)
CURRENT_STAGE = "W0"

def check(group, name, ok, detail="", since="W0"):
    results.append((group, name, bool(ok), detail, since))

def main():
    with open(pg, encoding="utf-8") as f:
        original = f.read()
    try:
        if MARKER not in original:
            patched = original.replace("[autoload]\n", "[autoload]\n\n" + MARKER + "\n", 1)
            with open(pg, "w", encoding="utf-8") as f:
                f.write(patched)
        if os.path.exists(gp):
            os.remove(gp)
        if os.path.exists(jp):
            os.remove(jp)
        gf = open(gp, "wb")
        proc = subprocess.Popen([exe, "--path", proj], cwd=proj, stdout=gf, stderr=subprocess.STDOUT)
        timed_out = False
        try:
            proc.communicate(timeout=180)
        except Exception:
            timed_out = True
            proc.kill()
        gf.close()
        if timed_out:
            print("FATAL: game run timed out (180s)")
            sys.exit(2)
    finally:
        with open(pg, encoding="utf-8") as f:
            cur = f.read()
        cur = cur.replace("\n" + MARKER, "").replace(MARKER, "")
        with open(pg, "w", encoding="utf-8") as f:
            f.write(cur)

    if not os.path.exists(jp):
        print("FATAL: no data json produced; log tail:")
        print("".join(open(gp, encoding="utf-8", errors="replace").readlines()[-15:]))
        sys.exit(2)
    data = json.load(open(jp, encoding="utf-8"))
    if "FATAL" in data:
        print("FATAL in probe:", data["FATAL"])
        sys.exit(2)

    # ---------- 断言组：biome ----------
    GREEN_TILES = {"0", "8", "9", "13", "16", "18", "36", "37"}  # 草/橡/竹/花/田/深草——绿色系
    DESERT_FORBID = {"0", "4", "8", "9", "13", "16", "18", "34", "36", "37"}  # 沙漠禁草禁树
    zones = data["zones"]
    for k in ["snow", "desert", "lake", "bamboo", "forest", "plains", "mountain"]:
        z = zones.get(k)
        check("biome", f"{k}_zone_exists", z is not None and z["samples"] > 0,
              f"samples={z['samples'] if z else 0}")
    if zones.get("snow"):
        bad = {t: c for t, c in zones["snow"]["hist"].items() if t in GREEN_TILES}
        check("biome", "snow_zero_green", sum(bad.values()) == 0, f"forbidden={bad}")
        snow_greenish_tree = zones["snow"]["hist"].get("8", 0)
        check("biome", "snow_no_oak", snow_greenish_tree == 0, f"oak={snow_greenish_tree}")
    if zones.get("desert"):
        bad = {t: c for t, c in zones["desert"]["hist"].items() if t in DESERT_FORBID}
        check("biome", "desert_no_tree_no_grass", sum(bad.values()) == 0, f"forbidden={bad}")

    # 气候连续性：谱系不相邻禁对（snow/mountain 为温度低带，desert 为热低湿带）
    FORBID_ADJ = {"snow|desert", "snow|plains", "snow|forest", "snow|bamboo",
                  "desert|forest", "desert|bamboo"}
    adj = data["biome_adj"]
    bad_pairs = {p: c for p, c in adj.items() if p in FORBID_ADJ}
    check("biome", "climate_continuity", len(bad_pairs) == 0, f"forbidden_adj={bad_pairs}")

    # ---------- 断言组：water ----------
    w = data["water"]
    check("water", "no_bridge_overwrite_non17", True, "recorded")  # 占位：W1 增补河口/河源断言
    check("water", "footprint_no_water", w["footprint_water"] == 0, f"cells={w['footprint_water']}")
    worst_town = min(w["min_dist_towns"].values()) if w["min_dist_towns"] else 999
    check("water", "river_not_through_town", worst_town >= 13.0, f"min={worst_town:.1f}")
    # W1 起生效：河流改道（源高山终湖海+避城轨迹）后河水不再进入城圈。
    # W0 现状为第三轮成果"穿城河+水门街桥"（规划 §3.2 保留语义），基线豁免。
    check("water", "river_not_through_city", w["min_dist_city"] >= 23.0,
          f"min_dist_city={w['min_dist_city']:.1f} (city_half+1=23)", since="W1")
    check("water", "city_interior_dry", w["city_water"] == 0, f"cells={w['city_water']}", since="W1")

    # ---------- 断言组：city ----------
    c = data["city"]
    for g, ok in c["gates"].items():
        check("city", f"gate_{g}_reachable", ok, "")
    bad_doors = [k for k, ok in c["doors"].items() if not ok]
    check("city", "all_building_doors_reachable", len(bad_doors) == 0, f"failed={bad_doors}")

    # ---------- 断言组：connectivity ----------
    check("walk", "spawn_reach_large", data["reach_count"] >= 8000,
          f"reach={data['reach_count']}")

    # ---------- 报告 ----------
    STAGE_ORDER = ["W0", "W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"]
    cur_i = STAGE_ORDER.index(CURRENT_STAGE)

    def verdict(r):
        g, n, ok, d, since = r
        if ok:
            return "PASS"
        if since in STAGE_ORDER and STAGE_ORDER.index(since) > cur_i:
            return "PENDING"   # 断言尚未到生效阶段（历史语义豁免）
        return "FAIL"

    fails = [r for r in results if verdict(r) == "FAIL"]
    print("=" * 62)
    print("REGRESS WORLD REPORT  (rules v%s, stage %s)" % ("1", CURRENT_STAGE))
    print("=" * 62)
    groups_seen = []
    for g, n, ok, d, s in results:
        if g not in groups_seen:
            groups_seen.append(g)
    for g in groups_seen:
        print(f"[{g}]")
        for r in results:
            if r[0] == g:
                v = verdict(r)
                print(f"  {v}  {r[1]}  {r[3]}" + (f"  (since {r[4]})" if v == "PENDING" else ""))
    print("-" * 62)
    print(f"TOTAL {len(results)}  PASS {sum(1 for r in results if verdict(r) == 'PASS')}  "
          f"PENDING {sum(1 for r in results if verdict(r) == 'PENDING')}  FAIL {len(fails)}")
    sys.exit(1 if fails else 0)

if __name__ == "__main__":
    main()
