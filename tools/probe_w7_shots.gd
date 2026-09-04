extends Node

## W7 终验 14 机位截图探针（临时 autoload 注入，run_w7_shots.py 调度）
## 机位规划（docs/武侠世界重构规划 §10.2）：城内 3 + 四门 4 + 桥 4（官道桥群×2/窄/宽）+ 领地 2 + 渡口村 1
## 输出：docs/shots/w7_<name>.png（规划 §10.2 要求机位图入库）
const LOG := "C:/Learn/my-godot-project/tools/probe_w7_shots_log.txt"
const OUT := "C:/Learn/my-godot-project/docs/shots/"

const SPOTS := [
	["0_city_plaza", Vector2i(75, 0)],       # 城中央石板广场
	["1_city_yamen", Vector2i(59, -17)],     # 官署坊·府衙
	["2_city_west_market", Vector2i(62, 26)],# 西市行肆（市巷 y=26）
	["3_gate_n", Vector2i(75, -30)],         # 北门·拱辰门（城门楼）
	["4_gate_s", Vector2i(75, 30)],          # 南门·明德门
	["5_gate_w", Vector2i(45, 0)],           # 西门·西成门
	["6_gate_e", Vector2i(105, 0)],          # 东门·东作门
	["7_bridge_s_group", Vector2i(75, 60)],  # 南门官道桥群（观感欠账①评估：跨宽水带碎段）
	["8_bridge_w_gate", Vector2i(31, 0)],    # 西门官道桥（8 格长干流桥）
	["9_bridge_narrow", Vector2i(76, 48)],   # 窄桥近景（2 格）
	["10_bridge_wide", Vector2i(76, 68)],    # 宽桥近景（4 格）
	["11_sect_qingfeng", Vector2i(-124, -26)],# 青峰剑宗（山门/主殿/界碑环）
	["12_sect_youming", Vector2i(-7, -128)], # 幽冥教雪原领地（观感欠账④评估：雪原树）
	["13_town_ferry", Vector2i(-51, 44)],    # 渡口村（渡亭+官道终点）
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
	img.save_png(OUT + "w7_" + name_ + ".png")
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
