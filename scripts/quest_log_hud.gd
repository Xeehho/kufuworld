extends Control

var quest_lines: Array = []
var section_quests: Label = null
var section_active: Label = null
var is_visible: bool = true

func _ready():
	position = Vector2(1640, 140)
	_create_panel()
	print("[QuestLog] HUD ready")

func _create_panel():
	var panel = Panel.new()
	panel.size = Vector2(240, 280)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.88)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var title = Label.new()
	title.text = "  任务日志"
	title.position = Vector2(4, 2)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	add_child(title)

	section_active = Label.new()
	section_active.position = Vector2(6, 22)
	section_active.add_theme_font_size_override("font_size", 10)
	section_active.add_theme_color_override("font_color", Color(1, 1, 1))
	add_child(section_active)

	section_quests = Label.new()
	section_quests.position = Vector2(6, 130)
	section_quests.add_theme_font_size_override("font_size", 10)
	section_quests.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
	add_child(section_quests)

func _process(_delta):
	_update_display()

func _update_display():
	var qs = get_node_or_null("/root/Main/QuestSystem")
	if qs == null:
		return

	var t = "=== 进行中的任务 ===\n"
	var tasks = qs.get_active_quests()
	if tasks.size() == 0:
		t += "  (暂无)\n"
	else:
		for i in range(tasks.size()):
			var q = tasks[i]
			var bar = _progress_bar(q.completion_ratio())
			t += "[" + str(i+1) + "] " + q.title + "\n"
			t += "    " + bar + " " + str(q.current_count) + "/" + str(q.target_count) + "\n"
	section_active.text = t

	var t2 = "=== 可接任务 ===\n"
	var avail = qs.get_available_quests()
	if avail.size() == 0:
		t2 += "  (暂无新任务)\n"
	else:
		for i in range(min(avail.size(), 5)):
			var q = avail[i]
			var stars = ""
			for _s in range(q.difficulty):
				stars += "*"
			t2 += "[" + str(i+1) + "] " + q.title + " " + stars + " " + str(q.reward_gold) + "金\n"
	t2 += "\n[N]刷新  [1-5]接任务  [F1]放弃"
	section_quests.text = t2

func _input(event):
	if event is InputEventKey and event.pressed:
		# 当建造模式或商店开启时，不处理任务按键，避免冲突
		if GameManager.is_build_mode:
			return
		var shop_hud = get_node_or_null("/root/Main/ShopHUD")
		if shop_hud and shop_hud.is_open:
			return
		var qs = get_node_or_null("/root/Main/QuestSystem")
		if qs == null:
			return
		if event.keycode == KEY_N:
			qs.refresh_available_quests()
			return
		if event.keycode == KEY_F1:
			var tasks = qs.get_active_quests()
			if tasks.size() > 0:
				qs.abandon_quest(tasks[0].quest_id)
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx = event.keycode - KEY_1
			qs.accept_quest(idx)
			return

func _progress_bar(ratio: float) -> String:
	var w = 10
	var filled = int(ratio * w)
	var s = "["
	for i in range(w):
		if i < filled:
			s += "="
		else:
			s += "-"
	s += "]"
	return s
