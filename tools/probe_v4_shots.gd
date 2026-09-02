extends Node

## v4 M1 farm 镇机位截图探针（临时 autoload 注入，run_v4_shots.py 调度）
## 机位：3 个 v4 farm 镇 × 全景/地块特写（zoom 显式设置，修 w7 无 zoom 继承）
## 输出：docs/shots/v4_<name>.png
const LOG := "C:/Learn/my-godot-project/tools/probe_v4_shots_log.txt"
const OUT := "C:/Learn/my-godot-project/docs/shots/"

# [name, 瓦片坐标, zoom]
const SPOTS := [
	["farm1_overview", Vector2i(-75, 55), 1.0],    # farm 镇全景（21×21 体）
	["farm1_north", Vector2i(-75, 51), 2.0],        # 北带祠堂/农舍地块特写
	["farm2_overview", Vector2i(-45, 69), 1.0],
	["farm2_south", Vector2i(-45, 73), 2.0],        # 南带民居地块特写
	["farm3_overview", Vector2i(128, 11), 1.0],
	["farm3_close", Vector2i(128, 8), 2.5],         # 北带门径/围栏放大
]

func _log(m):
	print(m)
	var f := FileAccess.open(LOG, FileAccess.WRITE if not FileAccess.file_exists(LOG) else FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line(m)
		f.close()

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _ready():
	var world := get_node_or_null("/root/Main/World")
	var n := 0
	while world == null and n < 900:
		await get_tree().process_frame
		n += 1
		world = get_node_or_null("/root/Main/World")
	await _wait(3.0)
	var cm := get_node_or_null("/root/Main/World/CanvasModulate")
	if cm:
		cm.color = Color(1, 1, 1)
	var wc := get_node_or_null("/root/Main/World/WeatherController")
	if wc:
		wc.set_process(false)
		for c in wc.get_children():
			if c is CanvasItem:
				c.visible = false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		_log("FATAL: player not found")
		get_tree().quit()
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	for s in SPOTS:
		player.global_position = Vector2(s[1].x * 16.0 + 8.0, s[1].y * 16.0 + 8.0)
		if cam:
			cam.zoom = Vector2(s[2], s[2])
		await _wait(1.4)
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT + "v4_" + str(s[0]) + ".png")
		_log("shot saved: " + str(s[0]) + " zoom=" + str(s[2]))
	_log("ALL_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
