extends Node
# 长安v2 灰盒 E2E 探针（autoload，run_changan_e2e.py 检测 CITY_VERSION=2 时注入本探针）
# 全链路：footprint 明德门踩格入城 → 落点3×3 → 朱雀/西市/宫城/平康/丰安陈宅/曲江预留 站立采样
#        → 春明门出城 → 回落位置断言 → 开放世界解冻
# v1 版探针见 probe_changan_e2e.gd（city_visit.gd CITY_VERSION 切回 1 时由 runner 分发）

const TILE := 16
var fails: Array = []


func _ready() -> void:
	await _settle(240)   # ~4s 等世界生成+CityVisit footprint 铺设完成
	# 冻主线防对话挡路（体验模式 quests_disabled 已冻结，双保险照抄 v1 E2E）
	var main := get_node_or_null("/root/Main")
	if main:
		var st := main.get_node_or_null("MainStory")
		if st:
			st.set_process(false)
	if DialogManager.is_dialog_open():
		DialogManager.close_dialog()
		await _settle(6)
	main = get_node_or_null("/root/Main")
	if main == null:
		_fail("主场景 /root/Main 不存在")
		_quit()
		return
	var cv = main.get_node_or_null("CityVisit")
	if cv == null or cv.gate_cells.size() != 4:
		_fail("CityVisit 未就绪 gate_cells=%s" % (cv.gate_cells.keys() if cv else []))
		_quit()
		return
	var p = main.get_node("World/Player")
	# 1) 入城：传明德门外2格 → 踩豁口格（物理重叠触发）
	var outside: Vector2i = cv.gate_cells["S"]["outside"]
	var gap: Vector2i = cv.gate_cells["S"]["gap"]
	_tp(p, Vector2(outside.x * TILE + 8, outside.y * TILE + 8))
	await _settle(8)
	_tp(p, Vector2(gap.x * TILE + 8, gap.y * TILE + 8))
	if not await _wait_city(cv, true, 15000):
		_quit()
		return
	_check(cv.in_city and cv.changan != null, "入城成功且v2城场景挂载")
	var ch = cv.changan
	await _settle(6)
	await _shot("changan_v2_e2e_mingde.png")
	# 角色接地/碰撞与城市建筑脚印：这些是视觉层和物理层的共同验收契约。
	_check(p.collision_layer == 2 and (p.collision_mask & 1) != 0,
			"玩家碰撞层可阻挡地形/建筑")
	_check(p.get_node_or_null("CollisionShape2D") != null and p.get_node_or_null("GroundShadow") != null,
			"玩家脚部碰撞盒与接地阴影齐备")
	var population = ch.get_node_or_null("Population")
	_check(population != null and population.get_child_count() == 24, "城内人口24名")
	var materials = ch.get_node_or_null("Materials")
	_check(materials != null and materials.z_index == p.z_index and population != null and population.z_index == p.z_index,
			"玩家/建筑/NPC同层递归Y-sort，人物可在建筑前后穿行")
	if population != null:
		for npc in population.get_children():
			if npc.get_node_or_null("CollisionShape2D") == null or npc.get_node_or_null("GroundShadow") == null:
				_fail("城内NPC缺脚部碰撞盒或接地阴影：%s" % npc.name)
				break
	_check(get_tree().get_nodes_in_group("changan_building_collision").size() >= 40,
			"建筑/树木脚印碰撞体不少于40处")
	_check(get_tree().get_nodes_in_group("changan_city_gate").size() == 4, "四城门楼素材齐备")
	_check(_main_streets_clear(ch, cv, p), "朱雀与两条横向主街保留可连续穿行的中央通道")
	# 2) 落点 3×3 可通行
	var spawn_cell := Vector2i(int((p.global_position.x - cv.CITY_OFFSET.x) / TILE), int((p.global_position.y - cv.CITY_OFFSET.y) / TILE))
	_check(ch.is_spawn_clear(spawn_cell), "明德门内落点3×3可通行 %s" % spawn_cell)
	_check(_in_city_space(p, cv), "玩家在 v2 城坐标空间（y>60000）")
	# 3) 站立采样（v2 剧情锚点；BFS 已证连通，此处验证物理不卡死/不弹飞）
	var spots := [
		["朱雀大街中段", Vector2i(ch.seam_x(ch.axis_col) + ch.zq_s / 2, ch.row_y(3) + 2)],
		["金光春明大街（皇城南缘）", Vector2i(ch.col_x(2) + 8, ch.seam_y(2) + 2)],
		["西市中心", _block_center(ch, "xishi")],
		["宫城·太极宫", _block_center(ch, "gongcheng")],
		["皇城官署带", _block_center(ch, "huangcheng")],
		["平康坊·天香阁", _block_center(ch, "pingkang")],
		["丰安坊·陈宅预留", _block_center(ch, "fengan")],
		["曲江预留地", _block_center(ch, "qujiang")],
		["玄武门内（凯旋动线）", ch.gate_info["N"]["inside"]],
	]
	for s in spots:
		if s[1].x < 0:
			_fail("锚点缺失 " + String(s[0]))
			continue
		_tp(p, cv.CITY_OFFSET + ch.cell_to_px(s[1]))
		await _settle(8)
		_check(_in_city_space(p, cv), "%s(%s)可站立无弹飞" % [s[0], s[1]])
	await _shot("changan_v2_e2e_pingkang.png")
	# 4) 出城：春明门豁口
	var egap_in: Vector2i = ch.gate_info["E"]["gap_cells"][1]
	_tp(p, cv.CITY_OFFSET + ch.cell_to_px(egap_in))
	if not await _wait_city(cv, false, 15000):
		_quit()
		return
	_check(not cv.in_city and cv.changan == null, "出城成功且城内场景已释放")
	# 5) 回落位置=春明门外±2格
	var eout: Vector2i = cv.gate_cells["E"]["outside"]
	var back := Vector2i(int(round((p.global_position.x - 8) / TILE)), int(round((p.global_position.y - 8) / TILE)))
	_check(abs(back.x - eout.x) <= 2 and abs(back.y - eout.y) <= 2,
			"出城回落位置正确 %s（期望门外%s）" % [back, eout])
	# 6) 开放世界系统解冻
	_check(cv.world_gen.process_mode != Node.PROCESS_MODE_DISABLED, "开放世界系统已解冻")
	_quit()


func _block_center(ch, bid: String) -> Vector2i:
	for b in ch.blocks:
		if String(b["id"]) == bid:
			var r: Rect2i = ch._block_rect(b)
			return r.position + r.size / 2
	return Vector2i(-1, -1)


func _in_city_space(p, cv) -> bool:
	return p.global_position.y > cv.CITY_OFFSET.y


# 主街不能把静态 NPC 或建筑脚印摆成横向人墙。以玩家同尺寸（12×8 的脚部盒）
# 查询三条礼制道路的中线；保留 NPC 在两侧/街口制造生活感，但中心线必须连续。
func _main_streets_clear(ch, cv, player) -> bool:
	var cells: Array[Vector2i] = []
	var zhuque_x: int = ch.seam_x(ch.axis_col) + ch.zq_s / 2
	for row in [1, 2, 3, 4]:
		cells.append(Vector2i(zhuque_x, ch.row_y(row) + 3))
		cells.append(Vector2i(zhuque_x, ch.row_y(row) + 11))
	for seam in [1, 2, 3]:
		var y: int = ch.seam_y(seam) + ch.main_s / 2
		cells.append(Vector2i(ch.col_x(1) + 8, y))
		cells.append(Vector2i(ch.col_x(3) + 8, y))
		cells.append(Vector2i(ch.col_x(5) - 3, y))
	for cell in cells:
		if not _footprint_clear(cv.CITY_OFFSET + ch.cell_to_px(cell), player):
			_fail("主街中央通道被实体碰撞占用：%s" % cell)
			return false
	return true


func _footprint_clear(pos: Vector2, player) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 8)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	# Player 的 CollisionShape2D 在脚底上方4px，查询需采用相同中心。
	query.transform = Transform2D(0, pos + Vector2(0, -4))
	query.collision_mask = 1 | 4
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]
	return player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _tp(p, pos: Vector2):
	p.global_position = pos
	p.velocity = Vector2.ZERO
	if p.has_node("Camera2D"):
		p.get_node("Camera2D").reset_smoothing()


func _wait_city(cv, want: bool, timeout_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		if cv.in_city == want:
			return true
		await get_tree().process_frame
	_fail("等待 in_city=%s 超时(%dms)" % [want, timeout_ms])
	return false


func _settle(frames: int):
	for i in range(frames):
		await get_tree().process_frame


func _shot(fname: String):
	if DisplayServer.get_name() == "headless":
		return   # headless 无渲染，跳过截图
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://docs/shots/" + fname)
	print("[probe] 截图 docs/shots/" + fname)


func _check(cond: bool, msg: String):
	if cond:
		print("[ChangAnV2-E2E][PASS] " + msg)
	else:
		fails.append(msg)
		print("[ChangAnV2-E2E][FAIL] " + msg)


func _fail(msg: String):
	fails.append(msg)
	print("[ChangAnV2-E2E][FAIL] " + msg)


func _quit():
	if fails.is_empty():
		print("[ChangAnV2-E2E][PASS] v2灰盒进出城全链路验收通过")
		get_tree().quit(0)
	else:
		print("[ChangAnV2-E2E][FAIL] " + str(fails))
		get_tree().quit(1)
