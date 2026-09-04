extends Node

## W4 目检截图探针（临时 autoload 注入，run_w4_shots.py 调度）：
## 验收门=城内+1村+1领地 NPC 站位走查（docs/武侠世界重构规划 §9 W4 行）
## 机位：城广场 / 城西市 / 渡口村 / 农耕村 / 市镇 / 剑宗领地（坐标取自 W4 基线锚点）
const LOG := "C:/Learn/my-godot-project/tools/probe_w4_shots_log.txt"
const OUT := "C:/Learn/my-godot-project/tools/"

## [机位名, 瓦片坐标]
const SPOTS := [
	["0_city_plaza", Vector2i(75, 0)],        # 青石城中央广场（酒楼/摊贩/广场）
	["1_city_market_w", Vector2i(64, 24)],    # 西市（铁匠/药师/布庄/市摊）
	["2_ferry_village", Vector2i(-51, 44)],   # 渡口村（渡亭+渡夫+村正）
	["3_farm_village", Vector2i(-130, 85)],   # 农耕村（祠堂+农带+农人）
	["4_market_town", Vector2i(110, 102)],    # 市镇（行肆+骡马店+广场）
	["5_sect_qingfeng", Vector2i(-124, -20)], # 青峰剑宗（主殿+演武场+长老弟子）
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
	img.save_png(OUT + "vshot_w4_" + name_ + ".png")
	_log("shot saved: " + name_)

func _ready():
	# 等世界/NPC 就绪
	var world := get_node_or_null("/root/Main/World")
	var n := 0
	while world == null and n < 900:
		await get_tree().process_frame
		n += 1
		world = get_node_or_null("/root/Main/World")
	await _wait(3.0)
	# 清天气干扰（陷阱12：大雾/昼夜 tint 全屏变色 → 截图前复位）
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
		await _wait(1.4)   # 等 chunk 加载+Y-sort 稳定
		await _shot(str(s[0]))
	_log("ALL_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
