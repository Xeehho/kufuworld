extends Node2D
# 长安城独立场景生成器（M0 灰盒）—— docs/长安城地图设计.md
# L1 外城层：外郭城墙/宫皇区/108坊/街网/两市，全部由 data/changan_city.json 驱动
# M0 验收：全图分帧生成 ≤3s；BFS 断言明德门可达全部 stage0 坊与两市；regress 无新 FAIL
# 注意：设计稿§5.1拟用ID 41~56 已被注册表占用，坊墙复用43（唐制坊墙），新瓦片从67起编

signal generation_done
signal exit_requested(gate_id: String)   # M1：玩家触碰城内出城触发区（city_visit 接管回开放世界）

const TilesetGen = preload("res://scripts/tileset_generator.gd")

# ---- 瓦片 ID（tileset_generator.gd 注册表）----
const T_GRASS = 0
const T_STONE = 35
const T_WARD_WALL = 43      # W2 唐制坊墙（白灰淡砖，带碰撞）
const T_GATE_OPEN = 67      # 坊门·开（无碰撞）
const T_GATE_CLOSED = 68    # 坊门·闭（宵禁/未解锁，带碰撞）
const T_PALACE_WALL = 69    # 宫墙
const T_OUTER_WALL = 70     # 外郭城墙
const T_ZHUQUE = 71         # 朱雀大街御道
const T_MAIN_ROAD = 72      # 主干街
const T_WARD_STREET = 73    # 坊内十字街

const COLLIDING := [5, 3, 7, 2, 10, 11, 12, 14, 15, 40, 43, 65, 66, 68, 69, 70]

# ---- 网格参数（JSON 解析后类型化）----
var bw := 26
var bh := 26
var main_s := 5
var zq_s := 9
var ring := 4
var wall := 1
var margin := 10
var cols := 12
var rows := 9
var palace_cols := Vector2i(4, 7)
var palace_rows := Vector2i(0, 1)

var blocks: Array = []
var markets: Array = []
var W := 0
var H := 0
var ground: PackedByteArray
var decor: PackedByteArray
var done := false
var stats := {}
var bfs_failures: Array = []
var tile_map: TileMap = null
# ---- M1 四城门注册表（side -> {name, gap_cells, inside}）----
# 明德门(南中)/玄武门(北中)/春明门(东中)/开远门(西中)，豁口均3格与城内街网对齐
var gate_info := {}
var portals_node: Node2D = null

func _ready():
	y_sort_enabled = true   # M1：与 World 递归 y-sort 对齐（玩家/坊墙按 y 排序）
	if _load_data():
		_paint_layout()
		_fill_tilemap_async()

func _load_data() -> bool:
	var f = FileAccess.open("res://data/changan_city.json", FileAccess.READ)
	if f == null:
		push_error("[ChangAn] data/changan_city.json 缺失，先跑 python tools/make_changan_data.py")
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("[ChangAn] changan_city.json 解析失败")
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
	palace_cols = Vector2i(int(g["palace_zone"]["cols"][0]), int(g["palace_zone"]["cols"][1]))
	palace_rows = Vector2i(int(g["palace_zone"]["rows"][0]), int(g["palace_zone"]["rows"][1]))
	markets = g["markets"]
	blocks = parsed["blocks"]
	W = margin * 2 + wall * 2 + ring * 2 + cols * bw + (cols - 1) * main_s + (zq_s - main_s)
	H = margin * 2 + wall * 2 + ring * 2 + rows * bh + (rows - 1) * main_s
	return true

func _origin() -> Vector2i:
	return Vector2i(margin + wall + ring, margin + wall + ring)

func col_x(c: int) -> int:
	return _origin().x + c * (bw + main_s) + (4 if c >= 5 else 0)   # 4=朱雀加宽补偿

func row_y(r: int) -> int:
	return _origin().y + r * (bh + main_s)

func block_span_x() -> int:
	return col_x(cols - 1) + bw - _origin().x

func block_span_y() -> int:
	return row_y(rows - 1) + bh - _origin().y

func _paint_layout():
	ground = PackedByteArray()
	ground.resize(W * H)          # 默认0=草
	decor = PackedByteArray()
	decor.resize(W * H)
	# 外郭城墙（1圈）+ 城外荒带（margin 默认草）
	_set_rect(decor, margin, margin, W - margin * 2, H - margin * 2, T_OUTER_WALL)
	_set_rect(decor, margin + 1, margin + 1, W - margin * 2 - 2, H - margin * 2 - 2, 0)
	# 环路（贴城墙内侧，4宽土路）
	var m := margin + wall
	_set_rect(ground, m, m, W - m * 2, ring, T_MAIN_ROAD)
	_set_rect(ground, m, H - m - ring, W - m * 2, ring, T_MAIN_ROAD)
	_set_rect(ground, m, m, ring, H - m * 2, T_MAIN_ROAD)
	_set_rect(ground, W - m - ring, m, ring, H - m * 2, T_MAIN_ROAD)
	# 纵向街道缝 i=1..cols-1；i=5 为朱雀大街（宽9，恰在 col4|col5 之间）
	for i in range(1, cols):
		if i == 5:
			_set_rect(ground, col_x(5) - zq_s, _origin().y, zq_s, block_span_y(), T_ZHUQUE)
		else:
			_set_rect(ground, col_x(i) - main_s, _origin().y, main_s, block_span_y(), T_MAIN_ROAD)
	# 横向街道缝 j=1..rows-1
	for j in range(1, rows):
		_set_rect(ground, _origin().x, row_y(j) - main_s, block_span_x(), main_s, T_MAIN_ROAD)
	# 宫皇区（合并8街区，覆盖已铺街道）
	_paint_palace()
	# 坊与市
	for b in blocks:
		if String(b["type"]) != "ward":
			continue
		if _in_palace(int(b["col"]), int(b["row"])):
			continue
		_paint_ward(b)
	for mk in markets:
		_paint_market(int(mk["col"]), int(mk["row"]))
	# M2 坊内填充：剧情坊按 lots 铺宅邸门面，非剧情 stage0 坊程序化院落（未解锁坊留白，§六-3）
	for b in blocks:
		if String(b["type"]) != "ward" or _in_palace(int(b["col"]), int(b["row"])):
			continue
		if int(b["stage_unlock"]) != 0:
			continue
		_fill_ward_contents(b)

# ---- M2 宅门品级瓦片（§5.1）----
const GATE_TILE_BY_GRADE := {"A": 75, "B": 76, "C": 77}

func _fill_ward_contents(b: Dictionary):
	var lots: Array = b.get("lots", [])
	if not lots.is_empty():
		var x0 := col_x(int(b["col"]))
		var y0 := row_y(int(b["row"]))
		for lot in lots:
			_paint_lot(x0, y0, lot)
	else:
		_fill_ward_generic(b)

# 剧情坊 lot：院墙圈 + 品级宅门（带碰撞门面，M4 换传送门）+ 门前甬道 + 后部正屋
func _paint_lot(x0: int, y0: int, lot: Dictionary):
	var lx := x0 + int(lot["at"][0])
	var ly := y0 + int(lot["at"][1])
	var w := int(lot["size"][0])
	var h := int(lot["size"][1])
	var x1 := lx + w - 1
	var y1 := ly + h - 1
	var kind := String(lot["kind"])
	var gate_id: int = GATE_TILE_BY_GRADE[String(lot["grade"])]
	# 院墙圈
	_set_rect(decor, lx, ly, w, h, T_WARD_WALL)
	_set_rect(decor, lx + 1, ly + 1, w - 2, h - 2, 0)
	# 寺观/风月场所院内满铺石板（体面），宅邸留草
	if kind == "temple" or kind == "venue":
		_set_rect(ground, lx + 1, ly + 1, w - 2, h - 2, T_STONE)
	# 院门（门侧墙正中2格，品级瓦）+ 门前石板甬道
	var gcx := lx + w / 2
	var gcy := ly + h / 2
	match String(lot.get("gate", "S")):
		"S":
			_set_rect(decor, gcx - 1, y1, 2, 1, gate_id)
			_set_rect(ground, gcx - 1, ly + 2, 2, y1 - (ly + 2) + 1, T_STONE)
		"N":
			_set_rect(decor, gcx - 1, ly, 2, 1, gate_id)
			_set_rect(ground, gcx - 1, ly, 2, y1 - 2 - ly + 1, T_STONE)
		"E":
			_set_rect(decor, x1, gcy - 1, 1, 2, gate_id)
			_set_rect(ground, lx + 2, gcy - 1, x1 - (lx + 2) + 1, 2, T_STONE)
		"W":
			_set_rect(decor, lx, gcy - 1, 1, 2, gate_id)
			_set_rect(ground, lx, gcy - 1, x1 - 2 - lx + 1, 2, T_STONE)
	# 正屋：门对侧内墙处（寺观/场所3连屋，宅邸1屋）
	var house_w := 3 if (kind == "temple" or kind == "venue") else 1
	match String(lot.get("gate", "S")):
		"S":
			_set_rect(decor, gcx - house_w / 2, ly + 2, house_w, 1, 2)
		"N":
			_set_rect(decor, gcx - house_w / 2, y1 - 2, house_w, 1, 2)
		"E":
			_set_rect(decor, lx + 2, gcy - house_w / 2, 1, house_w, 2)
		"W":
			_set_rect(decor, x1 - 2, gcy - house_w / 2, 1, house_w, 2)

# 非剧情坊程序化填充：四象限小院（朝十字街开敞口，不留封闭死角）+ 低密度坊散树
func _fill_ward_generic(b: Dictionary):
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(b["id"]))
	var high := String(b["fill"]) == "residential_high"
	var x0 := col_x(int(b["col"]))
	var y0 := row_y(int(b["row"]))
	var boxes := [Vector2i(2, 2), Vector2i(15, 2), Vector2i(2, 16), Vector2i(15, 16)]
	for q in range(4):
		var chance := 0.85 if high else 0.55
		if rng.randf() > chance:
			continue
		var bx: Vector2i = boxes[q]
		var lw := 7
		var lh := 6
		var lx := x0 + bx.x + rng.randi_range(0, 2)
		var ly := y0 + bx.y + rng.randi_range(0, 2)
		_set_rect(decor, lx, ly, lw, lh, T_WARD_WALL)
		_set_rect(decor, lx + 1, ly + 1, lw - 2, lh - 2, 0)
		var hx := lx + lw / 2
		var hy := ly + lh / 2
		_set_rect(decor, hx, hy, 1, 1, 2)   # 屋1格（城镇房屋瓦）
		if q < 2:   # 北象限小院朝南开敞口
			_set_rect(decor, hx, ly + lh - 1, 1, 1, 0)
			_set_rect(ground, hx, ly + lh - 1, 1, 1, T_WARD_STREET)
		else:
			_set_rect(decor, hx, ly, 1, 1, 0)
			_set_rect(ground, hx, ly, 1, 1, T_WARD_STREET)
	if not high:   # 低密度坊散树（橡树瓦，可行走装饰）
		for i in range(rng.randi_range(2, 5)):
			var tx := x0 + rng.randi_range(2, 23)
			var ty := y0 + rng.randi_range(2, 23)
			if int(decor[ty * W + tx]) == 0 and int(ground[ty * W + tx]) == 0:
				decor[ty * W + tx] = 8
	# 明德门：南城墙朱雀轴线开3格
	var cx := col_x(5) - zq_s + zq_s / 2
	_set_rect(decor, cx - 1, H - margin - wall, 3, 1, T_GATE_OPEN)
	# M1 四城门：豁口+注册（明德门S已有，玄武门N/春明门E/开远门W，均对齐街网轴线）
	_register_gate("S", "明德门", [Vector2i(cx - 1, H - margin - wall), Vector2i(cx, H - margin - wall), Vector2i(cx + 1, H - margin - wall)], Vector2i(cx, H - margin - wall - 2))
	_set_rect(decor, cx - 1, margin, 3, 1, T_GATE_OPEN)
	_register_gate("N", "玄武门", [Vector2i(cx - 1, margin), Vector2i(cx, margin), Vector2i(cx + 1, margin)], Vector2i(cx, margin + wall + 1))
	var cyc := _center_seam_y()
	_set_rect(decor, W - margin - wall, cyc - 1, 1, 3, T_GATE_OPEN)
	_register_gate("E", "春明门", [Vector2i(W - margin - wall, cyc - 1), Vector2i(W - margin - wall, cyc), Vector2i(W - margin - wall, cyc + 1)], Vector2i(W - margin - wall - 2, cyc))
	_set_rect(decor, margin, cyc - 1, 1, 3, T_GATE_OPEN)
	_register_gate("W", "开远门", [Vector2i(margin, cyc - 1), Vector2i(margin, cyc), Vector2i(margin, cyc + 1)], Vector2i(margin + wall + 1, cyc))

# 中央横街缝（rows=9 → row4|row5 之间 j=5 缝的y中心），东西门与其对齐
func _center_seam_y() -> int:
	return row_y(5) - main_s + main_s / 2

func _register_gate(side: String, gname: String, gap: Array, inside: Vector2i):
	gate_info[side] = {"name": gname, "gap_cells": gap, "inside": inside}

func _in_palace(c: int, r: int) -> bool:
	return c >= palace_cols.x and c <= palace_cols.y and r >= palace_rows.x and r <= palace_rows.y

func _paint_palace():
	var px0 := col_x(palace_cols.x)
	var py0 := row_y(palace_rows.x)
	var px1 := col_x(palace_cols.y) + bw - 1
	var py1 := row_y(palace_rows.y) + bh - 1
	_set_rect(ground, px0, py0, px1 - px0 + 1, py1 - py0 + 1, T_GRASS)
	_set_rect(decor, px0, py0, px1 - px0 + 1, py1 - py0 + 1, T_PALACE_WALL)
	_set_rect(decor, px0 + 1, py0 + 1, px1 - px0 - 1, py1 - py0 - 1, 0)
	# 四门：南中3（承天门，对朱雀轴线）、北中2、东西各2
	var cx := col_x(5) - zq_s + zq_s / 2
	var my := py0 + (py1 - py0) / 2
	_set_rect(decor, cx - 1, py1, 3, 1, T_GATE_OPEN)
	_set_rect(decor, cx - 1, py0, 2, 1, T_GATE_OPEN)
	_set_rect(decor, px0, my, 1, 2, T_GATE_OPEN)
	_set_rect(decor, px1, my, 1, 2, T_GATE_OPEN)

func _paint_ward(b: Dictionary):
	var c := int(b["col"])
	var r := int(b["row"])
	var x0 := col_x(c)
	var y0 := row_y(r)
	var x1 := x0 + bw - 1
	var y1 := y0 + bh - 1
	# 坊内清底（覆盖先铺的街道）再围坊墙
	_set_rect(ground, x0, y0, bw, bh, T_GRASS)
	_set_rect(decor, x0, y0, bw, bh, T_WARD_WALL)
	_set_rect(decor, x0 + 1, y0 + 1, bw - 2, bh - 2, 0)
	# 门洞：宽2，坊墙正中；stage>0 未解锁=闭门
	var gx0 := x0 + bw / 2 - 1
	var gy0 := y0 + bh / 2 - 1
	var open_id := T_GATE_OPEN if int(b["stage_unlock"]) == 0 else T_GATE_CLOSED
	for g in b["gates"]:
		match String(g):
			"N":
				_set_rect(decor, gx0, y0, 2, 1, open_id)
				_set_rect(ground, gx0, y0, 2, 3, T_WARD_STREET)
			"S":
				_set_rect(decor, gx0, y1, 2, 1, open_id)
				_set_rect(ground, gx0, y1 - 2, 2, 3, T_WARD_STREET)
			"W":
				_set_rect(decor, x0, gy0, 1, 2, open_id)
				_set_rect(ground, x0, gy0, 3, 2, T_WARD_STREET)
			"E":
				_set_rect(decor, x1, gy0, 1, 2, open_id)
				_set_rect(ground, x1 - 2, gy0, 3, 2, T_WARD_STREET)
	# 坊内十字街（2宽，与门洞对齐）
	_set_rect(ground, gx0, y0 + 1, 2, bh - 2, T_WARD_STREET)
	_set_rect(ground, x0 + 1, gy0, bw - 2, 2, T_WARD_STREET)

func _paint_market(c: int, r: int):
	var x0 := col_x(c)
	var y0 := row_y(r)
	var x1 := x0 + bw - 1
	var y1 := y0 + bh - 1
	_set_rect(ground, x0, y0, bw, bh, T_STONE)
	_set_rect(decor, x0, y0, bw, bh, T_WARD_WALL)
	_set_rect(decor, x0 + 1, y0 + 1, bw - 2, bh - 2, 0)
	# 市门四向各2格
	var gx0 := x0 + bw / 2 - 1
	var gy0 := y0 + bh / 2 - 1
	_set_rect(decor, gx0, y0, 2, 1, T_GATE_OPEN)
	_set_rect(decor, gx0, y1, 2, 1, T_GATE_OPEN)
	_set_rect(decor, x0, gy0, 1, 2, T_GATE_OPEN)
	_set_rect(decor, x1, gy0, 1, 2, T_GATE_OPEN)

func _set_rect(arr: PackedByteArray, x: int, y: int, w: int, h: int, id: int):
	for yy in range(y, y + h):
		if yy < 0 or yy >= H:
			continue
		var base = yy * W
		for xx in range(x, x + w):
			if xx < 0 or xx >= W:
				continue
			arr[base + xx] = id

func _tile_at(arr: PackedByteArray, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return T_OUTER_WALL
	return arr[y * W + x]

# ---- M1 传送落点校验（设计稿§七：3×3 可通行校验 + 螺旋外扩兜底）----
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
					continue   # 只扫外圈
				var p := near + Vector2i(dx, dy)
				if is_spawn_clear(p):
					return p
	return near   # BFS 已保证门口可达，兜底原点

func cell_to_px(c: Vector2i) -> Vector2:
	return Vector2(c.x * 16 + 8, c.y * 16 + 8)

# ---- 分帧填充 TileMap：16 分区，每帧一区 ----
func _fill_tilemap_async() -> void:
	var t0 := Time.get_ticks_msec()
	tile_map = TileMap.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = TilesetGen.build_tileset()
	tile_map.add_layer(1)          # 默认仅1层：0=地面，1=装饰/墙体
	tile_map.y_sort_enabled = true             # 对齐开放世界 TileMap y-sort 玩法
	tile_map.set_layer_y_sort_enabled(1, true) # 墙体按 y_sort_origin 与玩家互遮挡
	add_child(tile_map)
	var regions := 4
	var rw := int(ceil(W / float(regions)))
	var rh := int(ceil(H / float(regions)))
	var non_ground := 0
	var decor_cnt := 0
	for ry in range(regions):
		for rx in range(regions):
			for yy in range(ry * rh, min(H, (ry + 1) * rh)):
				var base = yy * W
				for xx in range(rx * rw, min(W, (rx + 1) * rw)):
					# 地面层全量铺贴（草地也画）——跳过草地会露出背景成黑洞（M1 走查踩坑）
					var gid := ground[base + xx]
					tile_map.set_cell(0, Vector2i(xx, yy), gid, Vector2i(0, 0))
					non_ground += 1
					var d := decor[base + xx]
					if d != 0:
						tile_map.set_cell(1, Vector2i(xx, yy), d, Vector2i(0, 0))
						decor_cnt += 1
			await get_tree().process_frame
	var ms := Time.get_ticks_msec() - t0
	_build_portals()
	_run_bfs()
	stats = {
		"size": "%dx%d" % [W, H], "ms": ms,
		"ground_cells": non_ground, "decor_cells": decor_cnt,
		"bfs_fail": bfs_failures.size(),
	}
	print("[ChangAn-M0] %s 生成 %dms 地面=%d 装饰=%d BFS未达=%d 城门=%d" %
			[stats["size"], ms, non_ground, decor_cnt, bfs_failures.size(), gate_info.size()])
	done = true
	generation_done.emit()

# ---- M1 出城触发区：每门一个 Area2D 盖住豁口格，玩家触碰即请求出城 ----
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
		area.set_meta("gate_id", side)
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		if side == "S" or side == "N":
			shape.size = Vector2(48, 16)
		else:
			shape.size = Vector2(16, 48)
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(_on_portal_body_entered.bind(side))
		portals_node.add_child(area)

func _on_portal_body_entered(body: Node2D, side: String):
	if body.is_in_group("player"):
		exit_requested.emit(side)

# ---- BFS 连通断言：明德门内出发，stage0 坊与两市中心须可达 ----
func _run_bfs():
	var blocked := {}
	for id in COLLIDING:
		blocked[id] = true
	var start := Vector2i(col_x(5) - zq_s + zq_s / 2 + 1, H - margin - wall - 1)
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0   # 索引指针替代 pop_front（Array.pop_front 是 O(n)，12万格会卡死）
	while qi < queue.size():
		var p: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if visited.has(q):
				continue
			if blocked.has(_tile_at(ground, q.x, q.y)) or blocked.has(_tile_at(decor, q.x, q.y)):
				continue
			visited[q] = true
			queue.append(q)
# 检查点：stage0 坊中心 + 市中心 + 四城门内侧（M1 全城骨架连通）
	for b in blocks:
		if String(b["type"]) != "ward" or int(b["stage_unlock"]) != 0:
			continue
		var cx := col_x(int(b["col"])) + bw / 2
		var cy := row_y(int(b["row"])) + bh / 2
		if not visited.has(Vector2i(cx, cy)):
			bfs_failures.append(String(b["name"]))
	for mk in markets:
		var cx2 := col_x(int(mk["col"])) + bw / 2
		var cy2 := row_y(int(mk["row"])) + bh / 2
		if not visited.has(Vector2i(cx2, cy2)):
			bfs_failures.append(String(mk["name"]) + "(市)")
	for side in gate_info:
		var inside: Vector2i = gate_info[side]["inside"]
		if not visited.has(inside):
			bfs_failures.append(String(gate_info[side]["name"]) + "(门内)")
