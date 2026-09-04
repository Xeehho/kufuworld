extends Node

## 山地死路取证探针（临时 autoload 注入，run_mtn_probe.py 调度）
## 只采样写 JSON + 截图，断言判定在 python 侧；跑完由 runner 还原 project.godot（陷阱备忘 §五33）。
## 指标：度≤1死路格 / 叶子剥离闭包（死路子树总量）/ 山地可行格到出口深度（陷深感受）
## 出口定义：非山群系可行格 ∪ 官道格 ∪ 桥17。深度=4向BFS步数。

const OUT := "C:/Learn/my-godot-project/tools/mtn_maze_data.json"
const LOG := "C:/Learn/my-godot-project/tools/mtn_maze_log.txt"

func _log(m):
	print(m)
	var f := FileAccess.open(LOG, FileAccess.WRITE if not FileAccess.file_exists(LOG) else FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line(m)
		f.close()

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _wg():
	var world := get_node_or_null("/root/Main/World")
	if world == null:
		return null
	for c in world.get_children():
		var s = c.get_script()
		if s != null and str(s.resource_path).ends_with("world_generator.gd"):
			return c
	return null

func _shot(path: String):
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	_log("shot saved: " + path)

func _ready():
	var tag := OS.get_environment("MTN_TAG")
	if tag == "":
		tag = "x"
	await _wait(4.5)
	var wg = _wg()
	if wg == null:
		var f2 := FileAccess.open(OUT, FileAccess.WRITE)
		f2.store_string(JSON.stringify({"FATAL": "world_generator not found"}))
		f2.close()
		get_tree().quit()
		return
	var R: int = wg.WORLD_RADIUS
	var B: int = R - 6
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var t0 := Time.get_ticks_msec()

	# ---- 1) 全图瓦片缓存 + 可行集（山地/雪群系范围）----
	var tile := {}
	var walk := {}
	var mtn_cells := {}
	for y in range(-B, B + 1):
		for x in range(-B, B + 1):
			var tid: int = wg.get_tile_id(x, y)
			tile[Vector2i(x, y)] = tid
			if tid in wg.collision_tiles:
				continue
			var c := Vector2i(x, y)
			walk[c] = true
			if wg._biome_kind(x, y) == "mountain":
				mtn_cells[c] = true
	_log("tile cache done in %dms walk=%d mtn=%d" % [Time.get_ticks_msec() - t0, walk.size(), mtn_cells.size()])

	# ---- 2) 度统计 + 死路子树（叶子剥离闭包，剥离集仅限山地可行格）----
	var deg := {}
	for c in walk:
		var d := 0
		for dd in dirs:
			if walk.has(c + dd):
				d += 1
		deg[c] = d
	var leaf1_mtn := 0
	var leaf1_all := 0
	for c in walk:
		if deg[c] <= 1:
			leaf1_all += 1
			if mtn_cells.has(c):
				leaf1_mtn += 1
	var stripped := {}
	var t1 := Time.get_ticks_msec()
	var changed := true
	var rounds := 0
	while changed and rounds < 128:
		changed = false
		rounds += 1
		var mark := []
		for c in mtn_cells:
			if stripped.has(c) or not walk.has(c):
				continue
			var d := 0
			for dd in dirs:
				var n: Vector2i = c + dd
				if walk.has(n) and not stripped.has(n):
					d += 1
			if d <= 1:
				mark.append(c)
		for c in mark:
			stripped[c] = true
			changed = true
	var strip_ms := Time.get_ticks_msec() - t1
	_log("leaf-strip fixpoint: rounds=%d stripped=%d in %dms" % [rounds, stripped.size(), strip_ms])

	# ---- 3) 陷深：出口=非山可行格∪官道∪桥17∪山口网格（W9 登记表，修复前为空）；山地可行格 4 向 BFS ----
	var src := {}
	for c in walk:
		if not mtn_cells.has(c):
			src[c] = true
	for rd in wg.official_roads:
		for c in rd["cells"]:
			if walk.has(c):
				src[c] = true
	for c in wg.override_cells:
		if walk.has(c) and int(wg.override_cells[c]) == 17:
			src[c] = true
	var passes = wg.get("mtn_pass_cells")
	if passes != null:
		for c in passes:
			if walk.has(c):
				src[c] = true
	var depth := {}
	var q: Array = []
	for c in src:
		depth[c] = 0
		q.append(c)
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		var dc: int = depth[cur]
		for dd in dirs:
			var n: Vector2i = cur + dd
			if depth.has(n) or not mtn_cells.has(n):
				continue
			depth[n] = dc + 1
			q.append(n)
	var dn := 0
	var dmax := 0
	var dsum := 0
	var dle8 := 0
	var dle16 := 0
	var deepest := Vector2i.ZERO
	var ddeepest := -1
	for c in mtn_cells:
		dn += 1
		var dv: int = int(depth.get(c, 999))
		if dv == 999:
			continue
		dsum += dv
		if dv > dmax:
			dmax = dv
		if dv <= 8:
			dle8 += 1
		if dv <= 16:
			dle16 += 1
		if dv > ddeepest:
			ddeepest = dv
			deepest = c

	# ---- 4) 城南箱体（用户截图区：城心(75,0) 南门外）指标 + 该箱最深点 ----
	var bx0 := 30
	var bx1 := 120
	var by0 := 0
	var by1 := 110
	var box_mtn := 0
	var box_leaf := 0
	var box_strip := 0
	var box_deep_n := 0
	var box_deep_sum := 0
	var box_deepest := Vector2i.ZERO
	var box_deepest_d := -1
	for y in range(by0, by1):
		for x in range(bx0, bx1):
			var c := Vector2i(x, y)
			if not mtn_cells.has(c):
				continue
			box_mtn += 1
			if deg.get(c, 0) <= 1:
				box_leaf += 1
			if stripped.has(c):
				box_strip += 1
			var dv: int = int(depth.get(c, 999))
			if dv == 999:
				continue
			box_deep_n += 1
			box_deep_sum += dv
			if dv > box_deepest_d:
				box_deepest_d = dv
				box_deepest = c

	# ---- 5) 粗地图dump（城南箱，1格1字符）----
	var map: Array = []
	for y in range(by0, by1):
		var line := ""
		for x in range(bx0, bx1):
			var c := Vector2i(x, y)
			var tid: int = tile.get(c, -1)
			if stripped.has(c):
				line += "x"   # 死路子树（诊断剥离集）
			elif tid in [3, 7]:
				line += "#"
			elif tid == 5:
				line += "~"
			elif tid == 14:
				line += "R"
			elif tid in [1, 42, 35]:
				line += "o"
			elif tid == 17:
				line += "b"
			elif tid in [4, 8, 9]:
				line += "T"
			elif tid in wg.collision_tiles:
				line += "+"
			else:
				line += "."
		map.append(line)

	var data := {
		"tag": tag,
		"global": {
			"walk": walk.size(), "mtn_walk": mtn_cells.size(),
			"leaf1_all": leaf1_all, "leaf1_mtn": leaf1_mtn,
			"strip_total": stripped.size(), "strip_rounds": rounds,
			"depth_n": dn, "depth_max": dmax,
			"depth_mean": float(dsum) / maxf(1.0, float(dn)),
			"depth_le8_ratio": float(dle8) / maxf(1.0, float(dn)),
			"depth_le16_ratio": float(dle16) / maxf(1.0, float(dn)),
			"ms_cache": Time.get_ticks_msec() - t0 - strip_ms,
		},
		"box": {"x0": bx0, "y0": by0, "x1": bx1, "y1": by1,
			"mtn": box_mtn, "leaf1": box_leaf, "strip": box_strip,
			"deep_n": box_deep_n, "deep_mean": float(box_deep_sum) / maxf(1.0, float(box_deep_n)),
			"deepest": [box_deepest.x, box_deepest.y], "deepest_d": box_deepest_d},
		"map": map,
	}
	var f3 := FileAccess.open(OUT, FileAccess.WRITE)
	f3.store_string(JSON.stringify(data))
	f3.close()
	_log("[MtnMaze] data written tag=%s" % tag)

	# ---- 6) 截图：南门外机位 + 箱内最深点机位（清天气，陷阱#12）----
	var cm := get_node_or_null("/root/Main/World/CanvasModulate")
	if cm:
		cm.color = Color(1, 1, 1)
	var wc := get_node_or_null("/root/Main/World/WeatherController")
	if wc:
		wc.set_process(false)
		for c in wc.get_children():
			if c is CanvasItem:
				c.visible = false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		player.global_position = Vector2(-40 * 16.0 + 8.0, -95 * 16.0 + 8.0)
		await _wait(1.6)
		await _shot("C:/Learn/my-godot-project/tools/mtn_%s_pass2.png" % tag)
		player.global_position = Vector2(box_deepest.x * 16.0 + 8.0, box_deepest.y * 16.0 + 8.0)
		await _wait(1.6)
		await _shot("C:/Learn/my-godot-project/tools/mtn_%s_deep.png" % tag)
	_log("ALL_DONE")
	await _wait(0.3)
	get_tree().quit()
