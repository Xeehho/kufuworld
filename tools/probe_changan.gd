extends Node
# M1 验收探针：加载长安城场景，等待分帧生成完成，输出计时与断言结果
# M0 断言：生成≤3s；BFS 明德门可达全部 stage0 坊+两市
# M1 新增：四城门注册+豁口铺贴正确+出城Portals齐备+门内落点3×3可通行+BFS四门内可达
# 运行: godot --headless --path . res://tools/probe_changan.tscn

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var changan = load("res://scenes/changan.tscn").instantiate()
	add_child(changan)
	# 超时保护 30s（生成卡死/脚本报错时不挂死进程）
	while not changan.done and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	var total := Time.get_ticks_msec() - t0
	if not changan.done:
		print("[ChangAn-M1][FAIL] 生成超时(>30s)")
		get_tree().quit(2)
		return
	print("[probe] 含实例化总耗时=%dms" % total)
	# 灰盒可视化：按 ID 上色导出 PNG（地面在下半透、装饰在上）
	var colors := {
		0: Color(0.42, 0.56, 0.35), 72: Color(0.72, 0.61, 0.46), 73: Color(0.66, 0.55, 0.42),
		74: Color(0.60, 0.50, 0.38), 71: Color(0.75, 0.73, 0.68), 35: Color(0.70, 0.68, 0.63),
		43: Color(0.83, 0.80, 0.74), 40: Color(0.45, 0.44, 0.42), 69: Color(0.62, 0.35, 0.28),
		70: Color(0.30, 0.30, 0.31), 67: Color(0.85, 0.45, 0.30), 68: Color(0.72, 0.25, 0.18),
		5: Color(0.30, 0.48, 0.72),
	}
	var img := Image.create(changan.W, changan.H, false, Image.FORMAT_RGBA8)
	for y in range(changan.H):
		for x in range(changan.W):
			var d := int(changan.decor[y * changan.W + x])
			var g := int(changan.ground[y * changan.W + x])
			var col: Color = colors[0]
			if d != 0:
				col = colors.get(d, colors[0])
			elif g != 0:
				col = colors.get(g, colors[0])
			img.set_pixel(x, y, col)
	img.save_png("res://docs/shots/changan_m0_graybox.png")
	print("[probe] 灰盒图已导出 docs/shots/changan_m0_graybox.png")
	# ---- M1 断言 ----
	var fails: Array = changan.bfs_failures
	var m1_fails: Array = []
	if changan.gate_info.size() != 4:
		m1_fails.append("城门数量=%d≠4" % changan.gate_info.size())
	for side in changan.gate_info:
		var g: Dictionary = changan.gate_info[side]
		for c in g["gap_cells"]:
			if int(changan.decor[c.y * changan.W + c.x]) != changan.T_GATE_OPEN:
				m1_fails.append("%s豁口格%s未铺开门瓦" % [g["name"], c])
		if not changan.is_spawn_clear(changan.find_clear_spawn(g["inside"])):
			m1_fails.append("%s门内落点不可通行" % g["name"])
	if changan.portals_node == null or changan.portals_node.get_child_count() != 4:
		m1_fails.append("出城Portals缺失或不全(%s)" % [changan.portals_node.get_child_count() if changan.portals_node else -1])
	if not m1_fails.is_empty():
		fails.append_array(m1_fails)
	if fails.is_empty() and int(changan.stats["ms"]) <= 3000:
		print("[ChangAn-M1][PASS] ", changan.stats)
		get_tree().quit(0)
	else:
		print("[ChangAn-M1][FAIL] 未达=", fails, " stats=", changan.stats)
		get_tree().quit(1)
