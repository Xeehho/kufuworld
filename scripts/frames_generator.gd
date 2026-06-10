@tool
extends Node

func _ready():
	_generate_frames()
	if not Engine.is_editor_hint():
		get_tree().quit()

func _generate_frames():
	var sf = SpriteFrames.new()
	var dir_names = ["down", "left", "right", "up"]

	# 待机动画 - 4方向
	for dir_name in dir_names:
		var anim_name = "idle_" + dir_name
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 4.0)
		sf.set_animation_loop(anim_name, true)
		for i in range(4):
			var tex = load("res://sprites/player/idle_%s_%d.png" % [dir_name, i])
			if tex:
				sf.add_frame(anim_name, tex)

	# 行走动画 - 4方向
	for dir_name in dir_names:
		var anim_name = "walk_" + dir_name
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 8.0)
		sf.set_animation_loop(anim_name, true)
		for i in range(6):
			var tex = load("res://sprites/player/walk_%s_%d.png" % [dir_name, i])
			if tex:
				sf.add_frame(anim_name, tex)

	# 攻击动画 - 4方向
	for dir_name in dir_names:
		var anim_name = "attack_" + dir_name
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 10.0)
		sf.set_animation_loop(anim_name, false)
		for i in range(4):
			var tex = load("res://sprites/player/attack_%s_%d.png" % [dir_name, i])
			if tex:
				sf.add_frame(anim_name, tex)

	# 格挡动画 - 4方向
	for dir_name in dir_names:
		var anim_name = "block_" + dir_name
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 5.0)
		sf.set_animation_loop(anim_name, true)
		for i in range(2):
			var tex = load("res://sprites/player/block_%s_%d.png" % [dir_name, i])
			if tex:
				sf.add_frame(anim_name, tex)

	ResourceSaver.save(sf, "res://sprites/player/player_frames.tres")
	print("[FramesGen] Player SpriteFrames saved with 4-direction animations")
