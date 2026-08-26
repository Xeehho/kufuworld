extends Node

# 临时自动加载探针：等待世界生成 -> 传送玩家到森林 -> 截图存盘 -> 退出
const LOG := "C:/Learn/my-godot-project/tools/probe_log.txt"

func _log(msg: String):
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if FileAccess.file_exists(LOG):
		f.seek_end()
	f.store_line(msg)
	f.close()
	print(msg)

func _ready():
	# autoload先于主场景初始化，轮询等Main就绪
	var gen = null
	var player = null
	for i in range(300):
		gen = get_node_or_null("/root/Main/World/WorldGenerator")
		player = get_tree().get_first_node_in_group("player")
		if gen and player:
			break
		await get_tree().process_frame
	if gen == null or player == null:
		_log("[Probe] gen/player not found"); get_tree().quit(); return
	await get_tree().create_timer(6.0).timeout
	# 螺旋搜索密集森林中心
	var pt := Vector2i(int(player.global_position.x / 16), int(player.global_position.y / 16))
	var target := Vector2i.ZERO
	var found := false
	for r in range(4, 90):
		for dx in range(-r, r + 1, 2):
			for dy in range(-r, r + 1, 2):
				var c := pt + Vector2i(dx, dy)
				var n := 0
				for ox in range(-3, 4):
					for oy in range(-3, 4):
						if gen.get_terrain(c.x + ox, c.y + oy) == gen.Terrain.FOREST:
							n += 1
				if n >= 40:
					target = c; found = true; break
			if found: break
		if found: break
	_log("[Probe] forest target=%s found=%s" % [str(target), str(found)])
	if found:
		player.global_position = Vector2(target.x * 16 + 8, target.y * 16 + 8)
	# 清除天气与全屏色调，保证验证画面干净
	var wc = get_node_or_null("/root/Main/World/WeatherController")
	if wc: wc.queue_free()
	var cm = get_node_or_null("/root/Main/World/CanvasModulate")
	if cm: cm.color = Color(1, 1, 1, 1)
	await get_tree().create_timer(3.0).timeout
	for i in range(3):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("C:/Learn/my-godot-project/tools/probe_shot_%d.png" % i)
		_log("[Probe] shot %d saved" % i)
		await get_tree().create_timer(0.3).timeout
	# Phase B-3 阴影审计（森林机位、传送POI之前）：树脚阴影中心 vs 同面控制点
	var vp := get_viewport()
	var img3 := vp.get_texture().get_image()
	var ct := vp.get_canvas_transform()
	var ratios: Array[float] = []
	for prop in get_tree().get_nodes_in_group("tree_prop"):
		if not prop is Sprite2D:
			continue
		var sh: Node = null
		for c in prop.get_children():
			if c.is_in_group("tree_shadow"):
				sh = c
				break
		if sh == null or not sh is Sprite2D:
			continue
		var sw: float = (sh as Sprite2D).scale.x * 48.0
		var center_wp: Vector2 = (sh as Node2D).global_position
		var ctrl_wp: Vector2 = center_wp + Vector2(sw * 0.5 + 6.0, 0)
		var sp: Vector2 = ct * center_wp
		var sc: Vector2 = ct * ctrl_wp
		var vr := vp.get_visible_rect().size
		if sp.x < 1 or sp.y < 1 or sp.x >= vr.x - 1 or sp.y >= vr.y - 1:
			continue
		if sc.x < 1 or sc.y < 1 or sc.x >= vr.x - 1 or sc.y >= vr.y - 1:
			continue
		var cu := img3.get_pixelv(Vector2i(sp))
		var cc := img3.get_pixelv(Vector2i(sc))
		# 只统计"控制点是草地(绿色占优)"的样本对，排除树冠/岩壁/水面干扰
		if cc.g > cc.r + 0.04 and cc.g > cc.b + 0.04 and cc.g > 0.15:
			ratios.append((cu.r + cu.g + cu.b) / max(cc.r + cc.g + cc.b, 0.001))
	if ratios.size() > 0:
		ratios.sort()
		var mid: float = ratios[int(ratios.size() / 2)]
		_log("[ShadowAudit] pairs=%d median_under_over_ctrl=%.2f min=%.2f max=%.2f" % [ratios.size(), mid, ratios[0], ratios[ratios.size() - 1]])
	else:
		_log("[ShadowAudit] no grass-ground shadow pairs sampled")
	# Phase B：追加城镇/POI机位，验证房屋黛青顶与装饰瓦片（POI挂在WorldGenerator下）
	var poi = null
	for child in gen.get_children():
		if String(child.name).begins_with("POI_"):
			poi = child
			break
	if poi and player:
		player.global_position = (poi as Node2D).global_position
		_log("[Probe] teleported to POI %s" % String(poi.name))
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png("C:/Learn/my-godot-project/tools/probe_shot_3.png")
		_log("[Probe] shot 3 saved")
	else:
		_log("[Probe] no POI found for town shot")
	_log("[Probe] done")
	get_tree().quit()