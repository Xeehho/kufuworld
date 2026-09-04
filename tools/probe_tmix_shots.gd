extends Node

## 地形掺杂调查探针（临时 autoload 注入，run_tmix_shots.py 调度）
## 目的：复现用户截图中的"无关联瓦片掺杂"地形——机位截图 + 33x33 群系/瓦片直方图双证据
const LOG := "C:/Learn/my-godot-project/tools/probe_tmix_shots_log.txt"
const OUT := "C:/Learn/my-godot-project/docs/shots/"

const SPOTS := [
	["mtn_a", Vector2i(60, -60)],
	["mtn_b", Vector2i(-40, -70)],
	["mtn_c", Vector2i(0, -95)],
	["mtn_d", Vector2i(110, -45)],
	["desert_a", Vector2i(60, 140)],
	["desert_b", Vector2i(-30, 170)],
	["desert_c", Vector2i(140, 150)],
	["city_edge_w", Vector2i(38, 18)],
	["city_edge_e", Vector2i(112, -20)],
	["trans_pm", Vector2i(0, -30)],
	["town_outskirt", Vector2i(-87, 96)],
	["spawn_ring", Vector2i(24, 10)],
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
	img.save_png(OUT + "tmix_" + name_ + ".png")
	_log("shot saved: " + name_)

func _sample(world: Node, name_: String, cx: int, cy: int):
	# 33x33 直方图：群系 kind + 瓦片 id
	var kinds := {}
	var tids := {}
	for y in range(cy - 16, cy + 17):
		for x in range(cx - 16, cx + 17):
			var k: String = world._biome_kind(x, y)
			kinds[k] = int(kinds.get(k, 0)) + 1
			var t: int = world.get_tile_id(x, y)
			tids[t] = int(tids.get(t, 0)) + 1
	var kind_str := ""
	for k in kinds.keys():
		kind_str += "%s=%d " % [k, kinds[k]]
	var tid_str := ""
	var keys := tids.keys()
	keys.sort()
	for t in keys:
		tid_str += "%d=%d " % [t, tids[t]]
	_log("SAMPLE %s @(%d,%d) kinds: %s | tids: %s" % [name_, cx, cy, kind_str, tid_str])

func _ready():
	# /root/Main/World 是场景文件节点（第1帧就存在）；必须等 Main._ready 动态创建的 WorldGenerator
	var world: Node = null
	var n := 0
	while n < 1800:
		world = get_node_or_null("/root/Main/World/WorldGenerator")
		if world != null:
			break
		await get_tree().process_frame
		n += 1
	_log("probe uses: %s (waited %d frames)" % [str(world), n])
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
		var c: Vector2i = s[1]
		player.global_position = Vector2(c.x * 16.0 + 8.0, c.y * 16.0 + 8.0)
		await _wait(1.4)
		await _shot(str(s[0]))
		_sample(world, str(s[0]), c.x, c.y)
	_log("ALL_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
