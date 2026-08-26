extends Node

const LOG := "C:/Learn/my-godot-project/tools/probe_log.txt"

func _log(msg: String):
	var f := FileAccess.open(LOG, FileAccess.READ)
	var prev := f.get_as_text() if f else ""
	if f: f.close()
	var w := FileAccess.open(LOG, FileAccess.WRITE)
	w.store_string(prev + msg + "\n")
	w.close()
	print(msg)

func _ready():
	_log("[Probe] ready, instancing main...")
	var ps: PackedScene = load("res://scenes/main.tscn")
	if ps == null:
		_log("[Probe] FATAL main.tscn load failed")
		get_tree().quit(); return
	var main_scene = ps.instantiate()
	add_child(main_scene)
	_log("[Probe] main added")
	await get_tree().create_timer(7.0).timeout
	_log("[Probe] timer done, drawing frames")
	for i in range(3):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("C:/Learn/my-godot-project/tools/probe_shot_%d.png" % i)
		_log("[Probe] shot %d err=%d size=%s" % [i, err, str(img.get_size())])
		await get_tree().create_timer(0.4).timeout
	_log("[Probe] done, quitting")
	get_tree().quit()
