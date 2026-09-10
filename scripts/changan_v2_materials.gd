extends Node2D
# 长安v2 材质层（第 2 轮 2026-09-09：先路后区再建模——地面区带由生成器负责，本层只做坊内建模）
# 布局规矩（changan_city_v2.json v2.2 = GPT 蓝图谈话合并产物 + 范式v3）：
#   kind_qc——palace 中轴/对称/大前庭；temple 山门→庭→殿→塔+绿化簇；noble 围合府邸/前庭/多层；
#             market 临街面连续/中央开放/忌同款连排；residential 合院簇/绿缓冲/背靠背巷排
#   import_qc——建筑链≤3 道具链≤2 间距≥1 退线1~3
# 遮挡关系（用户要求）：本层与玩家/NPC同为 z=2，递归 y-sort + 件底边锚
# （origin=底缘）→ 人在屋前压屋、人走到屋后被屋檐遮挡；建筑不再固定压在人物下方。
# 拼板整块铺（用户拍板）：仅晋昌坊 272×288（17×18 格恰入坊）；超宽拼板受街网格约束跳过。
# 素材库 pieces 为 gitignore 派生件：缺失整层跳过（克隆机自动回灰盒）。

const TextureGen = preload("res://scripts/texture_generator.gd")

const CAT_BY_BLOCK := {
	"banzheng": "01_民居坊", "huaiyuan": "01_民居坊", "yanshou": "01_民居坊",
	"tongji": "01_民居坊", "fengan": "01_民居坊", "changming": "01_民居坊",
	"yongxing": "02_官宅清流",
	"chongren": "03_贵戚府", "changshou": "03_贵戚府", "wuben": "03_贵戚府",
	"chongyi": "03_贵戚府", "shengye": "03_贵戚府",
	"yankang": "04_亲王公主府", "xuanyang": "04_亲王公主府",
	"huangcheng": "05_官署", "anyi": "05_官署",
	"gongcheng": "06_宫城", "donggong": "06_宫城",
	"daminggong": "06_宫城", "fanglin": "05_官署",
	"xiude": "07_寺观", "chongye": "07_寺观", "jingshan": "07_寺观", "jinchang": "07_寺观",
	"xishi": "08_市铺", "dongshi": "08_市铺",
	"pingkang": "08_市铺", "qujiang": "07_寺观",
}
# 有整块府邸（estate）的贵戚坊——estate 池按序分配，其余贵戚坊用 04 亲王门面件回退
const ESTATE_BLOCKS := ["yongxing", "chongren", "changshou", "wuben"]

var gen: Node2D = null
var lib := {}
var placed := 0
var rejected := 0
var shadow_count := 0
var collision_count := 0
var _tex := {}
var _pack_assets := {}
var _occ: Array = []   # 当前坊的占位矩形（px，世界坐标）


func setup(host: Node2D) -> void:
	gen = host
	z_index = 2                    # 与 Player/NPC 同层，交给递归 Y-sort 按脚底排序
	y_sort_enabled = true          # 遮挡关键：按 origin(=底缘) y 排序，南件压北件
	if not _load_manifest():
		return
	var t0 := Time.get_ticks_msec()
	_layout_outskirts()
	_layout_zhuque_axis()
	_layout_outer_wall_facade()
	_layout_city_gates()
	for b in gen.blocks:
		var cat: String = CAT_BY_BLOCK.get(String(b["id"]), "")
		if cat == "" or not lib.has(cat):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(b["id"]))
		var rect: Rect2i = gen._block_rect(b)
		_occ = []
		match String(b["kind"]):
			"residential": _layout_residential(cat, rect, rng, String(b["id"]))
			"noble": _layout_noble(rect, rng, String(b["id"]))
			"palace", "palace_east": _layout_palace(cat, rect)
			"office", "yamen": _layout_office(cat, rect, rng)
			"temple", "taoist": _layout_temple(cat, rect, rng, String(b["id"]))
			"market": _layout_market(cat, rect, rng)
			"military": _layout_military(cat, rect, rng)
			"venue": _layout_venue(cat, rect, rng)
			"royal_reserve", "reserve_empty": _layout_garden_reserve(cat, rect, rng, String(b["id"]))
		_fill_block_greenery(rect, rng, String(b["kind"]))
	print("[ChangAnV2材质] 建模 %d 件（阴影 %d / 建筑碰撞 %d / 占位拒入 %d）%dms" %
			[placed, shadow_count, collision_count, rejected, Time.get_ticks_msec() - t0])


# ---- 城市构图层：朱雀大街不是两侧坊的空隙，而是贯穿全城的礼制轴 ----
# 只使用用户已进件的 11_街饰过渡_12（小型灯柱），不写入碰撞、不占用道路中央两格；
# 成对、定距、确定性摆放让玩家沿轴移动时得到连续节奏，而非面对一条纯地砖走廊。
func _layout_zhuque_axis() -> void:
	var lamps := _pool("11_街饰过渡", 12, 20, 20, 30, "prop")
	if lamps.is_empty():
		return
	var lamp: Dictionary = lamps[0]
	var sx: int = gen.seam_x(gen.axis_col)
	for r in range(gen.rows):
		for yy in range(gen.row_y(r) + 4, gen.row_y(r) + gen.bh - 2, 8):
			_put_axis_prop("11_街饰过渡", lamp, Vector2i(sx + 1, yy))
			_put_axis_prop("11_街饰过渡", lamp, Vector2i(sx + gen.zq_s - 2, yy), true)


func _put_axis_prop(cat: String, p: Dictionary, cell: Vector2i, flip := false) -> void:
	var tex: Texture2D = _tex.get(p["file"])
	if tex == null:
		tex = TextureGen.load_png_texture("res://素材库/%s/%s" % [cat, p["file"]])
		if tex == null:
			return
		_tex[p["file"]] = tex
	var h_px := int(p["h"])
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.flip_h = flip
	sp.position = Vector2(cell.x * 16 + 8, (cell.y + 2) * 16)
	sp.offset = Vector2(0, -h_px / 2.0)
	add_child(sp)
	placed += 1


# ---- 外郭城墙完整立面：wall_run 自带垛口、灰砖墙身和石脚，整体重复而非分层贴条。----
func _layout_outer_wall_facade() -> void:
	if not _pack_assets.has("wall_run"):
		return
	var p: Dictionary = _pack_assets["wall_run"]
	var path := String(p["file"])
	var tex: Texture2D = TextureGen.load_png_texture(path)
	if tex == null:
		return
	_tex[path] = tex
	for side in ["N", "S"]:
		if not gen.gate_info.has(side):
			continue
		var cells: Array = gen.gate_info[side]["gap_cells"]
		var gate_cx := (float(cells[0].x + cells[cells.size() - 1].x) * 0.5 + 0.5) * 16.0
		var gate_name := "gate_tower_big" if side == "S" else "gate_tower_mid"
		var gate_half := 55.0
		if _pack_assets.has(gate_name):
			gate_half = float(_pack_assets[gate_name]["w"]) * 0.5
		var x_start := float(gen.margin * 16)
		var x_end := float((gen.W - gen.margin) * 16)
		var bottom := float((gen.margin + gen.wall) * 16 - 1) if side == "N" \
				else float((gen.H - gen.margin) * 16 - 1)
		# 从门楼边缘反向铺墙，把不可整除的余量赶到城角外侧；门墙接缝始终零缝。
		_spawn_wall_interval(tex, x_start, gate_cx - gate_half, bottom, side, true)
		_spawn_wall_interval(tex, gate_cx + gate_half, x_end, bottom, side, false)


func _spawn_wall_interval(tex: Texture2D, x0: float, x1: float, bottom: float, side: String,
		align_right: bool) -> void:
	var step := float(tex.get_width())
	var x := x1 if align_right else x0
	var index := 0
	while (x > x0 + 0.5) if align_right else (x < x1 - 0.5):
		if align_right:
			x -= step
		var sp := Sprite2D.new()
		sp.name = "OuterWall_%s_%02d" % [side, index]
		sp.texture = tex
		sp.position = Vector2(x + step * 0.5, bottom)
		sp.offset = Vector2(0, -tex.get_height() * 0.5)
		sp.set_meta("material_id", "wall_run")
		sp.add_to_group("changan_outer_wall_facade")
		add_child(sp)
		placed += 1
		if not align_right:
			x += step
		index += 1


# ---- 城外林带：让城墙落在环境中，而不是悬在纯绿色矩形上。----
func _layout_outskirts() -> void:
	var placements := [
		["tree_lush_a", Vector2i(18, 7)], ["tree_lush_b", Vector2i(42, 7)],
		["tree_big", Vector2i(66, 7)], ["tree_lush_a", Vector2i(106, 7)],
		["tree_lush_b", Vector2i(151, 7)],
		["tree_lush_b", Vector2i(24, gen.H - 2)], ["tree_big", Vector2i(54, gen.H - 2)],
		["tree_lush_a", Vector2i(114, gen.H - 2)], ["tree_lush_b", Vector2i(146, gen.H - 2)],
		["tree_lush_a", Vector2i(5, 35)], ["tree_big", Vector2i(5, 95)],
		["tree_lush_b", Vector2i(gen.W - 5, 28)], ["tree_lush_a", Vector2i(gen.W - 5, 102)],
	]
	for item in placements:
		_spawn_pack_free(String(item[0]), item[1])


func _spawn_pack_free(name: String, foot_cell: Vector2i) -> bool:
	if not _pack_assets.has(name):
		return false
	var p: Dictionary = _pack_assets[name]
	var path := String(p["file"])
	var tex: Texture2D = _tex.get(path)
	if tex == null:
		tex = TextureGen.load_png_texture(path)
		if tex == null:
			return false
		_tex[path] = tex
	var sp := Sprite2D.new()
	sp.name = "Outskirts_%s" % name
	sp.texture = tex
	sp.position = Vector2(foot_cell.x * 16.0 + 8.0, foot_cell.y * 16.0)
	sp.offset = Vector2(0, -tex.get_height() * 0.5)
	sp.set_meta("material_id", name)
	sp.add_to_group("changan_outskirts")
	var shadow := TextureGen.make_shadow_sprite(minf(72.0, tex.get_width() * 0.65), 0.20)
	shadow.name = "ContactShadow"
	shadow.position = sp.position + Vector2(0, -3)
	shadow.scale.y *= 0.48
	add_child(shadow)
	add_child(sp)
	shadow_count += 1
	placed += 1
	return true


# ---- 四门入口：南北门使用与墙带同模数的正面门楼；东西门使用侧向关口组合。----
# 位置只依赖 gate_info，不占门洞、不另加整块碰撞；实际阻挡由两侧墙带瓦片负责，
# 中央 48px 净宽可容玩家 24px 碰撞体通过。
func _layout_city_gates() -> void:
	var names := {
		"S": "gate_tower_big", "N": "gate_tower_mid",
	}
	for side in ["S", "N"]:
		if not gen.gate_info.has(side) or not _pack_assets.has(names[side]):
			continue
		var p: Dictionary = _pack_assets[names[side]]
		var path := String(p["file"])
		var tex: Texture2D = _tex.get(path)
		if tex == null:
			tex = TextureGen.load_png_texture(path)
			if tex == null:
				continue
			_tex[path] = tex
		var cells: Array = gen.gate_info[side]["gap_cells"]
		var c0: Vector2i = cells[0]
		var c1: Vector2i = cells[cells.size() - 1]
		var sp := Sprite2D.new()
		sp.name = "CityGate_%s" % side
		sp.texture = tex
		sp.set_meta("material_id", names[side])
		sp.add_to_group("changan_city_gate")
		var cx := (float(c0.x + c1.x) * 0.5 + 0.5) * 16.0
		var base_row: int = int(gen.H - gen.margin - 1 if side == "S" else gen.margin + 1)
		sp.position = Vector2(cx, (base_row + 1) * 16.0 - 1.0)
		sp.offset = Vector2(0, -tex.get_height() / 2.0)
		add_child(sp)
		placed += 1
	for side in ["E", "W"]:
		_layout_side_gate_checkpoint(side)


# 素材包没有真正的东西向城门/城墙透视件。旧版把正面门楼旋转 90°，瓦顶、
# 门洞与重力方向一起侧翻，视觉必然穿帮。本组合保留三格侧向通道，用原生朝向的
# 守望楼贴在关口北肩，城内侧以门灯和石兽标出门线；既不伪造侧门，也不挡横向通行。
func _layout_side_gate_checkpoint(side: String) -> void:
	if not gen.gate_info.has(side):
		return
	var cells: Array = gen.gate_info[side]["gap_cells"]
	var cy := (float(cells[0].y + cells[cells.size() - 1].y) * 0.5 + 0.5) * 16.0
	var wall_x := float((gen.W - gen.margin - gen.wall) * 16) if side == "E" \
			else float((gen.margin + gen.wall) * 16)
	var inward := -1.0 if side == "E" else 1.0
	var root := Node2D.new()
	root.name = "CityGate_%s" % side
	root.position = Vector2(wall_x, cy)
	root.y_sort_enabled = true
	root.set_meta("material_id", "side_gate_checkpoint")
	root.add_to_group("changan_city_gate")
	add_child(root)
	var tower := "bell_tower" if side == "E" else "drum_tower"
	_spawn_gate_piece(root, tower, Vector2(inward * 24.0, -32.0), side == "W")
	_spawn_gate_piece(root, "lamp_red", Vector2(inward * 34.0, -18.0))
	_spawn_gate_piece(root, "lamp_red2", Vector2(inward * 34.0, 72.0), true)
	_spawn_gate_piece(root, "lion_stone_a", Vector2(inward * 58.0, -18.0))
	_spawn_gate_piece(root, "lion_stone_b", Vector2(inward * 58.0, 64.0), true)


func _spawn_gate_piece(parent: Node2D, name: String, bottom: Vector2, flip := false) -> void:
	if not _pack_assets.has(name):
		return
	var p: Dictionary = _pack_assets[name]
	var path := String(p["file"])
	var tex: Texture2D = _tex.get(path)
	if tex == null:
		tex = TextureGen.load_png_texture(path)
		if tex == null:
			return
		_tex[path] = tex
	var sp := Sprite2D.new()
	sp.name = "GatePiece_%s" % name
	sp.texture = tex
	sp.flip_h = flip
	sp.position = bottom
	sp.offset = Vector2(0, -tex.get_height() * 0.5)
	sp.set_meta("material_id", name)
	parent.add_child(sp)
	placed += 1


func _load_manifest() -> bool:
	var f := FileAccess.open("res://data/material_library.json", FileAccess.READ)
	if f == null:
		print("[ChangAnV2材质] material_library.json 缺失——保持灰盒")
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed.has("categories"):
		return false
	for cat: String in parsed["categories"]:
		var arr: Array = []
		for p in parsed["categories"][cat]["pieces"]:
			var rec := {
				"id": String(p["id"]), "w": int(p["w"]), "h": int(p["h"]),
				"file": String(p["file"]), "cls": String(p["class"]),
			}
			if FileAccess.file_exists("res://素材库/%s/%s" % [cat, rec["file"]]):
				arr.append(rec)
		if not arr.is_empty():
			lib[cat] = arr
	if lib.is_empty():
		print("[ChangAnV2材质] 素材库 pieces 不在本机（gitignore 派生件）——保持灰盒")
		return false
	_load_pack_manifest()
	return true


# docs 全包经 import_sckr_changan.py 入库的语义清单；只读取已登记名字，
# 不在生成器里临时裁像素窗口。用于补充用户精选板里缺少的树、水岸桥和船。
func _load_pack_manifest() -> void:
	var f := FileAccess.open("res://data/sckr_manifest.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed.has("assets"):
		return
	for p in parsed["assets"]:
		if not p.has("name") or not p.has("box") or p["box"].size() < 4:
			continue
		var name := String(p["name"])
		var kind := String(p.get("kind", "prop"))
		var root := "res://sprites/tiles_changan_sckr/" if kind == "tile" else "res://sprites/changan_props_sckr/"
		var path := root + name + ".png"
		if FileAccess.file_exists(path):
			_pack_assets[name] = {
				"file": path, "w": int(p["box"][2]) - int(p["box"][0]),
				"h": int(p["box"][3]) - int(p["box"][1]), "kind": kind,
			}


# ---- 件池：按尺寸/类别筛 ----
func _pool(cat: String, min_w: int, max_w: int, min_h: int, max_h: int, cls := "unit") -> Array:
	var out: Array = []
	for p in lib.get(cat, []):
		if p["cls"] == cls and p["w"] >= min_w and p["w"] <= max_w \
				and p["h"] >= min_h and p["h"] <= max_h:
			out.append(p)
	return out


func _pick(pool: Array, rng: RandomNumberGenerator, avoid: String = "") -> Dictionary:
	if pool.is_empty():
		return {}
	for _i in range(4):
		var p: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if String(p["id"]) != avoid:
			return p
	return pool[0]


# ---- 摆件（合理性核心）：cell=左上格，底缘贴 anchor_bottom_row 下缘；
# ---- 占位矩形（件实际像素 bbox）与已放件相交即拒（零穿模），越界/退线不足亦拒 ----
func _put(cat: String, p: Dictionary, cell: Vector2i, bottom_row: int, rect: Rect2i,
		flip := false) -> bool:
	if p.is_empty():
		return false
	var w_px := int(p["w"])
	var h_px := int(p["h"])
	var px := Rect2(cell.x * 16.0, (bottom_row + 1) * 16.0 - h_px, w_px, h_px)
	if px.position.x < (rect.position.x + 1) * 16.0 \
			or px.position.y < rect.position.y * 16.0 \
			or px.end.x > (rect.position.x + rect.size.x) * 16.0 \
			or px.end.y > (rect.position.y + rect.size.y) * 16.0:
		rejected += 1
		return false
	for r in _occ:
		if px.intersects(r):
			rejected += 1
			return false
	var tex: Texture2D = _tex.get(p["file"])
	if tex == null:
		tex = TextureGen.load_png_texture("res://素材库/%s/%s" % [cat, p["file"]])
		if tex == null:
			rejected += 1
			return false
		_tex[p["file"]] = tex
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = true
	sp.flip_h = flip
	# 底边锚 + y-sort：origin 放在件底缘中心，画面向上展开；南件 origin 大 → 压住北件
	sp.position = Vector2(px.position.x + w_px / 2.0, px.end.y)
	sp.offset = Vector2(0, -h_px / 2.0)
	sp.set_meta("material_id", String(p["id"]))
	sp.set_meta("foot_y", px.end.y)
	_add_contact_shadow(px, String(p["cls"]))
	add_child(sp)
	_add_building_collision(px, p, cat)
	_occ.append(px)
	placed += 1
	return true


# ---- 接地阴影：只给建筑/合院加低矮软影；摊位与灯具保持原贴图自己的投影 ----
func _add_contact_shadow(px: Rect2, cls: String) -> void:
	if cls != "unit" and cls != "estate" and cls != "scene_board":
		return
	var width := clampf(px.size.x * 0.72, 32.0, 132.0)
	var shadow := TextureGen.make_shadow_sprite(width, 0.18 if cls == "unit" else 0.14)
	shadow.name = "ContactShadow"
	shadow.position = Vector2(px.get_center().x, px.end.y - 4.0)
	shadow.scale.y *= 0.42
	add_child(shadow)
	shadow_count += 1


# ---- 建筑物理脚印：单位建筑阻挡墙脚，整院采用四边围合且南侧留 32px 门洞 ----
# collision_layer=1 与 Player/NPC 既有 mask 对齐；只做脚印，不用整张 sprite bbox
# 封死院落。宫门/牌楼是通行构件，保持无碰撞以保中轴门洞。
func _add_building_collision(px: Rect2, p: Dictionary, cat: String) -> void:
	var cls := String(p["cls"])
	if cls != "unit" and cls != "estate" and cls != "scene_board":
		return
	if cat == "06_宫城":
		return
	var body := StaticBody2D.new()
	body.name = "BuildingCollision_%d" % collision_count
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("changan_building_collision")
	if cls == "estate" or cls == "scene_board":
		var edge := 10.0
		var gate := minf(40.0, px.size.x * 0.25)
		var side_h := maxf(24.0, px.size.y * 0.62)
		var side_y := px.end.y - side_h * 0.5
		_add_collision_rect(body, Vector2(px.position.x + edge * 0.5, side_y), Vector2(edge, side_h))
		_add_collision_rect(body, Vector2(px.end.x - edge * 0.5, side_y), Vector2(edge, side_h))
		_add_collision_rect(body, Vector2(px.get_center().x, px.position.y + px.size.y * 0.30),
				Vector2(maxf(24.0, px.size.x - edge * 2.0), 12.0))
		var wing_w := maxf(12.0, (px.size.x - gate) * 0.5)
		_add_collision_rect(body, Vector2(px.position.x + wing_w * 0.5, px.end.y - edge * 0.5),
				Vector2(wing_w, edge))
		_add_collision_rect(body, Vector2(px.end.x - wing_w * 0.5, px.end.y - edge * 0.5),
				Vector2(wing_w, edge))
	else:
		var foot_w := clampf(px.size.x * 0.68, 28.0, maxf(28.0, px.size.x - 12.0))
		_add_collision_rect(body, Vector2(px.get_center().x, px.end.y - 6.0), Vector2(foot_w, 12.0))
	add_child(body)
	collision_count += 1


func _add_collision_rect(body: StaticBody2D, center: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.position = center
	cs.shape = shape
	body.add_child(cs)


func _try_tree(rect: Rect2i, cell: Vector2i, rng: RandomNumberGenerator, bottom_off := 5) -> void:
	var tree_names := ["tree_lush_a", "tree_lush_b", "tree_big"]
	var name: String = tree_names[rng.randi_range(0, tree_names.size() - 1)]
	if not _put_pack_prop(name, cell, cell.y + bottom_off, rect):
		_put("11_街饰过渡", _pick(_pool("11_街饰过渡", 32, 52, 38, 70, "prop"), rng),
				cell, cell.y + bottom_off, rect)


func _put_pack_prop(name: String, cell: Vector2i, bottom_row: int, rect: Rect2i,
		flip := false, scale := 1.0) -> bool:
	if not _pack_assets.has(name):
		return false
	var p: Dictionary = _pack_assets[name]
	var w_px := float(p["w"]) * scale
	var h_px := float(p["h"]) * scale
	var px := Rect2(cell.x * 16.0, (bottom_row + 1) * 16.0 - h_px, w_px, h_px)
	if px.position.x < (rect.position.x + 1) * 16.0 or px.position.y < rect.position.y * 16.0 \
			or px.end.x > (rect.position.x + rect.size.x) * 16.0 \
			or px.end.y > (rect.position.y + rect.size.y) * 16.0:
		rejected += 1
		return false
	for occupied in _occ:
		if px.intersects(occupied):
			rejected += 1
			return false
	var path := String(p["file"])
	var tex: Texture2D = _tex.get(path)
	if tex == null:
		tex = TextureGen.load_png_texture(path)
		if tex == null:
			return false
		_tex[path] = tex
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.flip_h = flip
	sp.scale = Vector2(scale, scale)
	sp.position = Vector2(px.get_center().x, px.end.y)
	sp.offset = Vector2(0, -float(p["h"]) / 2.0)
	sp.set_meta("material_id", name)
	sp.set_meta("foot_y", px.end.y)
	if name.begins_with("tree_"):
		var shadow := TextureGen.make_shadow_sprite(minf(72.0, w_px * 0.65), 0.22)
		shadow.position = Vector2(px.get_center().x, px.end.y - 3.0)
		shadow.scale.y *= 0.48
		add_child(shadow)
		shadow_count += 1
	add_child(sp)
	if name.begins_with("tree_"):
		var body := StaticBody2D.new()
		body.name = "TreeCollision_%d" % collision_count
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("changan_building_collision")
		_add_collision_rect(body, Vector2(px.get_center().x, px.end.y - 6.0), Vector2(14, 12))
		add_child(body)
		collision_count += 1
	_occ.append(px)
	placed += 1
	return true


# 坊内庭树补位：组件摆完后只在真实空角尝试，最多补 1~2 棵，形成前/中/后景。
func _fill_block_greenery(rect: Rect2i, rng: RandomNumberGenerator, kind: String) -> void:
	if kind in ["market", "venue", "office", "yamen", "military", "palace", "palace_east"]:
		return
	var target := 2 if kind in ["temple", "taoist", "royal_reserve", "reserve_empty"] else 1
	var candidates := [Vector2i(1, 1), Vector2i(13, 1), Vector2i(1, 13), Vector2i(13, 13),
			Vector2i(7, 1), Vector2i(7, 13)]
	var start := rng.randi_range(0, candidates.size() - 1)
	var added := 0
	for i in range(candidates.size()):
		var off: Vector2i = candidates[(start + i) % candidates.size()]
		var name := "tree_lush_a" if (i + start) % 2 == 0 else "tree_lush_b"
		if _put_pack_prop(name, rect.position + off, rect.position.y + off.y + 5, rect):
			added += 1
			if added >= target:
				break


# ---- residential：两版式轮换（背靠背巷排 / 合院簇），绿缓冲补角 ----
func _layout_residential(cat: String, rect: Rect2i, rng: RandomNumberGenerator, id: String):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var small := _pool(cat, 80, 110, 80, 110)
	var estate := _pool(cat, 140, 200, 140, 200, "estate")
	var tall := _pool(cat, 80, 110, 150, 180)
	if not estate.is_empty() and hash(id) % 2 == 0:
		_put(cat, estate[rng.randi_range(0, estate.size() - 1)],
				Vector2i(x0 + 4, y0 + 1), y0 + 12, rect)
		# 后院大合院 + 南侧临街双门面，建立“后院—巷—前店”的纵深关系。
		if not small.is_empty():
			_put(cat, _pick(small, rng), Vector2i(x0 + 1, y0 + 13), y0 + 18, rect)
			_put(cat, _pick(small, rng), Vector2i(x0 + 13, y0 + 13), y0 + 18, rect, true)
		_try_tree(rect, Vector2i(x0 + 1, y0 + 3), rng)
		_try_tree(rect, Vector2i(x0 + 16, y0 + 14), rng)
	elif not tall.is_empty() and posmod(hash(id), 3) == 1:
		# 一座二层街楼压住坊心天际线，南侧三开间连续门面承接人流。
		_put(cat, _pick(tall, rng), Vector2i(x0 + 7, y0 + 1), y0 + 11, rect)
		for xx in [x0 + 1, x0 + 7, x0 + 13]:
			_put(cat, _pick(small, rng), Vector2i(xx, y0 + 13), y0 + 18, rect,
					xx == x0 + 7)
		_try_tree(rect, Vector2i(x0 + 1, y0 + 4), rng)
		_try_tree(rect, Vector2i(x0 + 16, y0 + 4), rng)
	else:
		# 两条连续街面各三开间，北排略退、南排贴街；六栋形成真正的坊巷界面。
		var last := ""
		for row in [[y0 + 2, y0 + 7, false], [y0 + 13, y0 + 18, true]]:
			for xx in [x0 + 1, x0 + 7, x0 + 13]:
				var s := _pick(small, rng, last)
				last = String(s.get("id", ""))
				_put(cat, s, Vector2i(xx, int(row[0])), int(row[1]), rect,
						bool(row[2]) != (xx == x0 + 7))


# ---- noble：estate 坊=府邸居北+前庭；其余用 04 亲王门面件（南北两排+中庭）----
func _layout_noble(rect: Rect2i, rng: RandomNumberGenerator, id: String):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var cat := String(CAT_BY_BLOCK.get(id, ""))
	if ESTATE_BLOCKS.has(id):
		var pool := _pool(cat, 140, 200, 140, 200, "estate")
		var idx := ESTATE_BLOCKS.find(id)
		if not pool.is_empty():
			_put(cat, pool[idx % pool.size()], Vector2i(x0 + 4, y0 + 1), y0 + 12, rect)
			# 前庭两翼石狮/灯笼架（各一，道具链=1）
			var flank := _pool("11_街饰过渡", 28, 50, 38, 55, "prop")
			if flank.size() >= 2:
				_put("11_街饰过渡", flank[0], Vector2i(x0 + 1, y0 + 16), y0 + 18, rect)
				_put("11_街饰过渡", flank[1], Vector2i(x0 + 16, y0 + 16), y0 + 18, rect, true)
			_try_tree(rect, Vector2i(x0 + 16, y0 + 1), rng)
			return
	# 04 门面件坊（yankang/xuanyang/贵戚回退）：南门面排 + 北楼阁排 + 中庭开放
	var units := _pool("04_亲王公主府", 80, 110, 80, 110)
	if units.size() >= 2:
		_put("04_亲王公主府", units[0], Vector2i(x0 + 1, y0 + 13), y0 + 18, rect)
		_put("04_亲王公主府", units[1 % units.size()], Vector2i(x0 + 8, y0 + 13), y0 + 18, rect, true)
		_put("04_亲王公主府", units[0], Vector2i(x0 + 1, y0 + 2), y0 + 7, rect, true)
		_put("04_亲王公主府", units[1 % units.size()], Vector2i(x0 + 8, y0 + 2), y0 + 7, rect)
	_try_tree(rect, Vector2i(x0 + 16, y0 + 2), rng)
	_put("11_街饰过渡", _pick(_pool("11_街饰过渡", 30, 50, 24, 38, "prop"), rng),
			Vector2i(x0 + 15, y0 + 15), y0 + 18, rect)


# ---- palace：中轴（门楼→大前庭→大殿）+ 像素级对称配殿（左右同款镜像）----
func _layout_palace(cat: String, rect: Rect2i):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var w_px := rect.size.x * 16
	var cx_cell := x0 + rect.size.x / 2
	var gate := _pool(cat, 130, 150, 85, 100)
	var pav := _pool(cat, 80, 110, 80, 100)
	if gate.is_empty():
		return
	# 三进中轴：南门—中殿—北殿，逐排换型；大宫城每进再配左右殿，形成天际线级差。
	var rows := [y0 + 6, y0 + 12, y0 + 18]
	for ri in range(rows.size()):
		var main: Dictionary = gate[ri % gate.size()]
		var main_cells := int(ceil(float(main["w"]) / 16.0))
		_put(cat, main, Vector2i(cx_cell - main_cells / 2, rows[ri] - 5), rows[ri], rect,
				ri == 1)
		if rect.size.x >= 40 and not pav.is_empty():
			var wing: Dictionary = pav[ri % pav.size()]
			var wing_cells := int(ceil(float(wing["w"]) / 16.0))
			_put(cat, wing, Vector2i(x0 + 4, rows[ri] - 5), rows[ri], rect)
			_put(cat, wing, Vector2i(rect.end.x - 4 - wing_cells, rows[ri] - 5), rows[ri], rect, true)


# ---- office/yamen：临街门面排 + 中央开放；步进留白+树打破机械连排 ----
func _layout_office(cat: String, rect: Rect2i, rng: RandomNumberGenerator):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var w := rect.size.x
	# 皇城横跨两坊：优先采用清流官宅的完整连续院落带，形成统一天际线与院墙，
	# 不再把两三个 96px 官署件均匀撒在 704px 大地坪上。
	if rect.size.x >= 40:
		var compounds := _pool("02_官宅清流", 450, 500, 180, 210, "scene_board")
		if not compounds.is_empty() and _put("02_官宅清流", compounds[0],
				Vector2i(x0 + 7, y0 + 4), y0 + 17, rect):
			return
	var units := _pool(cat, 75, 110, 80, 110)
	if units.is_empty():
		return
	var i := 0
	var xx := x0 + 3
	var flip := false
	while xx + 6 <= x0 + w - 3:
		if i % 3 == 2:
			_try_tree(rect, Vector2i(xx + 1, y0 + 3), rng)   # 每 3 位插树破连排
		else:
			_put(cat, units[i % units.size()], Vector2i(xx, y0 + 2), y0 + 7, rect, flip)
		i += 1
		flip = not flip
		xx += 7
	xx = x0 + 6
	flip = true
	while xx + 6 <= x0 + w - 3:
		_put(cat, units[i % units.size()], Vector2i(xx, y0 + 13), y0 + 18, rect, flip)
		i += 1
		flip = not flip
		xx += 9


# ---- temple：山门→庭→殿→塔 纵序（塔限高防压殿）+ 四角绿化簇 ----
func _layout_temple(cat: String, rect: Rect2i, rng: RandomNumberGenerator, id: String):
	var x0 := rect.position.x
	var y0 := rect.position.y
	if id == "jinchang":
		# 拼板整块铺（用户拍板）：272×288=17×18 格恰入坊内
		for p in lib[cat]:
			if int(p["w"]) >= 260 and int(p["w"]) <= 280 and int(p["h"]) >= 270:
				_put(cat, p, Vector2i(x0 + 1, y0 + 1), y0 + 18, rect)
				break
		return
	var gate := _pool(cat, 75, 110, 85, 100)       # 牌坊/山门
	var hall := _pool(cat, 75, 110, 80, 100)       # 殿
	var pagoda := _pool(cat, 30, 70, 85, 120)      # 塔（限高 120px 防压殿）
	if not gate.is_empty():
		_put(cat, gate[0], Vector2i(x0 + 7, y0 + 13), y0 + 18, rect)
	if not hall.is_empty():
		_put(cat, hall[hall.size() - 1], Vector2i(x0 + 7, y0 + 5), y0 + 10, rect)
	if not pagoda.is_empty():
		var t: Dictionary = pagoda[rng.randi_range(0, pagoda.size() - 1)]
		var tw := (int(t["w"]) + 15) / 16
		_put(cat, t, Vector2i(x0 + 10 - tw / 2, y0 + 1), y0 + 6, rect, rng.randf() < 0.5)
	for c in [Vector2i(x0 + 1, y0 + 2), Vector2i(x0 + 16, y0 + 2),
			Vector2i(x0 + 1, y0 + 15), Vector2i(x0 + 16, y0 + 15)]:
		_try_tree(rect, c, rng)


# ---- market：双侧连续店面 + 中央摊位带 ----
# 两市是全城最密的“街道界面”：建筑沿北/南边连续排布，中央留作可读的
# 集市带。避免旧版“4 间店铺漂在一大片地砖上”的素材陈列感。
func _layout_market(cat: String, rect: Rect2i, rng: RandomNumberGenerator):
	var x0 := rect.position.x
	var y0 := rect.position.y
	# 一座双开间大铺 + 一座单开间门面组成每条街面，南北错位，避免六个小方块陈列感。
	var shops := _pool(cat, 75, 100, 60, 100)
	var wide_shops := _pool(cat, 150, 195, 75, 100)
	var last := ""
	if not wide_shops.is_empty():
		var north_wide := _pick(wide_shops, rng)
		_put(cat, north_wide, Vector2i(x0 + 1, y0 + 2), y0 + 7, rect)
		_put(cat, _pick(shops, rng), Vector2i(x0 + 13, y0 + 2), y0 + 7, rect, true)
		_put(cat, _pick(shops, rng), Vector2i(x0 + 1, y0 + 13), y0 + 18, rect)
		_put(cat, _pick(wide_shops, rng, String(north_wide["id"])),
				Vector2i(x0 + 7, y0 + 13), y0 + 18, rect, true)
	else:
		for row in [[y0 + 2, y0 + 7], [y0 + 13, y0 + 18]]:
			for xx in [x0 + 1, x0 + 7, x0 + 13]:
				var shop := _pick(shops, rng, last)
				last = String(shop.get("id", ""))
				_put(cat, shop, Vector2i(xx, int(row[0])), int(row[1]), rect)
	# 中央摊位带 y+9..12：小件横向错开，保持东/西两端进出集市的视觉开口。
	var stalls := _pool("11_街饰过渡", 36, 50, 40, 56, "prop")
	last = ""
	for c in [Vector2i(x0 + 1, y0 + 10), Vector2i(x0 + 4, y0 + 10),
			Vector2i(x0 + 7, y0 + 10), Vector2i(x0 + 10, y0 + 10),
			Vector2i(x0 + 13, y0 + 10), Vector2i(x0 + 16, y0 + 10)]:
		if not stalls.is_empty():
			var st: Dictionary = _pick(stalls, rng, last)
			last = String(st["id"])
			_put("11_街饰过渡", st, c, c.y + 2, rect)
	# 入口两角只放低矮挂件，避免树冠遮住店招和市场动线。
	_put("11_街饰过渡", _pick(_pool("11_街饰过渡", 12, 20, 20, 30, "prop"), rng),
			Vector2i(x0 + 18, y0 + 9), y0 + 10, rect)


# ---- military：北署南营围合训练场，中央保持可走 ----
func _layout_military(cat: String, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var units := _pool(cat, 75, 110, 80, 110)
	if units.is_empty():
		return
	for entry in [[Vector2i(x0 + 4, y0 + 2), y0 + 7, false],
			[Vector2i(x0 + 10, y0 + 2), y0 + 7, true],
			[Vector2i(x0 + 4, y0 + 13), y0 + 18, true],
			[Vector2i(x0 + 10, y0 + 13), y0 + 18, false]]:
		_put(cat, _pick(units, rng), entry[0], entry[1], rect, entry[2])
	var props := _pool("11_街饰过渡", 30, 52, 24, 48, "prop")
	for cell in [Vector2i(x0 + 2, y0 + 10), Vector2i(x0 + 8, y0 + 10),
			Vector2i(x0 + 14, y0 + 10)]:
		_put("11_街饰过渡", _pick(props, rng), cell, cell.y + 2, rect)


# ---- venue：一座主楼 + 南侧连续门面 + 灯笼摊排，形成平康坊夜市界面 ----
func _layout_venue(cat: String, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var wide := _pool(cat, 150, 200, 80, 110)
	var shops := _pool(cat, 75, 100, 60, 100)
	if not wide.is_empty():
		_put(cat, _pick(wide, rng), Vector2i(x0 + 4, y0 + 2), y0 + 7, rect)
	for xx in [x0 + 1, x0 + 7, x0 + 13]:
		_put(cat, _pick(shops, rng), Vector2i(xx, y0 + 13), y0 + 18, rect, xx == x0 + 7)
	var stalls := _pool("11_街饰过渡", 32, 50, 32, 56, "prop")
	for cell in [Vector2i(x0 + 3, y0 + 9), Vector2i(x0 + 8, y0 + 10),
			Vector2i(x0 + 13, y0 + 9)]:
		_put("11_街饰过渡", _pick(stalls, rng), cell, cell.y + 2, rect)


# ---- reserve/garden：概念图目标下不再保留整坊裸草，先用现有亭塔形成园林组团 ----
func _layout_garden_reserve(cat: String, rect: Rect2i, rng: RandomNumberGenerator, id: String) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var units := _pool(cat, 60, 110, 75, 110)
	if units.is_empty():
		return
	if id == "qujiang":
		# 左半坊为水面，桥面底下已由生成器铺可走带；右半坊布亭塔与树。
		_put_pack_prop("boat_small", Vector2i(x0 + 2, y0 + 3), y0 + 6, rect)
		_put_pack_prop("bridge_arch_stone_deck", Vector2i(x0 + 1, y0 + 7), y0 + 11, rect)
		_put(cat, _pick(units, rng), Vector2i(x0 + 12, y0 + 2), y0 + 7, rect)
		_put(cat, _pick(units, rng), Vector2i(x0 + 12, y0 + 13), y0 + 18, rect, true)
		_try_tree(rect, Vector2i(x0 + 10, y0 + 2), rng)
		_try_tree(rect, Vector2i(x0 + 10, y0 + 14), rng)
		return
	for entry in [[Vector2i(x0 + 2, y0 + 2), y0 + 7, false],
			[Vector2i(x0 + 12, y0 + 2), y0 + 7, true],
			[Vector2i(x0 + 2, y0 + 13), y0 + 18, true],
			[Vector2i(x0 + 12, y0 + 13), y0 + 18, false]]:
		_put(cat, _pick(units, rng), entry[0], entry[1], rect, entry[2])
	var low_props := _pool("11_街饰过渡", 24, 52, 24, 48, "prop")
	for cell in [Vector2i(x0 + 7, y0 + 9), Vector2i(x0 + 12, y0 + 10)]:
		_put("11_街饰过渡", _pick(low_props, rng), cell, cell.y + 2, rect)
