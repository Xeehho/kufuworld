extends Node

# Phase G风格重构视觉探针：多机位截图（出生平原/城镇/山区/雪原/森林/小地图）
const LOG := "C:/Learn/my-godot-project/tools/probe_style_log.txt"

func _log(m):
	var f := FileAccess.open(LOG, FileAccess.WRITE if not FileAccess.file_exists(LOG) else FileAccess.READ_WRITE)
	if f and FileAccess.file_exists(LOG):
		f.seek_end()
	f.store_line(m)
	f.close()
	print(m)

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _shot(name_: String):
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Learn/my-godot-project/tools/sshot_" + name_ + ".png")
	_log("shot saved: " + name_)

func _tp(player, tile: Vector2i):
	player.global_position = Vector2(tile.x * 16 + 8, tile.y * 16 + 8)
	var cam = player.get_node_or_null("Camera2D")
	if cam and cam.has_method("reset_smoothing"):
		cam.reset_smoothing()

func _ready():
	var wg: Node2D = null
	var player = null
	for i in range(1200):
		wg = get_node_or_null("/root/Main/World/WorldGenerator")
		player = get_tree().get_first_node_in_group("player")
		if wg != null and player != null and wg.town_centers.size() > 0:
			break
		await get_tree().process_frame
	await _wait(3.0)
	_log("worldgen ready. radius=" + str(wg.WORLD_RADIUS) + " towns=" + str(wg.town_centers.size()) + " pois=" + str(wg.pois.size()))
	for b in wg.biome_seeds:
		_log("biome: " + str(b["kind"]) + " @ " + str(b["pos"]))

	# 0 出生平原
	await _shot("0_spawn")

	# 1 最近城镇
	if wg.town_centers.size() > 0:
		var tc: Vector2 = wg.town_centers[0]
		_tp(player, Vector2i(int(tc.x), int(tc.y)))
		await _wait(1.5)
		await _shot("1_town")

	# 2 山区
	for b in wg.biome_seeds:
		if b["kind"] == "mountain":
			_tp(player, b["pos"])
			await _wait(1.5)
			await _shot("2_mountain")
			break

	# 3 雪原
	for b in wg.biome_seeds:
		if b["kind"] == "snow":
			_tp(player, b["pos"])
			await _wait(1.5)
			await _shot("3_snow")
			break

	# 4 森林
	for b in wg.biome_seeds:
		if b["kind"] == "forest":
			_tp(player, b["pos"])
			await _wait(1.5)
			await _shot("4_forest")
			break

	# 5 森林+小地图开
	var mm = get_node_or_null("/root/Main/World/UI/MinimapHUD")
	if mm:
		mm._toggle()
		await _wait(1.2)
	await _shot("5_minimap")
	if mm:
		mm._toggle()

	# 6 古堡（找古堡POI传送+截图+模拟点击开信息面板）
	var castle_poi = null
	for p in wg.pois:
		if p["template"].poi_type == "古堡":
			castle_poi = p
			break
	if castle_poi != null:
		var cpos: Vector2 = castle_poi["position"]
		_tp(player, Vector2i(int(cpos.x / 16.0) + 3, int(cpos.y / 16.0) + 4))
		await _wait(1.5)
		await _shot("6_castle")
		# 模拟点击古堡（直接调用点击链，验证面板）
		var best: Node2D = null
		var best_d := 1e12
		for b in get_tree().get_nodes_in_group("building_prop"):
			if not b.has_meta("b_name"):
				continue
			var d: float = player.global_position.distance_to(b.global_position)
			if d < best_d:
				best_d = d
				best = b
		if best != null:
			_log("castle found: " + str(best.get_meta("b_name")) + " faction=" + str(best.get_meta("b_faction")) + " stance=" + str(best.get_meta("b_stance")))
			player._click_building_info(best)
			await _wait(0.5)
			await _shot("7_castle_info")
			var bih = get_node_or_null("/root/Main/World/UI/BuildingInfoHUD")
			if bih:
				bih.close_info()
	else:
		_log("WARN: no castle poi placed")

	_log("ALL_STYLE_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
