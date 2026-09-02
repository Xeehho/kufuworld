extends Node

## 世界回归采样探针（W0 基线，tools/regress_world.py 临时注入 autoload 运行）
## 职责：只采样原始数据写 JSON（tools/regress_world_data.json），断言判定在 python 侧。
## 陷阱备忘 §五33：跑完由 runner 还原 project.godot，本文件不注册进工程。
const OUT := "C:/Learn/my-godot-project/tools/regress_world_data.json"
const LOG := "C:/Learn/my-godot-project/tools/regress_world_log.txt"

func _log(m):
	print(m)

func _wg():
	var world := get_node_or_null("/root/Main/World")
	if world == null:
		return null
	for c in world.get_children():
		var s = c.get_script()
		if s != null and str(s.resource_path).ends_with("world_generator.gd"):
			return c
	return null

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _ready():
	await _wait(4.5)   # autoload 先于主场景 ready：等 World/WorldGenerator/NPC 全建好
	var wg = _wg()
	if wg == null:
		_write({"FATAL": "world_generator not found"})
		get_tree().quit()
		return
	var data := {}

	# ---- 1) 群系代表区直方图：中心=群系"最深点"（±18格邻域内异类最少的采样格）。
	# 首见格在边缘、质心在月牙形群系的弧内凹处——两者都会让直方图混入邻居群系。
	var R: int = wg.WORLD_RADIUS
	var kind_cells := {}
	var kind_at := {}
	for y in range(-R + 16, R - 16, 6):
		for x in range(-R + 16, R - 16, 6):
			var k: String = wg._biome_kind(x, y)
			if not kind_cells.has(k):
				kind_cells[k] = []
			kind_cells[k].append(Vector2i(x, y))
			kind_at[Vector2i(x, y)] = k
	var zones := {}
	for k in ["snow", "desert", "lake", "bamboo", "forest", "plains", "mountain"]:
		var cells: Array = kind_cells.get(k, [])
		if cells.is_empty():
			zones[k] = null
			continue
		var c0: Vector2i = cells[0]
		var best_foreign := 1 << 30
		for c in cells:
			var foreign := 0
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					if kind_at.get(c + Vector2i(dx * 6, dy * 6), "?") != k:
						foreign += 1
			if foreign < best_foreign:
				best_foreign = foreign
				c0 = c
		var hist := {}
		var oasis_skipped := 0
		for dx in range(-24, 25):
			for dy in range(-24, 25):
				var cell := c0 + Vector2i(dx, dy)
				# W8 规则 v3：河畔绿洲带（临水≤12 格，_water_humid_boost）是合法自然景观——
				# 河穿沙漠时两岸加湿成草地/花树带（W1 设计：河谷沃野），不计入"沙漠禁草"违例
				if k == "desert" and wg._water_humid_boost.has(cell):
					oasis_skipped += 1
					continue
				var id = wg.get_tile_id(cell.x, cell.y)
				var key := str(id)
				hist[key] = int(hist.get(key, 0)) + 1
		zones[k] = {"center": [c0.x, c0.y], "hist": hist, "samples": cells.size(),
			"oasis_skipped": oasis_skipped}
	data["zones"] = zones

	# ---- 2) 气候连续性：步长2相邻群系对计数（禁对判定在 python 侧） ----
	var adj := {}
	var prev_row := {}
	for y in range(-R + 16, R - 16, 2):
		var row := {}
		for x in range(-R + 16, R - 16, 2):
			var k: String = wg._biome_kind(x, y)
			row[x] = k
			var neigh: Array = []
			if row.has(x - 2): neigh.append(row[x - 2])
			if prev_row.has(x): neigh.append(prev_row[x])
			if prev_row.has(x - 2): neigh.append(prev_row[x - 2])
			if prev_row.has(x + 2): neigh.append(prev_row[x + 2])
			for k2 in neigh:
				var pk: String = k + "|" + k2 if k <= k2 else k2 + "|" + k
				adj[pk] = int(adj.get(pk, 0)) + 1
		prev_row = row
	data["biome_adj"] = adj

	# ---- 3) 水文组：非边界水格距城/镇心最小距离；建筑矩形压水；城内水格 ----
	var city_c: Vector2i = wg.CITY_POS
	var min_city := 1e9
	var water_min_town := {}
	var footprint_water := 0
	for cell in wg.override_cells:
		if int(wg.override_cells[cell]) != 5:
			continue
		if Vector2(cell.x, cell.y).length() > R - 8:
			continue   # 边界深水不计
		# 方形城用切比雪夫距离（欧氏会放过城角内的水：城角距城心可达 30√2）
		var dc: float = float(maxi(absi(cell.x - city_c.x), absi(cell.y - city_c.y)))
		if dc < min_city:
			min_city = dc
		for tc in wg.town_centers:
			var dt: float = Vector2(cell.x - tc.x, cell.y - tc.y).length()
			var key := str(tc)
			if not water_min_town.has(key) or dt < float(water_min_town[key]):
				water_min_town[key] = dt
	# 建筑矩形内不得有水（城+镇所有登记建筑）
	var rects: Array = []
	var binfo: Dictionary = wg.city_info.get("buildings", {})
	for key in binfo:
		var b: Dictionary = binfo[key]
		var a: Vector2i = b["anchor"]
		var fp: Vector2i = b["fp"]
		rects.append(Rect2i(a, fp))
	for tc in wg.town_centers:
		# town_info 键为 Vector2i，town_centers 存 Vector2——取键需显式转换
		var tci := Vector2i(int(tc.x), int(tc.y))
		var tb: Dictionary = wg.town_info.get(tci, {}).get("buildings", {}) if wg.get("town_info") != null else {}
		for key in tb:
			var b2: Dictionary = tb[key]
			var a2: Vector2i = b2["anchor"]
			var fp2: Vector2i = b2["fp"]
			rects.append(Rect2i(a2, fp2))
	for r in rects:
		for dx in range(r.size.x):
			for dy in range(r.size.y):
				if wg.get_tile_id(r.position.x + dx, r.position.y + dy) == 5:
					footprint_water += 1
	var city_water := 0
	var city_water_cells := []
	var ch: int = wg.city_half
	for dx in range(-ch + 1, ch):
		for dy in range(-ch + 1, ch):
			if wg.get_tile_id(city_c.x + dx, city_c.y + dy) == 5:
				city_water += 1
				if city_water_cells.size() < 20:
					var ov = wg.override_cells.get(Vector2i(city_c.x + dx, city_c.y + dy), "none")
					city_water_cells.append([dx, dy, str(ov)])
	data["water"] = {"min_dist_city": min_city, "min_dist_towns": water_min_town,
		"footprint_water": footprint_water, "city_water": city_water,
		"city_water_cells": city_water_cells}

	# ---- 4) 城池组：从广场 BFS，四门与全部 door_px 可达性 ----
	var reach := {}
	var q: Array = [city_c]
	reach[city_c] = true
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var bound: int = ch + 12
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		for d in dirs:
			var n: Vector2i = cur + d
			if reach.has(n):
				continue
			if absi(n.x - city_c.x) > bound or absi(n.y - city_c.y) > bound:
				continue
			if wg.get_tile_id(n.x, n.y) in wg.collision_tiles:
				continue
			reach[n] = true
			q.append(n)
	var gates := {
		"n": Vector2i(city_c.x, city_c.y - ch), "s": Vector2i(city_c.x, city_c.y + ch),
		"w": Vector2i(city_c.x - ch, city_c.y), "e": Vector2i(city_c.x + ch, city_c.y),
	}
	var gates_ok := {}
	for g in gates:
		gates_ok[g] = reach.has(gates[g])
	var doors_ok := {}
	for key in binfo:
		var dp: Vector2 = binfo[key]["door_px"]
		var dt2 := Vector2i(int(floor(dp.x / 16.0)), int(floor(dp.y / 16.0)))
		doors_ok[key] = reach.has(dt2)
	data["city"] = {"gates": gates_ok, "doors": doors_ok,
		"center": [city_c.x, city_c.y], "half": ch}   # v4 M0：城心/半边登记制输出（废 python 硬编码）

	# ---- 4b) W2 唐制城：坊/市存在性 + 坊内连通（中巷格可达）+ 坊内房间距≥2 ----
	var wards: Array = wg.city_info.get("wards", [])
	var markets: Array = wg.city_info.get("markets", [])
	data["city"]["wards_n"] = wards.size()
	data["city"]["markets_n"] = markets.size()
	var ward_reach := {}
	var spacing_ok := true
	var spacing_detail := {}
	for w in wards:
		var wr: Rect2i = w["rect"]
		var ar := Rect2i(wr.position + city_c, wr.size)
		# 坊内中横巷中点（坊门连通则从广场 BFS 可达）
		var mid := Vector2i(ar.position.x + ar.size.x / 2, ar.position.y + ar.size.y / 2)
		ward_reach[w["name"]] = reach.has(mid)
		# 同坊建筑 footprint 各膨胀 1 格后两两不相交 = 间隙 ≥2 格（防火巷）
		var rms: Array = []
		for key in binfo:
			var b: Dictionary = binfo[key]
			var ba: Vector2i = b["anchor"]
			var bf: Vector2i = b["fp"]
			var br := Rect2i(ba, bf).grow(1)
			if ar.intersects(Rect2i(ba, bf)):
				for other in rms:
					if br.intersects(other):
						spacing_ok = false
						spacing_detail[key] = str(other)
				rms.append(br)
	data["city"]["ward_reach"] = ward_reach
	data["city"]["room_spacing_ok"] = spacing_ok
	data["city"]["spacing_detail"] = spacing_detail

	# ---- 4c) W3 门派领地：在位/主殿/界碑环闭合（8 采样点=四角+四边中点）----
	var sects: Array = []
	for sname in wg.sect_info:
		var s: Dictionary = wg.sect_info[sname]
		var sc: Vector2i = s["center"]
		var r: int = int(s["radius"])
		var hall: Vector2i = s["hall"]
		var hall_ok: bool = wg.get_tile_id(hall.x, hall.y) == 39
		var stele_ok := true
		var stele_n := 0
		for p in [Vector2i(-r, -r), Vector2i(0, -r), Vector2i(r, -r), Vector2i(r, 0),
				Vector2i(r, r), Vector2i(0, r), Vector2i(-r, r), Vector2i(-r, 0)]:
			# 语义（规则 v3）：环上任意点沿边 ±5 格内必有界碑（=每 6 格一座，环闭合）；
			# 采样点自身为水 → 碑位按铺设语义跳过（湖畔派环可穿湖），不计失败
			if wg.get_tile_id(sc.x + p.x, sc.y + p.y) == 5:
				stele_n += 1
				continue
			var dirs2: Array = []
			if absi(p.x) == r and absi(p.y) == r:
				dirs2 = [Vector2i(signi(p.x), 0), Vector2i(0, signi(p.y))]   # 角：两个切向
			elif absi(p.x) == r:
				dirs2 = [Vector2i(0, 1), Vector2i(0, -1)]   # 竖边：y 切向
			else:
				dirs2 = [Vector2i(1, 0), Vector2i(-1, 0)]   # 横边：x 切向
			var okp := false
			for dvec in dirs2:
				for d in range(-5, 6):
					var sq: Vector2i = sc + p + dvec * d
					if wg.get_tile_id(sq.x, sq.y) == 44:
						okp = true
						break
				if okp:
					break
			if okp:
				stele_n += 1
			else:
				stele_ok = false
		sects.append({"name": sname, "center": [sc.x, sc.y], "radius": r,
			"hall_ok": hall_ok, "stele_ok": stele_ok, "stele_samples": stele_n})
		if sname == "铁砂帮" or sname == "幽冥教":
			var ring_hist := {}
			var non44 := []
			for dx in range(-r, r + 1):
				for dy in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var tid2 = wg.get_tile_id(sc.x + dx, sc.y + dy)
					var k3 := str(tid2)
					ring_hist[k3] = int(ring_hist.get(k3, 0)) + 1
					if tid2 != 44 and non44.size() < 8:
						non44.append([dx, dy, k3])
			data["ring_" + sname] = {"hist": ring_hist, "non44": non44}
	data["sects"] = sects

	# ---- 4d) W4 村镇 v2：town_info 登记/模板/岗位/door 可达/渡亭在位 ----
	var towns: Array = []
	for tkey in wg.town_info:
		var t: Dictionary = wg.town_info[tkey]
		var tc2: Vector2i = t["center"]
		var half2: int = int(t["half"])
		# 从镇心 BFS（cheby 界 half+24，覆盖渡亭外环），验证全部 door_px 可达
		var treach := {tc2: true}
		var tq: Array = [tc2]
		var th := 0
		var tbound: int = half2 + 24
		while th < tq.size():
			var cur: Vector2i = tq[th]
			th += 1
			for d in dirs:
				var n2: Vector2i = cur + d
				if treach.has(n2):
					continue
				if absi(n2.x - tc2.x) > tbound or absi(n2.y - tc2.y) > tbound:
					continue
				if wg.get_tile_id(n2.x, n2.y) in wg.collision_tiles:
					continue
				treach[n2] = true
				tq.append(n2)
		var tdoors_ok := {}
		var tdoor_lane := {}
		var tjobs: Array = []
		for bkey2 in t["buildings"]:
			var b3: Dictionary = t["buildings"][bkey2]
			var dp2: Vector2 = b3["door_px"]
			var dcell := Vector2i(int(floor(dp2.x / 16.0)), int(floor(dp2.y / 16.0)))
			tdoors_ok[str(bkey2)] = treach.has(dcell)
			# v4 关系断言（立项书 §六.2"门在巷边"，对齐样板区标准"door 4 格内有巷"）：
			# door cheby≤4 内有巷瓦（path1/雪径42/广场35/桥17）。
			# legacy 象限撒点不保证（南象限门径穿 footprint、河岸 6 不可铺）→ since=M1 生效
			var lane := false
			for ddx in range(-4, 5):
				for ddy in range(-4, 5):
					var nc: Vector2i = dcell + Vector2i(ddx, ddy)
					if wg.get_tile_id(nc.x, nc.y) in [1, 42, 35, 17]:
						lane = true
						break
				if lane:
					break
			tdoor_lane[str(bkey2)] = lane
			if str(b3.get("job", "")) != "":
				tjobs.append(str(b3["job"]))
		# v4 M1 预埋：同镇建筑 footprint 膨胀 1 格两两不相交（防火巷，城 room_spacing 同款；
		# 现行象限撒点未保证间距 → since=M1 PENDING）
		var tover: Array = []
		var trects: Array = []
		for bkey3 in t["buildings"]:
			var b4: Dictionary = t["buildings"][bkey3]
			var br2 := Rect2i(Vector2i(b4["anchor"]), Vector2i(b4["fp"])).grow(1)
			for other2 in trects:
				if br2.intersects(other2):
					tover.append(str(bkey3))
					break
			trects.append(br2)
		# v4 密度报告（info）：镇圈自然格碎屑瓦片占比（prop 占用不在瓦片层，仅供参考）
		var deco_n := 0
		var nat_n := 0
		for dx4 in range(-half2, half2 + 1):
			for dy4 in range(-half2, half2 + 1):
				var tc4 := tc2 + Vector2i(dx4, dy4)
				var tid5: int = wg.get_tile_id(tc4.x, tc4.y)
				if tid5 in [2, 10, 11, 12, 15, 16, 17, 33, 35, 39, 40, 41, 42, 43, 3, 5, 7]:
					continue
				nat_n += 1
				if tid5 in [13, 55, 56, 57, 58, 59, 60, 61, 62, 63]:
					deco_n += 1
		towns.append({"center": [tc2.x, tc2.y], "template": str(t["template"]), "half": half2,
			"buildings": t["buildings"].size(), "jobs": tjobs, "doors": tdoors_ok,
			"door_lane": tdoor_lane, "overlaps": tover, "deco_ratio": float(deco_n) / maxf(1.0, float(nat_n)),
			"has_ferry": t["buildings"].has("ferry1"), "has_shrine": t["buildings"].has("shrine")})
	data["towns"] = towns

	# ---- 5) 连通性：出生点可达区规模 ----
	var spawn_reach: Dictionary = wg._bfs_reachable_from_spawn(dirs)
	data["reach_count"] = spawn_reach.size()

	# ---- 6) 河流/湖泊采样（W1）：河源群系/河终位置/湖心表 ----
	var rivers: Array = []
	for rp in wg.river_paths:
		var p: Array = rp["path"]
		var head_kinds := {}
		for i in range(mini(10, p.size())):
			var k: String = wg._biome_kind(p[i].x, p[i].y)
			head_kinds[k] = int(head_kinds.get(k, 0)) + 1
		var tail: Vector2i = p[p.size() - 1]
		rivers.append({"main": rp["main"], "len": p.size(), "head_kinds": head_kinds,
			"tail": [tail.x, tail.y], "tail_len": Vector2(tail.x, tail.y).length()})
	data["rivers"] = rivers
	var lakes: Array = []
	for l in wg.lake_centers:
		lakes.append({"pos": [l["pos"].x, l["pos"].y], "r": l["r"]})
	data["lakes"] = lakes

	# ---- 7) W4 NPC 驻留：落位锚距（meta anchor_px）+ 总量 ----
	var spawner := get_node_or_null("/root/Main/World/NPCSpawner")
	var npc_total := 0
	var npc_static_n := 0
	var npc_bad: Array = []
	if spawner != null:
		for npc in spawner.npc_list:
			npc_total += 1
			if npc.has_meta("anchor_px"):
				npc_static_n += 1
				var ap: Vector2 = npc.get_meta("anchor_px")
				var dist_t: float = npc.global_position.distance_to(ap) / 16.0
				if dist_t > 3.0:
					var nm := str(npc.name)
					if npc.npc_data != null:
						nm = str(npc.npc_data.npc_name)
					npc_bad.append({"name": nm, "dist": dist_t, "ref": str(npc.get_meta("anchor_ref"))})
	data["npc"] = {"total": npc_total, "static_n": npc_static_n, "bad_anchors": npc_bad}

	# ---- 8) W8 任务重启：告示板计数 + 主线自动启动标志（等 node_index 至多 3s 防同帧竞态） ----
	var story := get_node_or_null("/root/Main/MainStory")
	var story_started := false
	if story != null:
		for _i in range(12):
			if int(story.get("node_index")) >= 0 or int(GameManager.story_stage) > 0:
				story_started = true
				break
			await _wait(0.25)
	var qs := get_node_or_null("/root/Main/QuestSystem")
	var quest_data := {"available": -1, "active": -1, "pending_story": -1, "completed": -1,
		"frozen": bool(WorldFeatures.FLAG["quests_disabled"]), "story_started": story_started}
	if qs != null:
		quest_data["available"] = qs.available_quests.size()
		quest_data["active"] = qs.get_active_quests().size()
		quest_data["pending_story"] = qs.get_pending_story_quests().size()
		quest_data["completed"] = qs.completed_quests.size()
	data["quest"] = quest_data

	# ---- 9) W4 营地避城回归：常规营地 in_settlement=false；故事营地=0 ----
	var ms := get_node_or_null("/root/Main/World/MobSpawner")
	var camps: Array = []
	var story_camps_n := -1
	if ms != null:
		story_camps_n = ms.story_camps.size()
		for camp in ms.camps_runtime:
			camps.append({"name": str(camp["def"]["name"]),
				"in_settlement": wg.is_in_settlement(camp["center"])})
	data["mob"] = {"camps": camps, "story_camps": story_camps_n}

	# ---- 10) W5 石拱桥：17 段 prop 覆盖审计 + 官道桥（17 全在 override_cells，直接遍历） ----
	var bprops: Array = wg.get("bridge_props") if wg.get("bridge_props") != null else []
	var b17_total := 0
	var b17_covered := 0
	var b17_single := 0
	for cell in wg.override_cells:
		if int(wg.override_cells[cell]) != 17:
			continue
		b17_total += 1
		var joined := false
		for d in dirs:
			if int(wg.override_cells.get(cell + d, -1)) == 17:
				joined = true
				break
		if not joined:
			b17_single += 1   # 单格 17（修补转角）豁免 prop
			b17_covered += 1
			continue
		for bp in bprops:
			var rr: Array = bp["run_rect"]
			if cell.x >= int(rr[0]) and cell.x < int(rr[0]) + int(rr[2]) \
					and cell.y >= int(rr[1]) and cell.y < int(rr[1]) + int(rr[3]):
				b17_covered += 1
				break
	var bridges_out: Array = []
	for bp in bprops:
		var water_side := false
		for cell2 in bp["cells"]:
			for d in dirs:
				if int(wg.override_cells.get(cell2 + d, -1)) == 5:
					water_side = true
					break
			if water_side:
				break
		bridges_out.append({"axis": str(bp["axis"]), "run": bp["run_rect"], "water_side": water_side})
	var roads_out: Array = []
	var roads_raw: Array = wg.get("official_roads") if wg.get("official_roads") != null else []
	for rd in roads_raw:
		roads_out.append({"gate": str(rd["gate"]), "len": rd["cells"].size(),
			"bridge_cells": rd["bridge_cells"].size()})
	data["bridge"] = {"props": bridges_out, "t17_total": b17_total, "t17_covered": b17_covered,
		"t17_single": b17_single, "roads": roads_out}

	# ---- 11) W6 可行域：分区零碰撞 / 岩石聚簇 / 2×2 走廊 ----
	# 11a) SETTLEMENT/ROAD 分区采样：城圈/每镇圈/领地圈(除禁地矩形)/官道 cells——
	#      豁免登记制碰撞 {39 建筑,40 城墙,43 坊墙}
	var exempt := {"39": true, "40": true, "43": true}
	var zone_bad: Array = []
	var zone_checked := 0
	var data_water_sect := 0
	var city_c2: Vector2i = wg.CITY_POS
	var ch2: int = wg.city_half
	for dx in range(-ch2 + 1, ch2):
		for dy in range(-ch2 + 1, ch2):
			var c := city_c2 + Vector2i(dx, dy)
			zone_checked += 1
			var t := str(wg.get_tile_id(c.x, c.y))
			if wg.collision_tiles.has(wg.get_tile_id(c.x, c.y)) and not exempt.has(t):
				zone_bad.append(["city", c.x, c.y, t])
	for tc in wg.town_centers:
		# v4 M0：镇采样圆参数化 r=max(13, half+4)——镇 half 扩大后仍全覆盖（W6 硬编码 13 废除）
		var tk: Vector2i = Vector2i(int(tc.x), int(tc.y))
		var th2: int = int(wg.town_info[tk]["half"]) if wg.town_info.has(tk) else 8
		var tr: float = maxf(13.0, float(th2 + 4))
		for dx in range(-int(tr) - 1, int(tr) + 2):
			for dy in range(-int(tr) - 1, int(tr) + 2):
				if Vector2(dx, dy).length() >= tr:
					continue
				var c2 := Vector2i(int(tc.x) + dx, int(tc.y) + dy)
				zone_checked += 1
				var t2 := str(wg.get_tile_id(c2.x, c2.y))
				if wg.collision_tiles.has(wg.get_tile_id(c2.x, c2.y)) and not exempt.has(t2):
					zone_bad.append(["town", c2.x, c2.y, t2])
	for s in wg.sect_info.values():
		var sc: Vector2i = s["center"]
		var sr: int = int(s["radius"])
		# 核心可行承诺区 21×21（选址规则"21×21 水格≤4"的范围）——外环是势力范围（自然山环/水缘
		# 屏障，W3 feature）；景观水(5)单独计数豁免（湖畔/绿洲派依水建派），固体碰撞零容忍
		for dx in range(-10, 11):
			for dy in range(-10, 11):
				# 后山禁地崖带（北侧 y∈[-r,-r+8] 相对格）豁免——故意不可行区（HOLY_GROUND）
				if dy <= -sr + 8:
					continue
				var c3 := sc + Vector2i(dx, dy)
				zone_checked += 1
				var tid3: int = wg.get_tile_id(c3.x, c3.y)
				if tid3 == 5:
					data_water_sect += 1
					continue
				if wg.collision_tiles.has(tid3) and not exempt.has(str(tid3)):
					zone_bad.append(["sect", c3.x, c3.y, str(tid3)])
	for rd in roads_raw:
		for c4 in rd["cells"]:
			zone_checked += 1
			var t4 := str(wg.get_tile_id(c4.x, c4.y))
			if wg.collision_tiles.has(wg.get_tile_id(c4.x, c4.y)) and not exempt.has(t4):
				zone_bad.append(["road", c4.x, c4.y, t4])
	data["walk6"] = {"zone_checked": zone_checked, "zone_bad": zone_bad.slice(0, 12),
		"zone_bad_n": zone_bad.size(), "sect_water_n": data_water_sect}

	# 11b) 岩石聚簇：desert/snow WILD 散石 step2 采样——贴山率/孤立率/总量
	var rock_total := 0
	var rock_near := 0
	var rock_isolated := 0
	for y in range(-R + 8, R - 8, 2):
		for x in range(-R + 8, R - 8, 2):
			if wg.get_tile_id(x, y) != 14:
				continue
			if wg._biome_kind(x, y) == "mountain":
				continue   # 山体语义不计散石
			rock_total += 1
			var near_m := false
			for dy2 in range(-3, 4):
				for dx2 in range(-3, 4):
					if wg._biome_kind(x + dx2, y + dy2) == "mountain":
						near_m = true
						break
				if near_m:
					break
			if near_m:
				rock_near += 1
			var iso := true
			for d in dirs:
				if wg.get_tile_id(x + d.x, y + d.y) == 14:
					iso = false
					break
			if iso:
				rock_isolated += 1
	data["walk6"]["rock_total"] = rock_total
	data["walk6"]["rock_near_mountain"] = rock_near
	data["walk6"]["rock_isolated"] = rock_isolated

	# 11c) 2×2 走廊：块洪泛可达覆盖 vs 1 格可达
	var offs22 := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var ok22 := func(c: Vector2i) -> bool:
		for off in offs22:
			var n: Vector2i = c + off
			if absi(n.x) > R or absi(n.y) > R:
				return false
			if wg.get_tile_id(n.x, n.y) in wg.collision_tiles:
				return false
		return true
	var r1: Dictionary = wg._bfs_reachable_from_spawn(dirs)
	var start22 := Vector2i.ZERO
	var found22 := false
	for c in r1.keys():
		if ok22.call(c):
			start22 = c
			found22 = true
			break
	var covered_n := 0
	if found22:
		var r2 := {start22: true}
		var q2: Array = [start22]
		var h2 := 0
		while h2 < q2.size():
			var cur: Vector2i = q2[h2]
			h2 += 1
			for d in dirs:
				var n: Vector2i = cur + d
				if not r2.has(n) and ok22.call(n):
					r2[n] = true
					q2.append(n)
		var covered := {}
		for c in r2:
			for off in offs22:
				covered[c + off] = true
		covered_n = covered.size()
	data["walk6"]["reach1"] = r1.size()
	data["walk6"]["reach2_covered"] = covered_n

	# ---- 12) v4 M0 预算：全图 prop 节点计量（建筑/树/装饰/桥/样板区；上限断言 M2 生效） ----
	var prop_stat := {"building": get_tree().get_nodes_in_group("building_prop").size(),
		"tree": get_tree().get_nodes_in_group("tree_prop").size(),
		"city": get_tree().get_nodes_in_group("city_prop").size(),
		"bridge": get_tree().get_nodes_in_group("bridge_prop").size(),
		"demo": get_tree().get_nodes_in_group("demo_building").size()}
	prop_stat["total"] = int(prop_stat["building"]) + int(prop_stat["tree"]) + int(prop_stat["city"]) \
			+ int(prop_stat["bridge"]) + int(prop_stat["demo"])
	data["props"] = prop_stat

	_write(data)
	_log("[RegressProbe] data written: zones=%d adj_pairs=%d reach=%d" % [zones.size(), adj.size(), spawn_reach.size()])
	await _wait(0.3)
	get_tree().quit()

func _write(d: Dictionary):
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()
