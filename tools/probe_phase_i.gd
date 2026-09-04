extends Node

# Phase I 临时探针：I1背包HUD挂载与45格/I2开关与刷新/I3容量上限/I4格子使用物品
#   /I5奇遇最高优先级强制弹出/I6建造退出+幽灵预览/I7疾跑闪避动作分离/I8操作指南文案
# 用法：run_probe_i.py 临时注入[autoload] -> 跑一局 -> 文件日志 tools/probe_i_log.txt -> 自动还原
const LOG := "C:/Learn/my-godot-project/tools/probe_i_log.txt"
var pass_n := 0
var fail_n := 0

func _log(msg: String):
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f and FileAccess.file_exists(LOG):
		f.seek_end()
	if f == null:
		f = FileAccess.open(LOG, FileAccess.WRITE)
	f.store_line(msg)
	f.close()
	print(msg)

func _chk(cond: bool, name_: String, detail := ""):
	if cond:
		pass_n += 1
		_log("[PASS] %s %s" % [name_, detail])
	else:
		fail_n += 1
		_log("[FAIL] %s %s" % [name_, detail])

func _ui(n: String) -> Control:
	return get_node_or_null("/root/Main/World/UI/" + n) as Control

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _ready():
	var hud: Control = null
	for i in range(900):
		hud = _ui("SurvivalHUD")
		if hud != null:
			break
		await get_tree().process_frame
	if hud == null:
		_log("[Probe] SurvivalHUD not found")
		get_tree().quit()
		return
	await _wait(2.5)

	_log("=== I-LOGIC ===")
	var inv = get_node_or_null("/root/Main/InventoryManager")
	var ihud = _ui("InventoryHUD")
	var qm = _ui("QuickMenu")

	# ---- I1 背包HUD挂载 ----
	_chk(ihud != null, "I1 inventory-hud-mounted")
	_chk(ihud != null and not ihud.visible, "I1 inventory-hud-hidden-init")
	_chk(ihud != null and ihud.is_in_group("ui_modal"), "I1 inventory-in-ui-modal")
	_chk(inv != null and inv.max_slots == 45, "I1 max-slots-45", str(inv.max_slots) if inv else "?")

	# ---- I2 开关+计数 ----
	ihud.toggle()
	_chk(ihud.visible, "I2 toggle-open")
	_chk(ihud.title_lbl.text.ends_with("/ 45"), "I2 count-text", ihud.title_lbl.text)
	ihud.close()
	_chk(not ihud.visible, "I2 close")

	# ---- I4 格子使用消耗品 ----
	ihud.toggle()
	var herb_idx := -1
	for i in range(ihud.cell_slots.size()):
		if ihud.cell_slots[i] != null and ihud.cell_slots[i]["item"].item_id == "gold_herb":
			herb_idx = i
			break
	_chk(herb_idx >= 0, "I4 herb-cell-found", str(herb_idx))
	var cnt_before: int = inv.get_item_count("gold_herb")
	ihud._on_cell_click(herb_idx)
	await get_tree().process_frame
	var cnt_after: int = inv.get_item_count("gold_herb")
	_chk(cnt_after == cnt_before - 1, "I4 use-consumable", "%d->%d" % [cnt_before, cnt_after])
	# 使用后格子自动重刷（数量角标变化）
	ihud.close()

	# ---- I7 疾跑/闪避动作分离 ----
	_chk(InputMap.has_action("player_sprint"), "I7 sprint-action-exists")
	var shift_ok := false
	if InputMap.has_action("player_sprint"):
		for ev in InputMap.action_get_events("player_sprint"):
			if ev is InputEventKey and ev.keycode == 4194325:
				shift_ok = true
	_chk(shift_ok, "I7 sprint-bound-to-shift")
	var space_ok := false
	for ev in InputMap.action_get_events("player_dodge"):
		if ev is InputEventKey and ev.keycode == 32:
			space_ok = true
	_chk(space_ok, "I7 dodge-bound-to-space")

	# ---- I8 操作指南文案 ----
	var help_text: String = ""
	for child in hud.help_panel.get_children():
		if child is Label and child.text.find("WASD") >= 0:
			help_text = child.text
	_chk(help_text.find("Shift") >= 0 and help_text.find("疾跑") >= 0, "I8 help-sprint")
	_chk(help_text.find("空格  闪避") >= 0, "I8 help-dodge")
	_chk(help_text.find("I  背包") >= 0, "I8 help-inventory")
	_chk(help_text.find("打坐") >= 0, "I8 help-meditate")

	# ---- I6 建造模式：开关+幽灵预览（饥荒式：建造中可移动+鼠标落点） ----
	var player = get_tree().get_first_node_in_group("player")
	_chk(player != null, "I6 player-found")
	player._toggle_build()
	_chk(GameManager.is_build_mode and player.state == player.State.BUILD, "I6 build-enter")
	player._select_building("围墙")
	await get_tree().process_frame
	player._update_build_ghost()
	_chk(player.build_ghost != null and player.build_ghost.visible, "I6 ghost-visible")
	var buildable_here: bool = player._is_area_buildable(player.build_ghost.global_position, 1, 1)
	var ghost_cell = player.build_ghost_cells[0]
	_chk(ghost_cell.visible and (ghost_cell.color.g > 0.9) == buildable_here, "I6 ghost-color-matches-buildable", "ok=%s" % str(buildable_here))
	# 建造中人物可移动（WASD仍然生效）——headless帧率不定，轮询按住期间的速度/位移
	var px_before: float = player.global_position.x
	var saw_move := false
	Input.action_press("ui_right")
	for i in range(40):
		await get_tree().process_frame
		if player.velocity.x > 0 or player.global_position.x > px_before + 1.0:
			saw_move = true
			break
	Input.action_release("ui_right")
	_chk(saw_move, "I6 move-while-build", "%.1f->%.1f" % [px_before, player.global_position.x])
	# ESC 关闭（真实按键事件注入，_unhandled_input事件驱动）
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_chk(not GameManager.is_build_mode, "I6 esc-exit-build")
	_chk(not player.build_ghost.visible, "I6 ghost-hidden-on-exit")

	# ---- I5 奇遇最高优先级：预开商店+人物面板 → 触发奇遇 → 全部被打断 ----
	var shop_hud = _ui("ShopHUD")
	var sheet = _ui("CharacterSheet")
	shop_hud.open_shop()
	sheet.open()
	_chk(shop_hud.is_open and sheet.visible, "I5 pre-shop-sheet-open")
	var es = get_node_or_null("/root/Main/EncounterSystem")
	_chk(es != null, "I5 encounter-system-found")
	es.active_encounter = es.encounters[1]  # 高人传功
	await _wait(0.5)
	_chk(qm.encounter_panel.visible, "I5 encounter-panel-auto-open")
	_chk(not shop_hud.is_open, "I5 shop-force-closed")
	_chk(not sheet.visible, "I5 sheet-force-closed")
	var parent = qm.encounter_panel.get_parent()
	_chk(parent.get_child(parent.get_child_count() - 1) == qm.encounter_panel, "I5 panel-on-top")
	# 清理：关闭奇遇
	es.active_encounter = null
	qm.encounter_panel.visible = false

	# ---- I3 容量上限45（末尾执行防污染，测完还原） ----
	var base_size: int = inv.inventory.size()
	var fill_ok := true
	for i in range(45 - base_size):
		var it = Resource.new()
		it.set_script(load("res://scripts/item_resource.gd"))
		it.item_id = "probe_tmp_%d" % i
		it.item_name = "探针占位"
		it.stackable = true
		it.max_stack = 99
		if not inv.add_item(it, 1):
			fill_ok = false
			break
	_chk(fill_ok and inv.inventory.size() == 45, "I3 fill-to-45", str(inv.inventory.size()))
	var overflow = Resource.new()
	overflow.set_script(load("res://scripts/item_resource.gd"))
	overflow.item_id = "probe_tmp_overflow"
	overflow.item_name = "溢出物"
	overflow.stackable = true
	overflow.max_stack = 99
	_chk(not inv.add_item(overflow, 1), "I3 overflow-rejected")
	# 还原背包
	inv.inventory = inv.inventory.slice(0, base_size)
	inv.inventory_changed.emit()

	_log("=== I-SUMMARY pass=%d fail=%d ===" % [pass_n, fail_n])
	await _wait(0.3)
	get_tree().quit()
