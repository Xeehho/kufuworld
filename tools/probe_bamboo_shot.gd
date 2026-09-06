extends Node

## 竹林实机截图探针（美术重构·竹9 程序化 MW 竹表一次性验收）
## 传送到竹林群系中心（regress data: bamboo center -58,14）→等chunk铺设→截图退出
const LOG := "C:/Learn/my-godot-project/tools/probe_bamboo_log.txt"
const SHOT := "C:/Learn/my-godot-project/docs/shots/bamboo_mw_ingame.png"

func _log(m: String):
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(m)
		f.close()
	print(m)

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _ready():
	_log("probe start")
	for i in range(900):
		if get_node_or_null("/root/Main/World/Player") != null:
			break
		await get_tree().process_frame
	await _wait(2.0)
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		_log("FATAL: player not found")
		get_tree().quit()
		return
	# 竹林群系代表中心（regress data bamboo center）常临湖——搜索竹格(9)最密的 5x5 邻域点
	var wg = get_node_or_null("/root/Main/World/WorldGenerator")
	var target := Vector2i(-58, 14)
	if wg != null:
		var best := -1
		for r in range(0, 40):
			var candidates := []
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if max(abs(dx), abs(dy)) != r:
						continue
					var cx := -58 + dx
					var cy := 14 + dy
					if wg.get_tile_id(cx, cy) != 9:
						continue
					var n := 0
					for oy in range(-2, 3):
						for ox in range(-2, 3):
							if wg.get_tile_id(cx + ox, cy + oy) == 9:
								n += 1
					candidates.append([n, cx, cy])
			if not candidates.is_empty():
				candidates.sort_custom(func(a, b): return a[0] > b[0])
				target = Vector2i(candidates[0][1], candidates[0][2])
				best = candidates[0][0]
				break
		_log("target tile=" + str(target) + " cluster9=" + str(best))
	player.global_position = Vector2(target.x * 16.0 + 8.0, target.y * 16.0 + 8.0)
	await _wait(3.5)   # 等chunk生成+树道具铺设
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT)
	_log("shot saved: " + SHOT)
	await _wait(0.3)
	get_tree().quit()
