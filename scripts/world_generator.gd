extends Node2D

const TextureGen = preload("res://scripts/texture_generator.gd")
const TilesetGen = preload("res://scripts/tileset_generator.gd")

const CHUNK_SIZE = 16
const TILE_SIZE_PX = 16
const CHUNK_PX = CHUNK_SIZE * TILE_SIZE_PX
const LOAD_RADIUS = 3
const WORLD_SEED = 12345

# 世界边界半径（瓦片坐标）
const WORLD_RADIUS = 120

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
# 需要碰撞的瓦片集合（含多格建筑部件19-32、39=大建筑footprint占位）
var collision_tiles: Array = [5, 3, 7, 2, 10, 11, 12, 14, 15, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 39]
# 多格建筑部件ID集合（供地面铺设/布局判断）
var building_part_tiles: Array = [19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]
# 每种宽度建筑各部件的瓦片ID（与 BUILDING_PARTS 顺序一致：左→右）
const BUILDING_PART_IDS = {
	2: [19, 20],
	3: [21, 22, 23],
	4: [24, 25, 26, 27],
	5: [28, 29, 30, 31, 32],
}
# ---- Phase F5: 大型建筑道具（星露谷比例，Sprite+StaticBody，替代16px瓦片房）----
# fp=footprint占格(瓦片)；纹理由 texture_generator.generate_big_buildings() 生成到 sprites/buildings/
const BUILDING_PROPS := {
	"hut":    {"png": "res://sprites/buildings/hut.png",    "fp": Vector2i(3, 2)},
	"house":  {"png": "res://sprites/buildings/house.png",  "fp": Vector2i(4, 3)},
	"manor":  {"png": "res://sprites/buildings/manor.png",  "fp": Vector2i(6, 4)},
	"temple": {"png": "res://sprites/buildings/temple.png", "fp": Vector2i(7, 5)},
}
# 虚拟占位tile id：footprint格子写入override_cells，参与碰撞/可达性但不在TileMap绘制
const TILE_BUILDING_RESERVE := 39
# 可达性洪泛结果（以玩家出生点为源，玩家可通行的瓦片集合）
var reachable_cells: Dictionary = {}

var poi_templates = []

var tile_map_parent: Node2D = null
var main_tile_map: TileMap = null  # 场景中的主TileMap
@onready var player: CharacterBody2D = $"../Player"

# ============ 素材包大树道具 (Pixel Crawler) ============
# 树瓦片ID(4松/8橡/9竹)不再画进TileMap，改为生成y排序Sprite道具
# Phase G2：连通分量实测真实网格——松32x80(4x2)、橡64x64(4x2)、竹48x80(3x2)。
# 旧声明(64x80/128x64/72x80)跨树取图：一个道具渲染出两棵半树、竹被x=72竖切一半（"树只渲染了一半"根因）
const TREE_SHEETS := {
	4: {"path": "res://downloaded_assets/Pixel Crawler - Free Pack/Environment/Props/Static/Trees/Model_03/Size_02.png", "cell": Vector2i(32, 80)},   # 松树(锥形) 4x2=8变体
	8: {"path": "res://downloaded_assets/Pixel Crawler - Free Pack/Environment/Props/Static/Trees/Model_01/Size_02.png", "cell": Vector2i(64, 64)},   # 橡树(宽冠) 4x2=8变体
	9: {"path": "res://downloaded_assets/Pixel Crawler - Free Pack/Environment/Props/Static/Trees/Model_02/Size_03.png", "cell": Vector2i(48, 80)},   # 竹/细高树 3x2=6变体
}
var _tree_sheet_cache: Dictionary = {}
var _tree_shadow_tex: ImageTexture = null

func _get_tree_sheet_texture(tid: int) -> Texture2D:
	if _tree_sheet_cache.has(tid):
		return _tree_sheet_cache[tid]
	var tex = TextureGen.load_png_texture(TREE_SHEETS[tid]["path"])
	_tree_sheet_cache[tid] = tex
	return tex

# Phase B-3：树底椭圆软阴影（径向衰减白椭圆，modulate压黑半透明），提升落地感
func _get_tree_shadow_texture() -> ImageTexture:
	if _tree_shadow_tex != null:
		return _tree_shadow_tex
	var img = Image.create(48, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(48):
		for y in range(20):
			var dx = (x - 23.5) / 23.5
			var dy = (y - 9.5) / 9.5
			var d = sqrt(dx * dx + dy * dy)
			if d < 1.0:
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, pow(a, 1.35)))
	_tree_shadow_tex = ImageTexture.create_from_image(img)
	return _tree_shadow_tex

func _tree_grid(tid: int) -> Vector2i:
	"""树表真实网格列×行（Phase G2连通分量实测，供变体索引取模）"""
	match tid:
		4: return Vector2i(4, 2)
		8: return Vector2i(4, 2)
		9: return Vector2i(3, 2)
	return Vector2i(2, 2)

func _near_water(wx: int, wy: int, r: int) -> bool:
	"""方形半径r内是否存在水面瓦片——防止树冠悬到海面/河面上（G2）"""
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if get_tile_id(wx + dx, wy + dy) == 5:
				return true
	return false

func _should_spawn_tree_prop(wx: int, wy: int, tid: int) -> bool:
	"""树道具落位闸门：水邻抑制+城镇净空抑制。被拒的格子只铺地面，不再回退画16px小树瓦片"""
	var cell: Vector2i = TREE_SHEETS[tid]["cell"]
	var r: int = int(ceil(cell.x / 32.0)) + 1   # 冠幅一半(格)+安全1格：松2 橡3 竹3
	if _near_water(wx, wy, r):
		return false
	if _in_town_clearance(wx, wy):
		return false
	return true

func _spawn_tree_prop(wx: int, wy: int, tid: int) -> bool:
	var info: Dictionary = TREE_SHEETS[tid]
	var sheet = _get_tree_sheet_texture(tid)
	if sheet == null:
		return false
	var cell: Vector2i = info["cell"]
	var grid := _tree_grid(tid)
	var variant: int = abs(int(detail_noise.get_noise_2d(wx * 7.3, wy * 11.9) * 100.0)) % (grid.x * grid.y)
	var atlas = AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(float(variant % grid.x) * cell.x, float(variant / grid.x) * cell.y, cell.x, cell.y)
	var prop = Sprite2D.new()
	prop.texture = atlas
	prop.z_index = 2  # 与玩家/NPC/Mob统一实体层z=2，交给World递归Y-sort交融（G4）
	# Phase G4基点锚定：节点原点=树干脚底(瓦片底缘+4px入土)，贴图用offset上移半高。
	# Y-sort按节点y排序，锚在脚底才能正确表现"人在树前/树后"
	var jitter_x: float = fposmod(detail_noise.get_noise_2d(wx * 3.1, wy * 5.7), 1.0) * 6.0 - 3.0
	prop.position = Vector2(wx * 16.0 + 8.0 + jitter_x, wy * 16.0 + 20.0)
	prop.offset = Vector2(0, -cell.y * 0.5)
	prop.add_to_group("tree_prop")
	prop.set_meta("base_y", prop.position.y)
	# 椭圆阴影垫在树脚（z=-1相对树体，画在树干后、地面之上）
	var shadow = Sprite2D.new()
	shadow.texture = _get_tree_shadow_texture()
	var shadow_w: float = clampf(cell.x * 0.75, 24.0, 48.0)
	shadow.scale = Vector2(shadow_w / 48.0, shadow_w * 0.38 / 20.0)
	shadow.position = Vector2(jitter_x * -0.5, -4.0)
	shadow.z_index = -1  # 相对-1=等效z1：地面之上、树干之下
	shadow.modulate = Color(0, 0, 0, 0.30)
	shadow.set_meta("shadow_base_a", 0.30)   # Phase D：昼夜树影强度基准（WeatherController按日照系数缩放）
	shadow.add_to_group("tree_shadow")
	prop.add_child(shadow)
	get_parent().add_child(prop)
	return true

func _ready():
	# Phase G4：本节点开启Y-sort，使POI地标等子节点并入World递归Y排序
	y_sort_enabled = true
	_setup_noise()
	_setup_biomes()	# Phase F6: 饥荒式区域划分（先于一切get_tile_id调用）
	_load_tileset()
	_setup_tilemap_parent()
	_setup_poi_templates()
	_generate_rivers()
	# 顺序关键：先定位安全出生点，再以出生点为源做可达性洪泛，
	# 之后城镇/POI选址必须落在可达区内（修复少林寺入口在海上等问题）
	_relocate_player_to_safe_spawn()
	_compute_reachable_region()
	_generate_towns()
	_scatter_pois()
	_apply_poi_terrain()
	_ensure_connectivity()	# Phase F6: 打通所有封闭区域（石中沙地等孤岛开路）
	_compute_reachable_region()	# 刷新对外可达查询（NPC/营地选址用最新数据）
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

# ---- Phase F6: 饥荒式生物群系区域 ----
const BIOME_KINDS := ["plains", "forest", "bamboo", "mountain", "desert", "snow", "lake"]
var biome_seeds: Array = []   # [{"pos":Vector2i, "kind":String}]

func _setup_biomes():
	"""环形撒9个群系首府+中央固定平原；瓦片归属=最近首府(带噪声抖动边界)"""
	var rng = RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 777
	biome_seeds.clear()
	var count := BIOME_KINDS.size() + 2
	for i in range(count):
		var ang := TAU * i / count + rng.randf_range(-0.3, 0.3)
		var rad := rng.randf_range(30.0, WORLD_RADIUS - 24.0)
		var pos := Vector2i(int(cos(ang) * rad), int(sin(ang) * rad))
		var kind: String = BIOME_KINDS[i % BIOME_KINDS.size()]
		biome_seeds.append({"pos": pos, "kind": kind})
	biome_seeds.append({"pos": Vector2i.ZERO, "kind": "plains"})	# 出生区必为平原

func _biome_kind(x: int, y: int) -> String:
	if biome_seeds.is_empty():
		return "plains"
	var jitter: float = detail_noise.get_noise_2d(x * 1.7, y * 2.3) * 14.0
	var best_d := 1e12
	var best_kind := "plains"
	for b in biome_seeds:
		var p: Vector2i = b["pos"]
		var d := Vector2(p.x - x, p.y - y).length_squared() + jitter * jitter * 0.01
		if d < best_d:
			best_d = d
			best_kind = b["kind"]
	return best_kind

func _lake_surface_dist(x: int, y: int, seed_pos: Vector2i) -> float:
	return Vector2(seed_pos.x - x, seed_pos.y - y).length()

func _load_tileset():
	# 每次启动在内存中构建TileSet：纹理直接从PNG解码，不依赖import系统与陈旧.tres
	tile_set = TilesetGen.build_tileset()

func _setup_tilemap_parent():
	# 使用场景中已有的TileMap作为主地图
	main_tile_map = get_node_or_null("../TileMap")
	if main_tile_map:
		# 运行时动态赋值tileset
		if tile_set and not main_tile_map.tile_set:
			main_tile_map.tile_set = tile_set
		if main_tile_map.tile_set:
			# 确保有2个layer：0=地面，1=装饰
			if main_tile_map.get_layers_count() < 2:
				main_tile_map.add_layer(1)
				main_tile_map.set_layer_name(1, "Decor")
				main_tile_map.set_layer_z_index(1, 1)
				main_tile_map.set_layer_y_sort_enabled(1, true)
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

	var river_count = rng.randi_range(3, 4)
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

			# 桥横跨河流水面部分（水面固定3格宽：w=-1,0,1）
			for w in range(-1, 2):
				var bridge_cell: Vector2i
				if horizontal:
					bridge_cell = Vector2i(t, center + w)
				else:
					bridge_cell = Vector2i(center + w, t)
				override_cells[bridge_cell] = 17  # 桥

			# 桥两端连接河岸铺路
			if horizontal:
				override_cells[Vector2i(t, center - 2)] = 1  # 上岸路
				override_cells[Vector2i(t, center + 2)] = 1  # 下岸路
			else:
				override_cells[Vector2i(center - 2, t)] = 1  # 左岸路
				override_cells[Vector2i(center + 2, t)] = 1  # 右岸路

	print("[WorldGen] Generated " + str(river_count) + " rivers")

# ============ 城镇系统 ============

# ---- Phase G3: 城镇模板——三型布局（主建筑/民居组合/农田数量/中心广场）----
const TOWN_TEMPLATES := [
	{"id": "village",     "main": "house",  "extras": ["hut", "hut", "house"],   "farms_min": 2, "farms_max": 2, "plaza": false},
	{"id": "market_town", "main": "manor",  "extras": ["house", "house", "hut"], "farms_min": 2, "farms_max": 3, "plaza": true},
	{"id": "temple_town", "main": "temple", "extras": ["house", "hut"],          "farms_min": 1, "farms_max": 2, "plaza": true},
]

# ---- Phase G3: 城镇净空区——城镇周边(half+余量)内不生成树木/岩石，杜绝树冠压街压田 ----
var _town_clear_rects: Array[Rect2i] = []
const TOWN_CLEAR_MARGIN := 3   # 净空外扩格数（树冠悬伸+呼吸空间）

func _in_town_clearance(x: int, y: int) -> bool:
	for r in _town_clear_rects:
		if r.has_point(Vector2i(x, y)):
			return true
	return false

func _register_town_clearance(cx: int, cy: int, half: int):
	var m: int = half + TOWN_CLEAR_MARGIN
	_town_clear_rects.append(Rect2i(cx - m, cy - m, 2 * m + 1, 2 * m + 1))

func _generate_towns():
	"""在合适位置生成3-5个城镇区域"""
	var rng = RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 4000

	var town_count = rng.randi_range(4, 6)
	var town_positions: Array = []

	for i in range(town_count):
		var placed = false
		for _attempt in range(30):
			var tx = rng.randi_range(-85, 85)
			var ty = rng.randi_range(-70, 70)
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

			# 避让玩家出生点（防止城镇建筑/栅栏把出生点围死）
			if Vector2(tx, ty).distance_to(_spawn_tile()) < 15:
				continue

			# 可达性校验：城镇中心必须玩家可达（防止城镇落在河对岸/山坳孤岛）
			if not _is_reachable_cell(tx, ty):
				continue

			# 不能压河：城镇范围（含栅栏农田环）内不得有水面
			if _area_has_water(tx, ty, 7):
				continue

			town_positions.append(Vector2(tx, ty))
			_generate_single_town(tx, ty, rng)
			placed = true
			break

		if not placed:
			print("[WorldGen] Could not place town " + str(i))

	print("[WorldGen] Generated " + str(town_positions.size()) + " towns")

func _area_has_water(cx: int, cy: int, r: int) -> bool:
	"""检查以(cx,cy)为中心半径r的方形区域内是否有水面瓦片（河流）"""
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if get_tile_id(cx + dx, cy + dy) == 5:
				return true
	return false

func _spawn_tile() -> Vector2:
	"""获取玩家出生点的瓦片坐标"""
	var p = get_node_or_null("../Player")
	var pos = Vector2(576, 500)
	if p:
		pos = p.global_position
	return Vector2(pos.x / TILE_SIZE_PX, pos.y / TILE_SIZE_PX)

func _is_area_walkable(cx: int, cy: int, r: int) -> bool:
	"""检查以(cx,cy)为中心、半径r的方形区域是否完全可通行（无碰撞瓦片）"""
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if get_tile_id(cx + dx, cy + dy) in collision_tiles:
				return false
	return true

func _spawn_area_connected(cx: int, cy: int, min_tiles: int = 200) -> bool:
	"""从(cx,cy)出发BFS洪泛，验证可通行区域足够大（避免出生在河流/山脉围死的孤岛上）"""
	var start = Vector2i(cx, cy)
	var visited = {start: true}
	var queue: Array = [start]
	var dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty() and visited.size() < min_tiles:
		var c = queue.pop_front()
		for d in dirs:
			var n = c + d
			if visited.has(n):
				continue
			if get_tile_id(n.x, n.y) in collision_tiles:
				continue
			visited[n] = true
			queue.append(n)
	return visited.size() >= min_tiles

# ============ 可达性洪泛系统 ============

func _compute_reachable_region():
	"""以玩家出生点为源BFS洪泛，标记所有玩家可通行的瓦片。
	城镇/POI/NPC选址必须落在可达区内，保证玩家能走到任何可交互地点。"""
	reachable_cells.clear()
	if player == null:
		return
	var start = Vector2i(
		int(floor(player.global_position.x / TILE_SIZE_PX)),
		int(floor(player.global_position.y / TILE_SIZE_PX)))
	if get_tile_id(start.x, start.y) in collision_tiles:
		push_warning("[WorldGen] spawn tile blocked, reachable region empty")
		return
	var queue: Array = [start]
	reachable_cells[start] = true
	var head = 0
	var dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in dirs:
			var n = c + d
			if reachable_cells.has(n):
				continue
			# 边界缓冲带之外不探索（深水区）
			if Vector2(n.x, n.y).length() > WORLD_RADIUS - 6:
				continue
			if get_tile_id(n.x, n.y) in collision_tiles:
				continue
			reachable_cells[n] = true
			queue.append(n)
	print("[WorldGen] Reachable region: ", reachable_cells.size(), " tiles")

func _is_reachable_cell(wx: int, wy: int) -> bool:
	"""瓦片坐标是否玩家可达"""
	return reachable_cells.has(Vector2i(wx, wy))

func is_world_pos_reachable(pos: Vector2) -> bool:
	"""世界像素坐标是否玩家可达（供NPC生成器等外部查询）"""
	return _is_reachable_cell(int(floor(pos.x / TILE_SIZE_PX)), int(floor(pos.y / TILE_SIZE_PX)))

func find_nearest_reachable(pos: Vector2, max_r: int = 60) -> Vector2:
	"""从给定世界坐标对应的瓦片向外做切比雪夫环扫描，找最近的可达瓦片，
	返回该瓦片中心的世界坐标；找不到则返回原坐标"""
	var origin = Vector2i(int(floor(pos.x / TILE_SIZE_PX)), int(floor(pos.y / TILE_SIZE_PX)))
	if reachable_cells.has(origin):
		return pos
	for radius in range(1, max_r):
		var ring: Array[Vector2i] = []
		for dx in range(-radius, radius + 1):
			ring.append(Vector2i(dx, -radius))
			ring.append(Vector2i(dx, radius))
		for dy in range(-radius + 1, radius):
			ring.append(Vector2i(-radius, dy))
			ring.append(Vector2i(radius, dy))
		for off in ring:
			var cand = origin + off
			if reachable_cells.has(cand):
				return Vector2(cand.x * TILE_SIZE_PX + TILE_SIZE_PX * 0.5, cand.y * TILE_SIZE_PX + TILE_SIZE_PX * 0.5)
	return pos

func _relocate_player_to_safe_spawn():
	"""世界生成后以默认出生点为中心做稠密环形扫描，把玩家搬运到安全出生点。
	避免出生在山区/水边被碰撞瓦片围死。"""
	if player == null:
		return
	var origin := Vector2i(int(_spawn_tile().x), int(_spawn_tile().y))
	# 分级搜索：严格(7x7净空+200连通) -> 宽松(5x5+80) -> 兜底(5x5无连通校验)
	# 稠密逐格扫描（切比雪夫环，从近到远不漏格）；原角度采样在环大时会跳过候选点
	var tiers = [[3, 200], [2, 80], [2, 0]]
	var best = Vector2i(-1, -1)
	var max_r = WORLD_RADIUS - 20
	for tier in tiers:
		var clear_r: int = tier[0]
		var min_conn: int = tier[1]
		for radius in range(0, max_r):
			var ring: Array[Vector2i] = []
			if radius == 0:
				ring.append(Vector2i.ZERO)
			else:
				for dx in range(-radius, radius + 1):
					ring.append(Vector2i(dx, -radius))
					ring.append(Vector2i(dx, radius))
				for dy in range(-radius + 1, radius):
					ring.append(Vector2i(-radius, dy))
					ring.append(Vector2i(radius, dy))
			for off in ring:
				var cand = origin + off
				# 不选太靠近世界边界（深水带）的点
				if Vector2(cand.x, cand.y).length() > WORLD_RADIUS - 12:
					continue
				if not _is_area_walkable(cand.x, cand.y, clear_r):
					continue
				if min_conn > 0 and not _spawn_area_connected(cand.x, cand.y, min_conn):
					continue
				best = cand
				break
			if best.x >= 0:
				break
		if best.x >= 0:
			break
	if best.x < 0:
		# 最终兜底：原地净空11x11，保证至少能站立走动
		print("[WorldGen] WARN: no safe spawn found, clearing area around default spawn")
		_dump_spawn_diagnostics(origin)
		for dx in range(-5, 6):
			for dy in range(-5, 6):
				override_cells[origin + Vector2i(dx, dy)] = 0
		return
	# 双保险：净空目标区域
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			override_cells[Vector2i(best.x + dx, best.y + dy)] = 0
	player.global_position = Vector2(best.x * TILE_SIZE_PX + TILE_SIZE_PX * 0.5, best.y * TILE_SIZE_PX + TILE_SIZE_PX * 0.5)
	var cam = player.get_node_or_null("Camera2D")
	if cam and cam.has_method("reset_smoothing"):
		cam.reset_smoothing()
	print("[WorldGen] Player relocated to safe spawn tile ", best, " -> ", player.global_position)

func _dump_spawn_diagnostics(origin: Vector2i):
	"""出生点搜索彻底失败时输出诊断：可通行比例 / 5x5净空数量 / 出生点附近ASCII地形图"""
	var total = 0
	var walk = 0
	for dx in range(-100, 101, 5):
		for dy in range(-100, 101, 5):
			total += 1
			if not (get_tile_id(origin.x + dx, origin.y + dy) in collision_tiles):
				walk += 1
	var clear5 = 0
	for dx in range(-60, 61, 2):
		for dy in range(-60, 61, 2):
			if _is_area_walkable(origin.x + dx, origin.y + dy, 2):
				clear5 += 1
	print("[WorldGen] DEBUG walkable sample: ", walk, "/", total, " 5x5-clear spots: ", clear5)
	# ASCII 地形图（出生点附近 41x21），#=碰撞 .=可通行
	var lines = ""
	for dy in range(-10, 11):
		var line = ""
		for dx in range(-20, 21):
			var tid = get_tile_id(origin.x + dx, origin.y + dy)
			line += "#" if tid in collision_tiles else "."
		lines += "\n[WorldGen]   " + line
	print("[WorldGen] ASCII map around spawn (#=blocked .=walk):" + lines)

func _generate_single_town(cx: int, cy: int, rng: RandomNumberGenerator):
	"""Phase G3模板化：十字土路+中心广场(可选)+主建筑/环绕民居(按模板)+开阔农田斑块。
	Phase F5基础上重构为TOWN_TEMPLATES驱动，并登记净空区抑制周边树木。"""
	var half := rng.randi_range(7, 9)	# 需容纳最大footprint(temple 7x5)+象限余量

	# 十字主路
	for dx in range(-half, half + 1):
		override_cells[Vector2i(cx + dx, cy)] = 1
	for dy in range(-half, half + 1):
		if not override_cells.has(Vector2i(cx, cy + dy)):
			override_cells[Vector2i(cx, cy + dy)] = 1

	var tpl: Dictionary = TOWN_TEMPLATES[rng.randi() % TOWN_TEMPLATES.size()]

	# 中心广场（市镇/庙宇型）：5x5石板芯，强化聚落感
	if bool(tpl.get("plaza", false)):
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				override_cells[Vector2i(cx + dx, cy + dy)] = 1

	# 主建筑（按模板）+ 环绕民居，四象限轮转分布
	var quadrants := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	var qi := rng.randi() % 4
	_try_place_town_building(cx, cy, half, quadrants[qi], str(tpl["main"]), rng)
	var extras: Array = tpl["extras"]
	for i in range(extras.size()):
		_try_place_town_building(cx, cy, half, quadrants[(qi + 1 + i) % 4], str(extras[i]), rng)

	# 开阔农田斑块（无栅栏，2x3）
	# 开阔农田斑块（无栅栏，2x3，数量按模板）——注释保留原F5语义
	for f in range(rng.randi_range(int(tpl["farms_min"]), int(tpl["farms_max"]))):
		var fx := rng.randi_range(-half + 1, half - 2)
		var fy := rng.randi_range(-half + 1, half - 2)
		var ok := true
		for dx in range(3):
			for dy in range(2):
				var cell := Vector2i(cx + fx + dx, cy + fy + dy)
				if override_cells.has(cell) or abs(fx + dx) <= 1 or abs(fy + dy) <= 1:
					ok = false
		if ok:
			for dx in range(3):
				for dy in range(2):
					override_cells[Vector2i(cx + fx + dx, cy + fy + dy)] = 16

	# Phase G3：登记城镇净空区（half+余量），周边格子不再生成树木/岩石
	_register_town_clearance(cx, cy, half)
	print("[WorldGen] Town[%s] @(%d,%d) half=%d plaza=%s" % [str(tpl["id"]), cx, cy, half, str(tpl.get("plaza", false))])

func _try_place_town_building(cx: int, cy: int, half: int, quad: Vector2i, kind: String, rng: RandomNumberGenerator) -> bool:
	"""在象限内随机找合法锚点放置建筑；footprint整体保持在中心十字路>=2格之外"""
	var fp: Vector2i = BUILDING_PROPS[kind]["fp"]
	var lo_x: int = (cx + 2) if quad.x > 0 else (cx - half)
	var hi_x: int = (cx + half - fp.x) if quad.x > 0 else (cx - 2 - fp.x + 1)
	var lo_y: int = (cy + 2) if quad.y > 0 else (cy - half)
	var hi_y: int = (cy + half - fp.y) if quad.y > 0 else (cy - 2 - fp.y + 1)
	if hi_x < lo_x or hi_y < lo_y:
		return false
	for _attempt in range(24):
		var a := Vector2i(rng.randi_range(lo_x, hi_x), rng.randi_range(lo_y, hi_y))
		if _place_building_prop(kind, a):
			_carve_door_path(a, fp, cy)
			return true
	return false

func _carve_door_path(a: Vector2i, fp: Vector2i, road_y: int):
	"""从门格(footprint下方中央)向主路铺小径，保证出门即达道路"""
	var dx := a.x + int(fp.x / 2.0)
	var y := a.y + fp.y
	var guard := 0
	while y != road_y and guard < 64:
		guard += 1
		var cell := Vector2i(dx, y)
		var cur = override_cells.get(cell, -1)
		if cur == 1:
			break
		if cur == -1 or cur == 0:
			override_cells[cell] = 1
		y += 1 if road_y > y else -1

func _can_place_footprint(a: Vector2i, fp: Vector2i) -> bool:
	for dx in range(fp.x):
		for dy in range(fp.y):
			var c := Vector2i(a.x + dx, a.y + dy)
			if Vector2(c.x, c.y).length() > WORLD_RADIUS - 10:
				return false
			if override_cells.has(c):
				return false
			if get_tile_id(c.x, c.y) in [5, 3, 7, 17]:
				return false
	return true

func _place_building_prop(kind: String, a: Vector2i) -> bool:
	"""放置大型建筑：占位39写入override(参与碰撞/可达)，Sprite+StaticBody挂World"""
	var fp: Vector2i = BUILDING_PROPS[kind]["fp"]
	if not _can_place_footprint(a, fp):
		return false
	for dx in range(fp.x):
		for dy in range(fp.y):
			override_cells[Vector2i(a.x + dx, a.y + dy)] = TILE_BUILDING_RESERVE
	var def: Dictionary = BUILDING_PROPS[kind]
	var tex := TextureGen.load_png_texture(def["png"])
	if tex == null:
		push_warning("[WorldGen] 大建筑纹理缺失: " + str(def["png"]))
		return true
	var bw := fp.x * TILE_SIZE_PX
	var bh := fp.y * TILE_SIZE_PX
	var tsz := tex.get_size()
	var base_cx := (a.x + fp.x * 0.5) * TILE_SIZE_PX
	var base_y := float((a.y + fp.y) * TILE_SIZE_PX)
	var root := Node2D.new()
	root.name = "Building_" + kind
	# Phase G4：实体层统一z=2，节点原点锚在footprint底缘(墙脚)，交给World递归Y-sort——
	# 玩家走到建筑下方(南)画在房前，上方(北)被屋顶遮挡，消除"贴图浮在另一图层"感
	root.z_index = 2
	root.position = Vector2(base_cx, base_y)
	root.add_to_group("building_prop")
	root.set_meta("base_y", base_y)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = Vector2(0, -tsz.y * 0.5 + 6.0)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(spr)
	var body := StaticBody2D.new()
	body.position = Vector2(0, -bh * 0.5 + 2.0)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(bw - 4, bh - 2)
	cs.shape = rect
	body.add_child(cs)
	root.add_child(body)
	get_parent().add_child(root)
	return true

# ---- Phase F6: 连通性保障（饥荒式：所有可走孤岛自动开路接回主大陆） ----
func _ensure_connectivity():
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var total_carved := 0
	for pass_i in range(6):
		var reach := _bfs_reachable_from_spawn(dirs)
		var pockets := _find_pockets(reach, dirs)
		if pockets.is_empty():
			if pass_i > 0:
				print("[WorldGen] Connectivity OK after ", pass_i, " repair pass(es), carved=", total_carved)
			break
		for pocket in pockets:
			total_carved += _carve_connection(pocket, reach)
	print("[WorldGen] Connectivity passes done, carved cells=", total_carved)

func _bfs_reachable_from_spawn(dirs: Array) -> Dictionary:
	var reach: Dictionary = {}
	if player == null:
		return reach
	var start := Vector2i(int(floor(player.global_position.x / TILE_SIZE_PX)), int(floor(player.global_position.y / TILE_SIZE_PX)))
	reach[start] = true
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in dirs:
			var n: Vector2i = c + d
			if reach.has(n):
				continue
			if Vector2(n.x, n.y).length() > WORLD_RADIUS - 6:
				continue
			if get_tile_id(n.x, n.y) in collision_tiles:
				continue
			reach[n] = true
			queue.append(n)
	return reach

func _find_pockets(reach: Dictionary, dirs: Array) -> Array:
	"""找未连通的可走pocket（>=6格才算，避免为2-3格凹缝开路浪费）"""
	var pockets: Array = []
	var visited := {}
	for wy in range(-WORLD_RADIUS + 8, WORLD_RADIUS - 8, 1):
		for wx in range(-WORLD_RADIUS + 8, WORLD_RADIUS - 8, 1):
			var p := Vector2i(wx, wy)
			if visited.has(p) or reach.has(p):
				continue
			if get_tile_id(wx, wy) in collision_tiles:
				continue
			var cells: Dictionary = {p: true}
			var q: Array = [p]
			var h2 := 0
			while h2 < q.size() and cells.size() < 4000:
				var cc: Vector2i = q[h2]
				h2 += 1
				for d in dirs:
					var nn: Vector2i = cc + d
					if cells.has(nn) or reach.has(nn):
						continue
					if Vector2(nn.x, nn.y).length() > WORLD_RADIUS - 6:
						continue
					if get_tile_id(nn.x, nn.y) in collision_tiles:
						continue
					cells[nn] = true
					q.append(nn)
					visited[nn] = true
			visited[p] = true
			if cells.size() >= 6 and cells.size() < 4000:
				pockets.append(cells.keys())
			elif cells.size() >= 4000:
				pockets.append(cells.keys())
	return pockets

func _carve_connection(pocket: Array, reach: Dictionary) -> int:
	"""最近点对L形开路：水架桥、山石沙化、栅栏拆除"""
	var best_a := Vector2i.ZERO
	var best_b := Vector2i.ZERO
	var best_d := 1e12
	var step := 2 if pocket.size() > 400 else 1
	var i := 0
	for a in pocket:
		i += 1
		if step > 1 and i % step != 0:
			continue
		var b_step := 3
		var j := 0
		for b in reach.keys():
			j += 1
			if b_step > 1 and j % b_step != 0:
				continue
			var dd: float = abs(a.x - b.x) + abs(a.y - b.y)
			if dd < best_d:
				best_d = dd
				best_a = a
				best_b = b
	var carved := 0
	var c := best_a
	var guard := 0
	while guard < 600:
		guard += 1
		carved += _carve_cell(c)
		if c == best_b:
			break
		if abs(best_b.x - c.x) >= abs(best_b.y - c.y) and c.x != best_b.x:
			c.x += signi(best_b.x - c.x)
		elif c.y != best_b.y:
			c.y += signi(best_b.y - c.y)
		else:
			c.x += signi(best_b.x - c.x)
	return carved

func _carve_cell(c: Vector2i) -> int:
	var tid = get_tile_id(c.x, c.y)
	if tid == 5:
		override_cells[c] = 17
		return 1
	if tid in collision_tiles:
		override_cells[c] = 6
		return 1
	return 0

# ============ 地形生成（含边界和覆盖） ============

func get_height(x: int, y: int) -> float:
	return height_noise.get_noise_2d(x, y)

func get_humidity(x: int, y: int) -> float:
	return humidity_noise.get_noise_2d(x, y)

func get_terrain(x: int, y: int) -> Terrain:
	"""Phase F6: 群系驱动的基础地形类别（供地面层/选址判断；装饰细节在get_tile_id）"""
	match _biome_kind(x, y):
		"desert":
			return Terrain.SAND
		"lake":
			for b in biome_seeds:
				if b["kind"] == "lake" and _lake_surface_dist(x, y, b["pos"]) < 12.0:
					return Terrain.WATER
			return Terrain.GRASS
		"mountain":
			return Terrain.MOUNTAIN
		"snow":
			return Terrain.SNOW
		"forest":
			return Terrain.FOREST
		"bamboo":
			return Terrain.GRASS_DARK
		_:
			return Terrain.GRASS

func get_tile_id(x: int, y: int) -> int:
	# 1. 检查世界边界覆盖
	var border_tile = _get_world_border_tile(x, y)
	if border_tile >= 0:
		return border_tile

	# 2. 检查河流/城镇覆盖
	var cell = Vector2i(x, y)
	if override_cells.has(cell):
		return override_cells[cell]

	# 3. Phase F6 群系驱动的地表+装饰（r=细节噪声决定密疏，群系间观感差异明显）
	var kind := _biome_kind(x, y)
	var d = detail_noise.get_noise_2d(x, y)
	var r = fposmod(d + 1.0, 1.0)
	var tid: int = _biome_decor_tile(kind, x, y, d, r)
	# Phase G3：城镇净空区内不生成树木/岩石（保留花），杜绝树冠压街压田、道具穿墙
	if (TREE_SHEETS.has(tid) or tid == 14) and _in_town_clearance(x, y):
		return 18 if kind == "bamboo" else 0
	return tid

func _biome_decor_tile(kind: String, x: int, y: int, d: float, r: float) -> int:
	match kind:
		"forest":
			if r > 0.86: return 4
			elif r > 0.70: return 8
			elif r > 0.64: return 13
			return 0
		"bamboo":
			if r > 0.72: return 9
			return 18 if r > 0.35 else 0
		"mountain":
			# 山脊成势(r高→山体)，谷地沙地走廊(r<=0.40)天然可穿行
			if r > 0.80: return 3
			elif r > 0.70: return 14
			elif r > 0.62: return 3
			elif r > 0.40: return 14
			return 6
		"desert":
			if r > 0.94: return 14
			return 6
		"snow":
			if r > 0.30: return 7
			return 6
		"lake":
			for b in biome_seeds:
				if b["kind"] == "lake":
					var dist: float = _lake_surface_dist(x, y, b["pos"])
					if dist < 11.0 + d * 3.0: return 5
					elif dist < 15.0: return 6
			return 13 if r > 0.90 else 0
		_:
			if r > 0.93: return 8
			elif r > 0.90: return 4
			elif r > 0.87: return 13
			return 0
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

	# 装饰瓦片ID（有透明区域，需要地面底层）
	# 注意：碰撞瓦片(3=山, 7=雪山, 5=水)不在此列表，始终在layer 0
	var decor_tiles = [2, 4, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]

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
					# 大树改用素材包道具（星露谷式冠幅），只铺地面层
					# Phase G2：水邻/城镇净空被拒的格子只铺地面——不再回退画16px小树瓦片
					if TREE_SHEETS.has(tid):
						tm.set_cell(0, cell, _get_ground_tile(wx, wy), Vector2i(0, 0))
						if _should_spawn_tree_prop(wx, wy, tid):
							_spawn_tree_prop(wx, wy, tid)
					elif tid == TILE_BUILDING_RESERVE:
						# Phase F5 大建筑footprint：只铺地面（视觉与碰撞由道具节点承担）
						tm.set_cell(0, cell, _get_ground_tile(wx, wy), Vector2i(0, 0))
					# 装饰瓦片放在layer 1，地面放在layer 0
					elif tid in decor_tiles:
						# 先铺地面底层
						var ground_id = _get_ground_tile(wx, wy)
						tm.set_cell(0, cell, ground_id, Vector2i(0, 0))
						tm.set_cell(1, cell, tid, Vector2i(0, 0))
					else:
						tm.set_cell(0, cell, tid, Vector2i(0, 0))
			world_cells[cell] = get_tile_id(wx, wy)

	loaded_chunks[chunk] = true

func _get_ground_tile(x: int, y: int) -> int:
	"""获取指定位置的地面瓦片ID（不含装饰物）"""
	var cell = Vector2i(x, y)
	if override_cells.has(cell):
		var ov = override_cells[cell]
		# 桥下面铺路，使桥可通行（避免水面碰撞阻挡）
		if ov == 17:
			return 1  # 路
		# 多格建筑/大建筑footprint下面铺路，与城镇街道质感统一
		if ov in building_part_tiles or ov == TILE_BUILDING_RESERVE:
			return 1  # 路
	var t = get_terrain(x, y)
	match t:
		Terrain.WATER: return 5
		Terrain.SAND: return 6
		Terrain.GRASS: return 0
		Terrain.GRASS_DARK: return 18
		Terrain.FOREST: return 0  # 森林地面是草地
		Terrain.MOUNTAIN: return 6  # 山区地面用沙地
		Terrain.SNOW: return 6  # 雪区地面用沙地
	return 0

func _unload_chunk(chunk: Vector2i):
	# 使用单一TileMap时，不卸载chunk以避免空隙
	loaded_chunks.erase(chunk)

# ============ 瓦片碰撞查询 ============

func is_tile_blocking(world_pos: Vector2) -> bool:
	"""检查世界坐标位置是否在碰撞瓦片上（供玩家移动检测使用）"""
	var tx = int(floor(world_pos.x / TILE_SIZE_PX))
	var ty = int(floor(world_pos.y / TILE_SIZE_PX))
	var cell = Vector2i(tx, ty)
	# 优先查world_cells缓存
	if world_cells.has(cell):
		return world_cells[cell] in collision_tiles
	# 回退：查override_cells或计算地形
	if override_cells.has(cell):
		return override_cells[cell] in collision_tiles
	var tid = get_tile_id(tx, ty)
	return tid in collision_tiles

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
				# 山环在十字方向留门（铺路），保证玩家可进入门派
				if dx == 0 or dy == 0:
					override_cells[cell] = 1   # 门口铺路
				else:
					override_cells[cell] = 3   # 山
			elif dist <= 3:
				# 外围松树
				var r = fmod(detail_noise.get_noise_2d(cx + dx, cy + dy) + 1.0, 1.0)
				if r > 0.5:
					override_cells[cell] = 4   # 松树
				else:
					override_cells[cell] = 0   # 草

func _apply_town_poi_terrain(cx: int, cy: int):
	"""Phase F5: 城镇POI——中心大宅道具+路+农田，无栅栏圈"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cx, cy)) + WORLD_SEED
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var cell := Vector2i(cx + dx, cy + dy)
			var dist: int = max(abs(dx), abs(dy))
			if dist == 0 or (dist == 1 and abs(dx) == 1 and abs(dy) == 1 and rng.randf() < 0.5):
				continue	# 留给大建筑footprint
			if dist <= 1:
				override_cells[cell] = 1   # 路
			elif dist == 2:
				override_cells[cell] = 16  # 农田
	_place_building_prop("manor" if rng.randf() < 0.7 else "house", Vector2i(cx - 3, cy - 2))
	_place_building_prop("hut", Vector2i(cx + 2, cy - 2))
	# Phase G3：城镇POI同样登记净空区
	_register_town_clearance(cx, cy, 4)

func _apply_cave_terrain(cx: int, cy: int):
	"""洞穴周围铺石头"""
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var cell = Vector2i(cx + dx, cy + dy)
			var dist = max(abs(dx), abs(dy))
			# 南侧（dx==0, dy>0）留一条草地通道，保证玩家可接近洞口
			if dx == 0 and dy > 0:
				override_cells[cell] = 0   # 通道
				continue
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
		var wx = rng.randi_range(-90, 90)
		var wy = rng.randi_range(-70, 70)
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
		# 可达性校验：POI必须玩家可达（防止入口在海上/山坳孤岛）
		if not _is_reachable_cell(wx, wy):
			continue
		_create_poi_marker(tpl, pos)
		return true
	return false

func _force_spawn_poi(tpl: POITemplate, rng: RandomNumberGenerator):
	"""强制POI不再硬编码坐标（曾导致少林寺落在海上），统一走"地形条件+可达性"搜索"""
	for _attempt in range(300):
		if _try_spawn_poi(tpl, rng):
			return
	# 兜底：系统扫描全图，收集满足地形条件且可达的候选点，随机取一
	var candidates: Array = []
	for wx in range(-WORLD_RADIUS + 15, WORLD_RADIUS - 15, 2):
		for wy in range(-WORLD_RADIUS + 15, WORLD_RADIUS - 15, 2):
			var h = get_height(wx, wy)
			var w = get_humidity(wx, wy)
			if h < tpl.min_height or h > tpl.max_height:
				continue
			if w < tpl.min_humidity or w > tpl.max_humidity:
				continue
			if not _is_reachable_cell(wx, wy):
				continue
			var pos = Vector2(wx * TILE_SIZE_PX, wy * TILE_SIZE_PX)
			if _too_close_to_other_poi(pos, tpl.min_distance):
				continue
			candidates.append(pos)
	if not candidates.is_empty():
		_create_poi_marker(tpl, candidates[rng.randi() % candidates.size()])
		return
	# 最终兜底：放宽可达性（地形会被POI铺地改造），保证POI不消失
	push_warning("[WorldGen] force spawn " + tpl.poi_name + ": no reachable candidate, fallback to terrain-only")
	for _attempt in range(200):
		var wx = rng.randi_range(-80, 80)
		var wy = rng.randi_range(-60, 60)
		var h = get_height(wx, wy)
		var w = get_humidity(wx, wy)
		if h < tpl.min_height or h > tpl.max_height:
			continue
		if w < tpl.min_humidity or w > tpl.max_humidity:
			continue
		if get_tile_id(wx, wy) in collision_tiles:
			continue
		var pos = Vector2(wx * TILE_SIZE_PX, wy * TILE_SIZE_PX)
		if _too_close_to_other_poi(pos, tpl.min_distance):
			continue
		_create_poi_marker(tpl, pos)
		return

func _create_poi_marker(tpl: POITemplate, pos: Vector2):
	var marker = Node2D.new()
	marker.name = "POI_" + tpl.poi_name.replace(" ", "_")
	marker.y_sort_enabled = true
	# Phase G4：POI地标并入实体层Y-sort——z=2，锚点=中心建筑墙脚基线。
	# 世界坐标整体平移anchor_dy保持视觉不变，但Y排序按墙脚算，玩家可绕行建筑前后
	var building_tile0 := _poi_building_tile(tpl.poi_type)
	var center_tex0 := TextureGen.load_png_texture(building_tile0)
	var anchor_dy: float = (center_tex0.get_size().y - 10.0) if center_tex0 else 0.0
	marker.global_position = pos + Vector2(0, anchor_dy)
	marker.z_index = 2

	# 建筑群 - 根据POI类型放置不同建筑
	var building_tile = _poi_building_tile(tpl.poi_type)
	var building_count = _poi_building_count(tpl.poi_type)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(tpl.poi_name)

	# 中心建筑（大建筑贴图：底缘对齐marker原点，即原点=墙脚基线）
	var center_sprite = Sprite2D.new()
	var center_tex := TextureGen.load_png_texture(building_tile)
	center_sprite.texture = center_tex
	if center_tex:
		center_sprite.position = Vector2(0, -center_tex.get_size().y * 0.5)
	center_sprite.z_index = 0
	marker.add_child(center_sprite)

	# 周围建筑（相对新锚点定位；z归0并入实体层）
	for i in range(building_count - 1):
		var bx = rng.randi_range(-4, 4) * TILE_SIZE_PX
		var by = rng.randi_range(-2, 3) * TILE_SIZE_PX
		if abs(bx) < 36 and abs(by) < 28:
			bx = 48 * (1 if bx >= 0 else -1)
		var bld_sprite = Sprite2D.new()
		var bld_tex := TextureGen.load_png_texture(_poi_secondary_building_tile(tpl.poi_type, rng))
		bld_sprite.texture = bld_tex
		if bld_tex:
			bld_sprite.position = Vector2(bx, by + bld_tex.get_size().y * 0.5 - anchor_dy)
		else:
			bld_sprite.position = Vector2(bx, by - anchor_dy)
		bld_sprite.z_index = 0
		marker.add_child(bld_sprite)

	# 装饰物（并入实体层Y-sort，可被玩家/树冠遮挡）
	var deco_count = rng.randi_range(2, 5)
	for i in range(deco_count):
		var dx = rng.randi_range(-4, 4) * TILE_SIZE_PX
		var dy = rng.randi_range(-3, 3) * TILE_SIZE_PX
		var deco_sprite = Sprite2D.new()
		var deco_tile = _random_decoration(rng)
		deco_sprite.texture = TextureGen.load_png_texture(deco_tile)
		deco_sprite.position = Vector2(dx, dy - anchor_dy)
		deco_sprite.z_index = 0
		marker.add_child(deco_sprite)

	# 地点名称标签（Phase F2: 字号与画面比例协调——zoom3下5px≈15px屏显，加描边保可读）
	# G4：标签保持在实体层之上(z相对20)，位置随锚点平移补偿
	var label = Label.new()
	label.text = tpl.poi_name
	label.position = Vector2(-30, -52 - anchor_dy)
	label.z_index = 20
	label.add_theme_color_override("font_color", tpl.icon_color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 1))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_font_size_override("font_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_child(label)

	# 环境区域（随锚点平移，保持世界空间触发范围不变）
	var env_zone = Area2D.new()
	env_zone.name = "EnvironmentZone"
	env_zone.position = Vector2(0, -anchor_dy)
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
		"门派": return "res://sprites/buildings/temple.png"
		"城镇": return "res://sprites/buildings/manor.png"
		"洞穴": return "res://sprites/tiles/house_cave.png"
		"修炼场": return "res://sprites/buildings/house.png"
		"遗迹": return "res://sprites/tiles/house_cave.png"
		"集市": return "res://sprites/buildings/manor.png"
		_: return "res://sprites/buildings/hut.png"

func _poi_secondary_building_tile(poi_type: String, rng: RandomNumberGenerator) -> String:
	match poi_type:
		"门派":
			return ["res://sprites/buildings/house.png", "res://sprites/buildings/hut.png"][rng.randi() % 2]
		"城镇":
			return ["res://sprites/buildings/house.png", "res://sprites/buildings/hut.png", "res://sprites/tiles/farmland.png"][rng.randi() % 3]
		"洞穴":
			return "res://sprites/tiles/rock.png"
		"修炼场":
			return "res://sprites/buildings/hut.png"
		_:
			return "res://sprites/buildings/hut.png"

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
