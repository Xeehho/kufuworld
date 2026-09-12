extends Node
# 长安v2 灰盒结构探针：加载 changan_v2.tscn，断言尺寸/城门/标签/BFS，导出灰盒图
# 运行: godot --headless --path . res://tools/probe_changan_v2.tscn

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var city = load("res://scenes/changan_v2.tscn").instantiate()
	add_child(city)
	# 本探针只审计城市场景，不会挂载主世界的 Player/UI；静态人口在这种孤立
	# 环境下没有可查询的鼠标/玩家对象，因此禁用其调度，避免把场景外依赖误报成城市错误。
	var population = city.get_node_or_null("Population")
	if population != null:
		population.process_mode = Node.PROCESS_MODE_DISABLED
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
	# 街区：正式材质展示时不叠加灰盒文字；素材缺失回退时才保留标签说明层。
	if city.blocks.size() != 28:
		fails.append("街区数=%d≠28" % city.blocks.size())
	var label_cnt: int = city.labels_node.get_child_count()
	if city.materials_count > 0 and label_cnt != 0:
		fails.append("正式材质展示仍有灰盒标签=%d" % label_cnt)
	if city.materials_count <= 0 and label_cnt < 28 * 2 + 4 + 5:
		fails.append("灰盒回退标签数=%d < 下限66" % label_cnt)
	if city.materials_count > 0:
		if int(city.stats.get("material_shadows", 0)) < 40:
			fails.append("建筑接地阴影=%d < 下限40" % int(city.stats.get("material_shadows", 0)))
		if int(city.stats.get("material_collisions", 0)) < 40:
			fails.append("建筑碰撞体=%d < 下限40" % int(city.stats.get("material_collisions", 0)))
		var bodies := get_tree().get_nodes_in_group("changan_building_collision").size()
		if bodies != int(city.stats.get("material_collisions", -1)):
			fails.append("建筑碰撞统计=%d，实际节点=%d" % [int(city.stats.get("material_collisions", -1)), bodies])
		if get_tree().get_nodes_in_group("changan_city_gate").size() != 4:
			fails.append("城门楼素材节点数≠4")
		var ai_side_gates := 0
		for gate in get_tree().get_nodes_in_group("changan_city_gate"):
			if String(gate.get_meta("material_id", "")) == "side_gate_bridge_ai":
				ai_side_gates += 1
		if ai_side_gates != 2:
			fails.append("Image 2.0 东西门桥节点数≠2（实=%d）" % ai_side_gates)
		var ai_side_walls := 0
		for wall in get_tree().get_nodes_in_group("changan_outer_wall_facade"):
			if String(wall.get_meta("material_id", "")).begins_with("side_wall_run_ai_"):
				ai_side_walls += 1
		if ai_side_walls < 52:
			fails.append("Image 2.0 东西竖向城墙不足52段（实=%d）" % ai_side_walls)
		var activity_nodes := get_tree().get_nodes_in_group("changan_activity_prop").size()
		if activity_nodes != int(city.stats.get("material_activity", -1)):
			fails.append("活动件统计=%d，实际节点=%d" %
					[int(city.stats.get("material_activity", -1)), activity_nodes])
		if int(city.stats.get("material_activity", 0)) < 16:
			fails.append("城市生活活动件=%d < 下限16" % int(city.stats.get("material_activity", 0)))
		if int(city.stats.get("material_vehicles", 0)) < 4:
			fails.append("两市物流车辆=%d < 下限4" % int(city.stats.get("material_vehicles", 0)))
		if int(city.stats.get("material_shore_life", 0)) < 4:
			fails.append("曲江水岸生活件=%d < 下限4" % int(city.stats.get("material_shore_life", 0)))
	if int(city.stats.get("population", 0)) != 40:
		fails.append("城市人口=%d≠40" % int(city.stats.get("population", 0)))
	# 城墙用完整 wall_run 立面连续铺设；TileMap 仍保留两格厚碰撞环。
	if city.materials_count > 0 and get_tree().get_nodes_in_group("changan_outer_wall_facade").size() < 50:
		fails.append("外郭高墙连续立面不足50段")
	var water_cells := 0
	for d in city.ground:
		if int(d) == city.T_WATER:
			water_cells += 1
	if water_cells < 60:
		fails.append("曲江水面=%d格 < 下限60" % water_cells)
	# BFS：明德门内可达全部街区中心+四门落点
	if not city.bfs_failures.is_empty():
		fails.append("BFS未达%d处：%s" % [city.bfs_failures.size(), str(city.bfs_failures.slice(0, 5))])
	# 朱雀大街御道抽检：轴心3宽连续（row2~row4 段）
	var zx: int = city.seam_x(city.axis_col) + city.zq_s / 2
	for y in range(city.row_y(2), city.row_y(4)):
		if int(city.ground[y * city.W + (zx - 1)]) != city.Z_ROAD:
			fails.append("朱雀道路中断 y=%d" % y)
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
