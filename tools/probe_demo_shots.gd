extends Node

## 城镇样板区验收截图（临时 autoload 注入，run_demo_shots.py 调度）
## 机位基于 2026-09-02 实测选址 rect=[P:(15,43) S:(56,44)]，区口 (67,43)，主巷 y≈53-54 全局
const LOG := "C:/Learn/my-godot-project/tools/probe_demo_shots_log.txt"
const OUT := "C:/Learn/my-godot-project/docs/shots/"

# [名称, 全局瓦片位, zoom(0=默认3)]
const SPOTS := [
	["p1_overview", Vector2i(43, 65), 1.1],  # 全区俯瞰（zoom-out 全景）
	["p3_farm_a", Vector2i(26, 74), 0],      # 菜圃A特写（垄行+作物+稻草人棚架）
	["p3_farm_b", Vector2i(43, 74), 0],      # 菜圃B特写
	["p3_yard_house", Vector2i(24, 65), 0],  # 农舍A前院（门径+围栏）
	["p3_yard_barn", Vector2i(24, 51), 0],   # 谷仓前院
	["p3_fence_s", Vector2i(43, 69), 0],     # 南带围栏+横巷
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

func _shot(name_: String):
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "demo_" + name_ + ".png")
	_log("shot saved: " + name_)

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
	var cam := player.get_node_or_null("Camera2D")
	for s in SPOTS:
		player.global_position = Vector2(s[1].x * 16.0 + 8.0, s[1].y * 16.0 + 8.0)
		if cam != null:
			var z := float(s[2])
			cam.zoom = Vector2(z, z) if z > 0.0 else Vector2(3, 3)   # 每机位显式设 zoom（0=默认3）
		await _wait(1.4)
		await _shot(str(s[0]))
	if cam != null:
		cam.zoom = Vector2(3, 3)
	_log("ALL_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
