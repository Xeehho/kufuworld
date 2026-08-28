extends Control

# Phase H: 任务追踪器——左轨常驻目标栏（对标巫师3/原神/Skyrim objective tracker）
# 实时显示追踪中任务的进度，无需打开任务日志；点击卡片=打开日志，点标题=折叠
# 放左侧理由：右上被EventHUD(江湖风云)+NPCInfoHUD占据；左轨统一"自身状态+自身目标"

var header_btn: Button = null
var list_box: VBoxContainer = null
var collapsed := false
var cards: Dictionary = {}          # quest_id -> {panel, title, bar, cnt}
var poll_t := 0.0

const TRACK_W := 236.0
const CARD_H := 38.0
const CARD_SEP := 5
const MAX_SHOW := 3
const HEADER_Y := 238.0   # BugFix: 210会压住SurvivalHUD手持chip(y202-224)，下移让出

func _ready():
	# AGENTS规范：全屏根节点 set_anchors_and_offsets_preset + mouse_filter IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_btn = Button.new()
	header_btn.name = "TrackerHeader"
	header_btn.text = "◆ 任 务 追 踪 ▾"
	header_btn.position = Vector2(14, HEADER_Y)
	header_btn.size = Vector2(TRACK_W, 22)
	UITheme.style_button(header_btn, 11)
	header_btn.add_theme_color_override("font_color", UITheme.JADE)
	header_btn.pressed.connect(_toggle_collapse)
	add_child(header_btn)

	list_box = VBoxContainer.new()
	list_box.name = "TrackerList"
	list_box.position = Vector2(14, HEADER_Y + 28)
	list_box.add_theme_constant_override("separation", CARD_SEP)
	add_child(list_box)

	var gm = get_node_or_null("/root/GameManager")
	if gm != null and gm.world_state_changed != null:
		gm.world_state_changed.connect(refresh)
	refresh()

func _toggle_collapse():
	collapsed = not collapsed
	header_btn.text = "◆ 任 务 追 踪 ▸" if collapsed else "◆ 任 务 追 踪 ▾"
	_sfx("ui")
	refresh()

func _process(delta):
	# 目标进度不经信号广播（progress_quest只改内存），0.25s轻轮询保证进度条实时
	poll_t += delta
	if poll_t >= 0.25:
		poll_t = 0.0
		refresh()

func _qs() -> Node:
	var a = get_node_or_null("/root/Main/QuestSystem")
	if a != null:
		return a
	return get_node_or_null("/root/QuestSystem")

func _tracked_quests() -> Array:
	"""钉选优先、其余按接取序补位；空pinned时自动展示前3个进行中任务"""
	var qs = _qs()
	if qs == null:
		return []
	var active: Array = qs.get_active_quests()
	if active.is_empty():
		return []
	var pinned: Array = []
	var rest: Array = []
	for q in active:
		if qs.pinned_ids.has(q.quest_id):
			pinned.append(q)
		else:
			rest.append(q)
	return (pinned + rest).slice(0, MAX_SHOW)

func _still_tracked(tracked: Array, qid: String) -> bool:
	for q in tracked:
		if q.quest_id == qid:
			return true
	return false

func refresh():
	if list_box == null or header_btn == null:
		return
	var tracked = _tracked_quests()
	for qid in cards.keys():
		if not _still_tracked(tracked, qid):
			cards[qid]["panel"].queue_free()
			cards.erase(qid)
	for i in range(tracked.size()):
		var q = tracked[i]
		var entry = cards.get(q.quest_id)
		if entry == null:
			entry = _make_card()
			cards[q.quest_id] = entry
			list_box.add_child(entry["panel"])
		entry["title"].text = "【%s】%s" % [q.category, q.title]
		entry["bar"].max_value = maxf(1.0, float(q.target_count))
		entry["bar"].value = float(q.current_count)
		entry["cnt"].text = "%d/%d" % [q.current_count, q.target_count]
	var has := tracked.size() > 0
	header_btn.visible = has
	list_box.visible = has and not collapsed

func _make_card() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(TRACK_W, CARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP	# 悬停不误触攻击；点击开日志
	panel.add_theme_stylebox_override("panel", UITheme.inset_style())
	panel.gui_input.connect(_on_card_gui_input.bind(panel))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(h)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", UITheme.TEXT_MAIN)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(title)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(52, 8)
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
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)

	var cnt := Label.new()
	cnt.add_theme_font_size_override("font_size", 10)
	cnt.add_theme_color_override("font_color", UITheme.JADE)
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cnt)

	return {"panel": panel, "title": title, "bar": bar, "cnt": cnt}

func _on_card_gui_input(event: InputEvent, _panel: Control):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ql = get_node_or_null("/root/Main/World/UI/QuestLogHUD")
		if ql and not ql.expanded:
			ql.toggle_panel()

func _sfx(n: String):
	var ac = get_node_or_null("/root/Main/World/AudioController")
	if ac and ac.has_method("play_sfx"):
		ac.play_sfx(n, -12.0)
