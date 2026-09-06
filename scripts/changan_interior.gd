extends Node2D
# 长安城内景房间构建器（M4）—— docs/长安城地图设计.md §5.3/§八
# 独立子地图（L3 内景层）：模板数据驱动 → 双层 TileMap（地面+装饰），瓦片复用主 TileSet（interior 80~89/113）
# 三标杆模板：琥珀光（酒肆 前/厨/库）· 天香阁一层（大厅）· 太极殿（宫院式 前庭+大殿）
# M5 批量 = 同一套 spec 换件；M6 现代场景（便利店）仅换瓦片皮肤复用本构建器
# 生成即校验：BFS 出生点→出口垫+各房间中心全可达
#
# 内景换皮（2026-09-06，SCKR 内景包）：
#   - 地面 80/81/113 与墙 83 换 SCKR 切片（tileset 双列首选，碰撞/y_sort 语义不变）
#   - 陈设走 furn 表：[prop 名, 锚格x, 锚格y, foot宽, foot高] → Sprite2D 底边中点锚（同外城 _spawn_building 模式）
#     + T_FOOT(102) 透明碰撞占格（COLLIDING 增补，原 83~89 语义不动）；foot=0,0 为墙面挂画（无碰撞）
#   - 切片缺失（克隆未跑 import）静默跳过 sprite 且不占格，内景保持可走

signal exit_entered   # 玩家踩上出口垫（city_visit 接管返回门面原位）

const TilesetGen = preload("res://scripts/tileset_generator.gd")
const TextureGen = preload("res://scripts/texture_generator.gd")
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
const T_MEDAL = 113     # 厅心花砖（毯心/蒲团区点缀，无碰撞）
const T_FOOT = 102      # 建筑足印（全透明带碰撞）——多格家具占格
# 内景内碰撞瓦片（83~89 段与 tileset_generator collision_tile_ids 一致；102 为家具足印增补）
const COLLIDING := [T_WALL, T_SCREEN, T_DESK, T_CABINET, T_SHELF, T_FOOT]

const PROP_ROOT := "res://sprites/changan_props_sckr/"

# ---- 三标杆模板（spec 格式见 _build_from_spec；M5 批量按此换件）----
const TEMPLATES := {
	"huguguang": {
		"name": "琥珀光", "size": [48, 36], "wall_tile": T_WALL,
		"rooms": [
			{"rect": [2, 2, 26, 20], "floor": T_FLOOR_WOOD, "door": "S", "label": "前堂"},
			{"rect": [30, 2, 16, 12], "floor": T_FLOOR_BRICK, "door": "W", "label": "后厨"},
			{"rect": [30, 16, 16, 10], "floor": T_FLOOR_BRICK, "door": "W", "label": "库房"},
		],
		# 前堂酒肆：北墙酒坛堆+菱格酒架，中部散台，雅座折屏；后厨灶蒸笼；库房酒架坛堆
		"furn": [
			["wine_jars", 5, 4, 3, 1], ["wine_rack", 9, 4, 4, 2], ["jars_cluster", 14, 4, 4, 2],
			["lantern_pole_pair", 21, 4, 0, 0],                                    # 北墙双灯宫灯架
			["counter_long", 4, 8, 4, 1], ["counter_long_b", 9, 8, 4, 1],          # 柜台带
			["table_square", 13, 11, 2, 1], ["stool_round_a", 12, 12, 1, 1], ["stool_round_b", 15, 12, 1, 1],
			["tea_table_a", 18, 8, 3, 1], ["table_square_red", 21, 12, 2, 1], ["stool_round_a", 20, 13, 1, 1],
			["screen_fold_land", 24, 6, 4, 2],                                     # 雅座折屏
			["lantern_stand_a", 4, 12, 1, 1], ["lantern_red_stand", 16, 15, 1, 1], ["lantern_stand_a", 24, 17, 1, 1],
			["scroll_h_a", 9, 2, 0, 0],                                            # 前堂横匾
			# 后厨
			["stove_fire", 34, 5, 4, 2], ["steamer", 39, 4, 2, 2], ["counter_kitchen", 42, 8, 3, 2],
			["stove_brick", 32, 10, 3, 2], ["lamp_small", 31, 12, 1, 1],
			# 库房
			["wine_rack", 34, 18, 4, 2], ["jars_cluster_b", 39, 18, 4, 2], ["jar_shelf_b", 43, 19, 3, 2],
			["wine_jars", 36, 22, 3, 1], ["jar_white", 42, 23, 1, 1], ["lamp_small", 32, 23, 1, 1],
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
		# 大厅：北墙山水折屏+条案官帽椅中堂，中堂毯方桌茶具，两翼茶几灯架；后院花几茶桌
		"furn": [
			["screen_fold_land", 20, 4, 11, 1],                                    # 中堂山水大折屏
			["altar_table", 20, 6, 5, 1], ["chair_arm_a", 14, 6, 2, 1], ["chair_arm_b", 26, 6, 2, 1],
			["scroll_pair_a", 8, 2, 0, 0], ["scroll_pair_b", 33, 2, 0, 0],         # 两翼挂画
			["table_square_red", 19, 14, 2, 1], ["tea_table_set", 22, 15, 3, 1], ["stool_round_a", 17, 15, 1, 1],
			["tea_table_a", 7, 9, 3, 1], ["tea_table_b", 33, 9, 3, 1], ["stand_plant", 4, 7, 1, 1], ["stand_vase", 37, 7, 1, 1],
			["lantern_pole_pair", 6, 16, 0, 0], ["lantern_pole_pair", 34, 16, 0, 0],
			["lantern_stand_a", 14, 8, 1, 1], ["lantern_stand_a", 26, 8, 1, 1],
			["sideboard", 6, 21, 4, 1], ["shelf_curio", 38, 21, 4, 2], ["lantern_red_stand", 30, 21, 1, 1],
			["mat_cushion", 19, 12, 0, 0],                                         # 毯心蒲团垫（平铺）
			# 后院
			["stand_plant", 46, 10, 1, 1], ["tea_table_set", 49, 14, 3, 1], ["lantern_std_red", 52, 19, 1, 1], ["stool_round_b", 46, 15, 1, 1],
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
		"accents": [[40, 52, 16, 2], [46, 34, 4, 6]],   # 御座毯心花砖带 + 前庭→大殿甬道
		# 前庭仪仗+灯柱；大殿丹陛金柱御座仪仗幡
		"furn": [
			["lantern_std_red", 10, 8, 1, 1], ["lantern_std_red", 86, 8, 1, 1],
			["lantern_std_red", 10, 28, 1, 1], ["lantern_std_red", 86, 28, 1, 1],
			["yizhang_fan_a", 30, 18, 0, 0], ["yizhang_fan_b", 66, 18, 0, 0],
			["rack_spear", 6, 18, 3, 1], ["rack_sword_b", 89, 18, 3, 1],
			["screen_fold_plum", 47, 41, 0, 0],                                    # 御座背后花鸟大屏（贴北墙）
			["cabinet_red_b", 47, 43, 3, 2],                                       # 御座（朱漆龙柜）
			["danbi_medallion", 47, 50, 10, 3],                                    # 丹陛团龙台
			["pillar_gold", 39, 50, 1, 2], ["pillar_gold", 56, 50, 1, 2],          # 金柱对
			["yizhang_fan_a", 34, 50, 0, 0], ["yizhang_fan_b", 61, 50, 0, 0],      # 仪仗幡
			["rack_sword", 23, 43, 3, 1], ["rack_halberd", 73, 43, 3, 1],          # 殿内仪仗兵器架
			["lantern_std_red", 30, 49, 1, 1], ["lantern_std_red", 65, 49, 1, 1],
			["lantern_pole_pair", 24, 62, 0, 0], ["lantern_pole_pair", 71, 62, 0, 0],
			["jar_shelf", 20, 56, 3, 2], ["jar_shelf_b", 75, 56, 3, 2],
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

static var _prop_tex_cache := {}

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
	for acc in spec.get("accents", []):   # 花砖/毯心点缀（地面层，可走）
		_set_rect(ground, int(acc[0]), int(acc[1]), int(acc[2]), int(acc[3]), T_MEDAL)
	for prop in spec.get("props", []):
		decor[int(prop[2]) * W + int(prop[1])] = int(prop[0])
	for f in spec.get("furn", []):        # 家具足印占格（sprite 在瓦片后生成）
		var fw: int = int(f[3])
		var fh: int = int(f[4])
		if fw > 0 and fh > 0:
			_set_rect(decor, int(f[1]) - fw / 2, int(f[2]) - fh + 1, fw, fh, T_FOOT)
	spawn_cell = Vector2i(int(spec["spawn"][0]), int(spec["spawn"][1]))
	exit_cell = Vector2i(int(spec["exit"][0]), int(spec["exit"][1]))
	# 出口垫（毯瓦标记，无碰撞）
	ground[exit_cell.y * W + exit_cell.x] = T_CARPET
	_build_tilemap()
	_spawn_furniture(spec.get("furn", []))
	_build_exit_area()
	_run_bfs()
	done = true
	return true

# 家具 sprite：SCKR 切片 → 底边中点锚（y_sort 与玩家自然遮挡）；缺失切片静默跳过
func _spawn_furniture(furn: Array) -> void:
	for f in furn:
		var pname := String(f[0])
		var tex: Texture2D = _prop_tex(pname)
		if tex == null:
			continue
		var prop := Sprite2D.new()
		prop.texture = tex
		prop.position = Vector2(int(f[1]) * 16 + 8, (int(f[2]) + 1) * 16)
		prop.offset = Vector2(0, -tex.get_height() / 2.0)
		prop.z_index = 2
		prop.add_to_group("changan_prop")
		prop.set_meta("prop", pname)
		add_child(prop)

static func _prop_tex(pname: String) -> Texture2D:
	if _prop_tex_cache.has(pname):
		return _prop_tex_cache[pname]
	var tex: Texture2D = TextureGen.load_png_texture(PROP_ROOT + pname + ".png")
	_prop_tex_cache[pname] = tex
	return tex

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
# kind=mansion(正厅+卧房+前院)/temple(前庭+大殿)/office(大堂)/house(居室)/shop(铺面)/palace(宫院)
# grade 定尺寸档；hash(ref) 抖动，同族不同景、确定性可回归
# 布置纪律（视觉验收规格）：北墙中堂组合/满室陈设/灯笼 6~10 格布光/E2E 站位格（spawn+(0,-3)）必留空

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
	var furn: Array = []
	var accents: Array = []
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
			# 东厢卧房（grade 定宽）：贴正厅东墙，门朝 S 接南部砖地
			var wch := 12 if grade == "A" else (10 if grade == "B" else 9)
			var chx: int = hx + hall_w / 2 + 1
			var hc: int = hh + 2
			rooms = [
				{"rect": [hx - hall_w / 2, hy, hall_w, hh], "floor": T_FLOOR_WOOD, "door": "S", "label": "正厅"},
				{"rect": [chx, hy, wch, hc], "floor": T_FLOOR_WOOD, "door": "S", "label": "卧房"},
				{"rect": [hx - hall_w / 2 + 4, cy, hall_w - 8, ch], "floor": T_FLOOR_BRICK, "door": "S", "label": "前院"},
				{"rect": [hx - hall_w / 2 + 4, cy, hall_w - 8, ch], "floor": T_FLOOR_BRICK, "door": "N", "label": "前院北门"},
				{"rect": [hx - 4, hy + 2, 9, hh - 4], "floor": T_CARPET, "walls": false, "label": "厅心毯"},
			]
			accents = [[hx - 1, hy + hh / 2, 3, 3],   # 厅心毯花砖心
					[hx - 2, hy + hh + 1, 4, cy - hy - hh - 1]]   # 正厅→前院甬道花砖径
			# 正厅中堂组合：挂画对+条案+太师椅+雕花屏；中央茶桌方凳；两翼茶几盆景+灯
			furn = [
				["scroll_pair_a", hx, hy, 0, 0], ["mural_landscape", hx - hall_w / 2 + 3, hy, 0, 0],
				["mural_landscape_b", hx + hall_w / 2 - 4, hy, 0, 0],
				["altar_table", hx, hy + 1, 5, 1],                        # 北墙条案
				["chair_arm_a", hx - 4, hy + 1, 2, 1], ["chair_arm_b", hx + 3, hy + 1, 2, 1],
				["screen_carved_a", hx - hall_w / 2 + 2, hy + 1, 4, 2], ["screen_carved_b", hx + hall_w / 2 - 3, hy + 1, 4, 2],
				["table_square_red", hx, hy + hh - 4, 2, 1], ["stool_round_a", hx - 2, hy + hh - 3, 1, 1], ["stool_round_b", hx + 1, hy + hh - 3, 1, 1],
				["tea_table_b", hx - 7, hy + 4, 3, 1], ["stand_plant", hx + 6, hy + 4, 1, 1],
				["tea_table_a", hx - 7, hy + hh - 5, 3, 1], ["stand_vase", hx + 6, hy + hh - 5, 1, 1],
				["lantern_stand_a", hx - hall_w / 2 + 2, hy + hh - 2, 1, 1], ["lantern_stand_a", hx + hall_w / 2 - 3, hy + hh - 2, 1, 1],
				["lantern_pole_pair", hx - 2, cy + 2, 0, 0],
				# 前院：门轴灯柱+角盆景（E2E 站位 spawn+(0,-3)=中下留空）
				["lantern_std_red", hx - hall_w / 2 + 5, cy + ch - 2, 1, 1], ["lantern_std_red", hx + hall_w / 2 - 6, cy + ch - 2, 1, 1],
				["stand_plant", hx - hall_w / 2 + 5, cy + 1, 1, 1], ["stand_vase", hx + hall_w / 2 - 6, cy + 1, 1, 1],
				["table_set_small", hx - 5, cy + 5, 3, 1], ["jar_white", hx + 5, cy + 5, 1, 1], ["stool_round_a", hx + 6, cy + 6, 1, 1],
				# 卧房：架子床+柜+妆台+灯（spec 视格：北墙中堂组合之外的次主角）
				["bed_canopy_red", chx + wch / 2 - 1, hy + 2, 4, 2],
				["mural_landscape_b", chx + wch / 2 - 1, hy, 0, 0],
				["cabinet_lattice", chx + wch - 3, hy + 2, 3, 2],
				["dresser", chx + 2, hy + 1, 2, 1],
				["lantern_stand_b", chx + 1, hy + hc - 2, 1, 1], ["jar_white", chx + wch - 2, hy + hc - 2, 1, 1],
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
			accents = [[W / 2 - 3, hy2 + 4, 6, 2],   # 蒲团区花砖
					[W / 2 - 2, hy2 + hh2 + 1, 4, cy2 - hy2 - hh2 - 1]]   # 大殿→前庭甬道
			furn = [
				# 大殿：长卷+供案+烛台对+红漆佛柜对+蒲团凳
				["scroll_h_long", W / 2 - 1, hy2, 0, 0],
				["altar_table", W / 2 - 1, hy2 + 1, 5, 1],
				["lantern_stand_a", W / 2 - 5, hy2 + 1, 1, 1], ["lantern_stand_a", W / 2 + 4, hy2 + 1, 1, 1],
				["cabinet_red", W / 2 - 10, hy2 + 1, 3, 2], ["cabinet_red_b", W / 2 + 9, hy2 + 1, 3, 2],
				["stool_round_a", W / 2 - 7, hy2 + 5, 1, 1], ["stool_round_a", W / 2 + 6, hy2 + 5, 1, 1],
				["stool_round_b", W / 2 - 7, hy2 + 7, 1, 1], ["stool_round_b", W / 2 + 6, hy2 + 7, 1, 1],
				["firepit", W / 2 - 10, hy2 + hh2 - 2, 1, 1], ["firepit", W / 2 + 9, hy2 + hh2 - 2, 1, 1],
				# 前庭：神龛+灯柱对+盆景对
				["shrine_small", W / 2 - 1, cy2 + 2, 3, 1],
				["lantern_std_red", 12, cy2 + 3, 1, 1], ["lantern_std_red", W - 14, cy2 + 3, 1, 1],
				["stand_plant", 12, cy2 + ch2 - 3, 1, 1], ["stand_vase", W - 14, cy2 + ch2 - 3, 1, 1],
				["lantern_red_stand", W / 2 - 1, cy2 + ch2 - 3, 1, 1],
			]
		"office":
			rooms = [{"rect": [5, 3, W - 10, int(H * 0.5)], "floor": T_FLOOR_BRICK, "door": "S", "label": "大堂"}]
			accents = [[W / 2 - 3, 9, 6, 2]]
			furn = [
				# 大堂：明镜高悬+文案大案对+文案架+仪仗兵器架+柜台
				["mural_elder", W / 2 - 1, 3, 0, 0],
				["desk_ink", W / 2 - 4, 5, 4, 1], ["desk_scroll", W / 2 + 1, 6, 4, 1],
				["bookshelf_books", 8, 4, 4, 2], ["shelf_curio", W - 10, 4, 4, 2],
				["rack_sword_b", 7, 9, 3, 1], ["rack_halberd", W - 9, 9, 3, 1],
				["counter_doc", W / 2 + 5, 12, 4, 1], ["jars_cluster_b", 8, 13, 4, 1],
				["lantern_stand_a", 11, 11, 1, 1], ["lantern_stand_a", W - 13, 11, 1, 1],
				["lantern_red_stand", W / 2 - 1, 13, 1, 1],
			]
		"palace":
			var py := int(H * 0.52)
			rooms = [
				{"rect": [8, 4, W - 16, int(H * 0.36)], "floor": T_FLOOR_BRICK, "door": "S", "label": "前庭"},
				{"rect": [W / 2 - 20, py, 40, int(H * 0.36)], "floor": T_FLOOR_WOOD, "door": "S", "label": "大殿"},
				{"rect": [W / 2 - 8, py + 6, 16, 8], "floor": T_CARPET, "walls": false, "label": "御座毯"},
			]
			accents = [[W / 2 - 7, py + 10, 14, 2],
					[W / 2 - 2, 4 + int(H * 0.36), 4, py - 4 - int(H * 0.36)]]   # 前庭→大殿甬道
			furn = [
				# 前庭仪仗：灯柱四角+仪仗幡对+兵器架对
				["lantern_std_red", 14, 8, 1, 1], ["lantern_std_red", W - 16, 8, 1, 1],
				["lantern_std_red", 14, int(H * 0.3), 1, 1], ["lantern_std_red", W - 16, int(H * 0.3), 1, 1],
				["yizhang_fan_a", W / 2 - 11, 15, 0, 0], ["yizhang_fan_b", W / 2 + 10, 15, 0, 0],
				["rack_spear", 11, 15, 3, 1], ["rack_sword_b", W - 13, 15, 3, 1],
				# 大殿：花鸟大屏御座+丹陛+金柱对+仪仗幡+兵器架
				["screen_fold_plum", W / 2 - 1, py + 2, 0, 0],
				["cabinet_red_b", W / 2 - 1, py + 4, 3, 2],
				["danbi_medallion", W / 2 - 1, py + 10, 10, 3],
				["pillar_gold", W / 2 - 9, py + 10, 1, 2], ["pillar_gold", W / 2 + 8, py + 10, 1, 2],
				["yizhang_fan_a", W / 2 - 14, py + 10, 0, 0], ["yizhang_fan_b", W / 2 + 13, py + 10, 0, 0],
				["rack_sword", W / 2 - 17, py + 3, 3, 1], ["rack_halberd", W / 2 + 15, py + 3, 3, 1],
				["lantern_std_red", W / 2 - 11, py + 17, 1, 1], ["lantern_std_red", W / 2 + 10, py + 17, 1, 1],
				["jar_shelf", W / 2 - 18, py + 15, 3, 2], ["jar_shelf_b", W / 2 + 16, py + 15, 3, 2],
			]
		"shop":
			rooms = [{"rect": [3, 3, W - 6, H - 8], "floor": T_FLOOR_BRICK, "door": "S", "label": "铺面"}]
			furn = _shop_furn(skin, W)
			accents = [[W / 2 - 1, 10, 2, 2]]   # 门径花砖（原毯心位被柜台遮出碎块）
		"house", "venue":
			rooms = [{"rect": [3, 3, W - 6, H - 8], "floor": T_FLOOR_WOOD, "door": "S", "label": "居室"}]
			furn = [
				["scroll_pair_a", W / 2 - 1, 3, 0, 0],
				["bed_canopy_tan", 7, 5, 4, 2],
				["cabinet_tall", W - 7, 5, 3, 2],
				["desk_ink", W / 2 + 2, 9, 4, 1], ["dresser", W / 2 - 3, 5, 2, 1],
				["tea_table_b", 9, 10, 3, 1], ["stool_round_b", 12, 11, 1, 1],
				["screen_carved_b", W - 6, 9, 4, 2],
				["lantern_stand_b", 5, 4, 1, 1], ["lantern_stand_b", W - 6, 12, 1, 1],
				["stand_plant", W / 2 + 5, 12, 1, 1],
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
			"rooms": rooms, "furn": furn, "accents": accents,
			"spawn": [spawn.x, spawn.y], "exit": [exit.x, exit.y]}

# 五皮肤店铺陈设（铺面 interior x4..W-5, y4..11；门轴 x=W/2±1 留空）
func _shop_furn(skin: String, W: int) -> Array:
	match skin:
		"silk":
			return [
				["shelf_cloth_tall", 6, 5, 4, 2], ["shelf_cloth", 10, 5, 4, 2], ["shelf_cloth_tall", 14, 5, 4, 2],
				["shelf_cloth_b", W - 6, 6, 3, 2],
				["counter_long", 7, 8, 4, 1], ["tea_table_a", 12, 9, 3, 1], ["stool_round_a", 15, 10, 1, 1],
				["lantern_stand_a", 5, 11, 1, 1], ["lantern_stand_a", W - 6, 11, 1, 1],
			]
		"herb":
			return [
				["herb_drawer", 6, 5, 4, 2], ["herb_cabinet_a", 10, 5, 4, 2], ["herb_drawer_b", 14, 5, 4, 2],
				["jar_shelf", W - 6, 6, 3, 2],
				["counter_herb", 8, 8, 4, 1], ["jar_white", 13, 9, 1, 1], ["stool_round_b", 16, 9, 1, 1],
				["lantern_stand_b", 5, 11, 1, 1], ["lantern_stand_b", W - 6, 11, 1, 1],
			]
		"book":
			return [
				["bookshelf_wall", 9, 5, 5, 2], ["bookshelf_books", 15, 5, 4, 2], ["shelf_curio", W - 6, 5, 3, 2],
				["desk_open", 8, 8, 4, 1], ["desk_scroll", 13, 9, 4, 1], ["stool_round_a", 17, 10, 1, 1],
				["lantern_stand_a", 5, 11, 1, 1], ["lantern_stand_a", W - 6, 11, 1, 1],
			]
		"pawn":
			return [
				["cabinet_lattice", 6, 5, 4, 2], ["counter_doc", 11, 5, 4, 1], ["counter_doc", 15, 6, 4, 1],
				["screen_carved_a", W - 6, 6, 4, 2],
				["cabinet_pair", 6, 9, 3, 1], ["jars_cluster_b", 12, 10, 4, 1],
				["lantern_stand_b", 5, 11, 1, 1], ["lantern_stand_b", W - 6, 11, 1, 1],
			]
		_:
			# wine（默认）：酒坛阵+菱格酒架+柜台
			return [
				["jars_cluster", 6, 5, 4, 2], ["wine_rack", 10, 5, 4, 2], ["jars_cluster_b", 14, 5, 4, 2],
				["counter_long_b", 8, 8, 4, 1], ["table_square", 13, 10, 2, 1], ["stool_round_a", 15, 11, 1, 1],
				["jar_white", 5, 9, 1, 1],
				["lantern_pole_pair", 16, 5, 0, 0], ["lantern_stand_a", 5, 11, 1, 1],
			]
