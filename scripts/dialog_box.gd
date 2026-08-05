extends Control

# 对话框 - 底部居中面板，按钮/回车/空格推进，样式统一由UITheme提供

signal dialog_finished

@onready var panel: Panel = $Panel
@onready var name_plate: Panel = $Panel/NamePlate
@onready var name_label: Label = $Panel/NamePlate/CharacterName
@onready var text_label: Label = $Panel/DialogText
@onready var next_button: Button = $Panel/NextButton

var dialog_queue: Array = []
var current_index: int = 0

func _ready():
	visible = false
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	name_plate.add_theme_stylebox_override("panel", UITheme.inset_style())
	UITheme.style_button(next_button, 14)

func show_dialog(character: String, texts: Array):
	if texts.is_empty():
		return
	name_label.text = character
	dialog_queue = texts
	current_index = 0
	visible = true
	# 弹出动画
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	panel.pivot_offset = panel.size / 2
	var tw = create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_current_text()

func _show_current_text():
	text_label.text = dialog_queue[current_index]
	text_label.visible_ratio = 0.0
	var tw = create_tween()
	var dur = clamp(text_label.text.length() * 0.02, 0.15, 0.8)
	tw.tween_property(text_label, "visible_ratio", 1.0, dur)
	next_button.text = "关闭 ✕" if current_index >= dialog_queue.size() - 1 else "继续 ▼"

func _advance():
	if not visible:
		return
	# 打字进行中则直接补全
	if text_label.visible_ratio < 1.0:
		text_label.visible_ratio = 1.0
		return
	current_index += 1
	if current_index >= dialog_queue.size():
		_finish_dialog()
	else:
		_show_current_text()

func _finish_dialog():
	visible = false
	dialog_queue.clear()
	current_index = 0
	dialog_finished.emit()

func _unhandled_input(event):
	if not visible:
		return
	if event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
