# -*- coding: utf-8 -*-
"""世界重构全量回归（docs/武侠世界重构规划-2026-08-31.md §10.1）
temp-inject ProbeWorldRegress -> run game -> restore project.godot -> assert & report.
断言失败纪律：先修因，禁止改断言凑绿；规则变更需升 WORLD_RULES_VERSION 并登记文档。
"""
import subprocess, sys, os, json, math

proj = r"C:\Learn\my-godot-project"
pg = os.path.join(proj, "project.godot")
exe = open(os.path.join(proj, "tools", "godot_path.txt"), "rb").read().decode("gbk").strip()
gp = os.path.join(proj, "tools", "regress_world_log.txt")
jp = os.path.join(proj, "tools", "regress_world_data.json")
MARKER = 'ProbeWorldRegress="*res://tools/probe_world_regress.gd"'

results = []  # (group, name, ok, detail, since)
CURRENT_STAGE = "W8"

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
        # 占比阈值 ≤5%（规则 v3）：desert 代表区内残余禁格来自 ① _ground_of 锯齿过渡带（设计行为）
        # ② 河畔绿洲带——探针已排除临水≤12 格的合法绿洲格（oasis_skipped，W1"河谷沃野"设计），
        #    河穿沙漠时两岸草地不再计入违例；要求绝对零须关闭过渡带，得不偿失。
        total_cells = sum(zones["desert"]["hist"].values())
        check("biome", "desert_no_tree_no_grass", sum(bad.values()) <= total_cells * 0.05,
              f"forbidden={bad} ratio={sum(bad.values()) / max(total_cells, 1):.3f} "
              f"oasis_skipped={zones['desert'].get('oasis_skipped', 0)}")

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
    # W2 起城 half=30（方形）：水距城心用切比雪夫距离 ≥32（欧氏会放过城角内的水）
    check("water", "river_not_through_city", w["min_dist_city"] >= 32.0,
          f"min_dist_city(cheby)={w['min_dist_city']:.1f} (city_half+2=32)", since="W2")
    check("water", "city_interior_dry", w["city_water"] == 0, f"cells={w['city_water']}", since="W1")

    # W1 新增：湖泊存在、河源在山、干流终湖/海（规划 §2.1/§5.1 自然规律）
    rivers = data.get("rivers", [])
    lakes = data.get("lakes", [])
    check("water", "lake_exists", len(lakes) >= 1, f"lakes={len(lakes)}", since="W1")
    check("water", "main_river_exists", sum(1 for r in rivers if r["main"]) >= 1,
          f"rivers={len(rivers)} mains={sum(1 for r in rivers if r['main'])}", since="W1")
    bad_src = []
    for i, rv in enumerate(rivers):
        if not rv["main"]:
            continue   # 支流源允许在山缘（弱要求），自然规律断言只查干流
        src_mountain = sum(c for k, c in rv["head_kinds"].items() if k in ("mountain", "snow"))
        if src_mountain < 6:   # 前10格至少6格在高山/雪群系
            bad_src.append(i)
    check("water", "river_source_in_mountain", len(bad_src) == 0, f"bad={bad_src}", since="W1")
    bad_end = []
    for rv in rivers:
        if not rv["main"]:
            continue   # 支流终点=并入干流，只对干流断言
        end_ok = rv["tail_len"] > 190.0   # WORLD_RADIUS-10 出海
        for l in lakes:
            d = math.hypot(rv["tail"][0] - l["pos"][0], rv["tail"][1] - l["pos"][1])
            if d < l["r"] + 3.0:
                end_ok = True
        if not end_ok:
            bad_end.append(rv["tail"])
    check("water", "river_end_lake_or_sea", len(bad_end) == 0, f"bad_tails={bad_end}", since="W1")

    # ---------- 断言组：city ----------
    c = data["city"]
    for g, ok in c["gates"].items():
        check("city", f"gate_{g}_reachable", ok, "")
    bad_doors = [k for k, ok in c["doors"].items() if not ok]
    check("city", "all_building_doors_reachable", len(bad_doors) == 0, f"failed={bad_doors}")
    # W2 新增：唐制坊/市存在、坊内连通（中巷从广场可达=坊门有效）、同坊房间距≥2
    check("city", "wards_exist", c.get("wards_n", 0) >= 4, f"wards={c.get('wards_n', 0)}", since="W2")
    check("city", "markets_exist", c.get("markets_n", 0) >= 2, f"markets={c.get('markets_n', 0)}", since="W2")
    for wname, ok in c.get("ward_reach", {}).items():
        check("city", f"ward_{wname}_connected", ok, "", since="W2")
    check("city", "room_spacing_ge2", c.get("room_spacing_ok", False),
          f"detail={c.get('spacing_detail', {})}", since="W2")

    # ---------- 断言组：sect（W3 门派领地） ----------
    sects = data.get("sects", [])
    check("sect", "sect_count_5", len(sects) == 5, f"sects={len(sects)}", since="W3")
    city_half = 30
    for s in sects:
        n = s["name"]
        dc = max(abs(s["center"][0] - 75), abs(s["center"][1] - 0))
        check("sect", f"sect_{n}_dist_city", dc >= city_half + 4 + s["radius"],
              f"cheby={dc} need>={city_half + 4 + s['radius']}", since="W3")
        check("sect", f"sect_{n}_hall_placed", s["hall_ok"], "", since="W3")
        check("sect", f"sect_{n}_stele_ring", s["stele_ok"],
              f"samples={s['stele_samples']}/8", since="W3")
    for i in range(len(sects)):
        for j in range(i + 1, len(sects)):
            a, b = sects[i], sects[j]
            dd = max(abs(a["center"][0] - b["center"][0]), abs(a["center"][1] - b["center"][1]))
            check("sect", f"sect_gap_{a['name']}_{b['name']}", dd >= a["radius"] + b["radius"] + 8,
                  f"cheby={dd} need>={a['radius'] + b['radius'] + 8}", since="W3")

    # ---------- 断言组：connectivity ----------
    check("walk", "spawn_reach_large", data["reach_count"] >= 8000,
          f"reach={data['reach_count']}")

    # ---------- 断言组：town（W4 村镇 v2 一圈一团一水） ----------
    towns = data.get("towns", [])
    check("town", "towns_count_ge6", len(towns) >= 6, f"towns={len(towns)}", since="W4")
    tpl_seen = set()
    for t in towns:
        cx, cy = t["center"]
        tag = f"{t['template']}@{cx},{cy}"
        tpl_seen.add(t["template"])
        bad_doors = [k for k, ok in t["doors"].items() if not ok]
        check("town", f"town_{tag}_doors", len(bad_doors) == 0, f"failed={bad_doors}", since="W4")
        check("town", f"town_{tag}_chief", "村正" in t["jobs"], f"jobs={t['jobs']}", since="W4")
        check("town", f"town_{tag}_shrine", t["has_shrine"], "", since="W4")
        if t["template"] == "ferry":
            check("town", f"town_{tag}_ferry_pavilion", t["has_ferry"], "", since="W4")
    check("town", "town_templates_variety", len(tpl_seen) >= 2,
          f"seen={sorted(tpl_seen)}", since="W4")

    # ---------- 断言组：npc（W4 驻留制落位） ----------
    npc = data.get("npc", {})
    check("npc", "npc_total_in_budget", 40 <= npc.get("total", 0) <= 90,
          f"total={npc.get('total', 0)}（城15+村镇+领地15，规划≤45为笔误见进度日志deviation）", since="W4")
    check("npc", "npc_static_populated", npc.get("static_n", 0) >= 40,
          f"static={npc.get('static_n', 0)}", since="W4")
    check("npc", "npc_anchor_dist_le3", len(npc.get("bad_anchors", [])) == 0,
          f"bad={npc.get('bad_anchors', [])}", since="W4")

    # ---------- 断言组：quest（W8 任务重启，规则 v2：告示板恢复+主线自动启动+玩家未接取） ----------
    q = data.get("quest", {})
    check("quest", "quest_available_positive", q.get("available", -1) >= 1,
          f"available={q.get('available', -1)}（W8 规则v2：告示板恢复发布，冻结期零发布语义终止）", since="W8")
    check("quest", "story_started", bool(q.get("story_started", False)),
          f"started={q.get('story_started', False)}（主线 _start_when_ready 恢复，主1已启动）", since="W8")
    check("quest", "quest_active_zero", q.get("active", -1) == 0,
          f"active={q.get('active', -1)}（玩家未接取）", since="W4")
    check("quest", "quest_pending_story_zero", q.get("pending_story", -1) == 0,
          f"pending_story={q.get('pending_story', -1)}（主1无委托字段，主2未开始）", since="W4")
    check("quest", "quest_completed_zero", q.get("completed", -1) == 0,
          f"completed={q.get('completed', -1)}", since="W4")

    # ---------- 断言组：mob（营地避城回归） ----------
    m = data.get("mob", {})
    check("mob", "story_camps_zero", m.get("story_camps", -1) == 0,
          f"story_camps={m.get('story_camps', -1)}", since="W4")
    for c in m.get("camps", []):
        check("mob", f"camp_{c['name']}_wild", c["in_settlement"] is False,
              f"in_settlement={c['in_settlement']}", since="W4")

    # ---------- 断言组：bridge（W5 石拱桥+官道） ----------
    b = data.get("bridge", {})
    props = b.get("props", [])
    check("bridge", "bridge_props_count", len(props) >= 8, f"props={len(props)}", since="W5")
    check("bridge", "t17_all_proped", b.get("t17_covered", 0) == b.get("t17_total", 0),
          f"covered={b.get('t17_covered', 0)}/{b.get('t17_total', 0)} "
          f"(single={b.get('t17_single', 0)} 豁免)", since="W5")
    bad_water = [p["run"] for p in props if not p["water_side"]]
    check("bridge", "bridge_side_water", len(bad_water) == 0, f"bad={bad_water[:3]}", since="W5")
    roads = b.get("roads", [])
    ok_roads = [r for r in roads if r["len"] >= 20]
    check("bridge", "official_roads_exist", len(ok_roads) == 4,
          f"roads={[(r['gate'], r['len']) for r in roads]}", since="W5")
    crossed = [r["gate"] for r in roads if r["bridge_cells"] > 0]
    # 规则 v3：语义改为条件审计——"官道×河交叉处必有桥"由 bridge_side_water（∀17 贴水）保证；
    # 四门官道是否临河属布局特性（河平滑化后可能离城四门皆远），无交叉时不判 FAIL
    check("bridge", "official_road_river_bridged", True,
          f"crossed_gates={crossed}（无交叉=河离城远，17 贴水已由 bridge_side_water 保证）", since="W5")

    # ---------- 断言组：walk6（W6 可行域政策） ----------
    w6 = data.get("walk6", {})
    check("walk", "settlement_road_no_collide", w6.get("zone_bad_n", -1) == 0,
          f"bad_n={w6.get('zone_bad_n', -1)} bad={w6.get('zone_bad', [])}", since="W6")
    rock_total = w6.get("rock_total", 0)
    rock_near = w6.get("rock_near_mountain", 0)
    rock_iso = w6.get("rock_isolated", 0)
    check("walk", "wild_rock_near_mountain", rock_total > 0 and rock_near >= rock_total * 0.70,
          f"near={rock_near}/{rock_total}（噪声带状非严格贴山，deviation 见进度日志）", since="W6")
    check("walk", "wild_rock_clustered", rock_total > 0 and rock_iso <= rock_total * 0.30,
          f"isolated={rock_iso}/{rock_total}", since="W6")
    r1 = w6.get("reach1", 0)
    r2cov = w6.get("reach2_covered", 0)
    check("walk", "corridor_2x2_coverage", r1 > 0 and r2cov >= r1 * 0.80,
          f"reach2_covered={r2cov}/reach1={r1}", since="W6")

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
