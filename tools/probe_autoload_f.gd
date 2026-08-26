extends Node
# Phase F 运行时探针：验证世界生成/大建筑/NPC/着装/新HUD（结果写tools/probe_f_log.txt）

var lines: Array = []

func _ready():
	await get_tree().process_frame
	for i in range(30):
		await get_tree().process_frame
	_run()

func _log(s: String):
	lines.append(s)

func _run():
	var main = get_node_or_null("/root/Main")
	_log("main_exists=" + str(main != null))
	if main == null:
		_finish()
		return
	var world = main.get_node_or_null("World")
	var wg = world.get_node_or_null("WorldGenerator") if world else null
	_log("worldgen=" + str(wg != null))
	if wg:
		_log("biome_seeds=" + str(wg.biome_seeds.size()))
		# footprint统计
		var fp_count := 0
		for v in wg.override_cells.values():
			if v == 39:
				fp_count += 1
		_log("footprint_tiles=" + str(fp_count))
		# 大建筑节点
		var bld_nodes := get_tree().get_nodes_in_group("building_prop")
		_log("building_props=" + str(bld_nodes.size()))
		var allnames := []
		for c in world.get_children():
			allnames.append(String(c.name))
		_log("world_children=" + str(allnames))
		# 可达区规模
		_log("reachable=" + str(wg.reachable_cells.size()))
		# 连通性全图扫描：不可达可走格数量（应为0或极小）
		var orphan := 0
		var sample := 0
		for wy in range(-110, 111, 1):
			for wx in range(-110, 111, 1):
				if Vector2(wx, wy).length() > 108.0:
					continue
				var tid: int = wg.get_tile_id(wx, wy)
				if tid in wg.collision_tiles:
					continue
				if not wg.reachable_cells.has(Vector2i(wx, wy)):
					orphan += 1
		_log("orphan_walkable=" + str(orphan))
		# 城镇道路规模(抽样统计id=1 override数)
		var road := 0
		for v in wg.override_cells.values():
			if v == 1:
				road += 1
		_log("road_overrides=" + str(road))
	# NPC
	var npcs = get_tree().get_nodes_in_group("npc")
	_log("npc_count=" + str(npcs.size()))
	var tag_hidden := true
	for n in npcs:
		if "NameTag" in n and n.get_node("NameTag").visible:
			tag_hidden = false
	_log("nametags_default_hidden=" + str(tag_hidden))
	# 玩家着装采样（躯干中心像素应为黛蓝色系）
	var players = get_tree().get_nodes_in_group("player")
	_log("player_exists=" + str(players.size() > 0))
	if players.size() > 0:
		var spr: AnimatedSprite2D = players[0].get_node_or_null("AnimatedSprite2D")
		if spr and spr.sprite_frames and spr.sprite_frames.has_animation("idle_down"):
			var tex = spr.sprite_frames.get_frame_texture("idle_down", 0)
			if tex:
				var img := tex.get_image()
				var robe := 0
				var hair := 0
				for x in range(img.get_width()):
					for y in range(img.get_height()):
						var c := img.get_pixel(x, y)
						if abs(c.r8 - 64) < 25 and abs(c.g8 - 76) < 25 and abs(c.b8 - 112) < 25:
							robe += 1
						elif abs(c.r8 - 38) < 20 and abs(c.g8 - 30) < 20 and abs(c.b8 - 44) < 20:
							hair += 1
				_log("robe_px=" + str(robe) + " hair_px=" + str(hair))
		else:
			_log("player_frames_missing=true")
	# 新HUD
	var ui = world.get_node_or_null("UI") if world else null
	_log("questlog=" + str(ui != null and ui.get_node_or_null("QuestLogHUD") != null))
	var has_cs: bool = ui != null and ui.get_node_or_null("CharacterSheet") != null
	_log("charsheet=" + str(has_cs))
	_finish()

func _finish():
	lines.append("PROBE_F_DONE")
	var f = FileAccess.open("res://tools/probe_f_log.txt", FileAccess.WRITE)
	if f:
		f.store_string(NL_JOIN(lines))
		f.close()
	get_tree().quit()

func NL_JOIN(arr: Array) -> String:
	var out := ""
	for l in arr:
		out += l + "\n"
	return out
