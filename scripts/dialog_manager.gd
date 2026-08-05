extends Node

# 对话管理器 - 全局单例，复用同一个DialogBox实例

var dialogue_box: Control = null

func show_dialog(npc_name: String, lines: Array):
	if lines.is_empty():
		return
	print("[Dialog] " + npc_name + ": " + str(lines[0]))
	_ensure_box()
	dialogue_box.show_dialog(npc_name, lines)

func is_dialog_open() -> bool:
	return dialogue_box != null and dialogue_box.visible

func close_dialog():
	if dialogue_box and dialogue_box.visible:
		dialogue_box._finish_dialog()

func _ensure_box():
	if dialogue_box != null and is_instance_valid(dialogue_box):
		return
	var box_scene = load("res://scenes/dialog_box.tscn")
	if box_scene:
		dialogue_box = box_scene.instantiate()
		# 必须挂到 UI CanvasLayer 下：直接挂 root 会脱离画布缩放与层级，
		# 导致对话框错位到右下角、且被世界渲染遮挡
		var ui = get_node_or_null("/root/Main/World/UI")
		if ui:
			ui.add_child(dialogue_box)
		else:
			get_tree().root.add_child(dialogue_box)
