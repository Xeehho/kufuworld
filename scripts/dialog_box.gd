extends Control

# 对话框 - 底部居中面板，按钮/回车/空格推进，样式统一由UITheme提供
# v2 分支对话：条目支持 Dictionary 格式 {"text","speaker"?,"options"?: [...]}
#   option = {"text", "result"?, 以及任意效果键(morality/reputation/.../create_oath) 由上层处理}
# 规则：含 options 的条目必须选择（数字键1-9或点击）才能结束；选择后有 result 文本则追加为收尾页

signal dialog_finished
signal option_chosen(opt: Dictionary)

@onready var panel: Panel = $Panel
@onready var name_plate: Panel = $Panel/NamePlate
@onready var name_label: Label = $Panel/NamePlate/CharacterName
@onready var text_label: Label = $Panel/DialogText
@onready var next_button: Button = $Panel/NextButton

var dialog_queue: Array = []
var current_index: int = 0
var base_speaker: String = ""
var last_meta: String = ""           # 本次对话的元标记（调用方区分剧情段）
var last_close_user_driven := true   # false=被外部强关(奇遇打断/close_dialog)，非玩家读完
var current_options: Array = []      # 当前待选分支（空=线性模式）
var options_box: VBoxContainer = null
var typing_tween: Tween = null
var _options_shown_for: int = -1     # 防重：当前页已展示过选项
var suspended := false               # 被外部强关挂起：保留队列/页码现场，可 resume_dialog() 原地续播
                                     # （修复：剧情对话被奇遇等强关后从头重播→WASD教学页出现两次）
# teach_move 教学页：页内解锁玩家移动，四方向全按过自动翻下一句
const MOVE_TEACH_ACTIONS := ["ui_left", "ui_right", "ui_up", "ui_down"]
var move_teach_active := false
var move_pressed_set := {}

func _ready():
	visible = false
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	name_plate.add_theme_stylebox_override("panel", UITheme.inset_style())
	UITheme.style_button(next_button, 14)
	# BugFix(H2)：NextButton从未接线——tscn里没有[connection]，此处也没connect，
	# 底部对话框"继续▼/关闭✕"点击无效（只有回车/空格能用），奇遇等所有底部提示均受影响
	next_button.pressed.connect(_advance)
	# 点击面板任意处也可推进/关闭（RPG惯例）
	panel.gui_input.connect(_on_panel_gui_input)
	# 分支选项容器（运行时构建，占位在正文下方区域）
	options_box = VBoxContainer.new()
	options_box.position = Vector2(24, 150)
	options_box.size = Vector2(752, 62)
	options_box.add_theme_constant_override("separation", 4)
	options_box.visible = false
	panel.add_child(options_box)

func _on_panel_gui_input(event: InputEvent):
	if current_options.size() > 0:
		return   # 分支未决：点面板空白不推进，必须按选项按钮
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()

func show_dialog(character: String, texts: Array, meta: String = ""):
	if texts.is_empty():
		return
	suspended = false   # 新对话使旧挂起现场失效
	base_speaker = character
	last_meta = meta
	dialog_queue = texts
	current_index = 0
	current_options = []
	move_teach_active = false
	move_pressed_set.clear()
	DialogManager.set_move_teach(false)
	visible = true
	# 弹出动画
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	panel.pivot_offset = panel.size / 2
	var tw = create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_current_text()

func _entry_text(entry) -> String:
	return entry["text"] if entry is Dictionary else str(entry)

func _entry_options(entry) -> Array:
	if entry is Dictionary and entry.has("options"):
		return entry["options"]
	return []

func _show_current_text():
	var entry = dialog_queue[current_index]
	text_label.text = _entry_text(entry)
	name_label.text = base_speaker
	if entry is Dictionary and entry.has("speaker"):
		name_label.text = str(entry["speaker"])
	current_options = []
	options_box.visible = false
	_options_shown_for = -1
	# 翻页即收回教学移动特许（若新条目仍带 teach_move，打字完成后由_after_typing重新授予）
	move_teach_active = false
	move_pressed_set.clear()
	DialogManager.set_move_teach(false)
	text_label.visible_ratio = 0.0
	if typing_tween and typing_tween.is_valid():
		typing_tween.kill()
	typing_tween = create_tween()
	var dur = clamp(text_label.text.length() * 0.02, 0.15, 0.8)
	typing_tween.tween_property(text_label, "visible_ratio", 1.0, dur)
	typing_tween.tween_callback(_after_typing)

func _after_typing():
	if not visible or suspended:
		return
	if _options_shown_for == current_index:
		return
	var opts = _entry_options(dialog_queue[current_index])
	if not opts.is_empty():
		_present_options(opts)
		return
	next_button.text = "关闭 ✕" if current_index >= dialog_queue.size() - 1 else "继续 ▼"
	next_button.visible = true
	_fit_next_button(next_button.text)
	# WASD教学页：解锁玩家移动，四方向全按过→自动翻页
	var entry = dialog_queue[current_index]
	move_teach_active = entry is Dictionary and bool(entry.get("teach_move", false))
	move_pressed_set.clear()
	DialogManager.set_move_teach(move_teach_active)
	if move_teach_active:
		next_button.text = "按 WASD 四方走动试试 ▼"
		_fit_next_button(next_button.text)

# BugFix: 动态替换的按钮文本（如WASD教学提示）超长会穿出固定112px按钮 → 按文本自适应向左扩展
func _fit_next_button(txt: String):
	var need := 40.0 + txt.length() * 14.0
	var w := clampf(need, 112.0, 240.0)
	next_button.position.x = 776.0 - w
	next_button.size.x = w

func _process(_delta):
	# 教学页监听四方向：全按过一次即自动推进（模拟完成"走动"练习）
	if not move_teach_active or not visible:
		return
	for a in MOVE_TEACH_ACTIONS:
		if not move_pressed_set.has(a) and Input.is_action_pressed(a):
			move_pressed_set[a] = true
			print("[Dialog] 教学移动: %s (%d/4)" % [a, move_pressed_set.size()])
	if move_pressed_set.size() >= MOVE_TEACH_ACTIONS.size():
		move_teach_active = false
		DialogManager.set_move_teach(false)
		_advance()

func _present_options(opts: Array):
	_options_shown_for = current_index
	current_options = opts.duplicate(true)
	for c in options_box.get_children():
		c.queue_free()
	for i in range(current_options.size()):
		var b := Button.new()
		b.text = "%d．%s" % [i + 1, str(current_options[i].get("text", "…"))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UITheme.style_button(b, 14)
		b.custom_minimum_size.y = 26
		b.pressed.connect(_select_option.bind(i))
		options_box.add_child(b)
	next_button.visible = false
	options_box.visible = true

func _select_option(idx: int):
	if not visible or idx < 0 or idx >= current_options.size():
		return
	var opt: Dictionary = current_options[idx]
	print("[Dialog] 选择: %s (meta=%s)" % [opt.get("text", ""), last_meta])
	option_chosen.emit(opt)
	current_options = []
	for c in options_box.get_children():
		c.queue_free()
	options_box.visible = false
	next_button.visible = true
	_fit_next_button(next_button.text)
	var result_text := str(opt.get("result", ""))
	if result_text != "":
		name_label.text = base_speaker
		# 追加结果句并推进到它（作为收尾线性页）
		dialog_queue.append(result_text)
		current_index += 1
		_show_current_text()
	else:
		_advance()

func _advance():
	if not visible:
		return
	# 打字进行中则直接补全并进入选项判定
	if text_label.visible_ratio < 1.0:
		if typing_tween and typing_tween.is_valid():
			typing_tween.kill()
		text_label.visible_ratio = 1.0
		_after_typing()
		return
	var has_opts = not _entry_options(dialog_queue[current_index]).is_empty()
	if has_opts:
		# 必选分支：不允许跳过（补全路径保险）
		_present_options(_entry_options(dialog_queue[current_index]))
		return
	current_index += 1
	if current_index >= dialog_queue.size():
		_finish_dialog()
	else:
		_show_current_text()

func _finish_dialog(user_driven: bool = true):
	suspended = false
	last_close_user_driven = user_driven
	visible = false
	dialog_queue.clear()
	current_index = 0
	current_options = []
	options_box.visible = false
	move_teach_active = false
	move_pressed_set.clear()
	DialogManager.set_move_teach(false)
	dialog_finished.emit()

# ---- 挂起/恢复：外部强关时保留现场，续播不再从头重放（WASD教学页双显根因）----
func suspend_dialog():
	"""外部强关（奇遇置顶/面板互斥）：挂起当前页现场并隐藏。
	仍发出 dialog_finished(false)，调用方据此登记待恢复。"""
	if not visible:
		return
	if typing_tween and typing_tween.is_valid():
		typing_tween.kill()
	suspended = true
	last_close_user_driven = false
	visible = false
	current_options = []
	options_box.visible = false
	move_teach_active = false
	move_pressed_set.clear()
	DialogManager.set_move_teach(false)
	dialog_finished.emit()

func resume_dialog() -> bool:
	"""原地续播挂起的对话（从挂起页继续，选项页会重新展示）。无现场返回false。"""
	if not suspended or dialog_queue.is_empty():
		return false
	if current_index >= dialog_queue.size():
		return false
	suspended = false
	visible = true
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	panel.pivot_offset = panel.size / 2
	var tw = create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_current_text()
	return true

func get_last_meta() -> String:
	return last_meta

func _unhandled_input(event):
	if not visible:
		return
	# 分支进行中：数字键选择；其余输入吞掉防误推进
	if current_options.size() > 0:
		if event is InputEventKey and event.pressed and not event.echo:
			var code: int = event.keycode
			if code >= KEY_1 and code <= KEY_9:
				var idx := code - KEY_1
				if idx < current_options.size():
					_select_option(idx)
					get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
