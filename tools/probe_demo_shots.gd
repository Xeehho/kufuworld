extends Node

## 城镇样板区验收截图（临时 autoload 注入，run_demo_shots.py 调度）
## 机位基于 2026-09-02 实测选址 rect=[P:(15,43) S:(56,44)]，区口 (67,43)，主巷 y≈53-54 全局
const LOG := "C:/Learn/my-godot-project/tools/probe_demo_shots_log.txt"
const OUT := "C:/Learn/my-godot-project/docs/shots/"

# [名称, 全局瓦片位, zoom(0=默认3), nofix(1=不覆盖光照/天气)]
const SPOTS := [
	["v1_gate", Vector2i(67, 43), 0, 0],      # 区口：立牌+入口路+连接巷
	["v2_main_w", Vector2i(24, 52), 0, 0],    # 谷仓+主巷西段（围栏/门径）
	["v3_plaza", Vector2i(42, 50), 0, 0],     # 水井广场+果树带
	["v4_green", Vector2i(60, 51), 0, 0],     # 温室+主巷东段
	["v5_house", Vector2i(24, 63), 0, 0],     # 农舍A前院（四要素+围栏）
	["v6_farm", Vector2i(26, 73), 0, 0],      # 菜圃A（垄行/稻草人/棚架）
	["v7_south", Vector2i(43, 70), 0, 0],     # 南带围栏全景
	["v8_overview", Vector2i(43, 65), 1.1, 0],# 全区俯瞰
	["v9_dark_zoom", Vector2i(32, 47), 5.0, 0],  # P5 待定位暗物放大
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
	var cm_default: Color = cm.color if cm != null else Color(1, 1, 1)
	var wc := get_node_or_null("/root/Main/World/WeatherController")
	var wt_default: float = wc.world_time if wc != null else 0.0
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
	# P5 性能项：样板区新增节点数（立项书预算 ≤400）
	var kit := get_node_or_null("/root/Main/World/WorldGenerator/TownDemoKit")
	if kit != null:
		_log("[P5] TownDemoKit 节点数=%d（预算<=400）" % kit.get_child_count())
	else:
		_log("[P5] TownDemoKit 未找到")
	for s in SPOTS:
		player.global_position = Vector2(s[1].x * 16.0 + 8.0, s[1].y * 16.0 + 8.0)
		if cam != null:
			var z := float(s[2])
			cam.zoom = Vector2(z, z) if z > 0.0 else Vector2(3, 3)   # 每机位显式设 zoom（0=默认3）
		var nofix: bool = int(s[3]) == 1
		if cm != null:
			cm.color = cm_default if nofix else Color(1, 1, 1)       # 夜景机位保留游戏光照
		if wc != null and nofix:
			wc.world_time = 22.0 * 60.0 * wc.time_scale              # 固定 22 点（陷阱27：直接改 world_time）
		await _wait(1.4)
		await _shot(str(s[0]))
	if cam != null:
		cam.zoom = Vector2(3, 3)
	if cm != null:
		cm.color = cm_default
	if wc != null:
		wc.world_time = wt_default
	_log("ALL_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
