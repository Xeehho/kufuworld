extends Node

# 视觉审计临时探针（2026-08-31 优化验收）：传送机位截图——青石城/城镇/雪原/群系边界
# 复用 run_shots.py 的临时 autoload 模式；跑完由 runner 还原 project.godot（陷阱备忘 §五33）
const LOG := "C:/Learn/my-godot-project/tools/probe_biome_log.txt"

func _log(m):
	var f := FileAccess.open(LOG, FileAccess.WRITE if not FileAccess.file_exists(LOG) else FileAccess.READ_WRITE)
	if f and FileAccess.file_exists(LOG):
		f.seek_end()
	f.store_line(m)
	f.close()
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

func _shot(name_: String):
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Learn/my-godot-project/tools/vshot_" + name_ + ".png")
	_log("shot saved: " + name_)

func _teleport(player, px: Vector2):
	player.global_position = px
	await _wait(1.2)   # 等chunk加载+相机平滑收敛

func _find_walkable_near(wg, tile: Vector2i, max_r: int) -> Vector2i:
	for r in range(max_r):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := tile + Vector2i(dx, dy)
				if Vector2(c.x, c.y).length() > wg.WORLD_RADIUS - 8:
					continue
				if not (wg.get_tile_id(c.x, c.y) in wg.collision_tiles):
					return c
	return tile

func _ready():
	await _wait(3.0)   # autoload先于主场景ready：必须先等World/WorldGenerator建好再查找
	var wg = _wg()
	if wg == null:
		_log("FATAL: world generator not found")
		get_tree().quit()
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		_log("FATAL: player not found")
		get_tree().quit()
		return

	# ---- 复刻 _setup_biomes 找雪原首府（同种子同公式）----
	var kinds: Array = ["plains", "forest", "bamboo", "mountain", "desert", "snow", "lake"]
	var rng := RandomNumberGenerator.new()
	rng.seed = wg.WORLD_SEED + 777
	var count := kinds.size() * 2
	var snow_seeds: Array = []
	for i in range(count):
		var ang := TAU * i / count + rng.randf_range(-0.3, 0.3)
		var rad := rng.randf_range(30.0, wg.WORLD_RADIUS - 24.0)
		var pos := Vector2i(int(cos(ang) * rad), int(sin(ang) * rad))
		if kinds[i % kinds.size()] == "snow":
			snow_seeds.append(pos)
	_log("snow seeds: " + str(snow_seeds))

	# ---- 定量违和指标：雪原首府周边48x48瓦片分布（应见34/3/4/14，禁见0/18草、13/37花、16田）----
	for k in range(snow_seeds.size()):
		var counts := {}
		for dx in range(-24, 25):
			for dy in range(-24, 25):
				var c: Vector2i = snow_seeds[k] + Vector2i(dx, dy)
				var id = wg.get_tile_id(c.x, c.y)
				counts[id] = int(counts.get(id, 0)) + 1
		var pairs := []
		for id in counts:
			pairs.append("%d:%d" % [id, counts[id]])
		pairs.sort()
		_log("snow[%d] tile histogram @%s: %s" % [k, str(snow_seeds[k]), ", ".join(pairs)])

	# 1) 青石城：广场南侧望向府衙/主街建筑群
	await _teleport(player, Vector2(75 * 16 + 8, 6 * 16))
	await _shot("city_plaza")
	# 2) 城北府衙近景
	await _teleport(player, Vector2((75 - 5) * 16 + 8, (0 - 20 + 6) * 16))
	await _shot("city_yamen")
	# 3) 城镇（可达中心最近的第一座）
	if wg.town_centers.size() > 0:
		var tc: Vector2 = wg.town_centers[0]
		var t2: Vector2i = await _find_walkable_near(wg, Vector2i(int(tc.x), int(tc.y)), 6)
		await _teleport(player, Vector2(t2.x * 16 + 8, t2.y * 16 + 8))
		await _shot("town")
	# 4) 雪原两处：直接传送到首府原点（可能落在崖上卡住1秒，仅截图用）
	var names := ["snow_a", "snow_b"]
	for k in range(snow_seeds.size()):
		await _teleport(player, Vector2(snow_seeds[k].x * 16 + 8, snow_seeds[k].y * 16 + 8))
		await _shot(names[k])

	# 5) 2026-08-31新增断言：营地必须全在城外；全图水面只允许被桥(17)覆写
	await _wait(2.0)   # 等MobSpawner._process懒初始化
	var ms = get_tree().get_first_node_in_group("mob_spawner")
	if ms != null:
		for camp in ms.camps_runtime:
			var in_city: bool = wg.is_in_settlement(camp["center"])
			_log("CAMP_CHECK %s center=%s in_settlement=%s" % [str(camp["def"]["name"]), str(camp["center"]), str(in_city)])
	else:
		_log("CAMP_CHECK skip: mob_spawner not found")
	var water_over := 0
	var water_over_kinds := {}
	for cell in wg.override_cells:
		if wg.get_tile_id(cell.x, cell.y) == 5 and int(wg.override_cells[cell]) != 17:
			water_over += 1
			var k2 := str(wg.override_cells[cell])
			water_over_kinds[k2] = int(water_over_kinds.get(k2, 0)) + 1
	_log("WATER_OVERWRITE non-bridge=%d kinds=%s (expect 0)" % [water_over, str(water_over_kinds)])

	# 6) 城内河道穿入检查（河道若进城需核查固定建筑锚点是否落水）
	var cw := 0
	for dx in range(wg.CITY_HALF * -1 + 1, wg.CITY_HALF):
		for dy in range(wg.CITY_HALF * -1 + 1, wg.CITY_HALF):
			if wg.get_tile_id(wg.CITY_POS.x + dx, wg.CITY_POS.y + dy) == 5:
				cw += 1
	_log("CITY_WATER interior=%d (0=河不进城)" % cw)

	_log("ALL_BIOME_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
