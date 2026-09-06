extends Node2D
# 长安城内景房间构建器（M4）—— docs/长安城地图设计.md §5.3/§八
# 独立子地图（L3 内景层）：模板数据驱动 → 双层 TileMap（地面+家具装饰），瓦片复用主 TileSet（interior 80~89）
# 三标杆模板：琥珀光（酒肆 前/厨/库）· 天香阁一层（大厅）· 太极殿（宫院式 前庭+大殿）
# M5 批量 = 同一套 spec 换件；M6 现代场景（便利店）仅换瓦片皮肤复用本构建器
# 生成即校验：BFS 出生点→出口垫+各房间中心全可达

signal exit_entered   # 玩家踩上出口垫（city_visit 接管返回门面原位）

const TilesetGen = preload("res://scripts/tileset_generator.gd")
const T_FLOOR_WOOD = 80
const T_FLOOR_BRICK = 81
const T_CARPET = 82
const T_WALL = 83
const T_SCREEN = 84
const T_LAMP = 85
const T_DESK = 86
const T_COUCH = 87
const T_CABINET = 88
const T_SHELF = 89
# 内景内碰撞瓦片（与 tileset_generator collision_tile_ids 的 interior 段一致）
const COLLIDING := [T_WALL, T_SCREEN, T_DESK, T_CABINET, T_SHELF]

# ---- 三标杆模板（spec 格式见 _build_from_spec；M5 批量按此换件）----
const TEMPLATES := {
	"huguguang": {
		"name": "琥珀光", "size": [48, 36], "wall_tile": T_WALL,
		"rooms": [
			{"rect": [2, 2, 26, 20], "floor": T_FLOOR_WOOD, "door": "S", "label": "前堂"},
			{"rect": [30, 2, 16, 12], "floor": T_FLOOR_BRICK, "door": "W", "label": "后厨"},
			{"rect": [30, 16, 16, 10], "floor": T_FLOOR_BRICK, "door": "W", "label": "库房"},
		],
		"props": [
			[T_DESK, 6, 6], [T_DESK, 12, 6], [T_DESK, 18, 6], [T_DESK, 12, 12],   # 前堂酒案
			[T_COUCH, 22, 15], [T_SCREEN, 20, 4],                                   # 雅座屏风
			[T_LAMP, 4, 4], [T_LAMP, 16, 4], [T_LAMP, 24, 10],
			[T_CABINET, 33, 4], [T_SHELF, 36, 4], [T_DESK, 34, 8],                  # 后厨
			[T_SHELF, 33, 18], [T_CABINET, 38, 18], [T_CABINET, 42, 20],             # 库房
		],
		"spawn": [14, 23], "exit": [14, 22],
	},
	"tianxiang_ge": {
		"name": "天香阁一层", "size": [56, 40], "wall_tile": T_WALL,
		"rooms": [
			{"rect": [2, 2, 40, 24], "floor": T_FLOOR_WOOD, "door": "S", "label": "一层大厅"},
			{"rect": [12, 10, 16, 10], "floor": T_CARPET, "walls": false, "label": "中堂毯"},
			{"rect": [44, 8, 10, 14], "floor": T_FLOOR_BRICK, "door": "W", "label": "后院"},
		],
		"props": [
			[T_COUCH, 47, 12], [T_DESK, 49, 16], [T_LAMP, 45, 9], [T_LAMP, 52, 20],   # 后院
			[T_SCREEN, 8, 6], [T_SCREEN, 34, 6],
			[T_COUCH, 14, 14], [T_COUCH, 22, 14], [T_DESK, 18, 13],   # 中堂榻案
			[T_LAMP, 5, 5], [T_LAMP, 15, 5], [T_LAMP, 28, 5], [T_LAMP, 37, 5],
			[T_LAMP, 5, 20], [T_LAMP, 37, 20],
			[T_DESK, 8, 21], [T_DESK, 30, 21],
			[T_CABINET, 38, 22], [T_SHELF, 36, 3],
		],
		"spawn": [21, 27], "exit": [21, 26],
	},
	"taiji_dian": {
		"name": "太极殿", "size": [96, 72], "wall_tile": T_WALL,
		"rooms": [
			{"rect": [4, 4, 88, 30], "floor": T_FLOOR_BRICK, "door": "S", "label": "前庭"},
			{"rect": [18, 40, 60, 26], "floor": T_FLOOR_WOOD, "door": "S", "label": "大殿"},
			{"rect": [36, 48, 24, 12], "floor": T_CARPET, "walls": false, "label": "御座毯"},
		],
		"props": [
			[T_LAMP, 10, 10], [T_LAMP, 30, 10], [T_LAMP, 60, 10], [T_LAMP, 84, 10],   # 前庭灯烛
			[T_LAMP, 10, 26], [T_LAMP, 84, 26],
			[T_SCREEN, 30, 44], [T_SCREEN, 62, 44],                                     # 大殿屏风
			[T_DESK, 44, 52], [T_DESK, 50, 52],                                         # 御案
			[T_COUCH, 46, 56], [T_COUCH, 48, 56],
			[T_LAMP, 22, 44], [T_LAMP, 70, 44], [T_LAMP, 22, 62], [T_LAMP, 70, 62],
			[T_CABINET, 20, 42], [T_CABINET, 72, 42], [T_SHELF, 24, 63], [T_SHELF, 68, 63],
		],
		"spawn": [47, 36], "exit": [47, 37],
	},
}

var W := 0
var H := 0
var ground := PackedByteArray()
var decor := PackedByteArray()
var spawn_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var interior_id := ""
var display_name := ""
var spec_rooms: Array = []     # 当前内景房间表（标杆/生成统一，BFS 校验用）
var tile_map: TileMap = null
var done := false
var bfs_failures: Array = []

func _ready():
	y_sort_enabled = true

# ---- 构建：spec 填数组 → TileMap（内景尺寸小，同步一遍成图）----
func build(id: String, meta: Dictionary = {}) -> bool:
	var spec: Dictionary
	if TEMPLATES.has(id):
		spec = TEMPLATES[id]
	else:
		# M5 批量：按门面元数据生成（kind/grade 决定族与规模，hash(ref) 抖动摆件）
		if meta.is_empty():
			push_error("[ChangAn-Interior] 非标杆内景缺少元数据 " + id)
			return false
		spec = _make_spec(String(meta.get("kind", "house")), String(meta.get("grade", "C")),
				id, String(meta.get("name", id)), String(meta.get("skin", "")))
	interior_id = id
	display_name = String(spec["name"])
	spec_rooms = spec["rooms"]
	W = int(spec["size"][0])
	H = int(spec["size"][1])
	ground = PackedByteArray()
	ground.resize(W * H)
	decor = PackedByteArray()
	decor.resize(W * H)
	# 底满铺砖地板：室内无户外草瓦，默认0=草会露"黑洞/草地"（M1 全量铺贴教训同源）
	_set_rect(ground, 0, 0, W, H, T_FLOOR_BRICK)
	for room in spec["rooms"]:
		_paint_room(room)
	for prop in spec["props"]:
		decor[int(prop[2]) * W + int(prop[1])] = int(prop[0])
	spawn_cell = Vector2i(int(spec["spawn"][0]), int(spec["spawn"][1]))
	exit_cell = Vector2i(int(spec["exit"][0]), int(spec["exit"][1]))
	# 出口垫（毯瓦标记，无碰撞）
	ground[exit_cell.y * W + exit_cell.x] = T_CARPET
	_build_tilemap()
	_build_exit_area()
	_run_bfs()
	done = true
	return true

# 房间：内墙圈+地板满铺+门洞（指定边中点2格，无碰撞通行）；walls=false 则纯地板覆盖（毯区）
func _paint_room(room: Dictionary):
	var rx := int(room["rect"][0])
	var ry := int(room["rect"][1])
	var rw := int(room["rect"][2])
	var rh := int(room["rect"][3])
	_set_rect(ground, rx, ry, rw, rh, int(room["floor"]))
	if not room.get("walls", true):
		return
	var x1 := rx + rw - 1
	var y1 := ry + rh - 1
	_set_rect(decor, rx, ry, rw, rh, T_WALL)
	_set_rect(decor, rx + 1, ry + 1, rw - 2, rh - 2, 0)
	var door := String(room.get("door", ""))
	if door == "":
		return
	if door == "S":
		_set_rect(decor, rx + rw / 2 - 1, y1, 2, 1, 0)
	elif door == "N":
		_set_rect(decor, rx + rw / 2 - 1, ry, 2, 1, 0)
	elif door == "W":
		_set_rect(decor, rx, ry + rh / 2 - 1, 1, 2, 0)
	elif door == "E":
		_set_rect(decor, x1, ry + rh / 2 - 1, 1, 2, 0)

static var _tileset_cache: TileSet = null   # 45+内景共用一份 TileSet（逐景重建不可接受）

func _build_tilemap():
	if _tileset_cache == null:
		_tileset_cache = TilesetGen.build_tileset()
	tile_map = TileMap.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = _tileset_cache
	tile_map.add_layer(1)
	tile_map.y_sort_enabled = true
	tile_map.set_layer_y_sort_enabled(1, true)
	add_child(tile_map)
	for y in range(H):
		var base = y * W
		for x in range(W):
			tile_map.set_cell(0, Vector2i(x, y), int(ground[base + x]), Vector2i(0, 0))
			var d := int(decor[base + x])
			if d != 0:
				tile_map.set_cell(1, Vector2i(x, y), d, Vector2i(0, 0))

func _set_rect(arr: PackedByteArray, x: int, y: int, w: int, h: int, id: int):
	for yy in range(y, y + h):
		if yy < 0 or yy >= H:
			continue
		var base = yy * W
		for xx in range(x, x + w):
			if xx < 0 or xx >= W:
				continue
			arr[base + xx] = id

func tile_at(arr: PackedByteArray, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return T_WALL
	return arr[y * W + x]

func is_spawn_clear(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := c + Vector2i(dx, dy)
			if COLLIDING.has(tile_at(ground, p.x, p.y)) or COLLIDING.has(tile_at(decor, p.x, p.y)):
				return false
	return true

func cell_to_px(c: Vector2i) -> Vector2:
	return Vector2(c.x * 16 + 8, c.y * 16 + 8)

# 出口触发区：出口垫一格 Area2D
func _build_exit_area():
	var area := Area2D.new()
	area.name = "ExitArea"
	area.position = cell_to_px(exit_cell)
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	cs.shape = shape
	area.add_child(cs)
	area.body_entered.connect(_on_exit_body_entered)
	add_child(area)

func _on_exit_body_entered(body: Node2D):
	if body.is_in_group("player"):
		exit_entered.emit()

# 生成即校验（§六-1）：出生点出发，出口垫+各房间中心须可达
func _run_bfs():
	var blocked := {}
	for id in COLLIDING:
		blocked[id] = true
	var visited := {spawn_cell: true}
	var queue: Array[Vector2i] = [spawn_cell]
	var qi := 0
	while qi < queue.size():
		var p: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if visited.has(q):
				continue
			if blocked.has(tile_at(ground, q.x, q.y)) or blocked.has(tile_at(decor, q.x, q.y)):
				continue
			visited[q] = true
			queue.append(q)
	if not visited.has(exit_cell):
		bfs_failures.append("出口垫不可达")
	for room in spec_rooms:
		var r: Array = room["rect"]
		var reached := false
		for yy in range(int(r[1]) + 1, int(r[1]) + int(r[3]) - 1):
			for xx in range(int(r[0]) + 1, int(r[0]) + int(r[2]) - 1):
				if visited.has(Vector2i(xx, yy)):
					reached = true
					break
		if room.get("walls", true) == false and not reached:
			for yy in range(int(r[1]), int(r[1]) + int(r[3])):
				for xx in range(int(r[0]), int(r[0]) + int(r[2])):
					if visited.has(Vector2i(xx, yy)):
						reached = true
						break
		if not reached:
			bfs_failures.append("%s不可达" % String(room.get("label", "?")))

# ==================== M5 批量模板族（§8.1：模板化流水线，标杆仅换件不另雕） ====================
# kind=mansion(正厅+前院二段式)/temple(前庭+大殿)/office(大堂)/house(居室)/shop(铺面)/palace(宫院)
# grade 定尺寸档；hash(ref) 抖动，同族不同景、确定性可回归

func _make_spec(kind: String, grade: String, ref: String, dname: String, skin: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ref)
	var sz := Vector2i(24, 18)
	match kind:
		"mansion":
			sz = Vector2i(56, 44) if grade == "A" else (Vector2i(48, 38) if grade == "B" else Vector2i(40, 32))
		"temple":
			sz = Vector2i(48, 40) if grade != "C" else Vector2i(40, 32)
		"office":
			sz = Vector2i(40, 30)
		"palace":
			sz = Vector2i(80, 60)
		_:
			sz = Vector2i(24, 18)
	var W: int = sz.x
	var H: int = sz.y
	var rooms: Array = []
	var props: Array = []
	var spawn := Vector2i(W / 2, H - 4)
	var exit := Vector2i(W / 2, H - 5)
	match kind:
		"mansion":
			var hall_w := 24 if grade != "C" else 20
			var hy := 3
			var hh := int(H * 0.34)
			var cy := int(H * 0.52)
			var ch := H - cy - 4
			var hx := W / 2
			rooms = [
				{"rect": [hx - hall_w / 2, hy, hall_w, hh], "floor": T_FLOOR_WOOD, "door": "S", "label": "正厅"},
				{"rect": [hx - hall_w / 2 + 4, cy, hall_w - 8, ch], "floor": T_FLOOR_BRICK, "door": "S", "label": "前院"},
				{"rect": [hx - hall_w / 2 + 4, cy, hall_w - 8, ch], "floor": T_FLOOR_BRICK, "door": "N", "label": "前院北门"},
				{"rect": [hx - 4, hy + 2, 9, hh - 4], "floor": T_CARPET, "walls": false, "label": "厅心毯"},
			]
			props = [
				[T_DESK, hx, hy + hh / 2], [T_SCREEN, hx - hall_w / 2 + 2, hy + 2], [T_SCREEN, hx + hall_w / 2 - 3, hy + 2],
				[T_COUCH, hx - 4, hy + hh - 3], [T_LAMP, hx - hall_w / 2 + 2, hy + hh - 3], [T_LAMP, hx + hall_w / 2 - 3, hy + hh - 3],
				[T_LAMP, hx - 5, cy + 2], [T_LAMP, hx + 4, cy + ch - 3],
			]
		"temple":
			var hy2 := 3
			var hh2 := int(H * 0.32)
			var cy2 := int(H * 0.48)
			var ch2 := H - cy2 - 4
			rooms = [
				{"rect": [W / 2 - 12, hy2, 24, hh2], "floor": T_FLOOR_WOOD, "door": "S", "label": "大殿"},
				{"rect": [8, cy2, W - 16, ch2], "floor": T_FLOOR_BRICK, "door": "S", "label": "前庭"},
				{"rect": [8, cy2, W - 16, ch2], "floor": T_FLOOR_BRICK, "door": "N", "label": "前庭北门"},
			]
			props = [
				[T_DESK, W / 2 - 2, hy2 + hh2 / 2], [T_LAMP, W / 2 - 9, hy2 + 2], [T_LAMP, W / 2 + 8, hy2 + 2],
				[T_SCREEN, W / 2 - 9, hy2 + hh2 - 3], [T_SCREEN, W / 2 + 8, hy2 + hh2 - 3],
				[T_LAMP, 12, cy2 + 3], [T_LAMP, W - 14, cy2 + ch2 - 4],
			]
		"office":
			rooms = [{"rect": [5, 3, W - 10, int(H * 0.5)], "floor": T_FLOOR_BRICK, "door": "S", "label": "大堂"}]
			props = [
				[T_DESK, W / 2 - 4, 8], [T_DESK, W / 2 + 3, 8], [T_DESK, W / 2, 12],
				[T_CABINET, 7, 4], [T_SHELF, W - 9, 4], [T_LAMP, W / 2 - 6, 14], [T_LAMP, W / 2 + 5, 14],
			]
		"palace":
			var py := int(H * 0.52)
			rooms = [
				{"rect": [8, 4, W - 16, int(H * 0.36)], "floor": T_FLOOR_BRICK, "door": "S", "label": "前庭"},
				{"rect": [W / 2 - 20, py, 40, int(H * 0.36)], "floor": T_FLOOR_WOOD, "door": "S", "label": "大殿"},
				{"rect": [W / 2 - 8, py + 6, 16, 8], "floor": T_CARPET, "walls": false, "label": "御座毯"},
			]
			props = [
				[T_DESK, W / 2 - 3, py + 9], [T_DESK, W / 2 + 2, py + 9],
				[T_SCREEN, W / 2 - 14, py + 3], [T_SCREEN, W / 2 + 13, py + 3],
				[T_LAMP, 14, 8], [T_LAMP, W - 16, 8], [T_LAMP, 14, int(H * 0.3)], [T_LAMP, W - 16, int(H * 0.3)],
				[T_LAMP, W / 2 - 16, py + 3], [T_LAMP, W / 2 + 15, py + 3],
			]
		"shop":
			rooms = [{"rect": [3, 3, W - 6, H - 8], "floor": T_FLOOR_BRICK, "door": "S", "label": "铺面"}]
			props = _shop_props(skin, W)
		"house", "venue":
			rooms = [{"rect": [3, 3, W - 6, H - 8], "floor": T_FLOOR_WOOD, "door": "S", "label": "居室"}]
			props = [
				[T_COUCH, W / 2 - 3, 6], [T_CABINET, 5, 4], [T_DESK, W / 2 + 3, 10],
				[T_LAMP, 5, 12], [T_SCREEN, W - 7, 6],
			]
	var entry_rect: Array = []
	for room in rooms:
		if String(room.get("door", "")) == "S":
			var r2: Array = room["rect"]
			if entry_rect.is_empty() or r2[1] + r2[3] > entry_rect[1] + entry_rect[3]:
				entry_rect = r2   # 取最靠南的 S 门（外入口），mansion 两段式才不会取到正厅
	if not entry_rect.is_empty():
		var dx: int = entry_rect[0] + entry_rect[2] / 2
		exit = Vector2i(dx, entry_rect[1] + entry_rect[3])
		spawn = exit + Vector2i(0, 1)
	return {"name": dname, "size": [W, H], "wall_tile": T_WALL,
			"rooms": rooms, "props": props, "spawn": [spawn.x, spawn.y], "exit": [exit.x, exit.y]}

func _shop_props(skin: String, W: int) -> Array:
	var dx := W / 2 - 5
	match skin:
		"silk":
			return [[T_SHELF, dx, 4], [T_SHELF, dx + 3, 4], [T_SHELF, dx + 6, 4],
					[T_DESK, dx + 1, 9], [T_COUCH, dx + 5, 10], [T_LAMP, 4, 4]]
		"herb":
			return [[T_CABINET, dx, 4], [T_CABINET, dx + 3, 4], [T_CABINET, dx + 6, 4],
					[T_DESK, dx + 2, 9], [T_SHELF, 4, 10], [T_LAMP, W - 6, 4]]
		"book":
			return [[T_SHELF, dx, 4], [T_SHELF, dx + 3, 4], [T_SHELF, dx + 6, 4],
					[T_DESK, dx + 1, 9], [T_DESK, dx + 5, 9], [T_LAMP, 4, 12]]
		"pawn":
			return [[T_CABINET, dx, 4], [T_CABINET, dx + 3, 4], [T_CABINET, dx + 6, 4],
					[T_SCREEN, dx + 1, 9], [T_DESK, dx + 5, 11], [T_LAMP, 4, 4]]
		_:
			return [[T_DESK, dx, 6], [T_DESK, dx + 3, 6], [T_DESK, dx + 6, 6],
					[T_COUCH, dx + 1, 11], [T_LAMP, 4, 4], [T_LAMP, W - 6, 12]]
