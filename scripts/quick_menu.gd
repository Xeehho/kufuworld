extends Control

# 快捷菜单 - 右上角入口按钮 + 奇遇/立誓弹窗
# 奇遇触发时自动弹出选项面板，支持点击或数字键选择

var encounter_panel: Panel = null
var encounter_title: Label = null
var encounter_desc: Label = null
var encounter_options_box: VBoxContainer = null
# 结果视图
var result_box: VBoxContainer = null
var result_text: Label = null
var result_rewards: VBoxContainer = null
var continue_btn: Button = null
var error_label: Label = null
var _showing_result: bool = false

var oath_panel: Panel = null
var oath_list_label: Label = null
var oath_tip_label: Label = null

var encounter_btn: Button = null
var _flash_tween: Tween = null
var _encounter_was_active: bool = false

# 门派交互
var clan_btn: Button = null
var clan_panel: Panel = null
var clan_title: Label = null
var clan_info: Label = null
var clan_options_box: VBoxContainer = null
var clan_hint: Label = null
var _clan_flash_tween: Tween = null
var _clan_btn_visible: bool = false

func _ready():
	# 全屏锚定以便弹窗居中；自身不拦截鼠标（按钮/面板各自接收）
	# 注意：必须用 set_anchors_and_offsets_preset —— set_anchors_preset 默认保留偏移，
	# 对初始尺寸为0的节点会把偏移设为负父尺寸，导致控件永远保持0尺寸（居中锚点全部失效）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_buttons()
	_create_encounter_panel()
	_create_oath_panel()
	_create_clan_panel()

func _create_buttons():
	var btn_e = Button.new()
	btn_e.text = "⚡ 奇遇"
	btn_e.size = Vector2(80, 30)
	btn_e.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn_e.position = Vector2(-180, 10)
	UITheme.style_button(btn_e, 13)
	btn_e.pressed.connect(_on_encounter_btn)
	add_child(btn_e)
	encounter_btn = btn_e

	var btn_o = Button.new()
	btn_o.text = "🎋 立誓"
	btn_o.size = Vector2(80, 30)
	btn_o.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn_o.position = Vector2(-92, 10)
	UITheme.style_button(btn_o, 13)
	btn_o.pressed.connect(_on_oath_btn)
	add_child(btn_o)

	# 门派按钮（进入门派地盘时才显示）
	var btn_c = Button.new()
	btn_c.text = "⛩ 门派"
	btn_c.size = Vector2(80, 30)
	btn_c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn_c.position = Vector2(-268, 10)
	btn_c.visible = false
	UITheme.style_button(btn_c, 13)
	btn_c.pressed.connect(_on_clan_btn)
	add_child(btn_c)
	clan_btn = btn_c

# ---------- 奇遇面板 ----------

func _create_encounter_panel():
	encounter_panel = Panel.new()
	UITheme.center_panel(encounter_panel, 520, 420)
	encounter_panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	encounter_panel.visible = false
	add_child(encounter_panel)

	encounter_title = Label.new()
	encounter_title.position = Vector2(20, 14)
	encounter_title.size = Vector2(480, 28)
	encounter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(encounter_title, 20)
	encounter_panel.add_child(encounter_title)

	encounter_desc = Label.new()
	encounter_desc.position = Vector2(24, 52)
	encounter_desc.size = Vector2(472, 70)
	encounter_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	UITheme.style_label(encounter_desc, 14)
	encounter_panel.add_child(encounter_desc)

	# 选项视图
	encounter_options_box = VBoxContainer.new()
	encounter_options_box.position = Vector2(24, 130)
	encounter_options_box.size = Vector2(472, 180)
	encounter_options_box.add_theme_constant_override("separation", 8)
	encounter_panel.add_child(encounter_options_box)

	# 错误提示（如铜钱不足）
	error_label = Label.new()
	error_label.position = Vector2(24, 316)
	error_label.size = Vector2(472, 20)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(error_label, 13, UITheme.DANGER)
	encounter_panel.add_child(error_label)

	# 结果视图（初始隐藏）
	result_box = VBoxContainer.new()
	result_box.position = Vector2(24, 130)
	result_box.size = Vector2(472, 240)
	result_box.add_theme_constant_override("separation", 6)
	result_box.visible = false
	encounter_panel.add_child(result_box)

	result_text = Label.new()
	result_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	result_text.custom_minimum_size = Vector2(472, 56)
	UITheme.style_label(result_text, 14)
	result_box.add_child(result_text)

	var sep = HSeparator.new()
	result_box.add_child(sep)

	var gain_title = Label.new()
	gain_title.text = "—— 得 失 ——"
	gain_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(gain_title, 13, UITheme.GOLD_DIM)
	result_box.add_child(gain_title)

	result_rewards = VBoxContainer.new()
	result_rewards.add_theme_constant_override("separation", 3)
	result_box.add_child(result_rewards)

	continue_btn = Button.new()
	continue_btn.text = " 继 续 "
	continue_btn.custom_minimum_size = Vector2(120, 36)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.style_button(continue_btn, 14)
	continue_btn.pressed.connect(_close_result_view)
	result_box.add_child(continue_btn)

	var hint = Label.new()
	hint.text = "点击选项 或 按数字键选择"
	hint.position = Vector2(24, 382)
	UITheme.style_label(hint, 11, UITheme.TEXT_DIM)
	encounter_panel.add_child(hint)

	# 离开按钮（可点击关闭，等价于按 [0]）
	var leave_btn = Button.new()
	leave_btn.text = "离开 [0]"
	leave_btn.position = Vector2(404, 378)
	leave_btn.size = Vector2(92, 32)
	UITheme.style_button(leave_btn, 13)
	leave_btn.pressed.connect(_close_encounter_panel)
	encounter_panel.add_child(leave_btn)

func _open_encounter_panel():
	var es = _get_encounter_system()
	if es == null or es.active_encounter == null:
		return
	_stop_encounter_flash()
	# 先关掉可能开着的对话框，避免与奇遇面板两层模态叠加
	DialogManager.close_dialog()
	var enc = es.active_encounter
	_showing_result = false
	result_box.visible = false
	encounter_options_box.visible = true
	error_label.text = ""
	encounter_title.text = "⚡ " + enc.title
	encounter_desc.text = enc.description
	for child in encounter_options_box.get_children():
		child.queue_free()
	for i in range(enc.options.size()):
		var opt = enc.options[i]
		var btn = Button.new()
		btn.text = str(i + 1) + ". " + opt.text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 36)
		UITheme.style_button(btn, 14)
		btn.pressed.connect(_on_encounter_option.bind(i))
		encounter_options_box.add_child(btn)
	encounter_panel.visible = true
	encounter_panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(encounter_panel, "modulate:a", 1.0, 0.15)

# 奇遇最高优先级弹出：打断/关闭一切在开的界面（商店/建造/任务日志/人物档案/NPC交互/对话），面板置顶
func _force_open_encounter():
	# 1. 退出建造模式
	var player = get_tree().get_first_node_in_group("player")
	if player and "state" in player and player.state == player.State.BUILD:
		player._toggle_build()
	# 2. 关商店
	var shop_hud = get_node_or_null("/root/Main/World/UI/ShopHUD")
	if shop_hud and shop_hud.is_open:
		shop_hud.close_shop()
	# 3. 关任务日志抽屉
	var quest_log = get_node_or_null("/root/Main/World/UI/QuestLogHUD")
	if quest_log and quest_log.expanded:
		quest_log.toggle_panel()
	# 4. 关统一角色面板（旧CharacterSheet已由CharacterPanel替代）
	var sheet = get_node_or_null("/root/Main/World/UI/CharacterPanel")
	if sheet and sheet.visible:
		sheet.close()
	# 5. 关NPC交互菜单
	var spawner = get_node_or_null("/root/Main/World/NPCSpawner")
	if spawner and spawner.has_method("hide_interaction_ui") and spawner.is_interaction_open():
		spawner.hide_interaction_ui()
	# 6. 关对话框（_open_encounter_panel 内也会兜底）
	DialogManager.close_dialog()
	# 7. 弹出面板并压到同级最上方
	_open_encounter_panel()
	if encounter_panel and encounter_panel.visible:
		var parent = encounter_panel.get_parent()
		parent.move_child(encounter_panel, parent.get_child_count() - 1)
		# 三国群英传式提示音（AudioController存在时）
		var ac = get_node_or_null("/root/Main/World/AudioController")
		if ac and ac.has_method("play_sfx"):
			ac.play_sfx("ui", -6.0)

func _on_encounter_option(idx: int):
	var es = _get_encounter_system()
	if es == null:
		return
	var result = es.resolve_encounter(idx)
	if not result.get("ok", false):
		# 结算失败（如铜钱不足）：留在选项视图并提示
		error_label.text = result.get("error", "")
		return
	_show_result_view(result)

# 结果视图：展示结果文本 + 得失明细，单击继续即关闭
func _show_result_view(result: Dictionary):
	_showing_result = true
	encounter_options_box.visible = false
	error_label.text = ""
	result_text.text = result.get("result_text", "")
	for child in result_rewards.get_children():
		child.queue_free()
	var rewards: Array = result.get("rewards", [])
	if rewards.is_empty():
		var none = Label.new()
		none.text = "（无得失）"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_label(none, 13, UITheme.TEXT_DIM)
		result_rewards.add_child(none)
	else:
		for r in rewards:
			var lbl = Label.new()
			lbl.text = r["text"]
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UITheme.style_label(lbl, 14, UITheme.JADE if r["good"] else UITheme.DANGER)
			result_rewards.add_child(lbl)
	result_box.visible = true
	result_box.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(result_box, "modulate:a", 1.0, 0.12)

func _close_result_view():
	_showing_result = false
	result_box.visible = false
	encounter_panel.visible = false

func _close_encounter_panel():
	var es = _get_encounter_system()
	if es and es.active_encounter:
		es.active_encounter = null
	encounter_panel.visible = false

func _on_encounter_btn():
	# 面板已打开时再点按钮 = 关闭（toggle），结果已结算不会丢失
	if encounter_panel and encounter_panel.visible:
		_close_encounter_panel()
		return
	var es = _get_encounter_system()
	if es == null or es.active_encounter == null:
		DialogManager.show_dialog("江湖", ["一时风平浪静，暂无奇遇..."])
		return
	_open_encounter_panel()

# ---------- 立誓面板 ----------

func _create_oath_panel():
	oath_panel = Panel.new()
	UITheme.center_panel(oath_panel, 520, 460)
	oath_panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	oath_panel.visible = false
	add_child(oath_panel)

	var title = Label.new()
	title.text = "🎋 立下誓言"
	title.position = Vector2(20, 14)
	title.size = Vector2(480, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(title, 20)
	oath_panel.add_child(title)

	var choices = ["成为天下第一", "富甲一方", "灭掉魔教", "博学多才", "行侠仗义"]
	var box = VBoxContainer.new()
	box.position = Vector2(24, 52)
	box.size = Vector2(472, 230)
	box.add_theme_constant_override("separation", 6)
	oath_panel.add_child(box)
	for i in range(choices.size()):
		var btn = Button.new()
		btn.text = str(i + 1) + ". " + choices[i]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 32)
		UITheme.style_button(btn, 13)
		btn.pressed.connect(_on_oath_choice.bind(choices[i]))
		box.add_child(btn)

	var tip = Label.new()
	tip.text = "（同时只能持有一个誓言；未竟之誓不可更换，与道行相悖的善誓将自动解除）"
	tip.position = Vector2(24, 246)
	tip.size = Vector2(472, 34)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(tip, 11, UITheme.TEXT_DIM)
	oath_panel.add_child(tip)
	oath_tip_label = tip

	var div = Label.new()
	div.text = "—— 当前誓言 ——"
	div.position = Vector2(24, 294)
	div.size = Vector2(472, 20)
	div.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(div, 12, UITheme.GOLD_DIM)
	oath_panel.add_child(div)

	oath_list_label = Label.new()
	oath_list_label.position = Vector2(24, 318)
	oath_list_label.size = Vector2(472, 96)
	oath_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	oath_list_label.clip_text = true
	UITheme.style_label(oath_list_label, 12)
	oath_panel.add_child(oath_list_label)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.position = Vector2(210, 420)
	close_btn.size = Vector2(100, 30)
	UITheme.style_button(close_btn, 13)
	close_btn.pressed.connect(func(): oath_panel.visible = false)
	oath_panel.add_child(close_btn)

func _on_oath_btn():
	_refresh_oath_list()
	oath_panel.visible = true
	oath_panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(oath_panel, "modulate:a", 1.0, 0.15)

func _on_oath_choice(choice: String):
	var os = get_node_or_null("/root/Main/OathSystem")
	if os:
		var res = os.create_oath(choice)
		# 立誓被拒（未竟之誓不可换/善誓与道行相斥）：面板内即时反馈
		if oath_tip_label:
			if bool(res.get("ok", true)):
				oath_tip_label.text = "✅ " + str(res.get("msg", "立誓成功"))
				oath_tip_label.add_theme_color_override("font_color", UITheme.JADE)
			else:
				oath_tip_label.text = "❌ " + str(res.get("msg", "立誓失败"))
				oath_tip_label.add_theme_color_override("font_color", UITheme.DANGER)
	_refresh_oath_list()

func _refresh_oath_list():
	var os = get_node_or_null("/root/Main/OathSystem")
	if os == null:
		return
	var oaths = os.get_oaths()
	if oaths.is_empty():
		oath_list_label.text = "（尚未立下任何誓言）"
		return
	# 只详细展示进行中的誓言（至多一个）；已达成的压缩为一行，防止超出容器
	var t = ""
	for o in oaths:
		if o["is_fulfilled"]:
			t += "✅ 已达成：「" + o["title"] + "」\n"
		else:
			t += "⏳ " + o["title"] + "  " + str(int(o["progress"] * 100)) + "%\n"
			for m in o["milestones"]:
				var check = "✓" if o["completed_milestones"].has(m) else "○"
				t += "   " + check + " " + m + "\n"
	oath_list_label.text = t.strip_edges()

# ---------- 门派面板 ----------

func _create_clan_panel():
	clan_panel = Panel.new()
	UITheme.center_panel(clan_panel, 520, 420)
	clan_panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	clan_panel.visible = false
	add_child(clan_panel)

	clan_title = Label.new()
	clan_title.position = Vector2(20, 14)
	clan_title.size = Vector2(480, 28)
	clan_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(clan_title, 20)
	clan_panel.add_child(clan_title)

	var div = ColorRect.new()
	div.color = UITheme.GOLD_DIM
	div.position = Vector2(24, 48)
	div.size = Vector2(472, 1)
	clan_panel.add_child(div)

	clan_info = Label.new()
	clan_info.position = Vector2(24, 58)
	clan_info.size = Vector2(472, 130)
	clan_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	UITheme.style_label(clan_info, 13, UITheme.TEXT_MAIN)
	clan_panel.add_child(clan_info)

	clan_options_box = VBoxContainer.new()
	clan_options_box.position = Vector2(24, 196)
	clan_options_box.size = Vector2(472, 160)
	clan_options_box.add_theme_constant_override("separation", 8)
	clan_panel.add_child(clan_options_box)

	clan_hint = Label.new()
	clan_hint.position = Vector2(24, 368)
	clan_hint.size = Vector2(472, 20)
	clan_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(clan_hint, 12, UITheme.TEXT_DIM)
	clan_panel.add_child(clan_hint)

	var close_btn = Button.new()
	close_btn.text = "离开"
	close_btn.position = Vector2(210, 382)
	close_btn.size = Vector2(100, 30)
	UITheme.style_button(close_btn, 13)
	close_btn.pressed.connect(func(): clan_panel.visible = false)
	clan_panel.add_child(close_btn)

func _on_clan_btn():
	if clan_panel and clan_panel.visible:
		clan_panel.visible = false
		return
	_open_clan_panel()

# P键入口：查看「本派」信息（不受所在地图位置限制，与地盘按钮面板区分）
func _open_my_clan_panel():
	if GameManager.player_clan == null:
		GameManager.emit_event("门派", "你尚未加入任何门派，可前往门派地盘按 J 拜入", 2)
		return
	DialogManager.close_dialog()
	var clan: Clan = GameManager.player_clan
	clan_title.text = "⛩ " + clan.clan_name
	var info = "立场：" + clan.stance + "    势力：" + str(int(clan.power)) + "    弟子：" + str(clan.member_count) + "人\n"
	info += "身份：" + GameManager.CLAN_RANKS[GameManager.player_rank] + "    贡献：" + str(GameManager.contribution) + "\n"
	info += clan.description
	clan_info.text = info
	clan_hint.text = ""
	for child in clan_options_box.get_children():
		child.queue_free()
	_add_clan_option("请安问好（贡献+5）", _on_clan_greet)
	_add_clan_option("切磋赐教（胜负难料）", _on_clan_spar)
	_add_clan_option("背叛师门", _on_clan_betray)
	clan_panel.visible = true
	clan_panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(clan_panel, "modulate:a", 1.0, 0.15)

func _open_clan_panel():
	var env = GameManager.current_environment
	var clan: Clan = GameManager.get_clan(env) if env != "" else null
	if clan == null:
		return
	DialogManager.close_dialog()
	clan_title.text = "⛩ " + clan.clan_name
	var info = "立场：" + clan.stance + "    势力：" + str(int(clan.power)) + "    弟子：" + str(clan.member_count) + "人\n"
	info += "入门要求：声望 ≥ " + str(int(clan.join_condition_reputation)) + "（当前 " + str(int(GameManager.reputation)) + "）\n"
	info += clan.description
	clan_info.text = info
	clan_hint.text = ""
	# 动态生成选项按钮
	for child in clan_options_box.get_children():
		child.queue_free()
	if GameManager.player_clan == clan:
		# 本派弟子
		clan_info.text += "\n\n你是本派「" + GameManager.CLAN_RANKS[GameManager.player_rank] + "」，贡献 " + str(GameManager.contribution)
		_add_clan_option("请安问好（贡献+5）", _on_clan_greet)
		_add_clan_option("切磋赐教（胜负难料）", _on_clan_spar)
		_add_clan_option("背叛师门", _on_clan_betray)
	elif GameManager.player_clan != null:
		# 已投他派
		clan_hint.text = "你已加入「" + GameManager.player_clan.clan_name + "」，不可另投"
		_add_clan_option("切磋赐教（胜负难料）", _on_clan_spar)
	else:
		# 未入门派
		_add_clan_option("拜入门下", _on_clan_join)
		_add_clan_option("切磋赐教（胜负难料）", _on_clan_spar)
	clan_panel.visible = true
	clan_panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(clan_panel, "modulate:a", 1.0, 0.15)

func _add_clan_option(text: String, handler: Callable):
	var btn = Button.new()
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 36)
	UITheme.style_button(btn, 14)
	btn.pressed.connect(handler)
	clan_options_box.add_child(btn)

func _on_clan_join():
	var env = GameManager.current_environment
	if GameManager.join_clan(env):
		clan_panel.visible = false
		DialogManager.show_dialog(env, ["掌门微微颔首：「既入我门，当守我门规。」"])
	else:
		clan_hint.text = "声望不足，掌门婉拒了你"
		UITheme.style_label(clan_hint, 12, UITheme.DANGER)

func _on_clan_greet():
	GameManager.add_contribution(5)
	GameManager.emit_event("门派", "你在" + GameManager.player_clan.clan_name + "请安问好，贡献+5", 1)
	clan_panel.visible = false

func _on_clan_spar():
	var env = GameManager.current_environment
	if randf() < 0.7:
		GameManager.reputation += 2
		GameManager.emit_event("切磋", "你在" + env + "与门中弟子切磋小胜，声望+2", 1)
		clan_hint.text = "切磋小胜！声望+2"
		UITheme.style_label(clan_hint, 12, UITheme.JADE)
	else:
		GameManager.health = max(GameManager.health - 8, 1)
		GameManager.emit_event("切磋", "你在" + env + "切磋落败，受伤-8生命", 1)
		clan_hint.text = "技不如人，落败受伤（生命-8）"
		UITheme.style_label(clan_hint, 12, UITheme.DANGER)

func _on_clan_betray():
	GameManager.betray_clan()
	clan_panel.visible = false

# ---------- 状态与输入 ----------

func is_panel_open() -> bool:
	return (encounter_panel and encounter_panel.visible) or (oath_panel and oath_panel.visible) or (clan_panel and clan_panel.visible)

func _get_encounter_system():
	return get_node_or_null("/root/Main/EncounterSystem")

func _process(_delta):
	# 奇遇触发=最高优先级事件（三国群英传式打断）：强制关闭一切在开UI并立即弹出面板置顶
	var es = _get_encounter_system()
	var active = es != null and es.active_encounter != null
	if active and not _encounter_was_active:
		_force_open_encounter()
	elif not active and _encounter_was_active:
		if encounter_panel.visible and not _showing_result:
			encounter_panel.visible = false
		_stop_encounter_flash()
	_encounter_was_active = active
	# 门派地盘检测：进入门派区域时显示门派按钮并闪烁提示
	var env = GameManager.current_environment
	var clan = GameManager.get_clan(env) if env != "" else null
	var show_clan = clan != null
	if show_clan != _clan_btn_visible:
		_clan_btn_visible = show_clan
		if show_clan:
			clan_btn.text = "⛩ " + env
			clan_btn.visible = true
			_flash_clan_btn()
		else:
			clan_btn.visible = false
			if clan_panel and clan_panel.visible:
				clan_panel.visible = false
			_stop_clan_flash()

# 门派按钮呼吸闪烁（进入门派地盘时提示可交互）
func _flash_clan_btn():
	if clan_btn == null:
		return
	if _clan_flash_tween and _clan_flash_tween.is_valid():
		_clan_flash_tween.kill()
	_clan_flash_tween = create_tween().set_loops(4)
	_clan_flash_tween.tween_property(clan_btn, "modulate:a", 0.3, 0.35)
	_clan_flash_tween.tween_property(clan_btn, "modulate:a", 1.0, 0.35)

func _stop_clan_flash():
	if _clan_flash_tween and _clan_flash_tween.is_valid():
		_clan_flash_tween.kill()
	_clan_flash_tween = null
	if clan_btn:
		clan_btn.modulate.a = 1.0

# 奇遇按钮呼吸闪烁，提示有可处理的奇遇
func _start_encounter_flash():
	if encounter_btn == null:
		return
	encounter_btn.text = "⚡ 奇遇!"
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(encounter_btn, "modulate:a", 0.3, 0.45)
	_flash_tween.tween_property(encounter_btn, "modulate:a", 1.0, 0.45)

func _stop_encounter_flash():
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if encounter_btn:
		encounter_btn.text = "⚡ 奇遇"
		encounter_btn.modulate.a = 1.0

func _input(event):
	if event is InputEventKey and event.pressed:
		if GameManager.is_build_mode:
			return
		var shop_hud = get_node_or_null("/root/Main/World/UI/ShopHUD")
		if shop_hud and shop_hud.is_open:
			return
		# 奇遇面板打开时的数字键
		if encounter_panel and encounter_panel.visible:
			var k = event.keycode
			# 结果视图：回车/空格/ESC/任意数字键均可关闭继续
			if _showing_result:
				if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE or k == KEY_ESCAPE or k == KEY_0 or (k >= KEY_1 and k <= KEY_9):
					_close_result_view()
				return
			if k == KEY_0 or k == KEY_ESCAPE:
				_close_encounter_panel()
				return
			if k >= KEY_1 and k <= KEY_9:
				_on_encounter_option(k - KEY_1)
				return
		# 立誓面板打开时的数字键
		if oath_panel and oath_panel.visible:
			var k = event.keycode
			if k == KEY_ESCAPE:
				oath_panel.visible = false
				return
			if k >= KEY_1 and k <= KEY_5:
				var choices = ["成为天下第一", "富甲一方", "灭掉魔教", "博学多才", "行侠仗义"]
				_on_oath_choice(choices[k - KEY_1])
				return
		# 门派面板 ESC 关闭
		if clan_panel and clan_panel.visible:
			if event.keycode == KEY_ESCAPE:
				clan_panel.visible = false
				return
