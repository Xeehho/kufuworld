extends Node
# 长安v2 全城导出 dump：实装 changan_v2.tscn（真实生成，材质层确定性随机原样保留），
# 把瓦片双层/材质件/城内人口/出城触发/街区全量写入 JSON，供 tools/build_changan_v2_tmx.py 转 Tiled tmx。
# 只读导出：不修改城市任何节点；ContactShadow/BuildingCollision 属运行时派生件，不导出。
# 运行: godot --headless --path . res://tools/export_changan_v2_dump.tscn

const TextureGen = preload("res://scripts/texture_generator.gd")
const OUT_PATH := "res://docs/参考/tiled_work/_changan_v2_city_dump.json"

# 单格瓦片 id → [首选贴图, 回退贴图]（镜像 tileset_generator.gd 注册表；运行时按存在性择一，
# 并与 TileMap 图集源贴图逐 id 尺寸核对，防止注册表漂移后导出错图）
const SINGLE_TILES := {
	0: ["res://sprites/tiles_mw22/grass.png", "res://sprites/tiles/grass.png"],
	72: ["res://sprites/tiles_changan_sckr/street_main.png", "res://sprites/tiles/path.png"],
	74: ["res://sprites/tiles_changan_sckr/street_lane.png", "res://sprites/tiles/path.png"],
	101: ["res://sprites/tiles_changan_sckr/pave_market.png", "res://sprites/tiles_mw22/stone.png"],
	111: ["res://sprites/tiles_changan_sckr/quay_stone.png", "res://sprites/tiles_mw22/stone.png"],
	112: ["res://sprites/tiles_changan_sckr/water_canal.png", "res://sprites/tiles/water.png"],
	69: ["res://sprites/tiles_changan_sckr/wall_palace.png", "res://sprites/tiles/changan_palace_wall.png"],
	70: ["res://sprites/tiles_changan_sckr/wall_city.png", "res://sprites/tiles/changan_outer_wall.png"],
	100: ["res://sprites/tiles_changan_sckr/wall_ward.png", "res://sprites/tiles/ward_wall.png"],
	103: ["res://sprites/tiles_changan_sckr/wall_city_face_v.png", "res://sprites/tiles/changan_outer_wall.png"],
	104: ["res://sprites/tiles_changan_sckr/wall_palace_v.png", "res://sprites/tiles/changan_palace_wall.png"],
	105: ["res://sprites/tiles_changan_sckr/wall_ward_v.png", "res://sprites/tiles/ward_wall.png"],
	108: ["res://sprites/tiles_changan_sckr/wall_city_cap_w.png", "res://sprites/tiles/changan_outer_wall.png"],
	109: ["res://sprites/tiles_changan_sckr/wall_city_cap_e.png", "res://sprites/tiles/changan_outer_wall.png"],
}

var fails: Array = []


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var city = load("res://scenes/changan_v2.tscn").instantiate()
	add_child(city)
	# 与 probe_changan_v2.gd 同款处理：孤立环境禁用人口调度，避免场景外依赖误报。
	var population = city.get_node_or_null("Population")
	if population != null:
		population.process_mode = Node.PROCESS_MODE_DISABLED
	while not city.done and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	if not city.done:
		print("[ChangAnV2-Dump][FAIL] 城市生成超时")
		get_tree().quit(2)
		return
	if city.materials_count <= 0:
		# 素材库缺件时城市是灰盒回退态，导出没有意义（本机必须有素材库全件）
		print("[ChangAnV2-Dump][FAIL] 材质件=%d（素材库缺件？），拒绝导出灰盒" % city.materials_count)
		get_tree().quit(2)
		return

	var mats = city.get_node("Materials")
	var lib_cats := {}
	for cat: String in mats.lib:
		lib_cats[cat] = mats.lib[cat]
	var pack_manifest := _load_pack_manifest()

	var out := {
		"meta": {
			"W": city.W, "H": city.H, "margin": city.margin, "wall": city.wall,
			"ring": city.ring, "stats": city.stats, "materials_count": city.materials_count,
			"gates": _gate_names(city), "dump_time": Time.get_datetime_string_from_system(),
		},
		"zone_tiles": _zone_tiles(city, lib_cats),
		"single_tiles": {},
		"ground": _layer_cells(city, 0),
		"decor": _layer_cells(city, 1),
		"lib_cats": lib_cats,
		"pack_props": [],
		"pieces": [],
		"npcs": [],
		"portals": [],
		"blocks": [],
	}

	var used_pack_names := {}
	var shadow_skipped: Array = [0]
	_walk_pieces(mats, "", out["pieces"], used_pack_names, lib_cats, shadow_skipped)
	for name: String in used_pack_names:
		if not pack_manifest.has(name):
			fails.append("sckr_manifest 缺少已用道具 %s" % name)
			continue
		var rec: Dictionary = pack_manifest[name]
		out["pack_props"].append({"name": name, "file": rec["file"], "w": rec["w"], "h": rec["h"]})
	out["pack_props"].sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))

	# 单格瓦片源：扫描两层实际用到的 id（而非照抄注册表），确保导出集合=实机集合
	var used_singles := {}
	for cells: Dictionary in [out["ground"], out["decor"]]:
		for sid: int in cells["sids"]:
			if sid >= 0 and sid < 200 and not used_singles.has(sid):
				used_sids_add(used_singles, sid)
	for sid: int in used_singles:
		out["single_tiles"][sid] = {"file": _resolve_single(city, sid)}

	out["npcs"] = _npcs(city)
	out["portals"] = _portals(city)
	out["blocks"] = _blocks(city)

	var text := JSON.stringify(out, "  ")
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		print("[ChangAnV2-Dump][FAIL] 无法写入 %s" % OUT_PATH)
		get_tree().quit(2)
		return
	f.store_string(text)
	f.close()

	# ---- 汇总与断言：导出件数必须与城市 stats 对账 ----
	var by_grp := {}
	for p: Dictionary in out["pieces"]:
		by_grp[String(p["group"])] = int(by_grp.get(String(p["group"]), 0)) + 1
	var gnd_n := 0
	for sid: int in out["ground"]["sids"]:
		if sid >= 0:
			gnd_n += 1
	var dcr_n := 0
	for sid: int in out["decor"]["sids"]:
		if sid >= 0:
			dcr_n += 1
	if int(shadow_skipped[0]) != int(city.stats["material_shadows"]):
		fails.append("跳过阴影件 %d ≠ stats.material_shadows %d（判别条件漂移？）" % [
			shadow_skipped[0], city.stats["material_shadows"]])
	if out["pieces"].size() != int(city.stats["materials"]):
		fails.append("材质件 %d ≠ stats.materials %d" % [out["pieces"].size(), city.stats["materials"]])
	if out["npcs"].size() != int(city.stats["population"]):
		fails.append("人口 %d ≠ stats.population %d" % [out["npcs"].size(), city.stats["population"]])
	if gnd_n != int(city.stats["ground_cells"]):
		fails.append("地面格 %d ≠ stats.ground_cells %d" % [gnd_n, city.stats["ground_cells"]])
	if dcr_n != int(city.stats["decor_cells"]):
		fails.append("装饰格 %d ≠ stats.decor_cells %d" % [dcr_n, city.stats["decor_cells"]])
	print("[ChangAnV2-Dump] 尺寸=%dx%d 地面格=%d 装饰格=%d 材质件=%d %s 人口=%d 城门=%d 街区=%d 单格源=%d" % [
		city.W, city.H, gnd_n, dcr_n, out["pieces"].size(), str(by_grp), out["npcs"].size(),
		out["portals"].size(), out["blocks"].size(), out["single_tiles"].size()])
	if not fails.is_empty():
		for e in fails:
			print("[ChangAnV2-Dump][FAIL] %s" % e)
		get_tree().quit(1)
		return
	print("[ChangAnV2-Dump] OK %s (%dms)" % [OUT_PATH, Time.get_ticks_msec() - t0])
	get_tree().quit(0)


func used_sids_add(d: Dictionary, sid: int) -> void:
	d[sid] = true


func _gate_names(city) -> Dictionary:
	var out := {}
	for side: String in city.gate_info:
		out[side] = String(city.gate_info[side]["name"])
	return out


# 区带图集源：sid → 实际贴图文件/网格数（tw/th 取图集源贴图真实尺寸）
func _zone_tiles(city, lib_cats: Dictionary) -> Dictionary:
	var out := {}
	var lib_ground: Array = lib_cats.get("00_地面", [])
	for zone: int in city.zone_tiles:
		var zt: Dictionary = city.zone_tiles[zone]
		var sid: int = int(zt["sid"])
		var src = city.tile_map.tile_set.get_source(sid)
		var tex: Texture2D = src.texture
		var rec := ""
		var file := ""
		for p in lib_ground:
			if String(p["id"]) == String(zt["swatch"]):
				rec = String(p["id"])
				file = "res://素材库/00_地面/" + String(p["file"])
				break
		if file == "":
			fails.append("区带 Z%d 找不到切件 %s" % [zone, zt["swatch"]])
			continue
		out[str(sid)] = {"zone": zone, "swatch": rec, "file": file,
				"tw": tex.get_width() / 16, "th": tex.get_height() / 16}
	return out


func _layer_cells(city, layer: int) -> Dictionary:
	var sids: Array = []
	var ax: Array = []
	var ay: Array = []
	var tm: TileMap = city.tile_map
	for yy in range(city.H):
		for xx in range(city.W):
			var c := Vector2i(xx, yy)
			var sid := tm.get_cell_source_id(layer, c)
			if sid == -1:
				sids.append(-1)
				ax.append(0)
				ay.append(0)
			else:
				var ac: Vector2i = tm.get_cell_atlas_coords(layer, c)
				sids.append(sid)
				ax.append(ac.x)
				ay.append(ac.y)
	return {"sids": sids, "ax": ax, "ay": ay}


# 递归收集材质 Sprite（跳过派生阴影；分组沿父链继承：城门件挂在 CityGate 根下）
func _walk_pieces(node: Node, grp: String, pieces: Array, used_pack: Dictionary,
		lib_cats: Dictionary, shadow_skipped: Array) -> void:
	var g := grp
	if node.is_in_group("changan_outer_wall_facade"):
		g = "wall_facade"
	elif node.is_in_group("changan_city_gate"):
		g = "city_gate"
	elif node.is_in_group("changan_outskirts"):
		g = "outskirts"
	if node is Sprite2D and not node.is_in_group("tree_shadow") \
			and not String(node.name).begins_with("ContactShadow"):
		_collect_piece(node, g, pieces, used_pack, lib_cats)
	elif node is Sprite2D:
		shadow_skipped[0] += 1
	for child in node.get_children():
		_walk_pieces(child, g, pieces, used_pack, lib_cats, shadow_skipped)


func _collect_piece(sp: Sprite2D, grp: String, pieces: Array, used_pack: Dictionary,
		lib_cats: Dictionary) -> void:
	var tex: Texture2D = sp.texture
	if tex == null:
		fails.append("件 %s 无贴图" % String(sp.name))
		return
	if absf(sp.scale.x - 1.0) > 0.001 or absf(sp.scale.y - 1.0) > 0.001:
		fails.append("件 %s 带缩放 %s（tmx 对象不支持，需单独处理）" % [String(sp.name), str(sp.scale)])
		return
	var pos: Vector2 = sp.get_parent().to_local(sp.global_position)
	var mid := ""
	if sp.has_meta("material_id"):
		mid = String(sp.get_meta("material_id"))
	var rec := {"group": grp if grp != "" else "block", "name": String(sp.name),
		"x": roundf(pos.x * 100.0) / 100.0, "y": roundf(pos.y * 100.0) / 100.0,
		"flip": sp.flip_h, "w": tex.get_width(), "h": tex.get_height()}
	if mid == "":
		# 轴灯件（_put_axis_prop 不写 meta）：按生成器同款过滤条件重算取 [0]（素材库件）
		mid = _axis_lamp_id(lib_cats)
		if mid == "":
			fails.append("无 meta 件 %s 且轴灯池为空" % String(sp.name))
			return
		rec["axis_lamp"] = true
	if _is_lib_id(mid):
		# 素材库件 id 形如 "01_民居坊_07"：类别=去掉末尾序号
		var cat: String = mid.substr(0, mid.rfind("_"))
		var lib: Array = lib_cats.get(cat, [])
		var hit := {}
		for p in lib:
			if String(p["id"]) == mid:
				hit = p
				break
		if hit.is_empty():
			fails.append("素材件 %s 不在 lib[%s]" % [mid, cat])
			return
		if int(hit["w"]) != rec["w"] or int(hit["h"]) != rec["h"]:
			fails.append("件 %s 尺寸 %dx%d ≠ manifest %dx%d" % [mid, rec["w"], rec["h"], hit["w"], hit["h"]])
		rec["cat"] = cat
		rec["piece"] = mid
		rec["file"] = "res://素材库/%s/%s" % [cat, String(hit["file"])]
	else:
		# SCKR 整包件（wall_run/门楼/树/船…）
		used_pack[mid] = true
		rec["cat"] = "sckr"
		rec["piece"] = mid
		rec["file"] = "res://sprites/changan_props_sckr/%s.png" % mid
	pieces.append(rec)


func _is_lib_id(mid: String) -> bool:
	# 素材库切件 id = <两位数字类别名>_<序号>，如 "00_地面_11"；SCKR 整包件为英文名
	if mid.length() < 5 or not (mid[0] >= "0" and mid[0] <= "9") or not (mid[1] >= "0" and mid[1] <= "9"):
		return false
	return mid.find("_", 3) != -1


# 轴灯件（_put_axis_prop 不写 meta）：按生成器同款过滤条件重算灯件池取 [0]
func _axis_lamp_id(lib_cats: Dictionary) -> String:
	for p in lib_cats.get("11_街饰过渡", []):
		if String(p["cls"]) == "prop" and int(p["w"]) >= 12 and int(p["w"]) <= 20 \
				and int(p["h"]) >= 20 and int(p["h"]) <= 30:
			return String(p["id"])
	return ""


func _load_pack_manifest() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://data/sckr_manifest.json", FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed.has("assets"):
		return out
	for p in parsed["assets"]:
		if not p.has("name") or not p.has("box") or p["box"].size() < 4:
			continue
		var name := String(p["name"])
		var kind := String(p.get("kind", "prop"))
		var root := "res://sprites/tiles_changan_sckr/" if kind == "tile" else "res://sprites/changan_props_sckr/"
		var path := root + name + ".png"
		if FileAccess.file_exists(path):
			out[name] = {"file": path,
				"w": int(p["box"][2]) - int(p["box"][0]), "h": int(p["box"][3]) - int(p["box"][1])}
	return out


func _resolve_single(city, sid: int) -> String:
	if not SINGLE_TILES.has(sid):
		fails.append("单格瓦片 %d 不在导出映射表" % sid)
		return ""
	var cands: Array = SINGLE_TILES[sid]
	var chosen := ""
	for path in cands:
		if FileAccess.file_exists(path):
			chosen = path
			break
	if chosen == "":
		fails.append("单格瓦片 %d 候选贴图全缺失" % sid)
		return ""
	# 与图集源贴图核对尺寸，防注册表漂移
	var src = city.tile_map.tile_set.get_source(sid)
	var tex: Texture2D = TextureGen.load_png_texture(chosen)
	if tex != null and src != null and src.texture != null \
			and (tex.get_width() != src.texture.get_width() or tex.get_height() != src.texture.get_height()):
		fails.append("单格瓦片 %d 贴图尺寸不符：%s" % [sid, chosen])
	return chosen


func _npcs(city) -> Array:
	var out := []
	var pop = city.get_node_or_null("Population")
	if pop == null:
		return out
	for npc in pop.get_children():
		var pos: Vector2 = pop.to_local(npc.global_position)
		var nname := ""
		if npc.get("npc_data") != null and npc.npc_data != null:
			nname = String(npc.npc_data.npc_name)
		out.append({"name": nname, "x": roundf(pos.x * 100.0) / 100.0,
			"y": roundf(pos.y * 100.0) / 100.0})
	return out


func _portals(city) -> Array:
	var out := []
	var portals = city.get_node_or_null("Portals")
	if portals == null:
		return out
	for area in portals.get_children():
		if not (area is Area2D):
			continue
		var side := String(area.name).trim_prefix("ExitPortal_")
		var size := Vector2.ZERO
		for ch in area.get_children():
			if ch is CollisionShape2D and ch.shape is RectangleShape2D:
				size = ch.shape.size
				break
		var center: Vector2 = city.to_local(area.global_position)
		out.append({"side": side, "name": String(city.gate_info[side]["name"]),
			"x": center.x - size.x * 0.5, "y": center.y - size.y * 0.5,
			"w": size.x, "h": size.y})
	return out


# 街区矩形：只用公开 API（col_x/row_y/bw/bh）复算 _block_rect 的格位契约
func _blocks(city) -> Array:
	var out := []
	for b in city.blocks:
		var c := int(b["col"])
		var r := int(b["row"])
		var sx := 1
		var sy := 1
		if b.has("span"):
			sx = int(b["span"][0])
			sy = int(b["span"][1])
		var x0: int = city.col_x(c)
		var y0: int = city.row_y(r)
		var x1: int = city.col_x(c + sx - 1) + city.bw
		var y1: int = city.row_y(r + sy - 1) + city.bh
		out.append({"id": String(b["id"]), "name": String(b["name"]), "kind": String(b["kind"]),
			"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0})
	return out
