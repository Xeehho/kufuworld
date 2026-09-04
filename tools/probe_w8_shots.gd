extends Node

## W8 观感修复复检 14 机位（临时 autoload 注入，run_w8_shots.py 调度）
## 重点：湖缘观感（药王谷/东湖）、河形舒展后官道桥、城内地坪统一
const LOG := "C:/Learn/my-godot-project/tools/probe_w8_shots_log.txt"
const OUT := "C:/Learn/my-godot-project/docs/shots/"

const SPOTS := [
	["0_city_plaza", Vector2i(75, 0)],        # 城中央广场（地坪统一后）
	["1_city_yamen", Vector2i(59, -17)],      # 官署坊·府衙
	["2_city_west_market", Vector2i(62, 26)], # 西市
	["3_gate_n", Vector2i(75, -30)],
	["4_gate_s", Vector2i(75, 30)],
	["5_gate_w", Vector2i(45, 0)],
	["6_gate_e", Vector2i(105, 0)],
	["7_gate_s_bridge", Vector2i(75, 55)],    # s 官道过河桥（[75,50,1,4]/[77,59,1,4]）
	["8_bridge_wide", Vector2i(-64, 5)],      # 4 格宽桥
	["9_bridge_long", Vector2i(-151, -72)],   # 7 格长桥（西北双桥群）
	["10_lake_east", Vector2i(158, 30)],      # 东湖湖心（湖缘低频化观感）
	["11_sect_youming", Vector2i(-91, -112)], # 幽冥教雪原领地
	["12_sect_qingfeng", Vector2i(-124, -26)],# 青峰剑宗
	["13_town_market", Vector2i(-87, 116)],   # 市镇
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
	img.save_png(OUT + "w8_" + name_ + ".png")
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
