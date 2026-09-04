extends Node
# 临时自动加载探针：Phase C 视觉验证（窗口模式跑，逻辑探针已全绿）
# 布置农田(湿润)/成熟作物/四站台/双怪 于玩家周边，截图+输出锚点供python调色板审计
const LOG := "C:/Learn/my-godot-project/tools/probe_log.txt"

func _log(msg: String):
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(msg)
		f.close()
	print(msg)

func _ready():
	var farm = null
	var player = null
	for i in range(400):
		farm = get_node_or_null("/root/Main/World/FarmSystem")
		player = get_tree().get_first_node_in_group("player")
		if farm and player:
			break
		await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	# 清天气与色调
	var wc = get_node_or_null("/root/Main/World/WeatherController")
	if wc: wc.queue_free()
	var cm = get_node_or_null("/root/Main/World/CanvasModulate")
	if cm: cm.color = Color(1, 1, 1, 1)
	var gen = get_node_or_null("/root/Main/World/WorldGenerator")
	# 找一片3x3净空草地并站到中心
	var origin := Vector2i(int(player.global_position.x / 16), int(player.global_position.y / 16))
	var spot := Vector2i(-9999, -9999)
	for r in range(2, 40):
		var found := false
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := origin + Vector2i(dx, dy)
				var ok := true
				for ox in range(-1, 2):
					for oy in range(-2, 3):
						var tid = gen.get_tile_id(c.x + ox, c.y + oy)
						if tid != 0 and tid != 18:
							ok = false
				if ok:
					spot = c
					found = true
					break
			if found: break
		if found: break
	_log("[VProbe] spot=%s" % str(spot))
	player.global_position = Vector2(spot.x * 16.0 + 8.0, spot.y * 16.0 + 8.0)
	var cam = player.get_node_or_null("Camera2D")
	if cam: cam.reset_smoothing()
	player.facing = 2   # RIGHT，指示器应出现在右邻格
	await get_tree().process_frame
	await get_tree().process_frame
	# 脚下格开垦+浇水+种+催熟；右邻格开垦+浇水（无作物湿润田）
	var c0 := Vector2i(spot.x, spot.y + 1)
	var c1 := Vector2i(spot.x + 1, spot.y)
	var c2 := Vector2i(spot.x + 2, spot.y)
	_log("[VProbe] till_c0=%s" % str(farm.try_till(_cc(c0))["ok"]))
	_log("[VProbe] water_c0=%s" % str(farm.try_water(_cc(c0))["ok"]))
	_log("[VProbe] plant_c0=%s" % str(farm.try_plant(_cc(c0))["ok"]))
	farm.crops[c0]["days"] = 3
	farm.crops[c0]["stage"] = 3
	farm._update_crop_sprite(c0)
	_log("[VProbe] till_c1=%s" % str(farm.try_till(_cc(c1))["ok"]))
	_log("[VProbe] water_c1=%s" % str(farm.try_water(_cc(c1))["ok"]))
	_log("[VProbe] till_c2=%s" % str(farm.try_till(_cc(c2))["ok"]))
	_log("[VProbe] grounds_after=%d/%d/%d" % [farm._ground_id(c0), farm._ground_id(c1), farm._ground_id(c2)])
	# 站台一排摆在下方
	var st = get_node_or_null("/root/Main/World/StationSystem")
	var types := ["工作台", "熔炉", "炼丹台", "篝火"]
	var anchors := {}
	for i in range(types.size()):
		var p := Vector2((spot.x - 1 + i) * 16.0 + 8.0, (spot.y - 2) * 16.0 + 8.0)
		p = gen.find_nearest_reachable(p, 12)
		st.place_station(types[i], p)
		anchors[types[i]] = p
	# 两只怪分列左右（关AI防走位）
	var MobScript = load("res://scripts/mob.gd")
	var mob1 = CharacterBody2D.new()
	mob1.set_script(MobScript)
	mob1.position = player.global_position + Vector2(-70, -30)
	player.get_parent().add_child(mob1)
	mob1.setup("orc_warrior")
	var mob2 = CharacterBody2D.new()
	mob2.set_script(MobScript)
	mob2.position = player.global_position + Vector2(80, 30)
	player.get_parent().add_child(mob2)
	mob2.setup("skeleton_mage")
	await get_tree().process_frame
	mob1.set_physics_process(false)
	mob2.set_physics_process(false)
	await get_tree().create_timer(0.6).timeout
	if cam: cam.reset_smoothing()
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Learn/my-godot-project/tools/probe_shot_c.png")
	_log("[VProbe] shot saved")
	# 输出相机中心与各锚点世界坐标（python换算屏幕坐标采样）
	var cc: Vector2 = cam.get_screen_center_position() if cam else player.global_position
	_log("[VProbe] cam_center=%s zoom=%s vp=%s" % [str(cc), str(cam.zoom if cam else Vector2.ONE), str(img.get_size())])
	_log("[VProbe] indicator_cell=%s" % str(Vector2((spot.x + 1) * 16.0 + 8.0, spot.y * 16.0 + 8.0)))
	_log("[VProbe] wet_crop_cell=%s" % str(_cc(c0)))
	_log("[VProbe] wet_only_cell=%s" % str(_cc(c1)))
	_log("[VProbe] tilled_dry_cell=%s" % str(_cc(c2)))
	for k in anchors.keys():
		_log("[VProbe] station_%s=%s" % [k, str(anchors[k])])
	_log("[VProbe] mob_orc=%s mob_skel=%s" % [str(mob1.global_position), str(mob2.global_position)])
	get_tree().quit()

func _cc(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)
