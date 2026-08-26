extends Control

# Phase F7: 游戏化任务日志——页签切换 + 任务卡片 + 真进度条 + 按钮化操作
# 替代旧SurvivalHUD中的ASCII文本日志；数字键/N/F1快捷键保留

var toggle_btn: Button = null
var panel: Panel = null
var tabs: Array = []
var scroll: ScrollContainer = null
var list_box: VBoxContainer = null
var count_lbl: Label = null
var expanded: bool = false
var current_tab: int = 0

const PANEL_W := 330.0
const PANEL_H := 400.0
const TAB_NAMES := ["进行中", "可接取", "已完成"]

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	var gm = get_node_or_null("/root/GameManager")
	if gm != null and gm.world_state_changed != null:
		gm.world_state_changed.connect(refresh)
	refresh()

func _build_ui():
	toggle_btn = Button.new()
	toggle_btn.text = " 任 务 日 志 "
	toggle_btn.position = Vector2(20, 358)
	toggle_btn.size = Vector2(150, 26)
	UITheme.style_button(toggle_btn, 12)
	toggle_btn.add_theme_color_override("font_color", UITheme.GOLD)
	toggle_btn.pressed.connect(toggle_panel)
	add_child(toggle_btn)

	panel = Panel.new()
	panel.name = "QuestPanel"
	panel.position = Vector2(20, 390)
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	add_child(panel)

	var title = Label.new()
	title.text = "· 江 湖 任 务 ·"
	title.position = Vector2(16, 10)
	title.size = Vector2(PANEL_W - 32, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(title, 15)
	panel.add_child(title)

	var tab_x := 16.0
	for i in range(TAB_NAMES.size()):
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.position = Vector2(tab_x, 38)
		b.size = Vector2(94, 26)
		UITheme.style_button(b, 11)
		b.pressed.connect(_switch_tab.bind(i))
		panel.add_child(b)
		tabs.append({"btn": b})
		tab_x += 100.0

	count_lbl = Label.new()
	count_lbl.position = Vector2(16, 68)
	count_lbl.size = Vector2(PANEL_W - 32, 16)
	UITheme.style_label(count_lbl, 10, UITheme.TEXT_DIM)
	panel.add_child(count_lbl)

	scroll = ScrollContainer.new()
	scroll.position = Vector2(14, 88)
	scroll.size = Vector2(PANEL_W - 28, PANEL_H - 118)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(list_box)

	var hint = Label.new()
	hint.text = "[N]刷新  [1-5]快速接取  [F1]放弃首个"
	hint.position = Vector2(16, PANEL_H - 24)
	hint.size = Vector2(PANEL_W - 32, 16)
	UITheme.style_label(hint, 9, UITheme.TEXT_DIM)
	panel.add_child(hint)

func toggle_panel():
	expanded = !expanded
	panel.visible = expanded
	if expanded:
		refresh()

func _switch_tab(idx: int):
	current_tab = idx
	_sfx("ui")
	refresh()

func _qs() -> Node:
	var a = get_node_or_null("/root/Main/QuestSystem")
	if a != null:
		return a
	return get_node_or_null("/root/QuestSystem")

func refresh():
	if panel == null or not panel.visible:
		return
	var qs = _qs()
	if qs == null:
		return
	for i in range(tabs.size()):
		var btn: Button = tabs[i]["btn"]
		btn.add_theme_color_override("font_color", UITheme.GOLD if i == current_tab else UITheme.TEXT_DIM)
	for c in list_box.get_children():
		c.queue_free()
	match current_tab:
		0:
			var tasks: Array = qs.get_active_quests()
			count_lbl.text = "进行中的委托：%d / 5" % tasks.size()
			if tasks.is_empty():
				_empty_hint("暂无进行中的任务\n可在「可接取」页签接取委托")
			for i in range(tasks.size()):
				list_box.add_child(_make_card(tasks[i], 0, i))
		1:
			var avail: Array = qs.get_available_quests()
			count_lbl.text = "告示板上的委托：%d" % avail.size()
			if avail.is_empty():
				_empty_hint("暂无可接取的委托\n按 N 刷新告示板")
			for i in range(min(avail.size(), 8)):
				list_box.add_child(_make_card(avail[i], 1, i))
		2:
			var done: Array = qs.completed_quests
			count_lbl.text = "已完成：%d" % done.size()
			if done.is_empty():
				_empty_hint("尚未完成任何委托")
			for i in range(done.size()):
				list_box.add_child(_make_card(done[i], 2, i))

func _empty_hint(text: String):
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 60, 40)
	UITheme.style_label(l, 11, UITheme.TEXT_DIM)
	list_box.add_child(l)

const CAT_COLORS := {
	"除恶": Color(0.95, 0.45, 0.35), "护送": Color(0.55, 0.8, 0.95),
	"寻宝": Color(1.0, 0.85, 0.4), "讨伐": Color(0.95, 0.6, 0.3),
	"比武": Color(0.65, 0.75, 1.0), "暗杀": Color(0.7, 0.5, 0.9),
	"采药": Color(0.5, 0.9, 0.55), "传功": Color(0.9, 0.75, 0.5),
}

func _make_card(q: Object, mode: int, index: int) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.inset_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	var cat := Label.new()
	cat.text = "【%s】" % q.category
	cat.add_theme_font_size_override("font_size", 10)
	cat.add_theme_color_override("font_color", CAT_COLORS.get(q.category, UITheme.GOLD_DIM))
	head.add_child(cat)
	var ttl := Label.new()
	ttl.text = (str(index + 1) + ". " + q.title) if mode == 1 else q.title
	ttl.add_theme_font_size_override("font_size", 12)
	ttl.add_theme_color_override("font_color", UITheme.TEXT_MAIN)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ttl.clip_text = true
	head.add_child(ttl)
	var stars := Label.new()
	for s in range(3):
		stars.text += "★" if s < int(q.difficulty) else "☆"
	stars.add_theme_font_size_override("font_size", 10)
	stars.add_theme_color_override("font_color", UITheme.GOLD)
	head.add_child(stars)

	if q.description != "":
		var desc := Label.new()
		desc.text = q.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(PANEL_W - 70, 0)
		desc.add_theme_font_size_override("font_size", 9)
		desc.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		v.add_child(desc)

	if mode == 0:
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 6)
		v.add_child(prow)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = maxf(1.0, float(q.target_count))
		bar.value = float(q.current_count)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(180, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg_sb := StyleBoxFlat.new()
		bg_sb.bg_color = Color(0.09, 0.09, 0.12, 0.95)
		bg_sb.set_corner_radius_all(3)
		bg_sb.border_color = Color(0.25, 0.22, 0.15)
		bg_sb.set_border_width_all(1)
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = UITheme.JADE
		fill_sb.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg_sb)
		bar.add_theme_stylebox_override("fill", fill_sb)
		prow.add_child(bar)
		var pv := Label.new()
		pv.text = "%d/%d" % [q.current_count, q.target_count]
		pv.add_theme_font_size_override("font_size", 10)
		pv.add_theme_color_override("font_color", UITheme.JADE)
		prow.add_child(pv)
	elif mode == 2:
		var done_l := Label.new()
		done_l.text = "✓ 已完成"
		done_l.add_theme_font_size_override("font_size", 10)
		done_l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		v.add_child(done_l)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	v.add_child(foot)
	var reward := Label.new()
	reward.text = "银两+%d  声望%+d  道德%+d" % [q.reward_gold, q.reward_reputation, q.reward_morality]
	reward.add_theme_font_size_override("font_size", 9)
	reward.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(reward)
	if mode == 0:
		var ab := Button.new()
		ab.text = "放弃"
		ab.custom_minimum_size = Vector2(52, 20)
		UITheme.style_button(ab, 9)
		ab.pressed.connect(_on_abandon.bind(q.quest_id))
		foot.add_child(ab)
	elif mode == 1:
		var ac := Button.new()
		ac.text = "接 取"
		ac.custom_minimum_size = Vector2(56, 20)
		UITheme.style_button(ac, 10)
		ac.add_theme_color_override("font_color", UITheme.GOLD)
		ac.pressed.connect(_on_accept.bind(index))
		foot.add_child(ac)
	return card

func _on_accept(index: int):
	var qs = _qs()
	if qs:
		qs.accept_quest(index)
		_sfx("craft_ok")
		refresh()

func _on_abandon(qid: String):
	var qs = _qs()
	if qs:
		qs.abandon_quest(qid)
		_sfx("craft_fail")
		refresh()

func _sfx(n: String):
	var ac = get_node_or_null("/root/Main/World/AudioController")
	if ac and ac.has_method("play_sfx"):
		ac.play_sfx(n, -12.0)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and expanded:
		toggle_panel()
		get_viewport().set_input_as_handled()

func _input(event):
	if not expanded or not (event is InputEventKey and event.pressed):
		return
	if GameManager.is_build_mode or DialogManager.is_dialog_open():
		return
	var quick_menu = get_node_or_null("/root/Main/World/UI/QuickMenu")
	if quick_menu and quick_menu.is_panel_open():
		return
	var shop_hud = get_node_or_null("/root/Main/World/UI/ShopHUD")
	if shop_hud and shop_hud.is_open:
		return
	var qs = _qs()
	if qs == null:
		return
	if event.keycode == KEY_N:
		qs.refresh_available_quests()
		refresh()
	elif event.keycode == KEY_F1:
		var tasks = qs.get_active_quests()
		if tasks.size() > 0:
			qs.abandon_quest(tasks[0].quest_id)
			refresh()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		qs.accept_quest(event.keycode - KEY_1)
		refresh()
