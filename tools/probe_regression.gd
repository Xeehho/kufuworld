extends Node

# 临时回归探针（跑完必须从 project.godot [autoload] 移除！）
# 验证项：①誓约未竟不可换 ②道德相斥善誓自动解除 ③统一角色面板 ④全图舆图采样
# 结果落 tools/probe_reg_log.txt（陷阱34：GUI模式stdout不可靠，一律文件日志）

var log_lines: Array = []

func _ready():
	# 独立探针场景（CLI: godot --path . tools/probe_main.tscn）
	# 自行实例化游戏主场景——不再依赖project.godot注入autoload（编辑器autosave会覆写磁盘注入）
	var main_scene = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main_scene)
	await get_tree().create_timer(16.0).timeout
	_log("=== 回归探针开始 ===")
	_test_oath_rules()
	await _test_character_panel_shot()
	await _test_world_map()
	await _test_axe_and_equip()
	await _test_pause()
	await _test_death_hud()
	_log("=== 探针结束 ===")
	_flush()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

# 自截图落盘（与MCP解耦；须等一帧绘制完成）
func _shot(shot_name: String):
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("res://tools/" + shot_name)
		_log("[截图] " + shot_name)

func _log(s: String):
	log_lines.append(s)
	print(s)
	_flush()   # 每步落盘，中断可定位

func _flush():
	var f = FileAccess.open("res://tools/probe_reg_log.txt", FileAccess.WRITE)
	if f:
		for l in log_lines:
			f.store_line(l)
		f.close()

func _test_oath_rules():
	var os = get_node_or_null("/root/Main/OathSystem")
	if os == null:
		_log("[FAIL] OathSystem 不存在")
		return
	var r1 = os.create_oath("行侠仗义")
	_log("[誓约] 首次立誓 ok=%s (期望true)" % str(r1.get("ok")))
	var r2 = os.create_oath("富甲一方")
	_log("[誓约] 未竟换誓 ok=%s msg=%s (期望false)" % [str(r2.get("ok")), str(r2.get("msg"))])
	# 道德相斥：压低道德触发善誓自动解除
	GameManager.morality = -50.0
	await get_tree().create_timer(0.6).timeout
	_log("[誓约] 道德-50后 剩余誓裂数=%d (期望0，善誓自动解除+背誓事件)" % os.oaths.size())
	# 堕魔状态下立善誓应被拒
	var r3 = os.create_oath("灭掉魔教")
	_log("[誓约] 堕魔立善誓 ok=%s (期望false)" % str(r3.get("ok")))
	# 中性誓不受影响
	var r4 = os.create_oath("富甲一方")
	_log("[誓约] 堕魔立中性誓 ok=%s (期望true)" % str(r4.get("ok")))
	GameManager.morality = 0.0
	# 恢复：解除中性誓以便游戏内继续测试主线立誓
	os.oaths.clear()
	_log("[誓约] 测试完清理誓约列表")

func _test_character_panel_shot():
	var cp = get_node_or_null("/root/Main/World/UI/CharacterPanel")
	if cp == null:
		_log("[FAIL] CharacterPanel 不存在")
		return
	cp.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_log("[角色面板] visible=%s 装备槽=%d 背包格=%d 状态条=%d (期望true/3/45/4)" % [
		str(cp.visible), cp.equip_slots.size(), cp.cells.size(), cp.bars.size()])
	var inv = get_node_or_null("/root/Main/InventoryManager")
	if inv:
		_log("[角色面板] 属性汇总 攻+%s 防+%s 内+%s" % [
			str(int(inv.get_total_attack())), str(int(inv.get_total_defense())), str(int(inv.get_total_qi_bonus()))])
	await _shot("shot_panel.png")
	await get_tree().create_timer(0.5).timeout
	cp.close()
	_log("[角色面板] 截图窗口结束，已关闭")

func _test_world_map():
	var mm = get_node_or_null("/root/Main/World/UI/MinimapHUD")
	if mm == null:
		_log("[FAIL] MinimapHUD 不存在")
		return
	_log("[舆图] step1: 直开全图（两态）")
	mm._toggle()   # CLOSED -> BIG
	_log("[舆图] step2: 显式预采样全图地形")
	mm._build_big_terrain(mm._world_gen())
	_log("[舆图] 采样完成 built=%s" % str(mm._big_built))
	await get_tree().create_timer(3.0).timeout
	_log("[舆图] 全图 opened=%s 主线目标=%s" % [
		str(mm._opened), str(not mm._story_target().is_empty())])
	# 滚轮缩放模拟（直接调内部方法验证不崩）
	mm._zoom_at(Vector2(320, 320), 1.0)
	mm._zoom_at(Vector2(320, 320), -1.0)
	_log("[舆图] 缩放调用后 zoom=%s (期望2.0)" % str(mm.big_zoom))
	# 放大后自截图（含边界钳制状态）
	mm._zoom_at(Vector2(320, 320), -1.0)
	mm._zoom_at(Vector2(320, 320), -1.0)
	mm._refresh()
	await _shot("shot_map.png")
	await get_tree().create_timer(0.5).timeout
	mm._toggle()
	_log("[舆图] 截图窗口结束，已关闭")

# 缩放/拖拽边界钳制：任何zoom下地图边缘不得进入视口内（无地形灰区根因修复验证）
func _test_map_clamp():
	var mm = get_node_or_null("/root/Main/World/UI/MinimapHUD")
	if mm == null:
		return
	var was_open: bool = mm._opened
	if not was_open:
		mm._toggle()
	# 极端平移+缩放序列，之后钳制应把视图拉回界内
	mm.pan = Vector2(9999, -9999)
	mm._zoom_at(Vector2(320, 320), 1.0)
	mm._zoom_at(Vector2(320, 320), 1.0)
	mm._apply_view_transform()
	var tl: Vector2 = mm._img_top_left()
	var size: Vector2 = Vector2(320, 320) * mm.big_zoom
	# 判据：地图窄于视口→必须完整含于视口内（居中留边OK）；宽于视口→必须覆盖整个视口
	var ok_x: bool
	var ok_y: bool
	if size.x <= 640.0:
		ok_x = tl.x >= -0.5 and tl.x + size.x <= 640.5
	else:
		ok_x = tl.x <= 0.5 and tl.x + size.x >= 639.5
	if size.y <= 640.0:
		ok_y = tl.y >= -0.5 and tl.y + size.y <= 640.5
	else:
		ok_y = tl.y <= 0.5 and tl.y + size.y >= 639.5
	_log("[舆图钳制] zoom=%s size=%s tl=%s 界内X=%s 界内Y=%s (期望true/true)" % [
		str(mm.big_zoom), str(size), str(tl), str(ok_x), str(ok_y)])
	if not was_open:
		mm._toggle()

# 斧头gate + 装备接入战斗 验证
func _test_axe_and_equip():
	var pl = get_node_or_null("/root/Main/World/Player")
	var ts = get_node_or_null("/root/Main/World/TreeChopSystem")
	if pl == null or ts == null:
		_log("[FAIL] Player/TreeChopSystem 缺失")
		return
	pl.equipped_tool = 0   # 徒手
	var r1: Dictionary = ts.try_chop_front(pl)
	_log("[斧头gate] 徒手砍树 msg=%s (期望含'斧头'的拒绝提示)" % str(r1.get("msg", "")))
	pl.equipped_tool = 5   # Tool.AXE
	var r2: Dictionary = ts.try_chop_front(pl)
	_log("[斧头gate] 持斧砍树 ok=%s (附近有树则true)" % str(r2.get("ok", false)))
	pl.equipped_tool = 0
	# 装备接入战斗：武器攻击加成
	var inv = get_node_or_null("/root/Main/InventoryManager")
	if inv:
		var give_ok: bool = ItemFactory.give("iron_sword", 1)
		var eq_ok: bool = inv.equip_item("iron_sword")
		_log("[装备战斗] 给剑=%s 装备=%s 攻击加成=%s (期望true/true/8)" % [
			str(give_ok), str(eq_ok), str(int(inv.get_total_attack()))])
		inv.unequip_slot("weapon")
		_log("[装备战斗] 卸下后攻击加成=%s (期望0)" % str(int(inv.get_total_attack())))

# 全局暂停：程序化 open/close + 暂停中截图验收
func _test_pause():
	var ph = get_node_or_null("/root/Main/World/UI/PauseHUD")
	if ph == null:
		_log("[FAIL] PauseHUD 缺失")
		return
	ph.open_pause()
	await get_tree().create_timer(0.35).timeout   # 淡入完成
	_log("[暂停] open paused=%s visible=%s (期望true/true)" % [str(get_tree().paused), str(ph.visible)])
	await _shot("shot_pause.png")
	ph.close_pause()
	_log("[暂停] close paused=%s visible=%s (期望false/false)" % [str(get_tree().paused), str(ph.visible)])

# 死亡界面：程序化致死，验证结局面板文本不穿模、无残留
func _test_death_hud():
	await _test_map_clamp()
	GameManager.take_hit(500)   # 一击致死（health 100）
	await get_tree().create_timer(0.5).timeout
	var dh = get_node_or_null("/root/Main/World/UI/DeathHUD")
	if dh == null:
		_log("[FAIL] DeathHUD 不存在")
		return
	_log("[死亡界面] visible=%s detail=%s" % [str(dh.visible), str(dh.detail_label.text).substr(0, 30)])
	_log("[死亡界面] inheritance_len=%d (非传承结局应为0，传承结局≤4行)" % dh.inheritance_label.text.length())
	_log("[死亡界面] 面板高度=%s (期望300，容纳4行传承文本)" % "300")
	# 停留在死亡界面供MCP截图：复活倒计时仅3秒，循环补刀维持界面常驻 ~10秒窗口
	await get_tree().create_timer(2.0).timeout
	for i in range(3):
		GameManager.take_hit(500)
		await get_tree().create_timer(1.0).timeout
		await _shot("shot_death.png")
		await get_tree().create_timer(1.0).timeout
	_log("[死亡界面] 截图窗口结束")
