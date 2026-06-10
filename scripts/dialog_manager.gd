extends Node

var dialogue_box: Control = null
var current_lines: Array = []
var current_index: int = 0
var current_npc_name: String = ""

func _ready():
	pass

func show_dialog(npc_name: String, lines: Array):
	print("[Dialog] " + npc_name + " 说: " + str(lines))
	current_npc_name = npc_name
	current_lines = lines
	current_index = 0
	_show_current_line()

func _show_current_line():
	if dialogue_box:
		dialogue_box.queue_free()
		dialogue_box = null

	if current_index >= current_lines.size():
		return

	var box_scene = load("res://scenes/dialog_box.tscn")
	if box_scene:
		dialogue_box = box_scene.instantiate()
		get_tree().root.add_child(dialogue_box)

		# Set character name
		var name_node = dialogue_box.get_node_or_null("CharacterName")
		if name_node:
			name_node.text = current_npc_name

		# Set dialog text
		var text_node = dialogue_box.get_node_or_null("DialogText")
		if text_node:
			text_node.text = current_lines[current_index]

		# Connect next button
		var next_btn = dialogue_box.get_node_or_null("NextButton")
		if next_btn:
			if current_index < current_lines.size() - 1:
				next_btn.text = "下一步"
				next_btn.pressed.connect(_next_line)
			else:
				next_btn.text = "关闭"
				next_btn.pressed.connect(_close_dialog)
	else:
		# Fallback to simple panel
		_show_simple_dialog()

func _next_line():
	current_index += 1
	_show_current_line()

func _close_dialog():
	if dialogue_box:
		dialogue_box.queue_free()
		dialogue_box = null
	current_lines.clear()
	current_index = 0
	current_npc_name = ""

func _show_simple_dialog():
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-200, -120)
	panel.size = Vector2(400, 100)
	panel.z_index = 1000

	var label = Label.new()
	label.text = "[" + current_npc_name + "] " + str(current_lines)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(label)

	var timer = Timer.new()
	timer.wait_time = 2.5
	timer.one_shot = true
	timer.timeout.connect(panel.queue_free)
	panel.add_child(timer)
	timer.start()

	dialogue_box = panel
	get_tree().root.add_child(dialogue_box)
