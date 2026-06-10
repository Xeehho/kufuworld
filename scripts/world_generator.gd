extends Node2D

const CHUNK_SIZE = 16
const TILE_SIZE_PX = 32
const CHUNK_PX = CHUNK_SIZE * TILE_SIZE_PX
const LOAD_RADIUS = 3
const WORLD_SEED = 12345

# 世界边界半径（瓦片坐标）
const WORLD_RADIUS = 80

enum Terrain {WATER, SAND, GRASS, GRASS_DARK, FOREST, MOUNTAIN, SNOW}

var height_noise: FastNoiseLite
var humidity_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var tile_set: TileSet = null
var loaded_chunks: Dictionary = {}
var player_chunk: Vector2i = Vector2i(0, 0)
var pois: Array = []
var world_cells: Dictionary = {}

# 河流和城镇的覆盖数据（瓦片坐标 -> tile_id）
var override_cells: Dictionary = {}
# 需要碰撞的瓦片集合
var collision_tiles: Array = [5, 3, 7]

var poi_templates = []

var tile_map_parent: Node2D = null
var main_tile_map: TileMap = null  # 场景中的主TileMap
@onready var player: CharacterBody2D = $"../Player"

func _ready():
	_setup_noise()
	_load_tileset()
	_setup_tilemap_parent()
	_setup_poi_templates()
	_generate_rivers()
	_generate_towns()
	_scatter_pois()
	_apply_poi_terrain()
	# 初始加载玩家周围的chunk
	_initial_load()
	# 强制加载POI所在位置的chunk
	_load_poi_chunks()
	print("[WorldGen] Ready - seed=" + str(WORLD_SEED))

func _setup_noise():
	height_noise = FastNoiseLite.new()
	height_noise.seed = WORLD_SEED
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	height_noise.frequency = 0.004
	height_noise.fractal_octaves = 4
	height_noise.fractal_lacunarity = 2.0
	height_noise.fractal_gain = 0.5

	humidity_noise = FastNoiseLite.new()
	humidity_noise.seed = WORLD_SEED + 1000
	humidity_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	humidity_noise.frequency = 0.003
	humidity_noise.fractal_octaves = 3

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = WORLD_SEED + 2000
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.05

func _load_tileset():
	if ResourceLoader.exists("res://tilesets/ground_tiles.tres"):
		tile_set = load("res://tilesets/ground_tiles.tres")

func _setup_tilemap_parent():
	# 使用场景中已有的TileMap作为主地图
	main_tile_map = get_node_or_null("../TileMap")
	if main_tile_map:
		# 运行时动态赋值tileset
		if tile_set and not main_tile_map.tile_set:
			main_tile_map.tile_set = tile_set
		if main_tile_map.tile_set:
			tile_map_parent = main_tile_map.get_parent()
			# 清空主TileMap中已有的瓦片（如果有）
			main_tile_map.clear()
			return
	# 如果没有主TileMap，创建一个容器
	var p = Node2D.new()
	p.name = "TileMapParent"
	p.y_sort_enabled = true
	add_child(p)
	tile_map_parent = p

# ============ 世界边界系统 ============

func _get_world_border_tile(x: int, y: int) -> int:
	"""检查瓦片是否在世界边界之外，返回强制覆盖的tile_id，-1表示不覆盖"""
	var dist = sqrt(x * x + y * y)
	if dist > WORLD_RADIUS:
		return 5  # 深水
	elif dist > WORLD_RADIUS - 5:
		# 边缘过渡带：根据距离插值
		var t = (dist - (WORLD_RADIUS - 5)) / 5.0
		if t > 0.6:
			return 5  # 水
		else:
			return 6  # 沙
	return -1  # 不覆盖

# ============ 河流系统 ============

func _generate_rivers():
	"""使用正弦曲线生成2-3条河流"""
	var rng = RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 3000

	var river_count = rng.randi_range(2, 3)
	for i in range(river_count):
		var amplitude = rng.randf_range(10.0, 25.0)
		var frequency = rng.randf_range(0.03, 0.08)
		var phase = rng.randf_range(0.0, TAU)
		var offset_y = rng.randi_range(-40, 40)
		var width = rng.randi_range(3, 5)
		var horizontal = rng.randf() > 0.5  # 水平或垂直河流

		# 河流路径
		for t in range(-WORLD_RADIUS, WORLD_RADIUS):
			var curve_val = offset_y + amplitude * sin(frequency * t + phase)
			var center: int
			if horizontal:
				center = int(round(curve_val))
			else:
				center = int(round(curve_val))

			for w in range(-width / 2, width / 2 + 1):
				var rx: int
				var ry: int
				if horizontal:
					rx = t
					ry = center + w
				else:
					rx = center + w
					ry = t

				var cell = Vector2i(rx, ry)
				# 河流中心是水，边缘是沙
				if abs(w) <= 1:
					override_cells[cell] = 5  # 水
				else:
					if not override_cells.has(cell):
						override_cells[cell] = 6  # 沙

		# 在河流上放置桥（每隔一定距离）
		for t in range(-WORLD_RADIUS + 10, WORLD_RADIUS - 10, 15):
			var curve_val = offset_y + amplitude * sin(frequency * t + phase)
			var center: int
			if horizontal:
				center = int(round(curve_val))
			else:
				center = int(round(curve_val))

			var bridge_cell: Vector2i
			if horizontal:
				bridge_cell = Vector2i(t, center)
			else:
				bridge_cell = Vector2i(center, t)

			# 桥替换水面
			override_cells[bridge_cell] = 17  # 桥
			# 桥两端铺路
			if horizontal:
				override_cells[Vector2i(t - 1, center)] = 1  # 路
				override_cells[Vector2i(t + 1, center)] = 1  # 路
			else:
				override_cells[Vector2i(center, t - 1)] = 1  # 路
				override_cells[Vector2i(center, t + 1)] = 1  # 路

	print("[WorldGen] Generated " + str(river_count) + " rivers")

# ============ 城镇系统 ============

func _generate_towns():
	"""在合适位置生成3-5个城镇区域"""
	var rng = RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 4000

	var town_count = rng.randi_range(3, 5)
	var town_positions: Array = []

	for i in range(town_count):
		var placed = false
		for _attempt in range(30):
			var tx = rng.randi_range(-50, 50)
			var ty = rng.randi_range(-40, 40)
			var h = get_height(tx, ty)
			var w = get_humidity(tx, ty)

			# 城镇只在平地（草地）生成
			if h < -0.15 or h > 0.2:
				continue
			if w < -0.3 or w > 0.6:
				continue

			# 检查与其他城镇的距离
			var too_close = false
			for tp in town_positions:
				if Vector2(tx, ty).distance_to(tp) < 20:
					too_close = true
					break
			if too_close:
				continue

			# 检查是否在边界内
			if sqrt(tx * tx + ty * ty) > WORLD_RADIUS - 10:
				continue

			town_positions.append(Vector2(tx, ty))
			_generate_single_town(tx, ty, rng)
			placed = true
			break

		if not placed:
			print("[WorldGen] Could not place town " + str(i))

	print("[WorldGen] Generated " + str(town_positions.size()) + " towns")

func _generate_single_town(cx: int, cy: int, rng: RandomNumberGenerator):
	"""在指定位置生成一个城镇"""
	var size = rng.randi_range(3, 5)  # 3x3 到 5x5
	var half = size / 2

	# 城镇周围先铺农田和栅栏
	for dx in range(-half - 2, half + 3):
		for dy in range(-half - 2, half + 3):
			var wx = cx + dx
			var wy = cy + dy
			var cell = Vector2i(wx, wy)
			var local_dist = max(abs(dx), abs(dy))

			if local_dist == half + 2:
				# 外围栅栏
				override_cells[cell] = 15  # 栅栏
			elif local_dist == half + 1:
				# 农田环
				override_cells[cell] = 16  # 农田

	# 城镇内部
	for dx in range(-half, half + 1):
		for dy in range(-half, half + 1):
			var wx = cx + dx
			var wy = cy + dy
			var cell = Vector2i(wx, wy)

			# 中心十字路
			if dx == 0 or dy == 0:
				override_cells[cell] = 1  # 路
			else:
				# 房屋
				var r = rng.randf()
				if r < 0.4:
					override_cells[cell] = 2   # 城镇房
				elif r < 0.6:
					override_cells[cell] = 10  # 茅屋
				else:
					override_cells[cell] = 0   # 草地（院子）

# ============ 地形生成（含边界和覆盖） ============

func get_height(x: int, y: int) -> float:
	return height_noise.get_noise_2d(x, y)

func get_humidity(x: int, y: int) -> float:
	return humidity_noise.get_noise_2d(x, y)

func get_terrain(x: int, y: int) -> Terrain:
	var h = get_height(x, y)
	var w = get_humidity(x, y)
	if h < -0.25:
		return Terrain.WATER
	elif h < -0.05:
		return Terrain.SAND
	elif h < 0.25:
		if w > 0.2:
			return Terrain.FOREST
		elif w > 0.0:
			return Terrain.GRASS_DARK
		return Terrain.GRASS
	elif h < 0.55:
		return Terrain.MOUNTAIN
	return Terrain.SNOW

func get_tile_id(x: int, y: int) -> int:
	# 1. 检查世界边界覆盖
	var border_tile = _get_world_border_tile(x, y)
	if border_tile >= 0:
		return border_tile

	# 2. 检查河流/城镇覆盖
	var cell = Vector2i(x, y)
	if override_cells.has(cell):
		return override_cells[cell]

	# 3. 默认噪声地形
	var t = get_terrain(x, y)
	var d = detail_noise.get_noise_2d(x, y)
	match t:
		Terrain.WATER: return 5
		Terrain.SAND: return 6
		Terrain.GRASS: return 0
		Terrain.GRASS_DARK: return 18
		Terrain.FOREST:
			var r = fmod(d + 1.0, 1.0)
			if r > 0.85:
				return 4  # 松树
			elif r > 0.75:
				return 8  # 橡树
			elif r > 0.70:
				return 9  # 竹子
			elif r > 0.67:
				return 13 # 花
			return 0
		Terrain.MOUNTAIN:
			if d > 0.3:
				return 14 # 石头
			return 3
		Terrain.SNOW:
			if d > 0.4:
				return 7  # 雪山
			return 7
	return 0

# ============ Chunk系统 ============

func world_to_chunk(world_pos: Vector2) -> Vector2i:
	var cx = int(floor(world_pos.x / CHUNK_PX))
	var cy = int(floor(world_pos.y / CHUNK_PX))
	return Vector2i(cx, cy)

func chunk_to_world(chunk: Vector2i) -> Vector2:
	return Vector2(chunk.x * CHUNK_PX, chunk.y * CHUNK_PX)

func _process(_delta):
	if not player:
		return
	var pc = world_to_chunk(player.global_position)
	if pc != player_chunk:
		player_chunk = pc
		_update_chunks()

func _initial_load():
	# 加载玩家初始位置周围的chunk
	if player:
		player_chunk = world_to_chunk(player.global_position)
	else:
		player_chunk = Vector2i(0, 0)
	_update_chunks()

func _update_chunks():
	var needed: Array = []
	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			needed.append(player_chunk + Vector2i(dx, dy))

	var to_remove: Array = []
	for key in loaded_chunks:
		if not needed.has(key):
			to_remove.append(key)

	for key in to_remove:
		_unload_chunk(key)

	for key in needed:
		if not loaded_chunks.has(key):
			_load_chunk(key)

func _load_chunk(chunk: Vector2i):
	if tile_set == null:
		return

	var tm = main_tile_map
	if tm == null:
		return

	var start_x = chunk.x * CHUNK_SIZE
	var start_y = chunk.y * CHUNK_SIZE
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var wx = start_x + x
			var wy = start_y + y
			var cell = Vector2i(wx, wy)
			# 只设置尚未设置的瓦片
			if tm.get_cell_source_id(0, cell) == -1:
				var tid = get_tile_id(wx, wy)
				if tid >= 0:
					tm.set_cell(0, cell, tid, Vector2i(0, 0))
			world_cells[cell] = get_tile_id(wx, wy)

	loaded_chunks[chunk] = true

func _unload_chunk(chunk: Vector2i):
	# 使用单一TileMap时，不卸载chunk以避免空隙
	loaded_chunks.erase(chunk)

# ============ POI周围chunk强制加载 ============

func _load_poi_chunks():
	"""确保所有POI位置周围的chunk被加载"""
	for p in pois:
		var poi_pos: Vector2 = p["position"]
		var poi_chunk = world_to_chunk(poi_pos)
		# 加载POI所在chunk及周围1格
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var c = poi_chunk + Vector2i(dx, dy)
				if not loaded_chunks.has(c):
					_load_chunk(c)
	print("[WorldGen] POI chunks loaded")

func _apply_poi_terrain():
	"""在POI周围铺上专属地形瓦片"""
	for p in pois:
		var poi_pos: Vector2 = p["position"]
		var tpl: POITemplate = p["template"]
		# 将像素坐标转为瓦片坐标
		var tx = int(round(poi_pos.x / TILE_SIZE_PX))
		var ty = int(round(poi_pos.y / TILE_SIZE_PX))

		match tpl.poi_type:
			"门派":
				_apply_sect_terrain(tx, ty)
			"城镇":
				_apply_town_poi_terrain(tx, ty)
			"洞穴":
				_apply_cave_terrain(tx, ty)
			"修炼场":
				_apply_training_terrain(tx, ty)

func _apply_sect_terrain(cx: int, cy: int):
	"""门派周围铺山地+寺庙"""
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var cell = Vector2i(cx + dx, cy + dy)
			var dist = max(abs(dx), abs(dy))
			if dist <= 1:
				# 中心：寺庙
				if dx == 0 and dy == 0:
					override_cells[cell] = 11  # 寺
				else:
					override_cells[cell] = 1   # 路
			elif dist <= 2:
				override_cells[cell] = 3   # 山
			elif dist <= 3:
				# 外围松树
				var r = fmod(detail_noise.get_noise_2d(cx + dx, cy + dy) + 1.0, 1.0)
				if r > 0.5:
					override_cells[cell] = 4   # 松树
				else:
					override_cells[cell] = 0   # 草

func _apply_town_poi_terrain(cx: int, cy: int):
	"""城镇POI周围铺房屋+农田"""
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var cell = Vector2i(cx + dx, cy + dy)
			var dist = max(abs(dx), abs(dy))
			if dist == 0:
				override_cells[cell] = 2   # 城镇房
			elif dist == 1:
				if dx == 0 or dy == 0:
					override_cells[cell] = 1   # 路
				else:
					override_cells[cell] = 10  # 茅屋
			elif dist == 2:
				override_cells[cell] = 16  # 农田
			elif dist == 3:
				override_cells[cell] = 15  # 栅栏

func _apply_cave_terrain(cx: int, cy: int):
	"""洞穴周围铺石头"""
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var cell = Vector2i(cx + dx, cy + dy)
			var dist = max(abs(dx), abs(dy))
			if dist == 0:
				override_cells[cell] = 12  # 洞
			elif dist <= 1:
				override_cells[cell] = 14  # 石头
			elif dist <= 2:
				var r = fmod(detail_noise.get_noise_2d(cx + dx, cy + dy) + 1.0, 1.0)
				if r > 0.6:
					override_cells[cell] = 14  # 石头
				else:
					override_cells[cell] = 3   # 山

func _apply_training_terrain(cx: int, cy: int):
	"""修炼场周围铺草地+花"""
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var cell = Vector2i(cx + dx, cy + dy)
			var dist = max(abs(dx), abs(dy))
			if dist == 0:
				override_cells[cell] = 11  # 寺
			elif dist <= 1:
				override_cells[cell] = 1   # 路
			elif dist <= 2:
				override_cells[cell] = 13  # 花
			else:
				override_cells[cell] = 0   # 草

# ============ POI系统 ============

func _setup_poi_templates():
	var shaolin = POITemplate.new()
	shaolin.poi_name = "少林寺"
	shaolin.poi_type = "门派"
	shaolin.min_height = 0.1
	shaolin.max_height = 0.6
	shaolin.min_humidity = -1.0
	shaolin.max_humidity = 0.3
	shaolin.min_distance = 20.0
	shaolin.spawn_weight = 100.0
	shaolin.icon_color = Color(1, 0.6, 0.1)
	shaolin.spawn_npcs = 3
	shaolin.description = "天下武功出少林"
	poi_templates.append(shaolin)

	var wudang = POITemplate.new()
	wudang.poi_name = "武当派"
	wudang.poi_type = "门派"
	wudang.min_height = 0.15
	wudang.max_height = 0.6
	wudang.min_humidity = -0.2
	wudang.max_humidity = 0.5
	wudang.min_distance = 20.0
	wudang.spawn_weight = 100.0
	wudang.icon_color = Color(0.3, 0.5, 1)
	wudang.spawn_npcs = 3
	wudang.description = "太极拳剑，以柔克刚"
	poi_templates.append(wudang)

	var town_tpl = POITemplate.new()
	town_tpl.poi_name = "江南小镇"
	town_tpl.poi_type = "城镇"
	town_tpl.min_height = -0.15
	town_tpl.max_height = 0.2
	town_tpl.min_humidity = -0.2
	town_tpl.max_humidity = 0.6
	town_tpl.min_distance = 12.0
	town_tpl.spawn_weight = 3.0
	town_tpl.icon_color = Color(0.6, 0.8, 0.4)
	town_tpl.spawn_npcs = 2
	town_tpl.description = "水乡小镇，商贾往来"
	poi_templates.append(town_tpl)

	var cave_tpl = POITemplate.new()
	cave_tpl.poi_name = "古墓密洞"
	cave_tpl.poi_type = "洞穴"
	cave_tpl.min_height = -0.1
	cave_tpl.max_height = 0.5
	cave_tpl.min_humidity = -1.0
	cave_tpl.max_humidity = 1.0
	cave_tpl.min_distance = 15.0
	cave_tpl.spawn_weight = 2.0
	cave_tpl.icon_color = Color(0.4, 0.2, 0.6)
	cave_tpl.spawn_npcs = 0
	cave_tpl.description = "幽深古洞，神秘莫测"
	poi_templates.append(cave_tpl)

	var sacred_tpl = POITemplate.new()
	sacred_tpl.poi_name = "灵脉修炼场"
	sacred_tpl.poi_type = "修炼场"
	sacred_tpl.min_height = 0.2
	sacred_tpl.max_height = 0.7
	sacred_tpl.min_humidity = -0.3
	sacred_tpl.max_humidity = 0.3
	sacred_tpl.min_distance = 18.0
	sacred_tpl.spawn_weight = 2.5
	sacred_tpl.icon_color = Color(1, 0.9, 0.4)
	sacred_tpl.spawn_npcs = 1
	sacred_tpl.description = "天地灵气汇聚之地"
	poi_templates.append(sacred_tpl)

func _scatter_pois():
	var rng = RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 5000

	pois.clear()

	for tpl in poi_templates:
		if tpl.spawn_weight >= 100:
			_force_spawn_poi(tpl, rng)
		else:
			var attempts = int(tpl.spawn_weight * 5)
			for _i in range(attempts):
				if rng.randf() < tpl.spawn_weight / 6.0:
					if _try_spawn_poi(tpl, rng):
						break

	print("[WorldGen] POIs scattered: " + str(pois.size()))

func _try_spawn_poi(tpl: POITemplate, rng: RandomNumberGenerator) -> bool:
	for _attempt in range(20):
		var wx = rng.randi_range(-60, 60)
		var wy = rng.randi_range(-45, 45)
		var h = get_height(wx, wy)
		var w = get_humidity(wx, wy)
		if h < tpl.min_height or h > tpl.max_height:
			continue
		if w < tpl.min_humidity or w > tpl.max_humidity:
			continue
		var pos = Vector2(wx * TILE_SIZE_PX, wy * TILE_SIZE_PX)
		if _too_close_to_other_poi(pos, tpl.min_distance):
			continue
		# 检查是否在世界边界内
		if sqrt(wx * wx + wy * wy) > WORLD_RADIUS - 10:
			continue
		_create_poi_marker(tpl, pos)
		return true
	return false

func _force_spawn_poi(tpl: POITemplate, _rng: RandomNumberGenerator):
	if tpl.poi_name == "少林寺":
		_create_poi_marker(tpl, Vector2(-600, 300))
	elif tpl.poi_name == "武当派":
		_create_poi_marker(tpl, Vector2(400, 200))
	else:
		for _attempt in range(50):
			if _try_spawn_poi(tpl, RandomNumberGenerator.new()):
				break

func _create_poi_marker(tpl: POITemplate, pos: Vector2):
	var marker = Node2D.new()
	marker.name = "POI_" + tpl.poi_name.replace(" ", "_")
	marker.global_position = pos
	marker.y_sort_enabled = true
	marker.z_index = 10

	# 建筑群 - 根据POI类型放置不同建筑
	var building_tile = _poi_building_tile(tpl.poi_type)
	var building_count = _poi_building_count(tpl.poi_type)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(tpl.poi_name)

	# 中心建筑
	var center_sprite = Sprite2D.new()
	center_sprite.texture = load(building_tile) if ResourceLoader.exists(building_tile) else null
	center_sprite.z_index = 10
	center_sprite.y_sort_enabled = true
	marker.add_child(center_sprite)

	# 周围建筑
	for i in range(building_count - 1):
		var bx = rng.randi_range(-3, 3) * TILE_SIZE_PX
		var by = rng.randi_range(-2, 2) * TILE_SIZE_PX
		var bld_sprite = Sprite2D.new()
		var bld_tile = _poi_secondary_building_tile(tpl.poi_type, rng)
		if ResourceLoader.exists(bld_tile):
			bld_sprite.texture = load(bld_tile)
		bld_sprite.position = Vector2(bx, by)
		bld_sprite.z_index = 10
		bld_sprite.y_sort_enabled = true
		marker.add_child(bld_sprite)

	# 装饰物
	var deco_count = rng.randi_range(2, 5)
	for i in range(deco_count):
		var dx = rng.randi_range(-4, 4) * TILE_SIZE_PX
		var dy = rng.randi_range(-3, 3) * TILE_SIZE_PX
		var deco_sprite = Sprite2D.new()
		var deco_tile = _random_decoration(rng)
		if ResourceLoader.exists(deco_tile):
			deco_sprite.texture = load(deco_tile)
		deco_sprite.position = Vector2(dx, dy)
		deco_sprite.z_index = 10
		deco_sprite.y_sort_enabled = true
		marker.add_child(deco_sprite)

	# 地点名称标签
	var label = Label.new()
	label.text = tpl.poi_name
	label.position = Vector2(-30, -40)
	label.z_index = 20
	label.add_theme_color_override("font_color", tpl.icon_color)
	label.add_theme_font_size_override("font_size", 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_child(label)

	# 环境区域
	var env_zone = Area2D.new()
	env_zone.name = "EnvironmentZone"
	env_zone.position = Vector2.ZERO
	env_zone.z_index = 0
	var col_shape = CollisionShape2D.new()
	col_shape.shape = RectangleShape2D.new()
	col_shape.shape.size = Vector2(150, 120)
	env_zone.add_child(col_shape)
	var zone_script = load("res://scripts/environment_zone.gd")
	if zone_script:
		env_zone.set_script(zone_script)
		env_zone.environment_name = tpl.poi_name
	marker.add_child(env_zone)

	add_child(marker)
	pois.append({"template": tpl, "position": pos, "node": marker})
	print("[WorldGen] Placed POI: " + tpl.poi_name + " at " + str(pos))

func _poi_building_tile(poi_type: String) -> String:
	match poi_type:
		"门派": return "res://sprites/tiles/house_temple.png"
		"城镇": return "res://sprites/tiles/house_town.png"
		"洞穴": return "res://sprites/tiles/house_cave.png"
		"修炼场": return "res://sprites/tiles/house_temple.png"
		"遗迹": return "res://sprites/tiles/house_cave.png"
		"集市": return "res://sprites/tiles/house_town.png"
		_: return "res://sprites/tiles/house_cottage.png"

func _poi_secondary_building_tile(poi_type: String, rng: RandomNumberGenerator) -> String:
	match poi_type:
		"门派":
			return ["res://sprites/tiles/house_cottage.png", "res://sprites/tiles/house_temple.png"][rng.randi() % 2]
		"城镇":
			return ["res://sprites/tiles/house_town.png", "res://sprites/tiles/house_cottage.png", "res://sprites/tiles/farmland.png"][rng.randi() % 3]
		"洞穴":
			return "res://sprites/tiles/rock.png"
		"修炼场":
			return "res://sprites/tiles/house_cottage.png"
		_:
			return "res://sprites/tiles/house_cottage.png"

func _poi_building_count(poi_type: String) -> int:
	match poi_type:
		"门派": return 4
		"城镇": return 5
		"洞穴": return 2
		"修炼场": return 3
		"遗迹": return 2
		"集市": return 4
		_: return 2

func _random_decoration(rng: RandomNumberGenerator) -> String:
	var options = [
		"res://sprites/tiles/tree_pine.png",
		"res://sprites/tiles/tree_oak.png",
		"res://sprites/tiles/flower.png",
		"res://sprites/tiles/rock.png",
		"res://sprites/tiles/fence.png",
	]
	return options[rng.randi() % options.size()]

func _too_close_to_other_poi(pos: Vector2, min_dist: float) -> bool:
	for p in pois:
		if pos.distance_to(p["position"]) < min_dist * TILE_SIZE_PX:
			return true
	return false

func get_pois_near(pos: Vector2, radius: float) -> Array:
	var result: Array = []
	for p in pois:
		if pos.distance_to(p["position"]) < radius:
			result.append(p)
	return result
