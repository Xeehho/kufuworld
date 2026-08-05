@tool
extends Node

const TextureGen = preload("res://scripts/texture_generator.gd")

func _ready():
	_generate_frames()
	# 注意：不能在此调用 get_tree().quit() —— 本节点由 Main._ensure_textures()
	# 以 add_child 方式创建时，quit 会直接退出整个游戏

func _generate_frames():
	var sf = SpriteFrames.new()
	var dir_names = ["down", "left", "right", "up"]
	var specs = [
		["idle", 4, 4.0, true],
		["walk", 6, 8.0, true],
		["attack", 4, 10.0, false],
		["block", 2, 5.0, true],
	]
	for spec in specs:
		var prefix = spec[0]
		for dir_name in dir_names:
			var anim_name = prefix + "_" + dir_name
			sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, spec[2])
			sf.set_animation_loop(anim_name, spec[3])
			for i in range(spec[1]):
				# 运行时新生成的PNG无import数据，必须直接解码
				var tex = TextureGen.load_png_texture("res://sprites/player/%s_%s_%d.png" % [prefix, dir_name, i])
				if tex:
					sf.add_frame(anim_name, tex)

	ResourceSaver.save(sf, "res://sprites/player/player_frames.tres")
	print("[FramesGen] Player SpriteFrames saved with 4-direction animations")
