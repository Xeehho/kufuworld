extends Node

## 刷怪落点取证探针（临时 autoload，run_mob_wall_probe.py 调度）
## 指标：每只 mob 脚下瓦片 get_tile_id 是否 ∈ collision_tiles（=站在墙里）、
## 该瓦片是否 ∈ reachable_cells（=吸附集认为可达）、 TileMap 实际渲染的 atlas source id。
## 跑完由 runner 还原 project.godot（陷阱备忘 §9）。

const OUT := "C:/Learn/my-godot-project/tools/mob_wall_data.json"
const LOG := "C:/Learn/my-godot-project/tools/mob_wall_log.txt"

func _log(m):
	print(m)
	var f := FileAccess.open(LOG, FileAccess.WRITE if not FileAccess.file_exists(LOG) else FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line(m)
		f.close()

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _wg():
	var world := get_node_or_null("/root/Main/World")
	if world == null:
		return null
	for c in world.get_children():
		var s = c.get_script()
		if s != null and str(s.resource_path).ends_with("world_generator.gd"):
			return c
	return null

func _ready():
	await _wait(6.0)
	var wg = _wg()
	if wg == null:
		var f2 := FileAccess.open(OUT, FileAccess.WRITE)
		f2.store_string(JSON.stringify({"FATAL": "world_generator not found"}))
		f2.close()
		get_tree().quit()
		return

	var data := {"mobs": [], "reachable_size": wg.reachable_cells.size()}
	var offenders := 0
	for mob in get_tree().get_nodes_in_group("mobs"):
		var p: Vector2 = mob.global_position
		var tx := int(floor(p.x / 16.0))
		var ty := int(floor(p.y / 16.0))
		var tid: int = wg.get_tile_id(tx, ty)
		var reach: bool = wg.reachable_cells.has(Vector2i(tx, ty))
		# TileMap 实际画的 source id（世界坐标→地图坐标需按玩家chunk区域查，未加载区查不到）
		var tm = wg.get("main_tile_map")
		var painted := -1
		if tm != null:
			var cell: Vector2i = tm.local_to_map(tm.to_local(p))
			painted = tm.get_cell_source_id(0, cell)
		var rec := {
			"name": String(mob.name), "kind": String(mob.kind_id),
			"pos": [p.x, p.y], "tile": [tx, ty],
			"logic_tile": tid, "in_collision": tid in wg.collision_tiles,
			"tile_reachable": reach, "painted_src": painted,
			"home": [mob.home_pos.x, mob.home_pos.y],
		}
		data["mobs"].append(rec)
		if tid in wg.collision_tiles:
			offenders += 1
			_log("[Probe] 墙内怪: %s pos=%s tile=(%d,%d) logic=%d reachable=%s painted=%d"
				% [String(mob.name), str(p), tx, ty, tid, str(reach), str(painted)])

	# 营地中心复核
	var camps := []
	var sp = get_node_or_null("/root/Main/World/MobSpawner")
	if sp != null:
		for c in sp.camps_runtime:
			var cp: Vector2 = c["center"]
			var ctx := int(floor(cp.x / 16.0))
			var cty := int(floor(cp.y / 16.0))
			camps.append({
				"name": String(c["def"]["name"]), "center": [cp.x, cp.y],
				"tile": [ctx, cty], "logic_tile": wg.get_tile_id(ctx, cty),
				"tile_reachable": wg.reachable_cells.has(Vector2i(ctx, cty)),
			})
	data["camps"] = camps
	data["offender_count"] = offenders

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_log("[Probe] done: %d mobs, %d in-wall, reachable=%d" % [data["mobs"].size(), offenders, wg.reachable_cells.size()])
	get_tree().quit()
