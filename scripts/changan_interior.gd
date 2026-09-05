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
		],
		"props": [
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
var tile_map: TileMap = null
var done := false
var bfs_failures: Array = []

func _ready():
	y_sort_enabled = true

# ---- 构建：spec 填数组 → TileMap（内景尺寸小，同步一遍成图）----
func build(id: String) -> bool:
	if not TEMPLATES.has(id):
		push_error("[ChangAn-Interior] 未知内景模板 " + id)
		return false
	var spec: Dictionary = TEMPLATES[id]
	interior_id = id
	display_name = String(spec["name"])
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

func _build_tilemap():
	tile_map = TileMap.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = TilesetGen.build_tileset()
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
	for id in TEMPLATES[interior_id]["rooms"]:
		var room: Array = id["rect"]
		var c := Vector2i(room[0] + room[2] / 2, room[1] + room[3] / 2)
		if not visited.has(c):
			bfs_failures.append("%s中心不可达" % String(id.get("label", "?")))
