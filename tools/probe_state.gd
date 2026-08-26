extends Node
# 临时状态探针：验证湿润农田瓦片切换是否真实生效（无头可跑）
const LOG := "C:/Learn/my-godot-project/tools/probe_log.txt"

func _log(m):
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(m)
		f.close()
	print(m)

func _ready():
	var farm = null
	var player = null
	for i in range(400):
		farm = get_node_or_null("/root/Main/World/FarmSystem")
		player = get_tree().get_first_node_in_group("player")
		if farm and player:
			break
		await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	var gen = get_node_or_null("/root/Main/World/WorldGenerator")
	var origin := Vector2i(int(player.global_position.x / 16), int(player.global_position.y / 16))
	var spot := Vector2i(-9999, -9999)
	for r in range(2, 40):
		var found := false
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := origin + Vector2i(dx, dy)
				var ok := true
				for ox in range(-1, 2):
					for oy in range(-2, 3):
						var tid = gen.get_tile_id(c.x + ox, c.y + oy)
						if tid != 0 and tid != 18:
							ok = false
				if ok:
					spot = c
					found = true
					break
			if found: break
		if found: break
	player.global_position = Vector2(spot.x * 16 + 8, spot.y * 16 + 8)
	var c0 := Vector2i(spot.x, spot.y + 1)
	var c1 := Vector2i(spot.x + 1, spot.y)
	var c2 := Vector2i(spot.x + 2, spot.y)
	_log("[SProbe] till c0=%s" % str(farm.try_till(Vector2(c0.x * 16.0 + 8, c0.y * 16.0 + 8))))
	_log("[SProbe] till c1=%s" % str(farm.try_till(Vector2(c1.x * 16.0 + 8, c1.y * 16.0 + 8))))
	_log("[SProbe] till c2=%s" % str(farm.try_till(Vector2(c2.x * 16.0 + 8, c2.y * 16.0 + 8))))
	_log("[SProbe] water c0=%s c1=%s" % [
		str(farm.try_water(Vector2(c0.x * 16.0 + 8, c0.y * 16.0 + 8))),
		str(farm.try_water(Vector2(c1.x * 16.0 + 8, c1.y * 16.0 + 8)))])
	_log("[SProbe] grounds c0=%d c1=%d c2=%d (期望33/33/16)" % [
		farm._ground_id(c0), farm._ground_id(c1), farm._ground_id(c2)])
	_log("[SProbe] tileset sources: has16=%s has33=%s" % [
		str(farm._tile_map.tile_set.has_source(16)), str(farm._tile_map.tile_set.has_source(33))])
	get_tree().quit()
