extends Node2D

const CHUNK_SIZE = 16
const TILE_SIZE_PX = 32
const CHUNK_PX = CHUNK_SIZE * TILE_SIZE_PX
const LOAD_RADIUS = 3
const WORLD_SEED = 12345

enum Terrain {WATER, SAND, GRASS, GRASS_DARK, FOREST, MOUNTAIN, SNOW}

var height_noise: FastNoiseLite
var humidity_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var tile_set: TileSet = null
var loaded_chunks: Dictionary = {}
var player_chunk: Vector2i = Vector2i(0, 0)
var pois: Array = []
var world_cells: Dictionary = {}

var poi_templates = []

var tile_map_parent: Node2D = null
var main_tile_map: TileMap = null  # 场景中的主TileMap
@onready var player: CharacterBody2D = $"../Player"

func _ready():
	_setup_noise()
	_load_tileset()
	_setup_tilemap_parent()
	_setup_poi_templates()
	_scatter_pois()
	# 初始加载玩家周围的chunk
	_initial_load()
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
	if main_tile_map and main_tile_map.tile_set:
		tile_map_parent = main_tile_map.get_parent()
		# 清空主TileMap中已有的瓦片（如果有）
		main_tile_map.clear()
	else:
		# 如果没有主TileMap，创建一个容器
		var p = Node2D.new()
		p.name = "TileMapParent"
		p.y_sort_enabled = true
		add_child(p)
		tile_map_parent = p

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
	var t = get_terrain(x, y)
	var d = detail_noise.get_noise_2d(x, y)
	match t:
		Terrain.WATER: return 5
		Terrain.SAND: return 6
		Terrain.GRASS: return 0
		Terrain.GRASS_DARK: return 18
		Terrain.FOREST:
			# 森林中随机放置树木和花朵
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

	# 使用主TileMap直接设置瓦片，避免创建多个TileMap导致空隙
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

	loaded_chunks[chunk] = true  # 标记chunk已加载

func _unload_chunk(chunk: Vector2i):
	# 使用单一TileMap时，不卸载chunk以避免空隙
	# 只标记为已加载，不实际删除瓦片
	loaded_chunks.erase(chunk)

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
		var wx = rng.randi_range(-80, 80)
		var wy = rng.randi_range(-60, 60)
		var h = get_height(wx, wy)
		var w = get_humidity(wx, wy)
		if h < tpl.min_height or h > tpl.max_height:
			continue
		if w < tpl.min_humidity or w > tpl.max_humidity:
			continue
		var pos = Vector2(wx * TILE_SIZE_PX, wy * TILE_SIZE_PX)
		if _too_close_to_other_poi(pos, tpl.min_distance):
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
	marker.z_index = 10  # 确保在地面瓦片之上

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

	# 地点名称标签 - 使用Label3D风格，确保在最上层
	var label = Label.new()
	label.text = tpl.poi_name
	label.position = Vector2(-30, -40)
	label.z_index = 20  # 标签在建筑之上
	label.add_theme_color_override("font_color", tpl.icon_color)
	label.add_theme_font_size_override("font_size", 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_child(label)

	# 环境区域
	var env_zone = Area2D.new()
	env_zone.name = "EnvironmentZone"
	env_zone.position = Vector2.ZERO
	env_zone.z_index = 0  # 碰撞区域不需要z_index
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
