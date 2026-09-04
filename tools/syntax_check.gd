extends SceneTree
# Phase C 语法自检：逐个load编译新/改脚本，结果写tools/syntax_log.txt
const LOG := "C:/Learn/my-godot-project/tools/syntax_log.txt"
const FILES := [
	"res://scripts/item_factory.gd",
	"res://scripts/farm_system.gd",
	"res://scripts/mob.gd",
	"res://scripts/mob_spawner.gd",
	"res://scripts/station_system.gd",
	"res://scripts/player.gd",
	"res://scripts/Main.gd",
	"res://scripts/tileset_generator.gd",
]
func _init():
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	for p in FILES:
		var s = load(p)
		if s == null:
			f.store_line("FAIL " + p)
			print("SYNTAX_FAIL " + p)
		else:
			f.store_line("OK   " + p)
			print("SYNTAX_OK " + p)
	f.close()
	quit()
