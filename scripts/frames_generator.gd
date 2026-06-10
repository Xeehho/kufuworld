@tool
extends Node

func _ready():
	_generate_frames()
	if not Engine.is_editor_hint():
		get_tree().quit()

func _generate_frames():
	var sf = SpriteFrames.new()

	sf.add_animation("idle")
	sf.set_animation_speed("idle", 4.0)
	sf.set_animation_loop("idle", true)
	for i in range(4):
		var tex = load("res://sprites/player/idle_" + str(i) + ".png")
		sf.add_frame("idle", tex)

	sf.add_animation("walk")
	sf.set_animation_speed("walk", 8.0)
	sf.set_animation_loop("walk", true)
	for i in range(6):
		var tex = load("res://sprites/player/walk_" + str(i) + ".png")
		sf.add_frame("walk", tex)

	ResourceSaver.save(sf, "res://sprites/player/player_frames.tres")
	print("[FramesGen] SpriteFrames saved")
