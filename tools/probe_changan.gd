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
		5: Color(0.30, 0.48, 0.72), 17: Color(0.62, 0.52, 0.40),
		100: Color(0.90, 0.88, 0.82), 101: Color(0.62, 0.66, 0.74), 102: Color(0.16, 0.16, 0.18),
		2: Color(0.55, 0.40, 0.30), 75: Color(0.80, 0.30, 0.25), 76: Color(0.75, 0.38, 0.30),
		77: Color(0.35, 0.32, 0.30), 8: Color(0.30, 0.50, 0.28),
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
	var exit_portal_cnt := 0
	if changan.portals_node:
		for child in changan.portals_node.get_children():
			if String(child.name).begins_with("ExitPortal_"):
				exit_portal_cnt += 1
	if changan.portals_node == null or exit_portal_cnt != 4:
		m1_fails.append("出城Portals缺失或不全(出城=%d/总数=%d)" % [exit_portal_cnt, changan.portals_node.get_child_count() if changan.portals_node else -1])
	# ---- M2 断言：剧情坊 lots 布局（门面 tile 与 interiors 登记一致）----
	var lot_wards := 0
	for b in changan.blocks:
		if String(b["type"]) != "ward" or int(b["stage_unlock"]) != 0:
			continue   # 未解锁坊不填充（§六-3），无断言意义
		var lots: Array = b.get("lots", [])
		if lots.is_empty():
			continue
		lot_wards += 1
		var interiors: Array = b.get("interiors", [])
		for lot in lots:
			if not interiors.has(lot["ref"]):
				m1_fails.append("%s 门面 %s 未登记 interiors" % [b["name"], lot["ref"]])
			# 门面格实铺校验（数据重算门位）
			var gx: int = changan.col_x(int(b["col"])) + int(lot["at"][0])
			var gy: int = changan.row_y(int(b["row"])) + int(lot["at"][1])
			var w := int(lot["size"][0])
			var h := int(lot["size"][1])
			var expect := 0
			match String(lot["grade"]):
				"A": expect = 75
				"B": expect = 76
				"C": expect = 77
			var got := -1
			match String(lot["gate"]):
				"S": got = int(changan.decor[(gy + h - 1) * changan.W + gx + w / 2 - 1])
				"N": got = int(changan.decor[gy * changan.W + gx + w / 2 - 1])
				"E": got = int(changan.decor[(gy + h / 2 - 1) * changan.W + gx + w - 1])
				"W": got = int(changan.decor[(gy + h / 2 - 1) * changan.W + gx])
			if got != expect:
				m1_fails.append("%s·%s 门面tile期望%d实铺%d" % [b["name"], lot["ref"], expect, got])
	if lot_wards < 8:
		m1_fails.append("stage0剧情坊带lots数=%d(<8)" % lot_wards)
	# ---- Slice F→视觉重构 断言：宅门楼 SCKR prop（75/76/77 门面瓦仍是探针基准） ----
	# 期望从数据推导：stage0 坊 lots 按品级计门楼数（两市店铺 76 门垫不配门楼，改配门面楼 prop）
	var expect_gate_props := 0
	for b in changan.blocks:
		if String(b["type"]) != "ward" or int(b["stage_unlock"]) != 0:
			continue
		expect_gate_props += b.get("lots", []).size()
	var props: Array = changan.get_children().filter(func(n): return n.is_in_group("changan_prop"))
	var prop_names := {}
	for p in props:
		prop_names[String(p.get_meta("prop", ""))] = prop_names.get(String(p.get_meta("prop", "")), 0) + 1
	var gate_props := int(prop_names.get("gate_red_gold", 0)) + int(prop_names.get("compound_gate", 0)) + int(prop_names.get("gate_stone_small", 0))
	if gate_props != expect_gate_props:
		m1_fails.append("宅门楼prop=%d≠stage0 lots数%d（克隆缺切片会全跳过）" % [gate_props, expect_gate_props])
	var bad_tex := 0
	for p2 in props:
		if p2.texture == null or p2.offset.y != -p2.texture.get_height() / 2.0:
			bad_tex += 1
	if bad_tex > 0:
		m1_fails.append("prop纹理/底边锚异常=%d" % bad_tex)
	# ---- M3 断言：三渠/宵禁/夜行BFS/锚点/城内NPC/阶段解锁 ----
	var m3_fails: Array = []
	# 三渠：每渠水格充足，桥格跨路
	for canal_name in changan.canal_cells:
		if int(changan.canal_cells[canal_name]) < 100:
			m3_fails.append("水渠%s水格=%d(<100)" % [canal_name, changan.canal_cells[canal_name]])
	if changan.bridge_count < 12:
		m3_fails.append("渠桥格=%d(<12)" % changan.bridge_count)
	# 宵禁册：坊门+市门格初始全开瓦，切换后换闭瓦（68 带碰撞）
	if changan.curfew_gates.size() < 20:
		m3_fails.append("宵禁门注册=%d(<20)" % changan.curfew_gates.size())
	var first_gate: Vector2i = changan.curfew_gates[0]["cells"][0]
	if int(changan.decor[first_gate.y * changan.W + first_gate.x]) != changan.T_GATE_OPEN:
		m3_fails.append("宵禁门格初始非开瓦")
	changan.set_curfew(true)
	if int(changan.decor[first_gate.y * changan.W + first_gate.x]) != changan.T_GATE_CLOSED:
		m3_fails.append("set_curfew(true) 未换闭门瓦")
	if not changan.curfew:
		m3_fails.append("curfew 标志未置位")
	changan.set_curfew(false)
	# 夜行 BFS：宵禁下四城门内侧仍可达
	if changan.night_bfs_failures.size() != 0:
		m3_fails.append("夜行BFS未达=%s" % [changan.night_bfs_failures])
	# 锚点：坊门/市门/plaza 已注册，城门走 gate_info
	for ref in ["plaza", "marketgate:西市:S", "marketgate:东市:S"]:
		if not changan.anchors.has(ref):
			m3_fails.append("锚点%s缺失" % ref)
	if changan.get_anchor_px("citygate:S") == Vector2.ZERO:
		m3_fails.append("citygate:S 锚点解析失败")
	# 城内NPC：与配置数一致
	if changan.npc_list.size() != changan.CITY_NPC_CONFIGS.size():
		m3_fails.append("城内NPC=%d≠配置%d" % [changan.npc_list.size(), changan.CITY_NPC_CONFIGS.size()])
	# 阶段解锁：stage1 坊开门后 BFS 可达其中心（闭门格换开瓦）
	var stage1_before := 0
	for b in changan.blocks:
		if String(b["type"]) == "ward" and int(b["stage_unlock"]) == 1:
			stage1_before += 1
	changan.unlock_stage(1)
	var reach: Dictionary = changan._bfs_from(Vector2i(changan.col_x(5) - changan.zq_s + changan.zq_s / 2 + 1, changan.H - changan.margin - changan.wall - 1))
	var stage1_center_fail := false
	for b in changan.blocks:
		if String(b["type"]) != "ward" or int(b["stage_unlock"]) != 1:
			continue
		if not reach.has(Vector2i(changan.col_x(int(b["col"])) + changan.bw / 2, changan.row_y(int(b["row"])) + changan.bh / 2)):
			stage1_center_fail = true
	if stage1_before == 0:
		m3_fails.append("数据中无 stage1 坊")
	if stage1_center_fail:
		m3_fails.append("unlock_stage(1) 后 stage1 坊中心不可达")
	# ---- 视觉重构断言（SCKR 第一层换皮 2026-09-06）----
	var mv_fails: Array = []
	# 瓦片注册：SCKR 首选路径存在（69~74 换皮 + 新 100/101；load_png_texture 无 resource_path，查文件）
	var ts_mv: TileSet = changan.tile_map.tile_set
	var sckr_paths := {69: "wall_palace.png", 70: "wall_city.png", 71: "street_zhuque.png",
			72: "street_main.png", 73: "street_ward.png", 74: "street_lane.png",
			100: "wall_ward.png", 101: "pave_market.png", 104: "wall_palace_v.png",
			105: "wall_ward_v.png", 106: "wall_city_body.png", 107: "wall_city_body_v.png"}
	for tid in sckr_paths:
		if not ts_mv.has_source(tid):
			mv_fails.append("瓦片%d未注册" % tid)
		if not FileAccess.file_exists("res://sprites/tiles_changan_sckr/" + sckr_paths[tid]):
			mv_fails.append("SCKR切片缺失 tiles_changan_sckr/%s（跑 tools/import_sckr_changan.py）" % sckr_paths[tid])
	# 城门楼×4（大骑楼明德门+中楼×3）
	if int(prop_names.get("gate_tower_big", 0)) != 1 or int(prop_names.get("gate_tower_mid", 0)) != 3:
		mv_fails.append("城门楼prop big=%d mid=%d≠1/3" % [int(prop_names.get("gate_tower_big", 0)), int(prop_names.get("gate_tower_mid", 0))])
	# 街巷点缀阈值（落格校验会吞个别格，阈值留余量）
	if int(prop_names.get("lamp_red", 0)) < 15:
		mv_fails.append("街灯=%d(<15)" % int(prop_names.get("lamp_red", 0)))
	var tree_cnt := int(prop_names.get("tree_lush_a", 0)) + int(prop_names.get("tree_lush_b", 0)) + int(prop_names.get("tree_big", 0))
	if tree_cnt < 12:
		mv_fails.append("行道树=%d(<12)" % tree_cnt)
	# 宫城：太极殿/两仪殿/东宫+角楼×4
	if int(prop_names.get("hall_taiji", 0)) != 1:
		mv_fails.append("太极殿prop缺失")
	if int(prop_names.get("hall_gold2", 0)) != 1 or int(prop_names.get("hall_gold3", 0)) != 1:
		mv_fails.append("两仪殿/东宫prop缺失")
	if int(prop_names.get("ting_gold", 0)) != 4:
		mv_fails.append("宫城角楼亭=%d≠4" % int(prop_names.get("ting_gold", 0)))
	# 民居密度：散院民居 prop ≥ 60（stage0 38坊×4象限×命中率）
	var house_cnt := int(prop_names.get("house_win_a", 0)) + int(prop_names.get("house_door_a", 0)) \
			+ int(prop_names.get("house_win_small", 0)) + int(prop_names.get("house_small_door", 0))
	if house_cnt < 60:
		mv_fails.append("民居prop=%d(<60)" % house_cnt)
	# 两市：市楼钟/鼓各1、摊贩≥12、店铺门面=9
	if int(prop_names.get("bell_tower", 0)) != 1 or int(prop_names.get("drum_tower", 0)) != 1:
		mv_fails.append("市楼钟/鼓≠1/1")
	var stall_cnt := 0
	for k in prop_names:
		if String(k).begins_with("stall_"):
			stall_cnt += int(prop_names[k])
	if stall_cnt < 12:
		mv_fails.append("市摊=%d(<12)" % stall_cnt)
	if int(prop_names.get("house_shop_open", 0)) < 4:
		mv_fails.append("店铺门面prop=%d(<4)" % int(prop_names.get("house_shop_open", 0)))
	# 坊门门楼（各坊 S 门挂灰瓦榜门楼，门洞内露开/闭门瓦）
	if int(prop_names.get("market_gate", 0)) < 90:
		mv_fails.append("坊门楼=%d(<90)" % int(prop_names.get("market_gate", 0)))
	# 坊墙方向感知抽样：竖段（E/W 走向）应为 105 竖版瓦
	var v_sample := Vector2i(changan.col_x(3), changan.row_y(6) + 13)   # 坊 w_3_6 西墙竖段中点
	if int(changan.decor[v_sample.y * changan.W + v_sample.x]) != changan.T_WARD_WALL_V:
		mv_fails.append("坊墙竖段未用竖版瓦(%d)" % int(changan.decor[v_sample.y * changan.W + v_sample.x]))
	# 街灯/行道树阈值已前置（城门楼断言后）——此处只留牌坊
	if int(prop_names.get("paifang_big_gold", 0)) != 1 or int(prop_names.get("paifang_stone_g", 0)) != 1:
		mv_fails.append("朱雀牌坊≠1/1")
	# footprint 与 prop 对齐：T_HOUSE(2) 占格数 ≥ 建筑props×2（每foot至少2格）
	var foot_cells := 0
	for v2 in changan.decor:
		if int(v2) == changan.T_FOOT:
			foot_cells += 1
	if foot_cells < 200:
		mv_fails.append("建筑footprint格=%d(<200)" % foot_cells)
	# 大雁塔：unlock_stage(1) 后晋昌坊 daciensi 塔出现（unlock_stage(1) 已在 M3 段调用过）
	var has_pagoda := false
	for p3 in changan.get_children():
		if p3.is_in_group("changan_prop") and String(p3.get_meta("prop", "")) == "pagoda_blue":
			has_pagoda = true
			break
	if not has_pagoda:
		mv_fails.append("大雁塔prop缺失（unlock_stage(1) 后应立）")
	# [DEBUG-V] 塔院/丹墀地坪 id 直查（daciensi lot 内格 + 宫城丹墀格）
	var dcell := Vector2i(changan.col_x(10) + 5, changan.row_y(8) + 10)
	print("[probe][V-DBG] daciensi yard(", dcell, ") ground=", int(changan.ground[dcell.y * changan.W + dcell.x]),
			" decor=", int(changan.decor[dcell.y * changan.W + dcell.x]))
	var pcell := Vector2i(changan.col_x(5) - changan.zq_s + changan.zq_s / 2 + 2, changan.row_y(0) + 10)
	print("[probe][V-DBG] palace pave(", pcell, ") ground=", int(changan.ground[pcell.y * changan.W + pcell.x]))
	if not mv_fails.is_empty():
		fails.append_array(mv_fails)
	if not m3_fails.is_empty():
		fails.append_array(m3_fails)
	# ---- M4 断言：内景瓦片族/传送门注册/三标杆构建+BFS ----
	var m4_fails: Array = []
	var ts: TileSet = changan.tile_map.tile_set
	for tid in [80, 81, 82, 83, 84, 85, 86, 87, 88, 89]:
		if not ts.has_source(tid):
			m4_fails.append("内景瓦片%d未注册" % tid)
	# 宅门去碰撞（tile 75 物理层应为空）
	var gate_src := ts.get_source(75) as TileSetAtlasSource
	var gate_td := gate_src.get_tile_data(Vector2i(0, 0), 0)
	if gate_td != null and gate_td.get_collision_polygons_count(0) > 0:
		m4_fails.append("宅门75仍有碰撞（应为传送门可走）")
	# 传送门落点诊断：门前景格 3×3 是否可通行
	var hp: Vector2i = changan.interior_portals["huguguang"]
	print("[probe][M4-DBG] huguguang portal=", hp, " clear=", changan.is_spawn_clear(hp))
	for dy in range(-2, 3):
		var row_txt := ""
		for dx in range(-2, 3):
			var c := hp + Vector2i(dx, dy)
			row_txt += "%d/%d " % [int(changan.ground[c.y * changan.W + c.x]), int(changan.decor[c.y * changan.W + c.x])]
		print("[probe][M4-DBG]   ", row_txt)
	# 传送门注册：三标杆齐
	for ref in ["tianxiang_ge", "huguguang", "taiji_dian"]:
		if not changan.interior_portals.has(ref):
			m4_fails.append("内景传送门%s未注册" % ref)
	# M5 全量内景：每个传送门 ref 元数据齐备+构建成功+底面无草洞+BFS全通+出生点3×3可通行
	var InteriorScript = load("res://scripts/changan_interior.gd")
	var built_cnt := 0
	var built_ids := {}
	changan.unlock_stage(2)   # 全解锁后传送门注册齐（stage1/2 坊 lots 在 unlock 时补挂）
	for ref in changan.interior_portals:
		if String(ref).begins_with("area:"):
			continue
		var meta: Dictionary = changan.get_interior_meta(String(ref))
		var is_benchmark: bool = InteriorScript.TEMPLATES.has(String(ref))
		if meta.is_empty() and not is_benchmark:
			m4_fails.append("内景%s元数据缺失" % ref)
			continue
		var node := Node2D.new()
		node.set_script(InteriorScript)
		if not node.build(String(ref), meta):
			m4_fails.append("内景%s构建失败" % ref)
			continue
		built_cnt += 1
		built_ids[String(ref)] = true
		var hole := false
		for y in range(node.H):
			for x in range(node.W):
				if int(node.ground[y * node.W + x]) == 0:
					hole = true
					break
		if hole:
			m4_fails.append("内景%s地面有草洞（底未满铺）" % ref)
		if node.bfs_failures.size() != 0:
			m4_fails.append("内景%s BFS未达=%s" % [ref, node.bfs_failures])
		if not node.is_spawn_clear(node.spawn_cell):
			m4_fails.append("内景%s出生点3×3受阻" % ref)
		node.free()
	# unlock 后补挂的 stage1/2 lot 内景也要构建通过
	var late_cnt := 0
	for ref in changan.interior_portals:
		var rid := String(ref)
		if rid.begins_with("area:") or built_ids.has(rid):
			continue
		var meta2: Dictionary = changan.get_interior_meta(rid)
		if meta2.is_empty():
			continue
		var node2 := Node2D.new()
		node2.set_script(InteriorScript)
		if node2.build(rid, meta2):
			late_cnt += 1
		node2.free()
	built_cnt += late_cnt
	if built_cnt < 40:
		m4_fails.append("批量内景构建数=%d(<36)" % built_cnt)
	print("[probe][M5] 内景构建=%d 传送门=%d" % [built_cnt, changan.interior_portals.size()])
	if not m4_fails.is_empty():
		fails.append_array(m4_fails)
	if not m1_fails.is_empty():
		fails.append_array(m1_fails)
	if fails.is_empty() and int(changan.stats["ms"]) <= 3000:
		print("[ChangAn-M1][PASS] ", changan.stats)
		get_tree().quit(0)
	else:
		print("[ChangAn-M1][FAIL] 未达=", fails, " stats=", changan.stats)
		get_tree().quit(1)
