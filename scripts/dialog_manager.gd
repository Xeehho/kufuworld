extends Node

# 对话管理器 - 全局单例，复用同一个DialogBox实例
# v2：转发分支选项选择；对话结束时带调用方 meta 回传（主线节点判定用）

signal option_chosen(opt: Dictionary)
signal dialog_by_meta_finished(meta: String, user_driven: bool)

var dialogue_box: Control = null
var move_teach_unlocked := false   # 石伯WASD教学页：特许玩家自由试走（仅移动，非战斗）

func set_move_teach(v: bool):
	move_teach_unlocked = v

func is_move_teach_open() -> bool:
	return dialogue_box != null and dialogue_box.visible and move_teach_unlocked

func show_dialog(npc_name: String, lines: Array, meta: String = ""):
	if lines.is_empty():
		return
	print("[Dialog] " + npc_name + ": " + str(lines[0]))
	_ensure_box()
	dialogue_box.show_dialog(npc_name, lines, meta)

func is_dialog_open() -> bool:
	return dialogue_box != null and dialogue_box.visible

func close_dialog():
	# 外部强关（奇遇置顶/面板互斥等）：优先挂起现场（可原地续播，防止剧情对话从头重放），
	# 并标记非用户读完，主线可据此恢复/重开
	if dialogue_box and dialogue_box.visible:
		print("[Dialog] 外部挂起对话 (meta=%s)" % str(dialogue_box.last_meta))
		dialogue_box.suspend_dialog()

func resume_dialog() -> bool:
	# 原地续播挂起的对话；无挂起现场返回false（调用方自行兜底重播）
	if dialogue_box == null or not is_instance_valid(dialogue_box):
		return false
	return dialogue_box.resume_dialog()

func _ensure_box():
	if dialogue_box != null and is_instance_valid(dialogue_box):
		return
	var box_scene = load("res://scenes/dialog_box.tscn")
	if box_scene:
		dialogue_box = box_scene.instantiate()
		# 转发信号（懒加载实例不固定，外部只连 DialogManager）
		dialogue_box.option_chosen.connect(func(opt): option_chosen.emit(opt))
		dialogue_box.dialog_finished.connect(func():
			dialog_by_meta_finished.emit(str(dialogue_box.last_meta),
				bool(dialogue_box.last_close_user_driven)))
		# 必须挂到 UI CanvasLayer 下：直接挂 root 会脱离画布缩放与层级，
		# 导致对话框错位到右下角、且被世界渲染遮挡
		var ui = get_node_or_null("/root/Main/World/UI")
		if ui:
			ui.add_child(dialogue_box)
		else:
			get_tree().root.add_child(dialogue_box)
