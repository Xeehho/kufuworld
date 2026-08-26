extends Node

# Phase G 临时探针：G1玩家四向着装帧 / G2树道具网格与水邻抑制 / G3城镇净空 / G4 Y-sort交融
# 用法：run_probe_g.py 临时注入[autoload] -> 窗口跑一局 -> 文件日志 tools/probe_g_log.txt -> 自动还原
const LOG := "C:/Learn/my-godot-project/tools/probe_g_log.txt"
const SHOT := "C:/Learn/my-godot-project/tools/probe_g_shot_%d.png"
var pass_n := 0
var fail_n := 0

func _log(msg: String):
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f and FileAccess.file_exists(LOG):
		f.seek_end()
	if f == null:
		f = FileAccess.open(LOG, FileAccess.WRITE)
	f.store_line(msg)
	f.close()
	print(msg)

func _chk(cond: bool, name_: String, detail := ""):
	if cond:
		pass_n += 1
		_log("[PASS] %s %s" % [name_, detail])
	else:
		fail_n += 1
		_log("[FAIL] %s %s" % [name_, detail])

func _ready():
	var gen = null
	var player = null
	for i in range(600):
		gen = get_node_or_null("/root/Main/World/WorldGenerator")
		player = get_tree().get_first_node_in_group("player")
		if gen and player:
			break
		await get_tree().process_frame
	if gen == null or player == null:
		_log("[Probe] gen/player not found")
		get_tree().quit()
		return
	await get_tree().create_timer(4.0).timeout

	_log("=== G-LOGIC ===")
	# ---- G2 树表网格与贴图边界 ----
	var expect_cells := {4: Vector2i(32, 80), 8: Vector2i(64, 64), 9: Vector2i(48, 80)}
	for tid in expect_cells.keys():
		var info: Dictionary = gen.TREE_SHEETS[tid]
		_chk(info["cell"] == expect_cells[tid], "G2 cell[%d]" % tid, str(info["cell"]))
		var tex: Texture2D = gen._get_tree_sheet_texture(tid)
		if tex:
			var grid: Vector2i = gen._tree_grid(tid)
			var cell: Vector2i = info["cell"]
			_chk(tex.get_size().x >= grid.x * cell.x and tex.get_size().y >= grid.y * cell.y,
				"G2 atlas-inbounds[%d]" % tid, "%s grid=%s" % [str(tex.get_size()), str(grid)])
	# 树道具抽检：基点锚定+区域不越界+水邻抑制复核
	var props := get_tree().get_nodes_in_group("tree_prop")
	_chk(props.size() > 50, "G2 prop-count", str(props.size()))
	var bad_anchor := 0
	var bad_region := 0
	var near_water := 0
	for p in props:
		if not (p is Sprite2D):
			continue
		var sp := p as Sprite2D
		if not sp.has_meta("base_y") or absf(sp.position.y - float(sp.get_meta("base_y"))) > 0.01:
			bad_anchor += 1
		if sp.texture is AtlasTexture:
			var at := sp.texture as AtlasTexture
			var tsz: Vector2 = at.atlas.get_size()
			var reg := at.region
			if reg.position.x < 0.0 or reg.position.y < 0.0 or reg.end.x > tsz.x or reg.end.y > tsz.y:
				bad_region += 1
			# 与生成器闸门同口径：反推闸门格子(base_y=wy*16+20；x=wx*16+8+抖动，先减中心偏移8)
			var wy_a: int = int(round((float(sp.get_meta("base_y")) - 20.0) / 16.0))
			var wx_a: int = int(round((sp.position.x - 8.0) / 16.0))
			var r_audit: int = int(ceil(reg.size.x / 32.0)) + 1
			if gen._near_water(wx_a, wy_a, r_audit):
				near_water += 1
	_chk(bad_anchor == 0, "G4 tree-anchor", "bad=%d" % bad_anchor)
	_chk(bad_region == 0, "G2 atlas-region-valid", "bad=%d" % bad_region)
	_chk(near_water == 0, "G2 no-tree-near-water", "violations=%d" % near_water)

	# ---- G3 城镇净空 ----
	var rects: Array = gen._town_clear_rects
	_chk(rects.size() >= 3, "G3 clearance-zones", str(rects.size()))
	var viol := 0
	var samples := 0
	for r in rects:
		var ri: Rect2i = r
		for x in range(ri.position.x, ri.end.x, 2):
			for y in range(ri.position.y, ri.end.y, 2):
				samples += 1
				var t: int = gen.get_tile_id(x, y)
				if t == 4 or t == 8 or t == 9 or t == 14:
					viol += 1
					if viol <= 3:
						_log("[G3] viol cell=%s tid=%d" % [str(Vector2i(x, y)), t])
	_chk(viol == 0, "G3 no-tree-rock-in-clearance", "viol=%d/%d" % [viol, samples])

	# ---- G4 层级统一 ----
	_chk(player.z_index == 2, "G4 player-z", str(player.z_index))
	_chk(gen.y_sort_enabled, "G4 worldgen-ysort")
	var world: Node = gen.get_parent()
	_chk(world.y_sort_enabled, "G4 world-ysort")
	var ns := get_node_or_null("/root/Main/World/NPCSpawner")
	var ms := get_node_or_null("/root/Main/World/MobSpawner")
	_chk(ns != null and ns.y_sort_enabled, "G4 npcspawner-ysort")
	_chk(ms != null and ms.y_sort_enabled, "G4 mobspawner-ysort")
	var npcs := get_tree().get_nodes_in_group("npc")
	_chk(npcs.size() > 0 and npcs[0].z_index == 2, "G4 npc-z", str(npcs.size()))

	# ---- G1 帧动画完整性（四向×walk/idle非空且帧数一致）----
	var anim: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	if anim and anim.sprite_frames:
		for d in ["down", "left", "right", "up"]:
			var wn: String = "walk_" + str(d)
			var has := anim.sprite_frames.has_animation(wn)
			var fc := anim.sprite_frames.get_frame_count(wn) if has else 0
			_chk(has and fc == 6, "G1 frames-%s" % d, "count=%d" % fc)
	else:
		_chk(false, "G1 spriteframes-exist")

	# ---- 视觉机位 ----
	_log("=== G-VISUAL ===")
	var wc = get_node_or_null("/root/Main/World/WeatherController")
	if wc:
		wc.queue_free()
	var cm = get_node_or_null("/root/Main/World/CanvasModulate")
	if cm:
		cm.color = Color(1, 1, 1, 1)
	var cam: Camera2D = player.get_node_or_null("Camera2D")

	# 机位A/B：同一棵树 南侧(人前)/北侧(人后) —— Y-sort遮挡差分
	var target: Node2D = null
	for p in props:
		if p is Sprite2D and (p as Sprite2D).texture is AtlasTexture:
			var reg2: Rect2 = ((p as Sprite2D).texture as AtlasTexture).region
			if reg2.size.x >= 60.0:   # 橡树宽冠遮挡最明显
				target = p
				break
	if target == null and props.size() > 0:
		target = props[0]
	if target:
		var base: Vector2 = target.global_position
		player.global_position = base + Vector2(6, 26)   # 南=人在树前
		if cam:
			cam.reset_smoothing()
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT % 0)
		_log("[shot0] player SOUTH of tree base=%s" % str(base))
		player.global_position = base + Vector2(6, -14)   # 北=人被树冠遮
		if cam:
			cam.reset_smoothing()
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT % 1)
		_log("[shot1] player NORTH of tree")

	# 机位C：海岸线（找水陆交界，验证无树冠悬海）
	var coast := _find_coast(gen)
	_log("[coast] %s" % str(coast))
	if coast.x != -9999:
		player.global_position = Vector2(coast.x * 16 + 8, coast.y * 16 + 8)
		if cam:
			cam.reset_smoothing()
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT % 2)
		_log("[shot2] coastline captured")

	# 机位D：城镇中心（净空区中心）
	if rects.size() > 0:
		var r0: Rect2i = rects[0]
		var tc := Vector2((r0.position.x + r0.end.x) * 0.5, (r0.position.y + r0.end.y) * 0.5)
		player.global_position = Vector2(tc.x * 16, tc.y * 16)
		if cam:
			cam.reset_smoothing()
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT % 3)
		_log("[shot3] town center captured")

	_log("GPROBE DONE pass=%d fail=%d" % [pass_n, fail_n])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

func _find_coast(gen) -> Vector2:
	# 从世界边缘向内扫：第一格水+相邻陆地
	for r in range(118, 40, -2):
		for a in range(0, 360, 4):
			var wx := int(cos(deg_to_rad(a)) * r)
			var wy := int(sin(deg_to_rad(a)) * r)
			if gen.get_tile_id(wx, wy) == 5 and gen.get_tile_id(wx, wy - 4) != 5 and gen.get_tile_id(wx, wy - 4) not in [3, 7]:
				return Vector2(wx, wy - 4)
	return Vector2(-9999, -9999)
