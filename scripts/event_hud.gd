extends Control

# 江湖信息HUD - 右上角醒目展示世界事件

var event_labels: Array = []
var max_visible: int = 5
var bg_panel: Panel = null
var title_label: Label = null

func _ready():
	# 锚定到右上角
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = 0  # GROW_DIRECTION_LEFT
	offset_left = -270
	offset_right = -10
	offset_top = 52  # 顶部让出快捷菜单位置
	_create_bg()
	GameManager.world_event.connect(_on_world_event)

func _create_bg():
	# 标题栏
	title_label = Label.new()
	title_label.text = "  江湖风云  "
	title_label.position = Vector2(0, 0)
	title_label.size = Vector2(260, 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1, 0.88, 0.3))
	add_child(title_label)

	# 标题背景
	var title_bg = Panel.new()
	title_bg.position = Vector2(0, 0)
	title_bg.size = Vector2(260, 28)
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = Color(0.12, 0.08, 0.04, 0.92)
	title_style.border_color = Color(0.6, 0.5, 0.2, 0.7)
	title_style.border_width_bottom = 2
	title_style.border_width_top = 2
	title_style.border_width_left = 2
	title_style.border_width_right = 2
	title_style.corner_radius_top_left = 6
	title_style.corner_radius_top_right = 6
	title_style.corner_radius_bottom_left = 0
	title_style.corner_radius_bottom_right = 0
	title_bg.add_theme_stylebox_override("panel", title_style)
	add_child(title_bg)
	move_child(title_bg, 0)

	# 内容背景
	bg_panel = Panel.new()
	bg_panel.position = Vector2(0, 28)
	bg_panel.size = Vector2(260, 0)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.05, 0.03, 0.88)
	bg_style.border_color = Color(0.5, 0.42, 0.18, 0.5)
	bg_style.border_width_bottom = 2
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)
	move_child(bg_panel, 1)

func _on_world_event(title: String, body: String, importance: int):
	# 事件标签（单行省略，防止长文溢出）
	var lbl = Label.new()
	var prefix = _importance_icon(importance)
	lbl.text = prefix + " " + title
	lbl.position = Vector2(8, 28 + event_labels.size() * 30 + 4)
	lbl.size = Vector2(244, 16)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	# 根据重要度设置颜色
	var c = Color(0.85, 0.85, 0.85)
	if importance >= 6:
		c = Color(1, 0.25, 0.25)
	elif importance >= 4:
		c = Color(1, 0.82, 0.2)
	elif importance >= 2:
		c = Color(0.6, 0.85, 1)
	lbl.add_theme_color_override("font_color", c)
	add_child(lbl)

	# 事件描述（第二行，单行省略）
	var desc = Label.new()
	desc.text = "   " + body
	desc.position = Vector2(8, 28 + event_labels.size() * 30 + 20)
	desc.size = Vector2(244, 14)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.tooltip_text = title + "\n" + body
	add_child(desc)

	event_labels.append({"title": lbl, "desc": desc})

	# 超出数量移除最旧的
	while event_labels.size() > max_visible:
		var old = event_labels.pop_front()
		old["title"].queue_free()
		old["desc"].queue_free()

	# 重新排列
	_relayout()

	# 淡出计时器
	var timer = get_node_or_null("FadeTimer")
	if timer == null:
		timer = Timer.new()
		timer.name = "FadeTimer"
		timer.wait_time = 8.0
		timer.one_shot = true
		timer.timeout.connect(_fade_oldest)
		add_child(timer)
	# 无论新建还是复用都要重新计时
	timer.start()

func _relayout():
	for i in range(event_labels.size()):
		var entry = event_labels[i]
		entry["title"].position.y = 28 + i * 30 + 4
		entry["desc"].position.y = 28 + i * 30 + 20
		# 越旧越透明
		var alpha = 1.0 - (event_labels.size() - 1 - i) * 0.15
		entry["title"].modulate.a = alpha
		entry["desc"].modulate.a = alpha * 0.85
	# 更新背景高度
	var content_h = max(event_labels.size() * 30, 0)
	bg_panel.size.y = content_h + 8

func _fade_oldest():
	if event_labels.size() > 0:
		var old = event_labels.pop_front()
		old["title"].queue_free()
		old["desc"].queue_free()
		_relayout()

func _importance_icon(importance: int) -> String:
	if importance >= 6:
		return "!!"
	elif importance >= 4:
		return "!"
	else:
		return ">"
