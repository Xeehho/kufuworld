extends Node2D

# Phase C 星露谷交互玩法：农田开垦/浇水/播种/作物生长状态机/浆果丛采集
# 挂载于 /root/Main/World/FarmSystem（Main._setup_farm_system 创建）
# 地面切换用TileMap层0：16=农田 33=湿润农田（tileset_generator已注册）

const TextureGen = preload("res://scripts/texture_generator.gd")
const ItemFactory = preload("res://scripts/item_factory.gd")

const TILE_FARMLAND := 16
const TILE_FARMLAND_WET := 33
const TILLABLE_IDS := [0, 18]          # 草地/深色草地可开垦
const MAX_STAGE := 3                    # 作物阶段 0芽 1苗 2丛 3成熟
const BUSH_REGROW_DAYS := 2
const BUSH_COUNT := 12
const BUSH_MIN_DIST := 10.0             # 距出生点最小距离（瓦片）
const BUSH_MAX_DIST := 55.0

var day_count: int = 1
var _prev_hour: float = -1.0
var _world_gen: Node2D = null
var _tile_map: TileMap = null
var crops: Dictionary = {}              # Vector2i -> {days:int, stage:int, watered:bool, node:Node2D}
var bushes: Dictionary = {}             # Vector2i -> {has_fruit:bool, regrow:int, node:Sprite2D}
var _bush_scattered := false
var _crop_tex_cache: Array = []
var _seeds_granted := false

func _ready():
	add_to_group("farm_system")
	for i in range(MAX_STAGE + 1):
		_crop_tex_cache.append(TextureGen.load_png_texture("res://sprites/farm/crop_%d.png" % i))
	print("[Farm] FarmSystem ready")

func _process(_delta):
	if _world_gen == null:
		_world_gen = get_node_or_null("/root/Main/World/WorldGenerator")
		if _world_gen:
			_tile_map = _world_gen.main_tile_map
			_scatter_berry_bushes()
			_grant_initial_seeds()
	elif not _bush_scattered and _world_gen.main_tile_map != null:
		# 兜底：首帧tile_map未就绪时重试
		_tile_map = _world_gen.main_tile_map
		_scatter_berry_bushes()
	_track_new_day()

# ---------- 新日推进 ----------
func _track_new_day():
	var h: float = GameManager.world_hour
	if _prev_hour > 22.0 and h < 4.0:
		day_count += 1
		on_new_day()
	_prev_hour = h

func on_new_day():
	var rain_water := GameManager.is_raining
	for cell in crops.keys():
		var c: Dictionary = crops[cell]
		if c["watered"] or rain_water:
			c["days"] = int(c["days"]) + 1
		c["watered"] = rain_water   # 雨天自动补水，否则浇水失效需重新浇
		var stage: int = min(int(c["days"]), MAX_STAGE)
		c["stage"] = stage
		_update_crop_sprite(cell)
		_set_ground(cell, TILE_FARMLAND_WET if c["watered"] else TILE_FARMLAND)
	for cell in bushes.keys():
		var b: Dictionary = bushes[cell]
		if not b["has_fruit"]:
			b["regrow"] = int(b["regrow"]) - 1
			if int(b["regrow"]) <= 0:
				b["has_fruit"] = true
				_update_bush_sprite(cell)
	print("[Farm] 第%d天开始 作物%d株 浆果丛%d处%s" % [day_count, crops.size(), bushes.size(), "（雨天自动补水）" if rain_water else ""])

# ---------- 工具动作API（player.gd调用，返回{ok, msg}供飘字） ----------
func try_till(world_pos: Vector2) -> Dictionary:
	var cell := _cell_of(world_pos)
	if crops.has(cell):
		return _fail("这里已有作物")
	if _ground_id(cell) == TILE_FARMLAND or _ground_id(cell) == TILE_FARMLAND_WET:
		return _fail("已经是农田了")
	if not _logical_id(cell) in TILLABLE_IDS:
		return _fail("只能开垦草地")
	_set_ground(cell, TILE_FARMLAND)
	return _ok("开垦完成")

func try_water(world_pos: Vector2) -> Dictionary:
	var cell := _cell_of(world_pos)
	var g := _ground_id(cell)
	if g != TILE_FARMLAND and g != TILE_FARMLAND_WET:
		return _fail("要先开垦成农田")
	if g == TILE_FARMLAND_WET and (not crops.has(cell) or not crops[cell]["watered"]):
		return _fail("土地已经湿润")
	_set_ground(cell, TILE_FARMLAND_WET)
	if crops.has(cell):
		crops[cell]["watered"] = true
	return _ok("浇水完毕")

func try_plant(world_pos: Vector2) -> Dictionary:
	var cell := _cell_of(world_pos)
	var g := _ground_id(cell)
	if g != TILE_FARMLAND and g != TILE_FARMLAND_WET:
		return _fail("要先用锄头开垦")
	if crops.has(cell):
		return _fail("这里已经种了作物")
	var inv := _inventory()
	if inv == null or not inv.has_item("vegetable_seeds"):
		return _fail("没有菜种了")
	inv.remove_item("vegetable_seeds", 1)
	var node := _make_crop_node(cell, 0)
	crops[cell] = {"days": 0, "stage": 0, "watered": g == TILE_FARMLAND_WET, "node": node}
	return _ok("播下菜种")

func try_collect(world_pos: Vector2) -> Dictionary:
	var cell := _cell_of(world_pos)
	# 优先：成熟作物
	if crops.has(cell):
		var c: Dictionary = crops[cell]
		if int(c["stage"]) >= MAX_STAGE:
			var amount := 1 + (randi() % 2)
			ItemFactory.give("veggie", amount)
			_free_crop(cell)
			return _ok("收获青菜x%d" % amount)
		return _fail("庄稼还没成熟(%d/%d天)" % [int(c["stage"]), MAX_STAGE])
	# 其次：浆果丛
	if bushes.has(cell) and bushes[cell]["has_fruit"]:
		var amount := 2 + (randi() % 2)
		ItemFactory.give("berry", amount)
		bushes[cell]["has_fruit"] = false
		bushes[cell]["regrow"] = BUSH_REGROW_DAYS
		_update_bush_sprite(cell)
		return _ok("采到浆果x%d" % amount)
	return _fail("这里没有可采集的东西")

# ---------- 内部实现 ----------
func _cell_of(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / 16.0)), int(floor(world_pos.y / 16.0)))

func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)

func _logical_id(cell: Vector2i) -> int:
	return _world_gen.get_tile_id(cell.x, cell.y) if _world_gen else 0

func _ground_id(cell: Vector2i) -> int:
	if _tile_map == null:
		return -1
	var sid := _tile_map.get_cell_source_id(0, cell)
	return sid  # source_id即瓦片逻辑id

func _set_ground(cell: Vector2i, tile_id: int):
	if _tile_map:
		_tile_map.set_cell(0, cell, tile_id, Vector2i(0, 0))
		if _world_gen and _world_gen.world_cells.has(cell):
			_world_gen.world_cells[cell] = tile_id

func _make_crop_node(cell: Vector2i, stage: int) -> Node2D:
	var node := Node2D.new()
	node.name = "Crop_%d_%d" % [cell.x, cell.y]
	node.position = _cell_center(cell)
	node.z_index = 2
	var spr := Sprite2D.new()
	spr.texture = _crop_tex_cache[clampi(stage, 0, MAX_STAGE)]
	spr.offset = Vector2(0, -8)   # 贴地：图底对齐格子中线偏下
	node.add_child(spr)
	get_parent().add_child(node)
	return node

func _update_crop_sprite(cell: Vector2i):
	var c: Dictionary = crops[cell]
	if c["node"] == null or not is_instance_valid(c["node"]):
		return
	var spr: Sprite2D = c["node"].get_child(0)
	spr.texture = _crop_tex_cache[clampi(int(c["stage"]), 0, MAX_STAGE)]

func _free_crop(cell: Vector2i):
	if crops[cell]["node"] and is_instance_valid(crops[cell]["node"]):
		crops[cell]["node"].queue_free()
	crops.erase(cell)

func _update_bush_sprite(cell: Vector2i):
	var b: Dictionary = bushes[cell]
	if b["node"] == null or not is_instance_valid(b["node"]):
		return
	var tex_path := "res://sprites/farm/berry_bush.png" if b["has_fruit"] else "res://sprites/farm/berry_bush_empty.png"
	b["node"].texture = TextureGen.load_png_texture(tex_path)

func _scatter_berry_bushes():
	if _bush_scattered or _world_gen == null or _tile_map == null:
		return
	_bush_scattered = true
	var spawn_cell := _cell_of(_spawn_player_pos())
	var placed: Array = []
	var attempts := 0
	while placed.size() < BUSH_COUNT and attempts < 400:
		attempts += 1
		var ang := randf() * TAU
		var dist := randf_range(BUSH_MIN_DIST, BUSH_MAX_DIST)
		var cand := spawn_cell + Vector2i(int(cos(ang) * dist), int(sin(ang) * dist))
		if not _world_gen.is_world_pos_reachable(Vector2(cand.x * 16 + 8, cand.y * 16 + 8)):
			continue
		if not _logical_id(cand) in TILLABLE_IDS:
			continue
		var too_close := false
		for p in placed:
			if Vector2(p).distance_to(Vector2(cand)) < 7.0:
				too_close = true
				break
		if too_close:
			continue
		var spr := Sprite2D.new()
		spr.texture = TextureGen.load_png_texture("res://sprites/farm/berry_bush.png")
		spr.position = _cell_center(cand) + Vector2(0, -6)
		spr.z_index = 2
		get_parent().add_child(spr)
		bushes[cand] = {"has_fruit": true, "regrow": 0, "node": spr}
		placed.append(cand)
	print("[Farm] 浆果丛散布 %d 处" % placed.size())

func _spawn_player_pos() -> Vector2:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	return p.global_position if p else Vector2.ZERO

func _grant_initial_seeds():
	if _seeds_granted:
		return
	_seeds_granted = true
	var inv := _inventory()
	if inv and not inv.has_item("vegetable_seeds"):
		ItemFactory.give("vegetable_seeds", 5)
		print("[Farm] 初始发放菜种x5")

func _inventory() -> Node:
	return get_node_or_null("/root/Main/InventoryManager")

func _ok(msg: String) -> Dictionary:
	return {"ok": true, "msg": msg}

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}
