extends SceneTree
func _init():
	var f := FileAccess.open("C:/Learn/my-godot-project/tools/mini_log.txt", FileAccess.WRITE)
	f.store_string("mini ok " + str(Time.get_ticks_msec()))
	f.close()
	print("[Mini] written")
	quit()
