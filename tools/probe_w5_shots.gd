extends Node

## W5 目检截图探针（临时 autoload 注入，run_w5_shots.py 调度）：
## 验收门=3 座桥近景走查（docs/武侠世界重构规划 §9 W5 行）
## 机位取自 regress_world_data.json bridge.props 基线：南门官道桥群/西门官道桥群/干流稀疏拱桥
const LOG := "C:/Learn/my-godot-project/tools/probe_w5_shots_log.txt"
const OUT := "C:/Learn/my-godot-project/tools/"

const SPOTS := [
	["0_road_s_bridge", Vector2i(75, 62)],    # 南门官道×河交叉（宽桥群+河曲）
	["1_road_w_bridge", Vector2i(31, 1)],     # 西门官道×干流交叉（官道桥群）
	["2_basic_arch", Vector2i(13, -11)],      # 沿河稀疏石拱桥（干流 4 宽）
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
	img.save_png(OUT + "vshot_w5_" + name_ + ".png")
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
	for s in SPOTS:
		player.global_position = Vector2(s[1].x * 16.0 + 8.0, s[1].y * 16.0 + 8.0)
		await _wait(1.4)
		await _shot(str(s[0]))
	_log("ALL_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
