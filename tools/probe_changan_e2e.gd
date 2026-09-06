extends Node
# M1 E2E 探针（临时 autoload，run_changan_e2e.py 调度）：游戏以真实主场景启动（/root/Main），
# 等世界就绪后驱动全链路：明德门入城 → 城内落点/站立采样 → 春明门出城 → 回落位置断言 → 自动退出
# 覆盖验收：入城自由行走不卡死（BFS已证连通+物理站立采样）/ BFS 100%（场景探针）/ 出城回开放世界位置正确

const TILE := 16
const LOG := "C:/Learn/my-godot-project/tools/changan_e2e_log.txt"
var fails: Array = []

func _log(m):
	print(m)
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(m)
		f.close()

func _ready() -> void:
	await _wait(4.0)   # 等世界生成+CityVisit footprint 铺设完成
	# E2E 冻结主线（石伯开场对话会挡 enter_interior 守卫且被剧情系统反复恢复）：
	# 关 MainStory 轮询 + 强关当前对话。FLAG 为 Godot4 冻结常量，运行期不可改。
	var main0 := get_node_or_null("/root/Main")
	if main0:
		var st := main0.get_node_or_null("MainStory")
		if st:
			st.set_process(false)
	if DialogManager.is_dialog_open():
		DialogManager.close_dialog()
		await _settle(2)
	var main := get_node_or_null("/root/Main")
	if main == null:
		_fail("主场景 /root/Main 不存在")
		_quit()
		return
	var cv = main.get_node_or_null("CityVisit")
	if cv == null or cv.gate_cells.size() != 4:
		_fail("CityVisit 未就绪 gate_cells=%s" % (cv.gate_cells.keys() if cv else []))
		_quit()
		return
	_log("[probe] footprint origin=%s 门格S=%s" % [cv.footprint_origin, cv.gate_cells["S"]])
	var p = main.get_node("World/Player")
	# 1) 传送到明德门外2格 → 踩豁口格（物理重叠触发入城）
	var outside: Vector2i = cv.gate_cells["S"]["outside"]
	var gap: Vector2i = cv.gate_cells["S"]["gap"]
	p.global_position = Vector2(outside.x * TILE + 8, outside.y * TILE + 8)
	await _settle(5)
	p.global_position = Vector2(gap.x * TILE + 8, gap.y * TILE + 8)
	if not await _wait_city(cv, true, 15000):
		_quit()
		return
	_check(cv.in_city and cv.changan != null, "入城成功且城内场景挂载")
	# 定点截图模式分叉：CHANGAN_SHOT="gx,gy" 城内格坐标——传送截图即退（材质排查用）
	var shot_env := OS.get_environment("CHANGAN_SHOT")
	if shot_env != "":
		var sp := shot_env.split(",")
		var scell := Vector2i(int(sp[0]), int(sp[1]))
		p.global_position = cv.CITY_OFFSET + cv.changan.cell_to_px(scell)
		p.velocity = Vector2.ZERO
		if p.has_node("Camera2D"):
			p.get_node("Camera2D").reset_smoothing()
		await _settle(10)
		await _shot("changan_v_spot.png")
		# dump 游戏进程内 tileset 71/105 实际纹理（定位"磁盘A渲染B"类问题）
		var ts_d: TileSet = cv.changan.tile_map.tile_set
		for tid in [71, 105]:
			if ts_d.has_source(tid):
				var sd := ts_d.get_source(tid) as TileSetAtlasSource
				sd.texture.get_image().save_png("res://docs/shots/dump_tile_%d.png" % tid)
				_log("[spot] dump tile %d -> docs/shots/dump_tile_%d.png" % [tid, tid])
		_log("[spot] done %s" % scell)
		_quit()
		return
	await _shot("changan_m1_city_mingde.png")   # 明德门内落点画面
	# 2) 城内落点 3×3 可通行（明德门内）
	var ch = cv.changan
	var spawn_cell := Vector2i(int((p.global_position.x - cv.CITY_OFFSET.x) / TILE), int((p.global_position.y - cv.CITY_OFFSET.y) / TILE))
	_check(ch.is_spawn_clear(spawn_cell), "明德门内落点3×3可通行 %s" % spawn_cell)
	# 3) 城内自由行走采样：西市中心与朱雀大街中段（BFS已证连通，此处验证物理不卡死/不坠出）
	var mk = ch.markets[0]
	var mcell := Vector2i(ch.col_x(int(mk["col"])) + ch.bw / 2, ch.row_y(int(mk["row"])) + ch.bh / 2)
	_tp(p, cv.CITY_OFFSET + ch.cell_to_px(mcell))
	await _settle(8)
	_check(_in_city_space(p, cv), "西市中心(%s)可站立无弹飞" % mcell)
	await _shot("changan_m1_city_xishi.png")   # 西市画面
	var zq_cell := Vector2i(ch.col_x(5) - ch.zq_s + ch.zq_s / 2, ch.H - ch.margin - ch.wall - 10)
	_tp(p, cv.CITY_OFFSET + ch.cell_to_px(zq_cell))
	await _settle(8)
	_check(_in_city_space(p, cv), "朱雀大街中段(%s)可站立无弹飞" % zq_cell)
	# 3.5) M2 剧情坊采样：宅邸门面前站立出样张（魏王府A门/天香阁A门）
	for wb in [["yankang", "延康坊"], ["pingkang", "平康坊"]]:
		var ward = null
		for b in ch.blocks:
			if String(b["name"]) == wb[1]:
				ward = b
				break
		if ward == null:
			continue
		var wx: int = ch.col_x(int(ward["col"]))
		var wy: int = ch.row_y(int(ward["row"]))
		_tp(p, cv.CITY_OFFSET + ch.cell_to_px(Vector2i(wx + 22, wy + 21)))   # SE象限（M4起NE宅门即是传送门，采样避开）
		await _settle(8)
		_check(_in_city_space(p, cv), "%s坊内可站立" % wb[1])
		await _shot("changan_m2_%s.png" % wb[0])
	# 3.5a) v4 坊内修缮样张：腹地错缝错排（延康坊西半）+ 渠畔坊缘（龙首渠临坊，水/岸石可见）
	var yk_block = null
	for b in ch.blocks:
		if String(b["name"]) == "延康坊":
			yk_block = b
			break
	if yk_block != null:
		var yx0: int = ch.col_x(int(yk_block["col"]))
		var yy0: int = ch.row_y(int(yk_block["row"]))
		var st_stag: Vector2i = ch.find_clear_spawn(Vector2i(yx0 + 6, yy0 + 12))
		_tp(p, cv.CITY_OFFSET + ch.cell_to_px(st_stag))
		await _settle(8)
		_check(_in_city_space(p, cv), "延康坊腹地可站立")
		await _shot("interior_ward_stagger.png")
	var cw_block = null
	for b in ch.blocks:
		if int(b["col"]) == 7 and int(b["row"]) == 2:
			cw_block = b
			break
	if cw_block != null:
		var cx0: int = ch.col_x(7)
		var cy0: int = ch.row_y(2)
		var st_canal: Vector2i = ch.find_clear_spawn(Vector2i(cx0 + 4, cy0 + 12))
		_tp(p, cv.CITY_OFFSET + ch.cell_to_px(st_canal))
		await _settle(8)
		_check(_in_city_space(p, cv), "龙首渠畔坊内可站立")
		await _shot("interior_ward_canal.png")
	# 3.5b) Slice F：宅门楼 prop 门前采样（站门外2格正对门楼；传送垫在门瓦上，门外不触发）
	var tower_shot := false
	for b in ch.blocks:
		if tower_shot:
			break
		for lot in b.get("lots", []):
			if String(lot.get("gate", "S")) != "S" or tower_shot:
				continue
			var lx: int = ch.col_x(int(b["col"])) + int(lot["at"][0])
			var ly: int = ch.row_y(int(b["row"])) + int(lot["at"][1])
			var lw: int = int(lot["size"][0])
			var lh: int = int(lot["size"][1])
			var gtx: int = lx + lw / 2
			var gty: int = ly + lh - 1
			_tp(p, cv.CITY_OFFSET + ch.cell_to_px(Vector2i(gtx, gty + 2)))
			await _settle(8)
			await _shot("changan_m2_gate_tower.png")
			_log("[probe] 门楼采样 grade=%s gate=(%d,%d)" % [String(lot["grade"]), gtx, gty])
			tower_shot = true
	# 3.6) M3 宵禁/夜色/时辰：城内时辰流动（Weather 未冻结）+ 暮鼓闭坊门 + 晨鼓复开
	var weather = main.get_node_or_null("World/WeatherController")
	_check(weather != null and weather.process_mode != Node.PROCESS_MODE_DISABLED,
			"城内 Weather 未冻结（时辰流动/CanvasModulate 夜色生效）")
	if weather:
		var gcell: Vector2i = ch.curfew_gates[0]["cells"][0]
		weather.world_time = 20.5 * 60.0 * weather.time_scale   # 戌时暮鼓
		await _settle(6)
		_check(ch.curfew and int(ch.decor[gcell.y * ch.W + gcell.x]) == ch.T_GATE_CLOSED,
				"暮鼓宵禁：坊门换闭门瓦(68)")
		await _wait(2.5)   # 等灯光 lerp 稳定再出夜色样张
		await _shot("changan_m3_curfew_night.png")
		weather.world_time = 10.0 * 60.0 * weather.time_scale   # 晨鼓开门
		await _settle(6)
		_check(not ch.curfew and int(ch.decor[gcell.y * ch.W + gcell.x]) == ch.T_GATE_OPEN,
				"晨鼓开门：坊门复开(67)")
		await _wait(2.5)   # 等灯光 lerp 回白天，内景样张不受夜色残留影响
	# 3.7) M3 城内NPC：按锚点日程生成
	_check(ch.npc_list.size() == ch.CITY_NPC_CONFIGS.size(),
			"城内NPC生成=%d（配置%d）" % [ch.npc_list.size(), ch.CITY_NPC_CONFIGS.size()])
	# 3.8) M4 内景：西市琥珀光 门面触发 → 内景采样/样张 → 踩出口垫返回门面前原位
	if DialogManager.is_dialog_open():
		DialogManager.close_dialog()   # 故事计时器在冻结前已开石伯对话；MainStory 已停轮询，此处关闭后不会重开
		await _settle(3)
	var pcell: Vector2i = ch.interior_portals["huguguang"]
	_tp(p, cv.CITY_OFFSET + ch.cell_to_px(pcell))
	var t_in := Time.get_ticks_msec()
	while cv.interior == null and Time.get_ticks_msec() - t_in < 8000:
		await get_tree().process_frame
	if cv.interior == null:
		_log("[probe][DBG] 8s未进内景: player=%s busy=%s dialog=%s portals=%s" %
				[p.global_position, cv._busy, DialogManager.is_dialog_open(), ch.interior_portals])
	_check(cv.interior != null and cv.interior.interior_id == "huguguang", "进内景·琥珀光")
	if cv.interior != null:
		var it = cv.interior
		var t_ready := Time.get_ticks_msec()
		while cv._busy and Time.get_ticks_msec() - t_ready < 3000:
			await get_tree().process_frame   # 等淡入完成再采样/截图（遮罩未退会拍出暗帧）
		_tp(p, cv.INTERIOR_OFFSET + it.cell_to_px(it.spawn_cell + Vector2i(-4, -3)))
		await _settle(8)
		_check(p.global_position.y > cv.INTERIOR_OFFSET.y, "琥珀光前堂内可站立")
		await _shot("changan_m4_huguguang.png")
		_tp(p, cv.INTERIOR_OFFSET + it.cell_to_px(it.exit_cell))
		var t_out := Time.get_ticks_msec()
		while cv.interior != null and Time.get_ticks_msec() - t_out < 8000:
			await get_tree().process_frame
		_check(cv.interior == null, "踩出口垫返回")
		var t_busy := Time.get_ticks_msec()
		while (cv._busy or cv.interior != null) and Time.get_ticks_msec() - t_busy < 5000:
			await get_tree().process_frame
		var dx_back: float = absf(p.global_position.x - (cv.CITY_OFFSET.x + ch.cell_to_px(pcell).x))
		var dy_back: float = absf(p.global_position.y - (cv.CITY_OFFSET.y + ch.cell_to_px(pcell).y))
		var back_ok: bool = dx_back <= 24.0 and dy_back <= 24.0
		_check(back_ok, "内景返回门面前原位（±1.5格）")
		await _shot("changan_m4_back_city.png")
	# 3.9) M5 批量内景：魏王府（mansion 模板族生成路径）往返
	var wcell: Vector2i = ch.interior_portals["wei_wangfu"]
	_tp(p, cv.CITY_OFFSET + ch.cell_to_px(wcell))
	var t_in2 := Time.get_ticks_msec()
	while cv.interior == null and Time.get_ticks_msec() - t_in2 < 8000:
		if DialogManager.is_dialog_open():
			DialogManager.close_dialog()
		await get_tree().process_frame
	_check(cv.interior != null and cv.interior.interior_id == "wei_wangfu", "进内景·魏王府（批量模板）")
	if cv.interior != null:
		var it2 = cv.interior
		var exit2_px: Vector2 = cv.INTERIOR_OFFSET + it2.cell_to_px(it2.exit_cell)   # 先存（退出后实例已释放）
		var t_r2 := Time.get_ticks_msec()
		while cv._busy and Time.get_ticks_msec() - t_r2 < 3000:
			await get_tree().process_frame
		_tp(p, cv.INTERIOR_OFFSET + it2.cell_to_px(it2.spawn_cell + Vector2i(0, -3)))   # 前院内站位（避开出口垫）
		await _settle(8)
		_check(_in_city_space(p, cv), "魏王府前院内可站立")
		await _shot("changan_m5_wei_wangfu.png")
		_tp(p, exit2_px)
		var t_out2 := Time.get_ticks_msec()
		while cv.interior != null and Time.get_ticks_msec() - t_out2 < 8000:
			await get_tree().process_frame
		var t_b2 := Time.get_ticks_msec()
		while (cv._busy or cv.interior != null) and Time.get_ticks_msec() - t_b2 < 5000:
			await get_tree().process_frame
		_check(cv.interior == null, "魏王府踩出口垫返回")
		var dx2: float = absf(p.global_position.x - (cv.CITY_OFFSET.x + ch.cell_to_px(wcell).x))
		var dy2: float = absf(p.global_position.y - (cv.CITY_OFFSET.y + ch.cell_to_px(wcell).y))
		_check(dx2 <= 24.0 and dy2 <= 24.0, "魏王府返回门面前原位")
	# 3.9b) 内景换皮样张×6（宅邸/寺观/酒肆/绸缎/宫院/琥珀光）——SCKR 陈设目检（2026-09-06）
	ch.unlock_stage(2)   # 靖善坊(stage2)寺观传送门需全解锁（unlocked_wards 去重，幂等）
	var shot_list := [
		["wei_wangfu", "正厅", "interior_mansion_weiwangfu.png", -2],
		["daxingshan_si", "大殿", "interior_temple_daxingshan.png", 0],
		["jiushi_e", "铺面", "interior_shop_wine_jiushi.png", 0],
		["sizhuang_w", "铺面", "interior_shop_silk_sizhuang.png", 0],
		["taiji_dian", "大殿", "interior_palace_taiji.png", -14],
		["huguguang", "前堂", "interior_huguguang.png", -8],
	]
	for shot in shot_list:
		await _visit_interior_shot(p, cv, ch, String(shot[0]), String(shot[1]), String(shot[2]), int(shot[3]))
	# 3.5) 视觉重构样张：宫城太极殿 + 晋昌坊大雁塔（unlock_stage(1) 后立塔）
	ch.unlock_stage(1)
	var ppal: Vector2 = cv.CITY_OFFSET + ch.cell_to_px(ch.interior_portals["taiji_dian"])
	_tp(p, ppal + Vector2(0, 48))
	await _settle(8)
	_check(_in_city_space(p, cv), "宫城丹墀可站立")
	await _shot("changan_v_palace.png")
	var pag_cell := Vector2i(ch.col_x(10) + 5, ch.row_y(8) + 12)   # 晋昌坊 daciensi 院内塔前
	_tp(p, cv.CITY_OFFSET + ch.cell_to_px(pag_cell))
	await _settle(8)
	await _shot("changan_v_pagoda.png")
	# 4) 走到春明门豁口（城内侧坐标）→ 出城
	var egap_in: Vector2i = ch.gate_info["E"]["gap_cells"][1]
	p.global_position = cv.CITY_OFFSET + ch.cell_to_px(egap_in)
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
	# 7) 开放世界侧轮廓画面（传回明德门外看城郭）
	var sout: Vector2i = cv.gate_cells["S"]["outside"]
	p.global_position = Vector2(sout.x * TILE + 8, sout.y * TILE + 8)
	await _settle(5)
	await _shot("changan_m1_world_footprint.png")
	_quit()

func _in_city_space(p, cv) -> bool:
	return p.global_position.y > cv.CITY_OFFSET.y

# 内景样张访问器：进内景 → 指定房间南中站位（家具占格向上兜底）→ 截图 → 踩出口垫返回
func _visit_interior_shot(p, cv, ch, ref: String, room_label: String, fname: String, dy: int = 0) -> void:
	var t0 := Time.get_ticks_msec()
	while (cv._busy or cv.interior != null) and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	if not ch.interior_portals.has(ref):
		_fail("样张传送门缺失 " + ref)
		return
	var pcell: Vector2i = ch.interior_portals[ref]
	# 刚从同一门面出来：玩家仍站门前景格（防重进作用域锁+无重入事件）——先挪开，等 800ms 锁过期再踩回
	if p.global_position.distance_to(cv.CITY_OFFSET + ch.cell_to_px(pcell)) < 8.0:
		_tp(p, cv.CITY_OFFSET + ch.cell_to_px(pcell + Vector2i(0, 2)))
		await _wait(0.9)
	_tp(p, cv.CITY_OFFSET + ch.cell_to_px(pcell))
	var t_in := Time.get_ticks_msec()
	while cv.interior == null and Time.get_ticks_msec() - t_in < 8000:
		if DialogManager.is_dialog_open():
			DialogManager.close_dialog()
		await get_tree().process_frame
	if cv.interior == null:
		_fail("样张进内景失败 " + ref)
		return
	var it = cv.interior
	var t_r := Time.get_ticks_msec()
	while cv._busy and Time.get_ticks_msec() - t_r < 3000:
		await get_tree().process_frame   # 等淡入完成（遮罩未退拍出暗帧）
	var stand := Vector2i(-1, -1)
	for room in it.spec_rooms:
		if String(room.get("label", "")) == room_label:
			var r: Array = room["rect"]
			stand = Vector2i(int(r[0]) + int(r[2]) / 2, int(r[1]) + int(r[3]) - 2 + dy)
			break
	if stand.x < 0:
		stand = it.spawn_cell
	for up in range(7):
		if it.is_spawn_clear(stand + Vector2i(0, -up)):
			stand = stand + Vector2i(0, -up)
			break
	_tp(p, cv.INTERIOR_OFFSET + it.cell_to_px(stand))
	await _settle(8)
	await _shot(fname)
	var exit_px: Vector2 = cv.INTERIOR_OFFSET + it.cell_to_px(it.exit_cell)   # 先缓存（退出后实例已释放）
	_tp(p, exit_px)
	var t_out := Time.get_ticks_msec()
	while cv.interior != null and Time.get_ticks_msec() - t_out < 8000:
		await get_tree().process_frame
	var t_b := Time.get_ticks_msec()
	while (cv._busy or cv.interior != null) and Time.get_ticks_msec() - t_b < 5000:
		await get_tree().process_frame
	_log("[probe] 内景样张 " + ref + " -> docs/shots/" + fname)

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

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _shot(fname: String):
	if DisplayServer.get_name() == "headless":
		return   # headless 无渲染，跳过截图（窗口模式才产出样张）
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://docs/shots/" + fname)
	_log("[probe] 截图 docs/shots/" + fname)

func _check(cond: bool, msg: String):
	if cond:
		_log("[E2E][PASS] " + msg)
	else:
		fails.append(msg)
		_log("[E2E][FAIL] " + msg)

func _fail(msg: String):
	fails.append(msg)
	_log("[E2E][FAIL] " + msg)

func _quit():
	if fails.is_empty():
		_log("[ChangAn-M1-E2E][PASS] 进出城全链路验收通过")
		get_tree().quit(0)
	else:
		_log("[ChangAn-M1-E2E][FAIL] " + str(fails))
		get_tree().quit(1)
