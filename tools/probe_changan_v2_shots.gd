extends Node
# 长安v2 窗口样张探针（autoload 注入，跑真实主场景）：等开机自动入城 → 定点传送截图
# 用法: python tools/run_changan_v2_shots.py（windowed 窗口模式渲染）
var _shots_done := false

func _ready():
	await _run()

func _run():
	var t0 := Time.get_ticks_msec()
	# 等 Main+Player+CityVisit 全部就绪（CityVisit 挂 Main._ready 末尾，须轮询防竞态）
	var main = null
	var player = null
	var cv = null
	while Time.get_ticks_msec() - t0 < 40000:
		main = get_node_or_null("/root/Main")
		if main != null:
			player = main.get_node_or_null("World/Player")
			cv = main.get_node_or_null("CityVisit")
			if player != null and cv != null:
				break
		await get_tree().process_frame
	if player == null or cv == null:
		print("[ChangAnV2-Shots][FAIL] Player/CityVisit 缺失")
		get_tree().quit(1)
		return
	# 探针环境下 _probe_present() 抑制自动入城——踩 footprint 明德门豁口物理触发（照抄 e2e 模式）
	var outside: Vector2i = cv.gate_cells["S"]["outside"]
	var gap: Vector2i = cv.gate_cells["S"]["gap"]
	player.global_position = Vector2(outside.x * 16 + 8, outside.y * 16 + 8)
	await get_tree().create_timer(0.4).timeout
	player.global_position = Vector2(gap.x * 16 + 8, gap.y * 16 + 8)
	# 等自动入城完成（淡入结束）
	while Time.get_ticks_msec() - t0 < 60000:
		if cv.in_city and not cv._busy and cv.changan != null:
			break
		await get_tree().process_frame
	if cv.changan == null:
		print("[ChangAnV2-Shots][FAIL] 60s 未入城")
		get_tree().quit(1)
		return
	var city = cv.changan
	var cam = player.get_node("Camera2D")
	cam.reset_smoothing()
	await get_tree().create_timer(0.5).timeout
	# 机位清单：[名, 城内格, zoom]
	var spots := [
		["overview", Vector2i(city.W / 2, city.H / 2), 0.45],
		["mingde", city.gate_info["S"]["inside"] + Vector2i(0, -6), 2.0],
		["zhuque", Vector2i(city.seam_x(city.axis_col) + city.zq_s / 2, city.row_y(3) + 4), 2.0],
		["xishi", Vector2i(city.col_x(0) + 10, city.row_y(2) + 10), 2.0],
		["gongcheng", Vector2i(city.col_x(2) + 23, city.row_y(0) + 14), 2.0],
		["pingkang", Vector2i(city.col_x(5) + 10, city.row_y(1) + 10), 2.0],
		["tongji", Vector2i(city.col_x(1) + 10, city.row_y(4) + 10), 2.0],
		["qujiang", Vector2i(city.col_x(5) + 10, city.row_y(4) + 10), 2.0],
	]
	var count := 0
	for s in spots:
		player.global_position = cv.CITY_OFFSET + city.cell_to_px(s[1])
		player.velocity = Vector2.ZERO
		cam.zoom = Vector2(s[2], s[2])
		cam.reset_smoothing()
		await get_tree().create_timer(0.35).timeout
		await _shot("changan_v2_%s.png" % String(s[0]))
		count += 1
	print("[ChangAnV2-Shots][PASS] 样张=%d 张 → docs/shots/changan_v2_*.png" % count)
	_shots_done = true
	get_tree().quit(0)

func _shot(fname: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://docs/shots/" + fname)
	print("[ChangAnV2-Shot] %s" % fname)
