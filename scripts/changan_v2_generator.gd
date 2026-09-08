extends Node2D
# 长安城 v2·剧情尺度灰盒生成器 —— docs/长安城v2-剧情尺度规划.md（v2.1 五项拍板）
# 灰盒=文字占位：道路/城墙/城门真实可走（碰撞+BFS），街区只铺地坪+世界空间文字标签
# 用户 Tiled 材质做好后按 JSON 格位对应导入（换皮不换结构：blocks 的 col/row/span 即格位契约）
# 城市接口与 v1 对齐：generation_done/exit_requested/gate_info/find_clear_spawn/cell_to_px/W/H/stats

signal generation_done
signal exit_requested(gate_id: String)   # 玩家触碰城门出城触发区（city_visit 接管回开放世界）
signal interior_requested(ref: String)   # 接口兼容声明（灰盒无内景，永不发射）

const TilesetGen = preload("res://scripts/tileset_generator.gd")

# ---- 瓦片 ID（复用现有注册表；材质后期整体替换，ID 语义不变）----
const T_GRASS = 0        # 城外/预留空地
const T_GATE_OPEN = 67   # 城门豁口（无碰撞）
const T_ZHUQUE = 71      # 朱雀大街御道
const T_MAIN_ROAD = 72   # 主干街/环城街
const T_LANE = 74        # 街区夯土地坪
const T_PAVE = 101       # 方砖（宫/皇/市/县署）
const T_OUTER_WALL = 70  # 外郭城墙（带碰撞）

const COLLIDING := [70]

# ---- 文字占位配色（按 kind；同色=同视觉等级，用户选材质时对照）----
const KIND_COLORS := {
	"palace": Color(1.0, 0.82, 0.40), "palace_east": Color(0.95, 0.72, 0.35),
	"royal_reserve": Color(0.60, 0.60, 0.60), "military": Color(0.85, 0.48, 0.42),
	"taoist": Color(0.79, 0.63, 0.86), "temple": Color(0.79, 0.63, 0.86),
	"office": Color(0.91, 0.76, 0.42), "yamen": Color(0.91, 0.76, 0.42),
	"noble": Color(0.54, 0.72, 0.91), "venue": Color(0.95, 0.63, 0.75),
	"market": Color(0.50, 0.85, 0.54), "residential": Color(0.96, 0.96, 0.96),
	"reserve_empty": Color(0.60, 0.60, 0.60),
}
# 方砖地面（其余街区=T_LANE 夯土，预留类=草）
const KIND_PAVE := ["palace", "palace_east", "office", "market", "yamen"]

# ---- 网格参数（JSON 解析后类型化）----
var bw := 20
var bh := 20
var main_s := 4
var zq_s := 6
var ring := 3
var wall := 2
var margin := 8
var cols := 6
var rows := 5
var axis_col := 3

var blocks: Array = []
var W := 0
var H := 0
var ground: PackedByteArray
var decor: PackedByteArray
var done := false
var stats := {}
var bfs_failures: Array = []
var tile_map: TileMap = null
var labels_node: Node2D = null
var label_count := 0
var gate_info := {}   # side -> {name, gap_cells, inside}
var portals_node: Node2D = null


func _ready():
	y_sort_enabled = true   # 与 World 递归 y-sort 对齐
	if _load_data():
		_build()


func _load_data() -> bool:
	var f = FileAccess.open("res://data/changan_city_v2.json", FileAccess.READ)
	if f == null:
		push_error("[ChangAnV2] data/changan_city_v2.json 缺失")
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("[ChangAnV2] changan_city_v2.json 解析失败")
		return false
	var g: Dictionary = parsed["grid"]
	bw = int(g["block"][0])
	bh = int(g["block"][1])
	main_s = int(g["street"]["main"])
	zq_s = int(g["street"]["zhunque"])
	ring = int(g["street"]["ring"])
	wall = int(g["wall"])
	margin = int(g["margin"])
	cols = int(g["cols"])
	rows = int(g["rows"])
	axis_col = int(g["axis_col"])
	blocks = parsed["blocks"]
	# W/H 公式与 v1 同构：margin*2+wall*2+ring*2+街区+街缝（朱雀加宽补 zq-main 一次）
	W = margin * 2 + wall * 2 + ring * 2 + cols * bw + (cols - 1) * main_s + (zq_s - main_s)
	H = margin * 2 + wall * 2 + ring * 2 + rows * bh + (rows - 1) * main_s
	return true


func _origin() -> Vector2i:
	return Vector2i(margin + wall + ring, margin + wall + ring)


func col_x(c: int) -> int:
	return _origin().x + c * (bw + main_s) + (zq_s - main_s if c >= axis_col else 0)


func row_y(r: int) -> int:
	return _origin().y + r * (bh + main_s)


func seam_x(i: int) -> int:
	# 第 i 条纵缝起始 x（i=1..cols-1；i==axis_col 为朱雀大街缝）
	return col_x(i) - (zq_s if i == axis_col else main_s)


func seam_y(j: int) -> int:
	return row_y(j) - main_s


func block_span_x() -> int:
	return col_x(cols - 1) + bw - _origin().x


func block_span_y() -> int:
	return row_y(rows - 1) + bh - _origin().y


func _build():
	var t0 := Time.get_ticks_msec()
	_paint_layout()
	var painted := _fill_tilemap()
	_spawn_labels()
	_build_portals()
	_run_bfs()
	var ms := Time.get_ticks_msec() - t0
	stats = {
		"size": "%dx%d" % [W, H], "ms": ms, "blocks": blocks.size(),
		"labels": label_count, "bfs_fail": bfs_failures.size(), "gates": gate_info.size(),
		"ground_cells": painted[0], "decor_cells": painted[1],
	}
	print("[ChangAnV2] %s 生成 %dms 街区=%d 标签=%d 城门=%d BFS未达=%d" %
			[stats["size"], ms, blocks.size(), label_count, gate_info.size(), bfs_failures.size()])
	done = true
	generation_done.emit()


func _paint_layout():
	ground = PackedByteArray()
	ground.resize(W * H)   # 默认 0=草（城外 margin/预留空地）
	decor = PackedByteArray()
	decor.resize(W * H)
	# 环城街（贴城墙内侧，宽 ring）
	var m := margin + wall
	_set_rect(ground, m, m, W - m * 2, ring, T_MAIN_ROAD)
	_set_rect(ground, m, H - m - ring, W - m * 2, ring, T_MAIN_ROAD)
	_set_rect(ground, m, m, ring, H - m * 2, T_MAIN_ROAD)
	_set_rect(ground, W - m - ring, m, ring, H - m * 2, T_MAIN_ROAD)
	# 横向街缝先铺（j=2 东西贯通=金光门·春明门大街；j=4 城南横街）——
	# 先横后纵：朱雀御道最后压上，连续穿过所有路口不被横街盖断
	for j in range(1, rows):
		_set_rect(ground, _origin().x, seam_y(j), block_span_x(), main_s, T_MAIN_ROAD)
	# 纵向街缝：axis_col=朱雀大街（中轴 3 宽御道+两翼夯土），其余主干 4 宽
	for i in range(1, cols):
		if i == axis_col:
			_set_rect(ground, seam_x(i), _origin().y, zq_s, block_span_y(), T_MAIN_ROAD)
			_set_rect(ground, seam_x(i) + zq_s / 2 - 1, _origin().y, 3, block_span_y(), T_ZHUQUE)
		else:
			_set_rect(ground, seam_x(i), _origin().y, main_s, block_span_y(), T_MAIN_ROAD)
	# 街区地坪（合并格吸收缝：宫城/皇城跨朱雀轴，朱雀大街止于皇城南缘）
	for b in blocks:
		var rect := _block_rect(b)
		var kind := String(b["kind"])
		if kind == "royal_reserve" or kind == "reserve_empty":
			continue   # 预留地保持草地
		var tile := T_PAVE if KIND_PAVE.has(kind) else T_LANE
		_set_rect(ground, rect.position.x, rect.position.y, rect.size.x, rect.size.y, tile)
	# 外郭城墙（厚 wall 的 70 环）+ 四城门豁口
	_paint_walls()
	_carve_gates()


func _block_rect(b: Dictionary) -> Rect2i:
	var c := int(b["col"])
	var r := int(b["row"])
	var sx := 1
	var sy := 1
	if b.has("span"):
		sx = int(b["span"][0])
		sy = int(b["span"][1])
	var x0 := col_x(c)
	var y0 := row_y(r)
	return Rect2i(x0, y0, col_x(c + sx - 1) + bw - x0, row_y(r + sy - 1) + bh - y0)


func _paint_walls():
	_set_rect(decor, margin, margin, W - margin * 2, wall, T_OUTER_WALL)
	_set_rect(decor, margin, H - margin - wall, W - margin * 2, wall, T_OUTER_WALL)
	_set_rect(decor, margin, margin, wall, H - margin * 2, T_OUTER_WALL)
	_set_rect(decor, W - margin - wall, margin, wall, H - margin * 2, T_OUTER_WALL)


# 城门对齐：S=朱雀轴心；N=东纵街(col4|col5缝)；E/W=金光春明大街(row1|row2缝)
func _carve_gates():
	var zgates: Dictionary = _load_gate_names()
	# S 明德门：朱雀缝中心（豁口恰与中轴 3 宽御道对齐）
	_carve_gate_ns("S", String(zgates["S"]), seam_x(axis_col) + zq_s / 2)
	# N 玄武门：东纵缝中心（凯旋动线）
	_carve_gate_ns("N", String(zgates["N"]), seam_x(cols - 1) + main_s / 2)
	# E/W 春明门·开远门：row1|row2 缝中心
	var cy := seam_y(2) + main_s / 2
	_carve_gate_ew("E", String(zgates["E"]), cy)
	_carve_gate_ew("W", String(zgates["W"]), cy)


func _load_gate_names() -> Dictionary:
	var f = FileAccess.open("res://data/changan_city_v2.json", FileAccess.READ)
	if f == null:
		return {"S": "明德门", "N": "玄武门", "E": "春明门", "W": "开远门"}
	var parsed = JSON.parse_string(f.get_as_text())
	var out := {}
	for side in ["S", "N", "E", "W"]:
		out[side] = String(parsed["gates"][side]["name"])
	return out


func _carve_gate_ns(side: String, gname: String, cx: int):
	var y_wall := H - margin - wall if side == "S" else margin
	_set_rect(decor, cx - 1, y_wall, 3, wall, T_GATE_OPEN)
	_set_rect(ground, cx - 1, y_wall - 1, 3, wall + 2, T_MAIN_ROAD)   # 门下+贴邻铺路
	var inside := Vector2i(cx, H - margin - wall - 2 if side == "S" else margin + wall + 2)
	var gaps: Array = []
	for i in range(-1, 2):
		gaps.append(Vector2i(cx + i, y_wall + wall / 2))
	gate_info[side] = {"name": gname, "gap_cells": gaps, "inside": inside}


func _carve_gate_ew(side: String, gname: String, cy: int):
	var x_wall := W - margin - wall if side == "E" else margin
	_set_rect(decor, x_wall, cy - 1, wall, 3, T_GATE_OPEN)
	_set_rect(ground, x_wall - 1, cy - 1, wall + 2, 3, T_MAIN_ROAD)
	var inside := Vector2i(W - margin - wall - 2 if side == "E" else margin + wall + 2, cy)
	var gaps: Array = []
	for i in range(-1, 2):
		gaps.append(Vector2i(x_wall + wall / 2, cy + i))
	gate_info[side] = {"name": gname, "gap_cells": gaps, "inside": inside}


func _set_rect(arr: PackedByteArray, x: int, y: int, w: int, h: int, id: int):
	for yy in range(y, y + h):
		if yy < 0 or yy >= H:
			continue
		var base := yy * W
		for xx in range(x, x + w):
			if xx < 0 or xx >= W:
				continue
			arr[base + xx] = id


func _tile_at(arr: PackedByteArray, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return arr[y * W + x]


func _fill_tilemap() -> Array:
	tile_map = TileMap.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = TilesetGen.build_tileset()
	tile_map.add_layer(1)   # 0=地面，1=城墙/豁口
	tile_map.y_sort_enabled = true
	add_child(tile_map)
	var gnd := 0
	var dcr := 0
	for yy in range(H):
		var base := yy * W
		for xx in range(W):
			var gid := ground[base + xx]
			tile_map.set_cell(0, Vector2i(xx, yy), gid, Vector2i(0, 0))
			gnd += 1
			var d := decor[base + xx]
			if d != 0:
				tile_map.set_cell(1, Vector2i(xx, yy), d, Vector2i(0, 0))
				dcr += 1
	return [gnd, dcr]


# ---- 文字占位标签（灰盒核心交付：坊名+场景列举；材质到位后整层退役）----
func _spawn_labels():
	labels_node = Node2D.new()
	labels_node.name = "Labels"
	labels_node.z_index = 60   # 压过一切地面/道具，禁止被吞
	add_child(labels_node)
	for b in blocks:
		var rect := _block_rect(b)
		var w_px := float(rect.size.x * 16)
		var center := cell_to_px(rect.position + rect.size / 2)
		var color: Color = KIND_COLORS.get(String(b["kind"]), Color.WHITE)
		_add_label(String(b["name"]), center + Vector2(0, -10), Vector2(w_px, 24), 12, color)
		_add_label(String(b["label"]), center + Vector2(0, 12), Vector2(w_px, 40), 10, Color(0.92, 0.92, 0.92))
		if b.has("extra_labels"):
			for ex in b["extra_labels"]:
				_add_label(String(ex["text"]), center + Vector2(0, 50), Vector2(w_px, 18), 9, Color(0.75, 0.85, 1.0))
	# 城门标签（金色，门内一格）
	for side in gate_info:
		var g: Dictionary = gate_info[side]
		_add_label(g["name"], cell_to_px(g["inside"]), Vector2(96, 20), 11, Color(1.0, 0.85, 0.4))
	# 街道标签（暗白，沿路）
	_add_label("朱雀大街", cell_to_px(Vector2i(seam_x(axis_col) + zq_s / 2, row_y(3) + 2)), Vector2(140, 20), 10, Color(0.85, 0.85, 0.85))
	_add_label("朱雀大街", cell_to_px(Vector2i(seam_x(axis_col) + zq_s / 2, row_y(2) + 6)), Vector2(140, 20), 10, Color(0.85, 0.85, 0.85))
	_add_label("金光门·春明门大街（皇城南缘横街）", cell_to_px(Vector2i(col_x(2) + 6, seam_y(2) + 2)), Vector2(300, 20), 10, Color(0.85, 0.85, 0.85))
	_add_label("城南横街", cell_to_px(Vector2i(col_x(2) + 4, seam_y(4) + 2)), Vector2(140, 20), 10, Color(0.85, 0.85, 0.85))
	_add_label("东纵街（玄武门凯旋线）", cell_to_px(Vector2i(seam_x(5) + 2, row_y(2) + 4)), Vector2(220, 20), 10, Color(0.85, 0.85, 0.85))
	label_count = labels_node.get_child_count()


func _add_label(text: String, center: Vector2, size: Vector2, font_size: int, color: Color):
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", font_size)
	lb.add_theme_color_override("font_color", color)
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lb.add_theme_constant_override("outline_size", 6)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.size = size
	lb.position = center - size / 2.0
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels_node.add_child(lb)


# ---- 出城触发区（照抄 v1 模式：豁口中心 Area2D 盖墙带）----
func _build_portals():
	portals_node = Node2D.new()
	portals_node.name = "Portals"
	add_child(portals_node)
	for side in gate_info:
		var g: Dictionary = gate_info[side]
		var cells: Array = g["gap_cells"]
		var c0: Vector2i = cells[0]
		var c1: Vector2i = cells[cells.size() - 1]
		var center_px := Vector2((c0.x + c1.x) * 0.5 + 0.5, (c0.y + c1.y) * 0.5 + 0.5) * 16.0
		var area := Area2D.new()
		area.name = "ExitPortal_%s" % side
		area.position = center_px
		area.collision_layer = 0
		area.collision_mask = 2   # 玩家层
		area.monitoring = true
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		if side == "S" or side == "N":
			shape.size = Vector2(48, 24)   # 墙厚2行，触发区盖满墙带防漏触
		else:
			shape.size = Vector2(24, 48)
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(_on_portal_body_entered.bind(side))
		portals_node.add_child(area)


func _on_portal_body_entered(body: Node2D, side: String):
	if body.is_in_group("player"):
		exit_requested.emit(side)


# ---- BFS 连通断言：明德门内可达全部街区中心+四门内落点 ----
func _run_bfs():
	if gate_info.is_empty():
		bfs_failures.append("城门未注册")
		return
	var start: Vector2i = gate_info["S"]["inside"]
	var reach := _bfs_from(start)
	var targets: Array = []
	for b in blocks:
		var rect := _block_rect(b)
		targets.append([String(b["id"]), rect.position + rect.size / 2])
	for side in gate_info:
		targets.append([String(gate_info[side]["name"]), gate_info[side]["inside"]])
	for t in targets:
		var cell: Vector2i = t[1]
		var key := "%d,%d" % [cell.x, cell.y]
		if not reach.has(key):
			bfs_failures.append("%s 中心 %s 不可达" % [t[0], str(cell)])


func _bfs_from(start: Vector2i) -> Dictionary:
	var reach := {}
	var queue: Array = [start]
	reach["%d,%d" % [start.x, start.y]] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var p: Vector2i = cur + d
			if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
				continue
			var key := "%d,%d" % [p.x, p.y]
			if reach.has(key):
				continue
			if COLLIDING.has(_tile_at(ground, p.x, p.y)) or COLLIDING.has(_tile_at(decor, p.x, p.y)):
				continue
			reach[key] = true
			queue.append(p)
	return reach


# ---- city_visit 接口（与 v1 同名同义）----
func is_spawn_clear(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := c + Vector2i(dx, dy)
			if COLLIDING.has(_tile_at(ground, p.x, p.y)) or COLLIDING.has(_tile_at(decor, p.x, p.y)):
				return false
	return true


func find_clear_spawn(near: Vector2i) -> Vector2i:
	if is_spawn_clear(near):
		return near
	for r in range(1, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(abs(dx), abs(dy)) != r:
					continue
				var p := near + Vector2i(dx, dy)
				if is_spawn_clear(p):
					return p
	return near


func cell_to_px(c: Vector2i) -> Vector2:
	return Vector2(c.x * 16 + 8, c.y * 16 + 8)
