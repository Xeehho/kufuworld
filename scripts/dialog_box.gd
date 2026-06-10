extends Control

signal dialog_finished

@onready var character_name_label: Label = $CharacterName
@onready var dialog_text_label: Label = $DialogText
@onready var next_button: Button = $NextButton
@onready var portrait: TextureRect = $Portrait

var dialog_queue: Array = []
var current_index: int = 0

func _ready():
	next_button.pressed.connect(_on_next_button_pressed)
	visible = false

func show_dialog(character: String, texts: Array):
	character_name_label.text = character
	dialog_queue = texts
	current_index = 0
	visible = true
	_show_current_text()

func _show_current_text():
	if current_index < dialog_queue.size():
		dialog_text_label.text = dialog_queue[current_index]
	else:
		_finish_dialog()

func _on_next_button_pressed():
	current_index += 1
	_show_current_text()

func _finish_dialog():
	visible = false
	dialog_queue.clear()
	dialog_finished.emit()
