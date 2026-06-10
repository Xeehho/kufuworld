extends Control

var panel: Control = null
var btn_e: Button = null
var btn_o: Button = null
var is_visible: bool = false

func _ready():
	position = Vector2(860, 10)
	_create_buttons()

func _create_buttons():
	btn_e = Button.new()
	btn_e.text = "奇遇"
	btn_e.size = Vector2(60, 28)
	btn_e.position = Vector2(0, 0)
	btn_e.pressed.connect(_on_encounter)
	add_child(btn_e)

	btn_o = Button.new()
	btn_o.text = "立誓"
	btn_o.size = Vector2(60, 28)
	btn_o.position = Vector2(65, 0)
	btn_o.pressed.connect(_on_oath)
	add_child(btn_o)

func _on_encounter():
	var es = get_node_or_null("/root/Main/EncounterSystem")
	if es == null or es.active_encounter == null:
		DialogManager.show_dialog("奇遇", ["暂无奇遇事件触发..."])
		return
	_show_encounter_dialog(es)

func _show_encounter_dialog(es: Node):
	var enc = es.active_encounter
	var lines: Array = [enc.title, enc.description]
	for i in range(enc.options.size()):
		var opt = enc.options[i]
		lines.append("[" + str(i+1) + "] " + opt.text)
	lines.append("按1-" + str(enc.options.size()) + "选择，按0忽略")
	DialogManager.show_dialog(enc.title, lines)

func _on_oath():
	_show_oath_menu()

func _show_oath_menu():
	var os = get_node_or_null("/root/Main/OathSystem")
	if os == null:
		return
	var oaths = os.get_oaths()
	var lines: Array = ["=== 立誓 ==="]
	var choices = ["1.成为天下第一", "2.富甲一方", "3.灭掉魔教", "4.博学多才", "5.行侠仗义", "6.自定义目标"]
	for ch in choices:
		lines.append(ch)
	lines.append("按1-6选择")

	if oaths.size() > 0:
		lines.append("")
		lines.append("=== 当前誓言 ===")
		for i in range(oaths.size()):
			var o = oaths[i]
			var status = "✅" if o["is_fulfilled"] else "⏳"
			lines.append(status + " " + o["title"] + " " + str(int(o["progress"]*100)) + "%")
			for m in o["milestones"]:
				var check = "✓" if o["completed_milestones"].has(m) else "○"
				lines.append("  " + check + " " + m)

	DialogManager.show_dialog("立誓", lines)

func _input(event):
	if event is InputEventKey and event.pressed:
		if not is_visible:
			return
		# 当建造模式或商店开启时，不处理按键，避免冲突
		if GameManager.is_build_mode:
			return
		var shop_hud = get_node_or_null("/root/Main/ShopHUD")
		if shop_hud and shop_hud.is_open:
			return
		var es = get_node_or_null("/root/Main/EncounterSystem")
		if es != null and es.active_encounter != null:
			var k = event.keycode
			if k >= KEY_0 and k <= KEY_9:
				var idx = k - KEY_0 - 1
				if idx < 0:
					es.active_encounter = null
					return
				es.resolve_encounter(idx)
				return
		var os = get_node_or_null("/root/Main/OathSystem")
		if os != null:
			var k = event.keycode
			if k >= KEY_1 and k <= KEY_6:
				var choices = ["成为天下第一", "富甲一方", "灭掉魔教", "博学多才", "行侠仗义", "自定义"]
				os.create_oath(choices[k - KEY_1])
