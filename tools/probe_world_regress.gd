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
		for dx in range(-24, 25):
			for dy in range(-24, 25):
				var id = wg.get_tile_id(c0.x + dx, c0.y + dy)
				var key := str(id)
				hist[key] = int(hist.get(key, 0)) + 1
		zones[k] = {"center": [c0.x, c0.y], "hist": hist, "samples": cells.size()}
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
		var dc: float = Vector2(cell.x - city_c.x, cell.y - city_c.y).length()
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
		binfo = wg.town_buildings.get(tc, {}) if wg.get("town_buildings") != null else {}
		for key in binfo:
			var b2: Dictionary = binfo[key]
			var a2: Vector2i = b2["anchor"]
			var fp2: Vector2i = b2["fp"]
			rects.append(Rect2i(a2, fp2))
	for r in rects:
		for dx in range(r.size.x):
			for dy in range(r.size.y):
				if wg.get_tile_id(r.position.x + dx, r.position.y + dy) == 5:
					footprint_water += 1
	var city_water := 0
	var ch: int = wg.CITY_HALF
	for dx in range(-ch + 1, ch):
		for dy in range(-ch + 1, ch):
			if wg.get_tile_id(city_c.x + dx, city_c.y + dy) == 5:
				city_water += 1
	data["water"] = {"min_dist_city": min_city, "min_dist_towns": water_min_town,
		"footprint_water": footprint_water, "city_water": city_water}

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
	data["city"] = {"gates": gates_ok, "doors": doors_ok}

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

	_write(data)
	_log("[RegressProbe] data written: zones=%d adj_pairs=%d reach=%d" % [zones.size(), adj.size(), spawn_reach.size()])
	await _wait(0.3)
	get_tree().quit()

func _write(d: Dictionary):
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()
