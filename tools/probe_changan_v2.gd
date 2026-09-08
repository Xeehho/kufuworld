extends Node
# 长安v2 灰盒结构探针：加载 changan_v2.tscn，断言尺寸/城门/标签/BFS，导出灰盒图
# 运行: godot --headless --path . res://tools/probe_changan_v2.tscn

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var city = load("res://scenes/changan_v2.tscn").instantiate()
	add_child(city)
	while not city.done and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	var total := Time.get_ticks_msec() - t0
	if not city.done:
		print("[ChangAnV2][FAIL] 生成超时(>30s)")
		get_tree().quit(2)
		return
	print("[probe] 含实例化总耗时=%dms" % total)
	var fails: Array = []
	# 尺寸契约（v2.1：20×20 街区/6×5 网格/朱雀6/主干4/环3/墙2/margin8）
	if city.W != 168 or city.H != 142:
		fails.append("尺寸 %dx%d ≠ 168x142" % [city.W, city.H])
	# 城门：4 座、豁口开门瓦、门内落点可通行、出城触发区齐备
	if city.gate_info.size() != 4:
		fails.append("城门数量=%d≠4" % city.gate_info.size())
	for side in city.gate_info:
		var g: Dictionary = city.gate_info[side]
		for c in g["gap_cells"]:
			if int(city.decor[c.y * city.W + c.x]) != city.T_GATE_OPEN:
				fails.append("%s豁口格%s未铺开门瓦" % [g["name"], c])
		if not city.is_spawn_clear(city.find_clear_spawn(g["inside"])):
			fails.append("%s门内落点不可通行" % g["name"])
	var portal_cnt := 0
	for n in city.get_node("Portals").get_children():
		if n is Area2D:
			portal_cnt += 1
	if portal_cnt != 4:
		fails.append("出城触发区=%d≠4" % portal_cnt)
	# 街区与文字标签：28 街区块、标签数 ≥ 坊名+场景两层+城门+街道
	if city.blocks.size() != 28:
		fails.append("街区数=%d≠28" % city.blocks.size())
	var label_cnt: int = city.labels_node.get_child_count()
	if label_cnt < 28 * 2 + 4 + 5:
		fails.append("标签数=%d < 下限66" % label_cnt)
	# BFS：明德门内可达全部街区中心+四门落点
	if not city.bfs_failures.is_empty():
		fails.append("BFS未达%d处：%s" % [city.bfs_failures.size(), str(city.bfs_failures.slice(0, 5))])
	# 朱雀大街御道抽检：轴心3宽连续（row2~row4 段）
	var zx: int = city.seam_x(city.axis_col) + city.zq_s / 2
	for y in range(city.row_y(2), city.row_y(4)):
		if int(city.ground[y * city.W + (zx - 1)]) != city.T_ZHUQUE:
			fails.append("朱雀御道中断 y=%d" % y)
			break
	# 灰盒图导出（tile 底色 + 街区块 kind 描边 + 标签落点白点）
	_export_graybox(city)
	if fails.is_empty():
		print("[ChangAnV2][PASS] %s 街区=%d 标签=%d BFS=0 城门=4 生成=%dms" %
				[city.stats["size"], city.blocks.size(), label_cnt, city.stats["ms"]])
		get_tree().quit(0)
	else:
		for f in fails:
			print("[ChangAnV2][FAIL] %s" % f)
		get_tree().quit(1)


func _export_graybox(city) -> void:
	var colors := {
		0: Color(0.42, 0.56, 0.35), 74: Color(0.60, 0.50, 0.38), 72: Color(0.72, 0.61, 0.46),
		71: Color(0.78, 0.76, 0.70), 101: Color(0.62, 0.66, 0.74),
		70: Color(0.30, 0.30, 0.31), 67: Color(0.85, 0.45, 0.30),
	}
	var img := Image.create(city.W, city.H, false, Image.FORMAT_RGBA8)
	for y in range(city.H):
		for x in range(city.W):
			var d := int(city.decor[y * city.W + x])
			var g := int(city.ground[y * city.W + x])
			var col: Color = colors[0]
			if d != 0:
				col = colors.get(d, colors[0])
			elif g != 0:
				col = colors.get(g, colors[0])
			img.set_pixel(x, y, col)
	# 街区块按 kind 描边 + 中心白点（kind 配色=生成器 KIND_COLORS）
	for b in city.blocks:
		var rect: Rect2i = city._block_rect(b)
		var kc: Color = city.KIND_COLORS.get(String(b["kind"]), Color.WHITE)
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			img.set_pixel(x, rect.position.y, kc)
			img.set_pixel(x, rect.position.y + rect.size.y - 1, kc)
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			img.set_pixel(rect.position.x, y, kc)
			img.set_pixel(rect.position.x + rect.size.x - 1, y, kc)
		var c := rect.position + rect.size / 2
		img.set_pixel(c.x, c.y, Color.WHITE)
	img.save_png("res://docs/shots/changan_v2_graybox.png")
	print("[probe] 灰盒图已导出 docs/shots/changan_v2_graybox.png")
