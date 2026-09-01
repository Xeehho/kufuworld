extends Node2D

const TextureGen = preload("res://scripts/texture_generator.gd")
const TilesetGen = preload("res://scripts/tileset_generator.gd")

const CHUNK_SIZE = 16
const TILE_SIZE_PX = 16
const CHUNK_PX = CHUNK_SIZE * TILE_SIZE_PX
const LOAD_RADIUS = 3
const WORLD_SEED = 12345

# 世界边界半径（瓦片坐标）——扩至200：为青石城（玩法锚点主城）腾出东侧疆域
const WORLD_RADIUS = 200

enum Terrain {WATER, SAND, GRASS, GRASS_DARK, FOREST, MOUNTAIN, SNOW}

var height_noise: FastNoiseLite
var humidity_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var tile_set: TileSet = null
var loaded_chunks: Dictionary = {}
var player_chunk: Vector2i = Vector2i(0, 0)
var pois: Array = []
var town_centers: Array = []   # 已生成城镇中心（瓦片坐标Vector2），供NPC日程寻路查询
var world_cells: Dictionary = {}

# 河流和城镇的覆盖数据（瓦片坐标 -> tile_id）
var override_cells: Dictionary = {}
# 需要碰撞的瓦片集合（39=大建筑footprint占位，40=青石城城墙，43=唐制坊墙）
var collision_tiles: Array = [5, 3, 7, 2, 10, 11, 12, 14, 15, 39, 40, 43]
# ---- Phase F5: 大型建筑道具（星露谷比例，Sprite+StaticBody，替代16px瓦片房）----
# fp=footprint占格(瓦片)；纹理由 texture_generator.generate_big_buildings() 生成到 sprites/buildings/
const BUILDING_PROPS := {
	"hut":    {"png": "res://sprites/buildings/hut.png",    "fp": Vector2i(3, 2)},
	"house":  {"png": "res://sprites/buildings/house.png",  "fp": Vector2i(4, 3)},
	"manor":  {"png": "res://sprites/buildings/manor.png",  "fp": Vector2i(6, 4)},
	"temple": {"png": "res://sprites/buildings/temple.png", "fp": Vector2i(7, 5)},
	"castle": {"png": "res://sprites/buildings/castle.png", "fp": Vector2i(8, 4)},
	# ---- 青石城功能建筑/市集道具 ----
	"yamen":      {"png": "res://sprites/buildings/yamen.png",      "fp": Vector2i(7, 5)},   # 府衙
	"tavern":     {"png": "res://sprites/buildings/tavern.png",     "fp": Vector2i(6, 5)},   # 酒楼
	"apothecary": {"png": "res://sprites/buildings/apothecary.png", "fp": Vector2i(5, 4)},   # 药坊
	"shop_a":     {"png": "res://sprites/buildings/shop_a.png",     "fp": Vector2i(4, 3)},   # 铁匠铺/杂货铺
	"shop_b":     {"png": "res://sprites/buildings/shop_b.png",     "fp": Vector2i(4, 3)},   # 布庄
	"stall_red":  {"png": "res://sprites/buildings/stall_red.png",  "fp": Vector2i(1, 1)},   # 市摊（红棚）
	"stall_teal": {"png": "res://sprites/buildings/stall_teal.png", "fp": Vector2i(1, 1)},   # 市摊（青棚）
	"well":       {"png": "res://sprites/buildings/well.png",       "fp": Vector2i(1, 1)},   # 水井
	"ferry":      {"png": "res://sprites/buildings/ferry.png",      "fp": Vector2i(2, 2)},   # W4 渡亭（渡口村）
	# ---- W3 门派主殿（accent=门派主色，hall_xx 见 BIG_BUILDING_DEFS）----
	"hall_qf": {"png": "res://sprites/buildings/hall_qf.png", "fp": Vector2i(7, 5)},
	"hall_ts": {"png": "res://sprites/buildings/hall_ts.png", "fp": Vector2i(6, 4)},
	"hall_gc": {"png": "res://sprites/buildings/hall_gc.png", "fp": Vector2i(7, 5)},
	"hall_yw": {"png": "res://sprites/buildings/hall_yw.png", "fp": Vector2i(6, 4)},
	"hall_ym": {"png": "res://sprites/buildings/hall_ym.png", "fp": Vector2i(7, 5)},
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
	# 雪原树木加冷霜色调（2026-08-31：素材包原树偏秋红，乘法染色降温增雪意）
	if _biome_kind(wx, wy) == "snow":
		prop.modulate = Color(0.78, 0.87, 1.0)
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
	_generate_city()	# 青石城：先于城镇/POI写入override，后续选址自动避让
	_generate_official_roads()	# W5：四门官道（宽2，过河段=17桥语义），镇/POI选址自动避让占格
	# 顺序关键：先定位安全出生点，再以出生点为源做可达性洪泛，
	# 之后城镇/POI选址必须落在可达区内（修复少林寺入口在海上等问题）
	_relocate_player_to_safe_spawn()
	_compute_reachable_region()
	_generate_towns()
	_generate_sect_territories()
	_build_wild_rock_clusters()	# W6：散石聚簇表（desert/snow 装饰层自此查表）
	_scatter_pois()
	_apply_poi_terrain()
	_restore_official_roads()	# W5/W6：POI 铺地可能覆盖官道格——按登记 cells 重放
	_ensure_connectivity()	# Phase F6: 打通所有封闭区域（石中沙地等孤岛开路）
	_ensure_corridor_width()	# W6：走廊宽度感知（窄喉口袋 2 宽开路，限量）
	_place_bridge_props()	# W5：连通性收尾后统一扫描17段→石拱桥prop（纯视觉z1）
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

# ---- W1: 气候驱动的群系分布（替换 Voronoi 首府撒点，docs/武侠世界重构规划 §2.1）----
# 温度场=纬度基线+海拔修正+噪声扰动；湿度场=湿度噪声+临水加湿；群系判定唯一入口 _climate_kind。
# biome_seeds 语义变更：只存湖泊种子 [{"pos":Vector2i, "kind":"lake", "r":float}]，由 _generate_rivers 登记。
var biome_seeds: Array = []
var _water_humid_boost: Dictionary = {}   # 临水加湿标记（河/湖12格内），_generate_rivers 末尾构建

func _setup_biomes():
	biome_seeds.clear()   # 湖泊种子在 _generate_rivers 生成湖时 append

func _climate_temp(x: int, y: int) -> float:
	"""温度场：北冷南暖（y越大越暖）+海拔越高越冷+噪声扰动+出生区温和修正"""
	var lat := (float(y) + float(WORLD_RADIUS)) / (2.0 * float(WORLD_RADIUS))
	var t := 0.04 + lat * 0.92
	t -= maxf(get_height(x, y), 0.0) * 0.38
	t += detail_noise.get_noise_2d(x * 0.9, y * 0.9) * 0.07
	var d0 := Vector2(x, y).length()
	if d0 < 26.0:
		t = lerpf(t, 0.55, clampf(1.2 - d0 / 22.0, 0.0, 0.7))
	return t

func _climate_hum(x: int, y: int) -> float:
	"""湿度场：湿度噪声归一 + 临水加湿（河谷竹林/湖畔沃野的自然来源）"""
	var h: float = get_humidity(x, y) * 0.5 + 0.5
	if _water_humid_boost.has(Vector2i(x, y)):
		h = minf(h + 0.2, 1.0)
	return h

func _climate_kind(x: int, y: int, jitter: float = 0.0) -> String:
	"""群系判定唯一入口。jitter 供 _ground_of 在阈值边界做锯齿过渡（替代 Voronoi dither）"""
	for b in biome_seeds:
		if b["kind"] == "lake":
			var dist := float(Vector2(b["pos"].x - x, b["pos"].y - y).length())
			if dist < float(b["r"]) + detail_noise.get_noise_2d(x, y) * 3.0:
				return "lake"
	var t := _climate_temp(x, y) + jitter
	var h := _climate_hum(x, y)
	if t < 0.25:
		return "snow"
	if t < 0.45:
		return "mountain"
	if t < 0.7:
		if h >= 0.62:
			return "bamboo"
		if h > 0.45:
			return "forest"
		return "plains"
	# 热带蒸发干旱：起点 t≥0.79（与 forest 上界 0.7 间留 plains 缓冲带，隔断干湿突变咬合）；
	# 温度越高有效湿度越低（自然规律驱动沙漠分布）
	if t >= 0.79 and h - maxf(0.0, t - 0.62) * 1.6 < 0.30:
		return "desert"
	return "plains"

func _biome_kind(x: int, y: int) -> String:
	"""全项目群系查询口（W1 起转调气候场，接口不变）"""
	return _climate_kind(x, y)

func _lake_surface_dist(x: int, y: int, seed_pos: Vector2i) -> float:
	return Vector2(seed_pos.x - x, seed_pos.y - y).length()

# ============ 群系调色板（2026-08-31：铺设规则群系感知，治"雪地长草"类违和） ============
# 所有 override 铺设点禁止直接写 0/1/6/16 等硬编码地面瓦片，一律按类别经调色板翻译。
# 类别语义：ground=基础地面 path=道路 farm=农田 channel=连通开路 plaza=石板广场
# 41=雪覆农田 / 42=雪径（新瓦片，无碰撞，layer 0）
const BIOME_PALETTES := {
	"plains":   {"ground": 0,  "path": 1,  "farm": 16, "channel": 0,  "plaza": 35},
	"forest":   {"ground": 0,  "path": 1,  "farm": 16, "channel": 0,  "plaza": 35},
	"bamboo":   {"ground": 18, "path": 1,  "farm": 16, "channel": 18, "plaza": 35},
	"mountain": {"ground": 6,  "path": 1,  "farm": 16, "channel": 6,  "plaza": 35},
	"desert":   {"ground": 6,  "path": 6,  "farm": 16, "channel": 6,  "plaza": 35},
	"snow":     {"ground": 34, "path": 42, "farm": 41, "channel": 34, "plaza": 35},
	"lake":     {"ground": 0,  "path": 1,  "farm": 16, "channel": 0,  "plaza": 35},
}

func _palette_at(x: int, y: int) -> Dictionary:
	"""取指定坐标所属群系的铺设调色板"""
	return BIOME_PALETTES.get(_biome_kind(x, y), BIOME_PALETTES["plains"])

func _ground_of(x: int, y: int) -> int:
	"""群系过渡感知的基础地面：判定时 temp 加噪声抖动→阈值边界天然锯齿 dither，消除硬切边"""
	var k := _climate_kind(x, y, detail_noise.get_noise_2d(x * 1.7, y * 2.3) * 0.045)
	return BIOME_PALETTES.get(k, BIOME_PALETTES["plains"])["ground"]

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

# ============ 河流系统（W1 重写：源—流—汇，docs/武侠世界重构规划 §5.1） ============
# 河源固定在高山群系内高处，沿 get_height 下坡游走（噪声摆动），汇入湖泊或边界深水；
# 城市斥力保证河不进城；旧"正弦横穿+等距桥"废弃——桥位由官道接驳(W2)/连通修补/W5 规则化。
var river_paths: Array = []    # [{"path":Array[Vector2i], "main":bool}]，供回归断言采样
var lake_centers: Array = []   # [{"pos":Vector2i, "r":float}]

func _generate_rivers():
	var rng = RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 3000
	# 河流先于城生成：斥力/湖泊避城须预知 v2 城规模（half=30）
	city_half = WorldData.CITY_V2["half"]
	_generate_lakes(rng)
	# 干流 2~3 条：源=高山，下坡游走终湖/海
	var mains := _find_river_sources(rng, 3, 60.0, [])
	for src in mains:
		var path := _walk_river(src, rng, true)
		if path.size() < 40:
			continue
		_force_sea_connection(path)
		_stamp_river(path, 4)
		_bridge_along(path, 4, 36)
		river_paths.append({"path": path, "main": true})
	# 支流 1~2 条：源=另一处高山，触碰干流/湖即并入
	var used: Array = mains.duplicate()
	var tribs := _find_river_sources(rng, 2, 70.0, used)
	for src in tribs:
		var path := _walk_river(src, rng, false)
		if path.size() < 30:
			continue
		_stamp_river(path, 2)
		_bridge_along(path, 2, 40)
		river_paths.append({"path": path, "main": false})
	_build_water_humid_boost()
	print("[WorldGen] Rivers: mains=%d tribs=%d lakes=%d" % [mains.size(), tribs.size(), lake_centers.size()])

func _generate_lakes(rng):
	"""1~2 个显式湖：洼地+暖带+避城/出生区/互距；湖面 override=5+湖缘沙6，登记湖种子"""
	var placed := 0
	for _attempt in range(80):
		if placed >= 2:
			break
		var x: int = rng.randi_range(-int(WORLD_RADIUS) + 40, int(WORLD_RADIUS) - 40)
		var y: int = rng.randi_range(-int(WORLD_RADIUS) + 40, int(WORLD_RADIUS) - 40)
		if get_height(x, y) > -0.2 or _climate_temp(x, y) < 0.4:
			continue
		if Vector2(x, y).length() < 30.0:
			continue
		# 避城 62 = 城外接圆 30√2≈42.4 + 湖半径16 + 噪声余量（规划§2.1：湖泊不与城重叠，
		# 旧 45 只防圆形半径，湖缘会侵入方形城角）
		if Vector2(x - CITY_POS.x, y - CITY_POS.y).length() < 62.0:
			continue
		var ok := true
		for l in lake_centers:
			if Vector2(x - l["pos"].x, y - l["pos"].y).length() < 60.0:
				ok = false
				break
		if not ok:
			continue
		var r: int = rng.randi_range(9, 13)
		for dx in range(-r - 4, r + 5):
			for dy in range(-r - 4, r + 5):
				var d := Vector2(dx, dy).length()
				var edge := float(r) + detail_noise.get_noise_2d(x + dx, y + dy) * 3.0
				var cell := Vector2i(x + dx, y + dy)
				if d < edge:
					override_cells[cell] = 5
				elif d < edge + 4.0 and not override_cells.has(cell):
					override_cells[cell] = 6
		lake_centers.append({"pos": Vector2i(x, y), "r": float(r)})
		biome_seeds.append({"pos": Vector2i(x, y), "kind": "lake", "r": float(r)})
		placed += 1

func _find_river_sources(rng, want: int, min_apart: float, exclude: Array) -> Array:
	"""在高山群系内找高处源点；候选不足时放宽海拔阈值"""
	var picked: Array = []
	for h_min in [0.3, 0.15]:
		var cands: Array = []
		for y in range(-int(WORLD_RADIUS) + 30, int(WORLD_RADIUS) - 30, 6):
			for x in range(-int(WORLD_RADIUS) + 30, int(WORLD_RADIUS) - 30, 6):
				if _climate_kind(x, y) != "mountain" or get_height(x, y) < h_min:
					continue
				# 城禁域：源点不得落城墙邻域（曾在城东南角选出源点→河出生即被困）
				if absi(x - CITY_POS.x) < city_half + 8 and absi(y - CITY_POS.y) < city_half + 8:
					continue
				var p := Vector2i(x, y)
				var bad := false
				for e in exclude:
					if Vector2(p - e).length() < 40.0:
						bad = true
						break
				if bad:
					continue
				cands.append(p)
		while cands.size() > 0 and picked.size() < want:
			var idx: int = rng.randi_range(0, cands.size() - 1)
			var p2: Vector2i = cands[idx]
			cands.remove_at(idx)
			var ok := true
			for q in picked:
				if Vector2(p2 - q).length() < min_apart:
					ok = false
					break
			if ok:
				picked.append(p2)
		if picked.size() >= want:
			break
	return picked

func _walk_river(src: Vector2i, rng, is_main: bool) -> Array:
	"""下坡游走：8邻域选 height 最低+噪声摆动；边界引导出海；城市斥力绕城；支流触碰水即并入"""
	var path: Array = []
	var cur := src
	var visited := {src: true}
	for _guard in range(1000):
		path.append(cur)
		var merged := false
		for l in lake_centers:
			if Vector2(cur.x - l["pos"].x, cur.y - l["pos"].y).length() < float(l["r"]):
				merged = true
				break
		if merged:
			return path
		if Vector2(cur.x, cur.y).length() > WORLD_RADIUS - 8:
			return path
		if not is_main and _touches_water(cur):
			return path
		# 保底：干流 400 步后未终湖/海 → 径向 d4 冲海（无视 visited：水面自相交无害）
		var force_out := is_main and path.size() > 400
		var best := cur
		if not force_out:
			var best_score := 1e12
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var n := cur + Vector2i(dx, dy)
					if visited.has(n) or Vector2(n.x, n.y).length() > WORLD_RADIUS - 6:
						continue
					var score: float = get_height(n.x, n.y) * 8.0 + rng.randf() * 2.5
					# 边界引导出海；步数越深权重越大（防河困死内陆）
					score += Vector2(n.x, n.y).length() * (0.012 + path.size() * 0.00008)
					# 城市斥力（方形判定）：城墙邻域绝对拒绝（不进候选，相对排序会被地形差压过），
					# 外圈软斥力引导绕行——河贴城墙切向绕行
					var cdx := absi(n.x - CITY_POS.x)
					var cdy := absi(n.y - CITY_POS.y)
					var cheby := maxi(cdx, cdy)
					if cdx < city_half + 2 and cdy < city_half + 2:
						continue
					if cheby < city_half + 8:
						score += (city_half + 8 - cheby) * 4.0
					if is_main:
						for l in lake_centers:
							var dl := Vector2(n.x - l["pos"].x, n.y - l["pos"].y).length()
							if dl < float(l["r"]) + 14.0:
								score -= (float(l["r"]) + 14.0 - dl) * 1.5
					if score < best_score:
						best_score = score
						best = n
		if best == cur:
			# 洼地/冲海兜底：8 邻径向外推（切向绕行出口更充分；禁回头/禁城禁域；1000 步上限防死循环）
			var outward := Vector2(cur.x, cur.y)
			if outward.length() < 1.0:
				outward = Vector2(1, 0)
			var cand: Array = []
			for dx2 in range(-1, 2):
				for dy2 in range(-1, 2):
					if dx2 == 0 and dy2 == 0:
						continue
					cand.append(Vector2i(dx2, dy2))
			cand.sort_custom(func(a, b): return Vector2(a.x, a.y).dot(outward) > Vector2(b.x, b.y).dot(outward))
			var nc := cur
			for cd in cand:
				var tc: Vector2i = cur + cd
				if path.size() >= 2 and tc == Vector2i(path[path.size() - 2]):
					continue
				# 避城硬禁域（冲海径向也不许穿城角）
				if absi(tc.x - CITY_POS.x) < city_half + 2 and absi(tc.y - CITY_POS.y) < city_half + 2:
					continue
				nc = tc
				break
			cur = nc
		else:
			cur = best
		visited[cur] = true
	return path

func _touches_water(c: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var v = override_cells.get(Vector2i(c.x + dx, c.y + dy), -1)
			if v != null and int(v) == 5:
				return true
	return false

## 干流强制接海：终态非湖/海时，从尾端径向 d4 推进（贴城切向绕行、禁回头）直至出界
func _force_sea_connection(path: Array):
	var tail: Vector2i = path[path.size() - 1]
	if _at_sea(tail) or _at_lake(tail):
		return
	var c := tail
	var prev := tail
	for _i in range(500):
		var outward := Vector2(c.x, c.y)
		if outward.length() < 1.0:
			outward = Vector2(1, 0)
		var cand := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		cand.sort_custom(func(a, b): return Vector2(a.x, a.y).dot(outward) > Vector2(b.x, b.y).dot(outward))
		var moved := false
		for cd in cand:
			var tc: Vector2i = c + cd
			if tc == prev:
				continue
			if absi(tc.x - CITY_POS.x) < city_half + 2 and absi(tc.y - CITY_POS.y) < city_half + 2:
				continue
			if Vector2(tc.x, tc.y).length() > WORLD_RADIUS - 6:
				continue
			prev = c
			c = tc
			moved = true
			break
		if not moved:
			break
		path.append(c)
		if _at_sea(c) or _at_lake(c):
			break

func _at_sea(c: Vector2i) -> bool:
	return Vector2(c.x, c.y).length() > WORLD_RADIUS - 8

func _at_lake(c: Vector2i) -> bool:
	for l in lake_centers:
		if Vector2(c.x - l["pos"].x, c.y - l["pos"].y).length() < float(l["r"]):
			return true
	return false

func _bridge_along(path: Array, water_w: int, period: int):
	"""沿河稀疏架基本桥（tile 17）保世界基本连通：W2 官道桥/W5 石拱桥再规则化"""
	var half: int = water_w / 2
	for i in range(period / 2, path.size() - 1, period):
		var c: Vector2i = path[i]
		var dirv := Vector2i(1, 0)
		if i + 1 < path.size():
			dirv = path[i + 1] - c
		elif i > 0:
			dirv = c - path[i - 1]
		var perp := Vector2i(signi(-dirv.y), signi(dirv.x))
		if perp == Vector2i.ZERO:
			perp = Vector2i(0, 1)
		for w in range(-half, water_w - half):
			override_cells[c + perp * w] = 17
		override_cells[c + perp * (-half - 1)] = 1   # 两岸接路
		override_cells[c + perp * (water_w - half)] = 1

# ============ W5 四门官道 + 石拱桥（docs/武侠世界重构规划 §5.2，FLAG bridge_prop） ============
# 官道：四门外宽 2 path 直线外铺（≤48 格），过河段写 17（桥语义），遇崖/建筑占格/边界即停。
# 石拱桥 prop：_ensure_connectivity 收尾后统一扫描 17 连通块（≥2 格）→ 矩形判定 → prop
#（桥端石阶外扩 1 格落在岸上；z=1 垫在实体 z2 之下、TileMap z0 之上——World y_sort 下
#  北半球桥若 z=0 会被 TileMap(y=0) 盖住，z1 是关键）。
var official_roads: Array = []   # [{gate, cells, bridge_cells}]
var bridge_props: Array = []     # [{cells, axis, run_rect:[x,y,w,h], prop_rect:[...]}]

func _generate_official_roads():
	official_roads.clear()
	var h := city_half
	var dirs := {"n": Vector2i(0, -1), "s": Vector2i(0, 1), "w": Vector2i(-1, 0), "e": Vector2i(1, 0)}
	for g in dirs:
		var d: Vector2i = dirs[g]
		var perp := Vector2i(-d.y, d.x)
		var cells: Array = []
		var bridge_cells: Array = []
		for step in range(1, 49):
			var stopped := false
			for w in [-1, 0]:   # 宽 2：门中缝两侧（gap 4 格中线）
				var c: Vector2i = Vector2i(CITY_POS.x, CITY_POS.y) + d * (h + step) + perp * w
				if Vector2(c.x, c.y).length() > WORLD_RADIUS - 10:
					stopped = true
					break
				var tid := get_tile_id(c.x, c.y)
				if tid == 5:
					override_cells[c] = 17   # 过河=桥语义（prop 由 _place_bridge_props 统一铺）
					bridge_cells.append(c)
				elif int(override_cells.get(c, -1)) == 39:
					stopped = true   # 建筑/镇体占格即停
					break
				elif tid in [3, 7]:
					# 官道穿崖（山口语义，实测城周环山曾秒断三向官道）——材质同 _carve_cell 纪律
					override_cells[c] = _palette_at(c.x, c.y)["channel"]
				elif int(override_cells.get(c, -1)) != 1 and tid != 17:
					override_cells[c] = _palette_at(c.x, c.y)["path"]
				cells.append(c)
			if stopped:
				break
		official_roads.append({"gate": g, "cells": cells, "bridge_cells": bridge_cells})
		print("[WorldGen] 官道[%s] len=%d 过河格=%d" % [g, cells.size(), bridge_cells.size()])

func _place_bridge_props():
	bridge_props.clear()
	var R := int(WORLD_RADIUS)
	var visited := {}
	var naked_singles := 0   # 单格 17（修补转角/擦边）——保留裸 17 不做 prop
	for y in range(-R, R + 1):
		for x in range(-R, R + 1):
			var c := Vector2i(x, y)
			if visited.has(c) or get_tile_id(x, y) != 17:
				continue
			# 4 连通洪泛整段桥
			var comp := {c: true}
			var q: Array = [c]
			var head := 0
			visited[c] = true
			while head < q.size():
				var cur: Vector2i = q[head]
				head += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n2: Vector2i = cur + d
					if visited.has(n2) or comp.has(n2) or get_tile_id(n2.x, n2.y) != 17:
						continue
					comp[n2] = true
					visited[n2] = true
					q.append(n2)
			var cells: Array = comp.keys()
			if cells.size() < 2:
				naked_singles += 1
				continue
			var minc: Vector2i = cells[0]
			var maxc: Vector2i = cells[0]
			for cc in cells:
				minc = Vector2i(mini(minc.x, cc.x), mini(minc.y, cc.y))
				maxc = Vector2i(maxi(maxc.x, cc.x), maxi(maxc.y, cc.y))
			var rect := Rect2i(minc, maxc - minc + Vector2i.ONE)
			if cells.size() == rect.size.x * rect.size.y:
				# 矩形桥段：整段一座 prop，长边=跨河方向
				_make_bridge_prop(cells, minc, rect.size, rect.size.x >= rect.size.y)
				continue
			# L 形（修补桥转弯）：分解为直段 prop——先横后纵（剩余格）
			var remaining := {}
			for cc2 in cells:
				remaining[cc2] = true
			for axis in ["h", "v"]:
				var dv: Vector2i = Vector2i(1, 0) if axis == "h" else Vector2i(0, 1)
				for cc2 in cells:
					if not remaining.has(cc2):
						continue
					if not remaining.has(cc2 + dv) and not remaining.has(cc2 - dv):
						continue
					var a0: int = cc2.x if axis == "h" else cc2.y
					var a1: int = a0
					while remaining.has(cc2 + (Vector2i(a0 - 1 - cc2.x, 0) if axis == "h" else Vector2i(0, a0 - 1 - cc2.y))):
						a0 -= 1
					while remaining.has(cc2 + (Vector2i(a1 + 1 - cc2.x, 0) if axis == "h" else Vector2i(0, a1 + 1 - cc2.y))):
						a1 += 1
					if a1 - a0 + 1 < 2:
						continue
					var seg: Array = []
					var seg_min := Vector2i(a0, cc2.y) if axis == "h" else Vector2i(cc2.x, a0)
					for t in range(a0, a1 + 1):
						var sc: Vector2i = cc2 + (Vector2i(t - cc2.x, 0) if axis == "h" else Vector2i(0, t - cc2.y))
						remaining.erase(sc)
						seg.append(sc)
					var seg_size := Vector2i(a1 - a0 + 1, 1) if axis == "h" else Vector2i(1, a1 - a0 + 1)
					_make_bridge_prop(seg, seg_min, seg_size, axis == "h")
			# 兜底：两轮直段后仍剩余（阶梯形）——按原连通块延伸（允许与既有 prop 重叠，
			# 同贴图叠加视觉无痕；审计按 rect 覆盖判定）
			for cc2 in cells:
				if not remaining.has(cc2):
					continue
				var horizontal3: bool = comp.has(cc2 + Vector2i(1, 0)) or comp.has(cc2 + Vector2i(-1, 0))
				var dv3: Vector2i = Vector2i(1, 0) if horizontal3 else Vector2i(0, 1)
				var a3s := 0
				var a3e := 0
				while comp.has(cc2 + dv3 * (a3s - 1)):
					a3s -= 1
				while comp.has(cc2 + dv3 * (a3e + 1)):
					a3e += 1
				var seg3: Array = []
				var seg3_min: Vector2i = cc2 + dv3 * a3s
				for t in range(a3s, a3e + 1):
					seg3.append(cc2 + dv3 * t)
				var size3 := Vector2i(a3e - a3s + 1, 1) if horizontal3 else Vector2i(1, a3e - a3s + 1)
				_make_bridge_prop(seg3, seg3_min, size3, horizontal3)
				for ccc in seg3:
					remaining.erase(ccc)
	print("[WorldGen] 石拱桥 prop: %d 座（裸单格 %d）" % [bridge_props.size(), naked_singles])

func _make_bridge_prop(cells: Array, run_min: Vector2i, run_size: Vector2i, horizontal: bool):
	"""prop 覆盖 = 桥段沿长轴两端各外扩 1 格（桥端石阶落岸上）；宽=桥段实际宽。
	z=1：TileMap(z0) 之上、实体(z2) 之下——World y_sort 下北半球桥若 z=0 会被 TileMap(y=0) 盖住"""
	var pr: Rect2i
	if horizontal:
		pr = Rect2i(run_min + Vector2i(-1, 0), run_size + Vector2i(2, 0))
	else:
		pr = Rect2i(run_min + Vector2i(0, -1), run_size + Vector2i(0, 2))
	var spr := Sprite2D.new()
	spr.texture = TextureGen.get_bridge_texture(pr.size.x, pr.size.y, horizontal)
	spr.centered = false
	spr.position = Vector2(pr.position.x * 16.0, pr.position.y * 16.0)
	spr.z_index = 1
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.add_to_group("bridge_prop")
	get_parent().add_child(spr)
	bridge_props.append({"cells": cells, "axis": "h" if horizontal else "v",
		"run_rect": [run_min.x, run_min.y, run_size.x, run_size.y],
		"prop_rect": [pr.position.x, pr.position.y, pr.size.x, pr.size.y]})

## W5：官道走廊避让（POI 铺地半径可达 15，bbox 外扩 2 防贴脸）
func _near_official_road(wx: int, wy: int, margin: int = 2) -> bool:
	for rd in official_roads:
		var cells: Array = rd["cells"]
		if cells.is_empty():
			continue
		var c0: Vector2i = cells[0]
		var c1: Vector2i = cells[cells.size() - 1]
		if wx >= mini(c0.x, c1.x) - margin and wx <= maxi(c0.x, c1.x) + margin \
				and wy >= mini(c0.y, c1.y) - margin and wy <= maxi(c0.y, c1.y) + margin:
			return true
	return false

func _restore_official_roads():
	"""官道复原重铺：旧版 POI 铺地（门派山环 3/城镇 POI 等）可能覆盖官道格——
	按登记 cells 重放铺设逻辑（水→17/崖→channel/其余→path；39 建筑占格让位）"""
	var restored := 0
	for rd in official_roads:
		for c in rd["cells"]:
			var tid: int = get_tile_id(c.x, c.y)
			if tid == 5:
				override_cells[c] = 17
				restored += 1
			elif tid == 39:
				pass   # 建筑占格让位（登记制碰撞）——异常压道由 walk6 断言暴露
			elif tid in [3, 7]:
				override_cells[c] = _palette_at(c.x, c.y)["channel"]
				restored += 1
			elif tid != 1 and tid != 17:
				override_cells[c] = _palette_at(c.x, c.y)["path"]
				restored += 1
	if restored > 0:
		print("[WorldGen] 官道复原重铺 %d 格（POI 铺地覆盖回滚）" % restored)

func _stamp_river(path: Array, water_w: int):
	"""沿中心线垂直流向铺水（干流4格/支流2格），岸沙1格只写空格；先水后沙"""
	var sands: Array = []
	for i in range(path.size()):
		var c: Vector2i = path[i]
		var dirv := Vector2i(1, 0)
		if i + 1 < path.size():
			dirv = path[i + 1] - c
		elif i > 0:
			dirv = c - path[i - 1]
		var perp := Vector2i(absi(dirv.y) if dirv.x != 0 else 0, absi(dirv.x) if dirv.y != 0 else 0)
		if dirv.x != 0 and dirv.y != 0:
			perp = Vector2i(-dirv.y, dirv.x)   # 斜向步取正交
		perp = Vector2i(signi(perp.x), signi(perp.y))
		var offs: Array = []
		if water_w >= 4:
			offs = [-2, -1, 0, 1]
		else:
			offs = [0, 1]
		for w in offs:
			var cell := c + perp * int(w)
			override_cells[cell] = 5
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var s: Vector2i = cell + dd
				if not override_cells.has(s):
					sands.append(s)
	for s in sands:
		if not override_cells.has(s):
			override_cells[s] = 6

func _build_water_humid_boost():
	"""临水加湿表：河中心线/湖心向外扩12格（O(中心线)构建，运行期O(1)查询）"""
	_water_humid_boost.clear()
	var centers: Array = []
	for l in lake_centers:
		centers.append({"pos": l["pos"], "r": int(l["r"]) + 12})
	for rp in river_paths:
		for c in rp["path"]:
			centers.append({"pos": c, "r": 13})
	for c in centers:
		var p: Vector2i = c["pos"]
		var r: int = c["r"]
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				_water_humid_boost[Vector2i(p.x + dx, p.y + dy)] = true

# ============ 青石城（主城）============
# 玩法锚点城池：围墙圈+四门+十字主街+中央广场+功能建筑（府衙/酒楼/药坊/铁匠铺/布庄/杂货铺/民居）
# 城内市摊/水井点缀；非门派NPC（商人/手工业者/衙役等）由 npc_spawner 依 city_info 迁入并赋予固定日程
const TILE_CITY_WALL := 40
const TILE_WARD_WALL := 43            # W2 唐制坊墙（41/42 已被雪田/雪径占用）
const CITY_POS := Vector2i(75, 0)     # 城中心（瓦片坐标）：出生点正东

var city_half: int = 30               # 运行时城半边长（唐制城=30，河斥力/聚落判定/探针读它）

var city_info: Dictionary = {}        # v2: {center_px, gates, gate_px, wards, markets, buildings:{key:{anchor,fp,door_px,job}}}

## W2 唐制城池（WorldData.CITY_V2 蓝图施工）：市坊分离/棋盘路网/官署居北/寺观居东北/东西两市
## W7：legacy 城路径已删，本函数为唯一城生成路径
func _generate_city():
	var cx := CITY_POS.x
	var cy := CITY_POS.y
	var h: int = WorldData.CITY_V2["half"]
	city_half = h
	# 1) 城内地坪压平（避水；地面按群系调色板）
	for dx in range(-h + 1, h):
		for dy in range(-h + 1, h):
			var cc := Vector2i(cx + dx, cy + dy)
			if get_tile_id(cc.x, cc.y) == 5:
				continue
			override_cells[cc] = _palette_at(cc.x, cc.y)["ground"]
	# 2) 城墙圈 + 四门豁口（4格宽对齐主街）
	for dx in range(-h, h + 1):
		for dy in range(-h, h + 1):
			if absi(dx) == h or absi(dy) == h:
				var wc := Vector2i(cx + dx, cy + dy)
				override_cells[wc] = (17 if get_tile_id(wc.x, wc.y) == 5 else TILE_CITY_WALL)
	for g in range(-2, 2):
		for wc in [Vector2i(cx + g, cy - h), Vector2i(cx + g, cy + h), Vector2i(cx - h, cy + g), Vector2i(cx + h, cy + g)]:
			override_cells[wc] = (17 if get_tile_id(wc.x, wc.y) == 5 else _palette_at(wc.x, wc.y)["path"])
	# 3) 主街宽4（x,y∈[-2,1] 全贯）+ 次街宽2（横 y∈[14,15]、纵 x∈[14,15]）
	for d in range(-h, h + 1):
		for w in ([-2, -1, 0, 1] + [14, 15]):
			for sc in [Vector2i(cx + d, cy + w), Vector2i(cx + w, cy + d)]:
				override_cells[sc] = (17 if get_tile_id(sc.x, sc.y) == 5 else _palette_at(sc.x, sc.y)["path"])
	# 4) 中央石板广场
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			if get_tile_id(cx + dx, cy + dy) != 5:
				override_cells[Vector2i(cx + dx, cy + dy)] = 35
	# 5) 里坊：坊墙一圈(tile 43) + 中横/中纵巷道 + 坊门2格 + 门外接引
	var wards: Dictionary = WorldData.CITY_V2["wards"]
	var ward_gate_out := {}   # 坊名 -> 门外接引格（连接主街/次街）
	for wname in wards:
		var r: Rect2i = wards[wname]
		for dx in range(r.position.x, r.end.x):
			for dy in range(r.position.y, r.end.y):
				if dx != r.position.x and dx != r.end.x - 1 and dy != r.position.y and dy != r.end.y - 1:
					continue
				override_cells[Vector2i(cx + dx, cy + dy)] = TILE_WARD_WALL
		var mx: int = r.position.x + r.size.x / 2
		var my: int = r.position.y + r.size.y / 2
		for dx in range(r.position.x + 1, r.end.x - 1):
			_ward_path(cx + dx, cy + my)
		for dy in range(r.position.y + 1, r.end.y - 1):
			_ward_path(cx + mx, cy + dy)
		# 坊门：朝主街侧墙中点 2 格；门外接引 2 格接主街/次街
		var east_side: bool = r.position.x < 0
		var gx: int = (r.end.x - 1) if east_side else r.position.x
		var ox: int = gx + (1 if east_side else -1)
		for gy in [my - 1, my]:
			_ward_path(cx + gx, cy + gy)
			_ward_path(cx + ox, cy + gy)
		ward_gate_out[wname] = Vector2i(ox, my - 1)
	# 6) 市巷（横 y=26 两市各一条，接主街）
	for mname in WorldData.CITY_V2["markets"]:
		var mr: Rect2i = WorldData.CITY_V2["markets"][mname]
		for dx in range(mr.position.x, mr.end.x):
			_ward_path(cx + dx, cy + 26)
	# 7) 功能建筑（规划化摆放，job 供 W4 NPC 岗位）
	city_info = {
		"center_px": Vector2(cx * 16.0 + 8.0, cy * 16.0 + 8.0),
		"gates": WorldData.CITY_V2["gates"],
		"gate_px": {
			"n": Vector2(cx * 16.0 + 8.0, (cy - h + 2) * 16.0 + 8.0),
			"s": Vector2(cx * 16.0 + 8.0, (cy + h - 2) * 16.0 + 8.0),
			"w": Vector2((cx - h + 2) * 16.0 + 8.0, cy * 16.0 + 8.0),
			"e": Vector2((cx + h - 2) * 16.0 + 8.0, cy * 16.0 + 8.0),
		},
		"wards": [], "markets": [], "buildings": {},
	}
	for wname in wards:
		city_info["wards"].append({"name": wname, "rect": wards[wname]})
	for mname in WorldData.CITY_V2["markets"]:
		city_info["markets"].append({"name": mname, "rect": WorldData.CITY_V2["markets"][mname]})
	# key 命名保持 npc_spawner.city_npc_configs 依赖（tavern/apothecary/smithy/cloth/yamen/house_w/house_ne/stall_w1/stall_e1/well）
	var bdefs := {
		"yamen":      ["yamen", Vector2i(-27, -27), "捕头"],
		"constable":  ["shop_a", Vector2i(-13, -27), "捕快"],
		"temple":     ["temple", Vector2i(6, -27), "知客僧"],
		"smithy":     ["shop_a", Vector2i(-16, 22), "铁匠"],
		"apothecary": ["apothecary", Vector2i(-11, 22), "药师"],
		"cloth":      ["shop_b", Vector2i(-6, 22), "布庄"],
		"grocery":    ["shop_a", Vector2i(2, 22), "杂货"],
		"house_ne":   ["house", Vector2i(7, 22), "商户"],
		"tavern":     ["tavern", Vector2i(4, 5), "掌柜"],
		"hut_s1":     ["hut", Vector2i(11, 5), "民"],
		"hut_s2":     ["hut", Vector2i(4, 12), "民"],
		"house_w":    ["house", Vector2i(-27, 5), "民居"],
		"hut_w2":     ["hut", Vector2i(-20, 5), "民"],
		"house_w3":   ["house", Vector2i(-13, 5), "民居"],
		"hut_w4":     ["hut", Vector2i(-26, 11), "民"],
		"house_w5":   ["house", Vector2i(-20, 11), "民居"],
		"hut_w6":     ["hut", Vector2i(-13, 11), "民"],
		"house_e1":   ["house", Vector2i(18, 5), "民居"],
		"hut_e2":     ["hut", Vector2i(24, 5), "民"],
		"house_se":   ["house", Vector2i(18, 11), "民居"],
		"hut_e4":     ["hut", Vector2i(24, 11), "民"],
		"house_e5":   ["house", Vector2i(24, 15), "民居"],
		"stall_w1":   ["stall_red", Vector2i(-13, 26), "小贩"],
		"stall_w2":   ["stall_teal", Vector2i(-9, 27), "小贩"],
		"stall_e1":   ["stall_red", Vector2i(8, 26), "小贩"],
		"stall_e2":   ["stall_teal", Vector2i(11, 27), "小贩"],
		"well":       ["well", Vector2i(-4, 28), "井"],
	}
	var doors := {}
	for key in bdefs:
		var kind: String = bdefs[key][0]
		var rel: Vector2i = bdefs[key][1]
		var a := Vector2i(cx + rel.x, cy + rel.y)
		_force_place_building_prop(kind, a)
		var fp: Vector2i = BUILDING_PROPS[kind]["fp"]
		var door := Vector2i(a.x + int(fp.x / 2.0), a.y + fp.y)
		doors[key] = door
		city_info["buildings"][key] = {"anchor": a, "fp": fp,
			"door_px": Vector2(door.x * 16.0 + 8.0, door.y * 16.0 + 8.0), "job": bdefs[key][2]}
	# 8) 门前小径：BFS 连接最近路（主街/次街/坊巷/市巷；阻挡建筑/墙/坊墙/水）
	var city_lim := Rect2i(cx - h + 2, cy - h + 2, 2 * h - 4, 2 * h - 4)
	for key in doors:
		_connect_door_to_road(doors[key], city_lim)
	# 9) 城门楼（纯视觉 prop，无碰撞，挂四门上方）
	var gtex = TextureGen.load_png_texture("res://sprites/buildings/gate_tower.png")
	if gtex:
		for gp in [Vector2(cx * 16.0 + 8.0, (cy - h) * 16.0 + 8.0), Vector2(cx * 16.0 + 8.0, (cy + h) * 16.0 + 8.0),
				Vector2((cx - h) * 16.0 + 8.0, cy * 16.0 + 8.0), Vector2((cx + h) * 16.0 + 8.0, cy * 16.0 + 8.0)]:
			var sp := Sprite2D.new()
			sp.texture = gtex
			sp.position = gp
			sp.offset = Vector2(0, -26)
			sp.z_index = 3
			get_parent().add_child(sp)
	# 10) 城名标（北门上方）
	var lbl := Label.new()
	lbl.text = "· 青 石 城 ·"
	lbl.add_theme_font_size_override("font_size", 5)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.z_index = 20
	lbl.position = Vector2(cx * 16.0 + 8.0 - 26.0, (cy - h) * 16.0 - 12.0)
	get_parent().add_child(lbl)
	# 11) 净空区（城墙外余量圈）
	_register_town_clearance(cx, cy, h)
	print("[WorldGen] City[青石城·唐制] @(%d,%d) half=%d wards=%d markets=%d buildings=%d" % [cx, cy, h, city_info["wards"].size(), city_info["markets"].size(), city_info["buildings"].size()])

## 坊内/市内铺巷（不覆盖建筑footprint/墙/水）
func _ward_path(wx: int, wy: int):
	var t = get_tile_id(wx, wy)
	if t in [39, 40, 43, 5]:
		return
	override_cells[Vector2i(wx, wy)] = _palette_at(wx, wy)["path"]

## 门前小径：从 door BFS 找最近路格（path/35/桥），沿途铺 path（阻挡建筑/墙/坊墙/水）
func _connect_door_to_road(door: Vector2i, limit: Rect2i):
	var road_id: int = _palette_at(door.x, door.y)["path"]
	if get_tile_id(door.x, door.y) == road_id:
		return
	var prev := {door: door}
	var q: Array = [door]
	var head := 0
	var found := Vector2i.ZERO
	var ok := false
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c != door:
			var t = get_tile_id(c.x, c.y)
			if t == road_id or t == 35 or t == 17:
				found = c
				ok = true
				break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if prev.has(n) or not limit.has_point(n):
				continue
			if get_tile_id(n.x, n.y) in [39, 40, 43, 5]:
				continue
			prev[n] = c
			q.append(n)
	if not ok:
		return
	var c2 := found
	while c2 != door:
		var p: Vector2i = prev[c2]
		if get_tile_id(p.x, p.y) not in [road_id, 35, 17]:
			override_cells[p] = road_id
		c2 = p

func get_city_info() -> Dictionary:
	return city_info

# ============ 城镇系统 ============

# ---- 城镇净空区——城镇周边(half+余量)内不生成树木/岩石，杜绝树冠压街压田 ----
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

var town_info: Dictionary = {}

# W7：legacy 村镇路径（TOWN_TEMPLATES/象限撒点）已删，本函数为唯一村镇生成路径。
func _generate_towns():
	var rng = RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 4000
	var town_count := rng.randi_range(6, 9)
	town_centers.clear()
	town_info.clear()
	var placed := 0
	for i in range(town_count):
		var roll := rng.randf()
		var tpl_key := "farm"
		if roll < 0.30:
			tpl_key = "market"
		elif roll < 0.58:
			tpl_key = "ferry"
		# ferry 选址受水带约束，50 次未果退回 farm（保证城镇数量优先）
		var tries: Array = [["ferry", 50]] if tpl_key == "ferry" else [[tpl_key, 50]]
		if tpl_key == "ferry":
			tries.append(["farm", 50])
		var done := false
		for t in tries:
			var k: String = t[0]
			for _attempt in range(int(t[1])):
				var tx := rng.randi_range(-155, 155)
				var ty := rng.randi_range(-145, 145)
				var h := get_height(tx, ty)
				var w := get_humidity(tx, ty)
				if h < -0.15 or h > 0.2 or w < -0.3 or w > 0.6:
					continue
				var bk := _biome_kind(tx, ty)
				# 竹林排除（deviation：规划允许镇落竹林，但竹林带稀缺且为古刹禅宗
				# 指定气候位——8 镇铺开会挤占选址，竹林让位领地）
				if bk == "snow" or bk == "desert" or bk == "lake" or bk == "bamboo":
					continue
				var too_close := false
				for tp in town_centers:
					if Vector2(tx, ty).distance_to(tp) < 24:
						too_close = true
						break
				if too_close:
					continue
				if Vector2(tx, ty).distance_to(Vector2(CITY_POS)) < 46:
					continue
				if Vector2(tx, ty).length() > WORLD_RADIUS - 10:
					continue
				if Vector2(tx, ty).distance_to(_spawn_tile()) < 15:
					continue
				if not _is_reachable_cell(tx, ty):
					continue
				# 水规则：建成区 cheby≤13 无水（严于回归断言 13 欧氏）；渡口村需外带 cheby 14~22 有水
				if _area_has_water(tx, ty, 13):
					continue
				if k == "ferry" and not _water_in_band(tx, ty, 14, 22):
					continue
				# 崖带排除：cheby≤10 内有山体/雪崖 → 建筑无成片干地（曾产出 1 建筑空镇）
				if _area_has_cliff(tx, ty, 10):
					continue
				town_centers.append(Vector2(tx, ty))
				_generate_single_town_v2(tx, ty, k, rng)
				placed += 1
				done = true
				break
			if done:
				break
	print("[WorldGen] Generated %d towns (v2 templates)" % placed)

func _water_in_band(cx: int, cy: int, r0: int, r1: int) -> bool:
	"""cheby 环带 [r0,r1] 内是否存在水面（渡口村选址：临河而不压河）"""
	for d in range(r0, r1 + 1):
		for t in range(-d, d + 1):
			for p in [Vector2i(cx + t, cy - d), Vector2i(cx + t, cy + d),
					Vector2i(cx - d, cy + t), Vector2i(cx + d, cy + t)]:
				if get_tile_id(p.x, p.y) == 5:
					return true
	return false

func _generate_single_town_v2(cx: int, cy: int, tpl_key: String, rng: RandomNumberGenerator):
	var tpl: Dictionary = WorldData.TOWN_TEMPLATES_V2[tpl_key]
	var half := 9 if tpl_key == "market" else 8
	# 十字土路（逐格避水，同 legacy）
	for dx in range(-half, half + 1):
		var rc := Vector2i(cx + dx, cy)
		if get_tile_id(rc.x, rc.y) != 5:
			override_cells[rc] = _palette_at(rc.x, rc.y)["path"]
	for dy in range(-half, half + 1):
		var rc2 := Vector2i(cx, cy + dy)
		if get_tile_id(rc2.x, rc2.y) != 5:
			override_cells[rc2] = _palette_at(rc2.x, rc2.y)["path"]
	var info := {"template": tpl_key, "center": Vector2i(cx, cy), "half": half, "buildings": {}}
	town_info[Vector2i(cx, cy)] = info
	# 市镇中央石板广场
	if tpl_key == "market":
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var pc := Vector2i(cx + dx, cy + dy)
				if get_tile_id(pc.x, pc.y) != 5:
					override_cells[pc] = 35
	# 模板建筑组（key 与 NPC_JOBS.building 对齐；job 空串=无岗位纯民居/功能）
	# 祠堂：首选 temple；山缘镇 7x5 摆不下时回退 hut 小筑祠堂（村正岗位必须落位）
	match tpl_key:
		"farm":
			if not _place_town_building(cx, cy, half, "shrine", "temple", "村正", rng, info):
				_place_town_building(cx, cy, half, "shrine", "hut", "村正", rng, info)
			_place_town_building(cx, cy, half, "farm1", "hut", "农人", rng, info)
			_place_town_building(cx, cy, half, "farm2", "hut", "农人", rng, info)
			if rng.randf() < 0.5:
				_place_town_building(cx, cy, half, "smithy", "shop_a", "铁匠", rng, info)
			else:
				_place_town_building(cx, cy, half, "grocer", "shop_b", "货郎", rng, info)
			# 环状农带（L 形两邻边各 2 宽；避路/避水/避建筑）
			for dx in range(-half + 1, -half + 3):
				for dy in range(-half + 1, half):
					_stamp_farm_cell(Vector2i(cx + dx, cy + dy))
			for dy in range(half - 2, half):
				for dx in range(-half + 1, half):
					_stamp_farm_cell(Vector2i(cx + dx, cy + dy))
		"market":
			if not _place_town_building(cx, cy, half, "shrine", "temple", "村正", rng, info):
				_place_town_building(cx, cy, half, "shrine", "hut", "村正", rng, info)
			_place_town_building(cx, cy, half, "smithy", "shop_a", "铁匠", rng, info)
			_place_town_building(cx, cy, half, "grocer", "shop_b", "货郎", rng, info)
			_place_town_building(cx, cy, half, "inn", "tavern", "", rng, info)   # 骡马店
		"ferry":
			if not _place_town_building(cx, cy, half, "shrine", "temple", "村正", rng, info):
				_place_town_building(cx, cy, half, "shrine", "hut", "村正", rng, info)
			_place_town_building(cx, cy, half, "farm1", "hut", "农人", rng, info)
			_place_town_building(cx, cy, half, "farm2", "hut", "农人", rng, info)
			_place_town_building(cx, cy, half, "grocer", "shop_b", "货郎", rng, info)
			_place_ferry(cx, cy, half, info)
	# 补足民居（hut/house 混合，无 job）
	var lo: int = int(tpl["houses"][0])
	var hi: int = int(tpl["houses"][1])
	var want := rng.randi_range(lo, hi)
	for i in range(want):
		var kind := "house" if rng.randf() < 0.4 else "hut"
		_place_town_building(cx, cy, half, "house%d" % i, kind, "", rng, info)
	# 登记净空区
	_register_town_clearance(cx, cy, half)
	var jobs: Array = []
	for key in info["buildings"]:
		if str(info["buildings"][key]["job"]) != "":
			jobs.append(str(info["buildings"][key]["job"]))
	print("[WorldGen] TownV2[%s] @(%d,%d) half=%d buildings=%d jobs=%s" % [tpl_key, cx, cy, half, info["buildings"].size(), str(jobs)])

func _stamp_farm_cell(cell: Vector2i):
	"""农带单格：不覆已有铺设（路/广场/建筑占格）与水面"""
	if override_cells.has(cell) or get_tile_id(cell.x, cell.y) == 5:
		return
	override_cells[cell] = _palette_at(cell.x, cell.y)["farm"]

func _place_town_building(cx: int, cy: int, half: int, key: String, kind: String, job: String,
		rng: RandomNumberGenerator, info: Dictionary) -> bool:
	"""四象限轮转选址摆放（每象限 16 次尝试），成功后登记 town_info + 门前小径"""
	var quads := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	var qi := rng.randi() % 4
	var fp: Vector2i = BUILDING_PROPS[kind]["fp"]
	for i in range(4):
		var quad: Vector2i = quads[(qi + i) % 4]
		var lo_x: int = (cx + 2) if quad.x > 0 else (cx - half)
		var hi_x: int = (cx + half - fp.x) if quad.x > 0 else (cx - 2 - fp.x + 1)
		var lo_y: int = (cy + 2) if quad.y > 0 else (cy - half)
		var hi_y: int = (cy + half - fp.y) if quad.y > 0 else (cy - 2 - fp.y + 1)
		if hi_x < lo_x or hi_y < lo_y:
			continue
		for _a in range(16):
			var a := Vector2i(rng.randi_range(lo_x, hi_x), rng.randi_range(lo_y, hi_y))
			if not _town_anchor_ok(a, fp, cy):
				continue
			if not _place_building_prop(kind, a):
				continue
			var door := Vector2i(a.x + int(fp.x / 2.0), a.y + fp.y)
			_carve_door_path(a, fp, cy)
			info["buildings"][key] = {"kind": kind, "anchor": a, "fp": fp,
				"door_px": Vector2(door.x * 16.0 + 8.0, door.y * 16.0 + 8.0), "job": job}
			return true
	print("[WorldGen] TownV2 building[%s %s] placement failed @%s" % [key, kind, str(info["center"])])
	return false

func _town_anchor_ok(a: Vector2i, fp: Vector2i, road_y: int) -> bool:
	"""门前小径预检：door 列（door 行→主路）不得穿越建筑占格(39)/水/崖——
	dense 摆放时后放建筑的占格会打断先放建筑的 _carve_door_path，door 与路之间留断点
	（W4 回归 9 FAIL 根因：house/smithy door 不可达）"""
	var dx := a.x + int(fp.x / 2.0)
	var y := a.y + fp.y
	var guard := 0
	while y != road_y and guard < 64:
		guard += 1
		var c := Vector2i(dx, y)
		if int(override_cells.get(c, -1)) == 39:
			return false
		if get_tile_id(c.x, c.y) in [5, 3, 7]:
			return false
		y += signi(road_y - y)
	return true

func _place_ferry(cx: int, cy: int, half: int, info: Dictionary):
	"""渡口：环带找贴水干格放渡亭 + 官道接驳（W5 石拱桥读 ferry_axis）"""
	var bank := _find_bank_spot(cx, cy, half)
	if bank.x == 9999:
		print("[WorldGen] TownV2[ferry] no bank spot @", info["center"])
		return
	var fp: Vector2i = BUILDING_PROPS["ferry"]["fp"]
	if not _place_building_prop("ferry", bank):
		return
	var door := Vector2i(bank.x + int(fp.x / 2.0), bank.y + fp.y)
	info["buildings"]["ferry1"] = {"kind": "ferry", "anchor": bank, "fp": fp,
		"door_px": Vector2(door.x * 16.0 + 8.0, door.y * 16.0 + 8.0), "job": "渡夫"}
	# 官道：主街 → 渡亭门（X 段 + Y 段，逐格避水即停；河曲阻挡由 _ensure_connectivity 兜底架桥）
	var road_end := Vector2i(cx, cy)   # 起点=镇心（十字路已铺，必干燥）
	var x := cx
	while x != door.x:
		x += signi(door.x - x)
		var c := Vector2i(x, cy)
		if get_tile_id(c.x, c.y) == 5:
			break
		override_cells[c] = _palette_at(c.x, c.y)["path"]
		road_end = c
	var y := cy
	while y != door.y:
		y += signi(door.y - y)
		var c2 := Vector2i(door.x, y)
		if get_tile_id(c2.x, c2.y) == 5:
			break
		override_cells[c2] = _palette_at(c2.x, c2.y)["path"]
		road_end = c2
	# 官道终点朝水方向登记（W5 渡口配桥规则）
	var end_dir := Vector2i.ZERO
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if get_tile_id(road_end.x + d.x, road_end.y + d.y) == 5:
			end_dir = d
			break
	info["ferry_axis"] = {"road_end": road_end, "dir": end_dir}
	# 渡夫岗位锚=官道终点干格（door_px 语义沿用了南门惯例，但亭外临水侧不可站人——
	# world gen 显式登记 job_anchor_px，npc_spawner 优先读它，仍是"登记制"非自算）
	info["buildings"]["ferry1"]["job_anchor_px"] = Vector2(road_end.x * 16.0 + 8.0, road_end.y * 16.0 + 8.0)

func _find_bank_spot(cx: int, cy: int, half: int) -> Vector2i:
	"""从 cheby half+2 起逐环外扫：2x2 干置放渡亭 + 外邻 1 格贴水 + 亭门行（footprint 正南）干燥
	（渡亭惯例门朝镇侧/南，门格落水会断 BFS 可达与岗位落位）"""
	var fp := Vector2i(2, 2)
	for r in range(half + 2, half + 12):
		for t in range(-r, r + 1):
			for p in [Vector2i(cx + t, cy - r), Vector2i(cx + t, cy + r),
					Vector2i(cx - r, cy + t), Vector2i(cx + r, cy + t)]:
				if not _can_place_footprint(p, fp) or not _footprint_near_water(p, fp):
					continue
				var door_row_dry := true
				for dx in range(fp.x):
					if get_tile_id(p.x + dx, p.y + fp.y) == 5:
						door_row_dry = false
						break
				if door_row_dry:
					return p
	return Vector2i(9999, 9999)

func _footprint_near_water(a: Vector2i, fp: Vector2i) -> bool:
	"""footprint 外圈 1 格是否存在水面（贴岸判定）"""
	for dx in range(-1, fp.x + 1):
		for dy in range(-1, fp.y + 1):
			if dx >= 0 and dx < fp.x and dy >= 0 and dy < fp.y:
				continue
			if get_tile_id(a.x + dx, a.y + dy) == 5:
				return true
	return false

func _area_has_water(cx: int, cy: int, r: int) -> bool:
	"""检查以(cx,cy)为中心半径r的方形区域内是否有水面瓦片（河流）"""
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if get_tile_id(cx + dx, cy + dy) == 5:
				return true
	return false

func _area_has_cliff(cx: int, cy: int, r: int) -> bool:
	"""cheby r 内是否有山体/雪崖（W4 镇选址：崖地镇建筑无成片干地）"""
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if get_tile_id(cx + dx, cy + dy) in [3, 7]:
				return true
	return false

# ============ W3 门派领地（docs/武侠世界重构规划 §2.2） ============
# 选址硬规则：气候位匹配 + 距城/镇/领地切比雪夫缘距 + 核心区少水；
# 建设组：核心清场 + 主殿(accent=门派主色) + 弟子舍×2 + 演武场 + 界碑环(tile 14 每6格) + 后山禁地。
var sect_info: Dictionary = {}   # {name: {center, radius, hall, fp, style, clan}}

func _generate_sect_territories():
	var rng = RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 5000
	var placed: Array = []   # [{name, center(Vector2i), radius}]
	for sname in WorldData.SECT_TERRITORIES:
		var def: Dictionary = WorldData.SECT_TERRITORIES[sname]
		var r: int = def["radius"]
		var site := Vector2i.ZERO
		var found := false
		var dbg := {"climate": 0, "ring": 0, "city": 0, "town": 0, "gap": 0, "wet": 0, "bound": 0}
		for _attempt in range(1200):
			var x: int
			var y: int
			if def["climate"] == "lakeside_bamboo" and lake_centers.size() > 0 and _attempt % 3 != 2:
				# 湖锚定搜索（朝世界中心定向 ±90°：两湖偏居东西缘，向外锚必越界）
				var l: Dictionary = lake_centers[_attempt % lake_centers.size()]
				var to_center: float = (Vector2.ZERO - Vector2(l["pos"])).angle()
				var ang: float = to_center + rng.randf_range(-PI / 2, PI / 2)
				var dist := rng.randf_range(float(l["r"]) + 6.0, float(l["r"]) + 14.0)
				x = l["pos"].x + int(cos(ang) * dist)
				y = l["pos"].y + int(sin(ang) * dist)
				if absi(x) > int(WORLD_RADIUS) - 30 or absi(y) > int(WORLD_RADIUS) - 30:
					dbg["bound"] += 1
					continue
			elif def["climate"] == "desert_oasis":
				# 沙漠纬度带定向（desert 判定 t≥0.79 → y≥113；界内可用至 y≈160）
				x = rng.randi_range(-150, 150)
				y = rng.randi_range(110, int(WORLD_RADIUS) - 40)
			else:
				x = rng.randi_range(-int(WORLD_RADIUS) + 30, int(WORLD_RADIUS) - 30)
				y = rng.randi_range(-int(WORLD_RADIUS) + 30, int(WORLD_RADIUS) - 30)
			if not _sect_climate_match(def["climate"], x, y):
				dbg["climate"] += 1
				continue
			# 界碑环断言采样点（4 角+4 边中点）必须落在世界边界内（边界带从 R-5 起覆盖；
			# 曾有领地角越界被边界水覆盖界碑）——非采样碑位越界则铺设时跳过
			var ring_out := false
			for p in [Vector2i(-r, -r), Vector2i(0, -r), Vector2i(r, -r), Vector2i(r, 0),
					Vector2i(r, r), Vector2i(0, r), Vector2i(-r, r), Vector2i(-r, 0)]:
				if Vector2(x + p.x, y + p.y).length() > WORLD_RADIUS - 6:
					ring_out = true
					break
			if ring_out:
				dbg["ring"] += 1
				continue
			# 距城（切比雪夫，城缘到领地缘 ≥4）
			if maxi(absi(x - CITY_POS.x), absi(y - CITY_POS.y)) < city_half + 4 + r:
				dbg["city"] += 1
				continue
			var too_close := false
			# 距镇（镇 half 9+净空 → 缘距 ≥1）
			for tc in town_centers:
				if maxi(absi(x - int(tc.x)), absi(y - int(tc.y))) < r + 13:
					too_close = true
					break
			# 领地间距（缘距 ≥8）
			if not too_close:
				for p in placed:
					if maxi(absi(x - p["center"].x), absi(y - p["center"].y)) < r + int(p["radius"]) + 8:
						too_close = true
						break
			if too_close:
				dbg["town"] += 1
				continue
			# 核心 21x21 内水格 ≤4
			var wet := 0
			for dx in range(-10, 11):
				for dy in range(-10, 11):
					if get_tile_id(x + dx, y + dy) == 5:
						wet += 1
			if wet > 4:
				dbg["wet"] += 1
				continue
			site = Vector2i(x, y)
			found = true
			break
		if not found:
			print("[WorldGen] Sect[", sname, "] no site found! attempts_dbg=", dbg)
			continue
		placed.append({"name": sname, "center": site, "radius": r})
		_build_sect_territory(sname, def, site, r)
	print("[WorldGen] Sect territories: ", placed.size())

func _sect_climate_match(key: String, x: int, y: int) -> bool:
	"""气候位匹配（规划 §2.2 驻地气候位 → 气候场判定）"""
	match key:
		"temperate_mountain":
			return _climate_kind(x, y) == "mountain" and _climate_temp(x, y) > 0.28
		"desert_oasis":
			# 绿洲语义=沙漠核心+领地自建水井/药圃（河畔带实测过于稀有：沙漠河段少）
			return _climate_kind(x, y) == "desert"
		"bamboo_edge":
			return _climate_kind(x, y) == "bamboo"
		"lakeside_bamboo":
			var near_lake := false
			for l in lake_centers:
				if Vector2(x - l["pos"].x, y - l["pos"].y).length() < float(l["r"]) + 24.0:
					near_lake = true
					break
			return near_lake and _climate_kind(x, y) in ["bamboo", "forest", "plains"]
		"snow_black_rock":
			return _climate_kind(x, y) == "snow"
	return false

## 河畔带判定：cheby 6~20 格内有水（沙漠绿洲=依河而不压河）
func _near_river_band(x: int, y: int) -> bool:
	for dx in range(-20, 21):
		for dy in range(-20, 21):
			var d := maxi(absi(dx), absi(dy))
			if d >= 6 and d <= 20 and get_tile_id(x + dx, y + dy) == 5:
				return true
	return false

func _build_sect_territory(sname: String, def: Dictionary, c: Vector2i, r: int):
	var pal: Dictionary = _palette_at(c.x, c.y)
	# 1) 核心清场 25x25（覆盖崖/石/树tag；避水格跳过）
	for dx in range(-12, 13):
		for dy in range(-12, 13):
			var cc := c + Vector2i(dx, dy)
			if get_tile_id(cc.x, cc.y) == 5:
				continue
			override_cells[cc] = pal["ground"]
	# 2) 主殿（accent=门派主色）
	var hk: String = WorldData.SECT_HALL_KIND[sname]
	var ha := c + Vector2i(-3, -6)
	_force_place_building_prop(hk, ha)
	var hfp: Vector2i = BUILDING_PROPS[hk]["fp"]
	# 3) 弟子舍 ×2
	_force_place_building_prop("hut", c + Vector2i(-10, -1))
	_force_place_building_prop("hut", c + Vector2i(7, -1))
	# 4) 演武场（石板 7x4 @ 南侧）
	for dx in range(-3, 4):
		for dy in range(3, 7):
			var tc := c + Vector2i(dx, dy)
			if get_tile_id(tc.x, tc.y) != 5:
				override_cells[tc] = 35
	# 药王谷药圃（农田 6x3 @ 西侧）
	if sname == "药王谷":
		for dx in range(-11, -5):
			for dy in range(2, 5):
				var fc := c + Vector2i(dx, dy)
				if get_tile_id(fc.x, fc.y) != 5:
					override_cells[fc] = 16
	# 5) 界碑环：方形 cheby=r，四角必放 + 每边中段每 6 格一座（tile 44 界碑，无碰撞标记——
	# 碰撞环会挡路被连通性修补切开；南门语义由无碰撞标记天然满足）
	for corner in [Vector2i(-r, -r), Vector2i(r, -r), Vector2i(r, r), Vector2i(-r, r)]:
		override_cells[c + corner] = 44
	for t in range(3, 2 * r - 3, 6):
		for bp in [Vector2i(-r + t, -r), Vector2i(r, -r + t), Vector2i(r - t, r), Vector2i(-r, r - t)]:
			var bp_abs: Vector2i = c + bp
			if Vector2(bp_abs.x, bp_abs.y).length() > WORLD_RADIUS - 6:
				continue   # 越界碑跳过（边界水会覆盖）
			override_cells[bp_abs] = 44
	# 回读验证（诊断：区分铺设端失败 vs 事后覆盖）
	var ring_bad := 0
	for corner in [Vector2i(-r, -r), Vector2i(r, -r), Vector2i(r, r), Vector2i(-r, r)]:
		if get_tile_id(c.x + corner.x, c.y + corner.y) != 44:
			ring_bad += 1
	# 6) 后山禁地：北侧崖带（cheby 带 y ∈ [-r+2, -r+7]，雪原派用雪崖 7）
	var cliff := 7 if _biome_kind(c.x, c.y) == "snow" else 3
	for dx in range(-r + 3, r - 2):
		for dy in range(-r + 2, -r + 8):
			override_cells[c + Vector2i(dx, dy)] = cliff
	# 7) 净空（抑树）+ 登记（npc_anchors=领地 NPC 落位唯一来源：主殿门 px / 演武场中心 px）
	var hall_door := Vector2i(ha.x + int(hfp.x / 2.0), ha.y + hfp.y)
	_register_town_clearance(c.x, c.y, r)
	sect_info[sname] = {"center": c, "radius": r, "hall": ha, "fp": hfp,
		"style": def["style"], "clan": sname, "ring_bad_at_build": ring_bad,
		"npc_anchors": {"hall": Vector2(hall_door.x * 16.0 + 8.0, hall_door.y * 16.0 + 8.0),
			"arena": Vector2(c.x * 16.0 + 8.0, (c.y + 4) * 16.0 + 8.0)}}
	print("[WorldGen] Sect[", sname, "] @", c, " r=", r, " ring_bad_at_build=", ring_bad)


func is_in_settlement(p: Vector2) -> bool:
	"""2026-08-31：判定某像素点是否落在青石城/城镇范围内（MobSpawner营地避让用）"""
	var t := Vector2i(int(p.x / 16.0), int(p.y / 16.0))
	if absi(t.x - CITY_POS.x) <= city_half + 2 and absi(t.y - CITY_POS.y) <= city_half + 2:
		return true
	# W3 门派领地（界碑环内=聚落）
	for s in sect_info.values():
		if maxi(absi(t.x - s["center"].x), absi(t.y - s["center"].y)) <= int(s["radius"]):
			return true
	for tc in town_centers:
		if Vector2(t.x, t.y).distance_to(tc) < 13.0:
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

func find_npc_path(from_px: Vector2, to_px: Vector2, max_explore: int = 20000) -> PackedVector2Array:
	"""NPC瓦片寻路：A*（曼哈顿启发+二叉堆），返回像素路点队列（不含起点、含终点）。
	目标瓦片不可通行时就近吸附；整体不可达时返回空数组（调用方自行退化处理）。"""
	var start := Vector2i(int(floor(from_px.x / TILE_SIZE_PX)), int(floor(from_px.y / TILE_SIZE_PX)))
	var goal := Vector2i(int(floor(to_px.x / TILE_SIZE_PX)), int(floor(to_px.y / TILE_SIZE_PX)))
	if get_tile_id(goal.x, goal.y) in collision_tiles:
		var snapped := find_nearest_reachable(to_px, 12)
		goal = Vector2i(int(floor(snapped.x / TILE_SIZE_PX)), int(floor(snapped.y / TILE_SIZE_PX)))
		if get_tile_id(goal.x, goal.y) in collision_tiles:
			return PackedVector2Array()
	if start == goal:
		return PackedVector2Array([Vector2(goal.x * TILE_SIZE_PX + 8, goal.y * TILE_SIZE_PX + 8)])
	var came_from := {start: start}
	var g_score := {start: 0}
	var heap: Array = [[_manhattan(start, goal), start]]   # 最小堆条目 [f, pos]
	var explored := 0
	var found := false
	while heap.size() > 0 and explored < max_explore:
		var cur: Vector2i = heap[0][1]
		heap[0] = heap[heap.size() - 1]
		heap.pop_back()
		_heap_sift_down(heap)
		if cur == goal:
			found = true
			break
		explored += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if get_tile_id(n.x, n.y) in collision_tiles:
				continue
			var ng: int = int(g_score[cur]) + 1
			if g_score.has(n) and int(g_score[n]) <= ng:
				continue
			g_score[n] = ng
			came_from[n] = cur
			_heap_push(heap, [ng + _manhattan(n, goal), n])
	if not found:
		return PackedVector2Array()
	var path_tiles: Array = []
	var cur := goal
	while cur != start:
		path_tiles.append(cur)
		cur = came_from[cur]
	path_tiles.reverse()
	var out := PackedVector2Array()
	for t in path_tiles:
		out.append(Vector2(t.x * TILE_SIZE_PX + 8, t.y * TILE_SIZE_PX + 8))
	return out

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _heap_push(heap: Array, item):
	"""二叉最小堆插入"""
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := int((i - 1) / 2)
		if int(heap[p][0]) <= int(heap[i][0]):
			break
		var tmp = heap[p]
		heap[p] = heap[i]
		heap[i] = tmp
		i = p

func _heap_sift_down(heap: Array):
	"""二叉最小堆下沉（堆顶已被替换为末尾元素）"""
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		var r := i * 2 + 2
		var m := i
		if l < n and int(heap[l][0]) < int(heap[m][0]):
			m = l
		if r < n and int(heap[r][0]) < int(heap[m][0]):
			m = r
		if m == i:
			break
		var tmp = heap[m]
		heap[m] = heap[i]
		heap[i] = tmp
		i = m

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

func _carve_door_path(a: Vector2i, fp: Vector2i, road_y: int):
	"""从门格(footprint下方中央)向主路铺小径，保证出门即达道路"""
	var dx := a.x + int(fp.x / 2.0)
	var y := a.y + fp.y
	var guard := 0
	while y != road_y and guard < 64:
		guard += 1
		var cell := Vector2i(dx, y)
		# 2026-08-31：基面为水/崖即停——小径不得穿河凿崖（旧逻辑只看override，河水被硬铺成路）
		if get_tile_id(cell.x, cell.y) in [5, 3, 7]:
			break
		var cur = override_cells.get(cell, -1)
		# 已是既有路径（含调色板路径/主街）即接驳完成
		if cur == _palette_at(cell.x, cell.y)["path"]:
			break
		# 空地或调色板基础地面（城内地坪已整体压平为调色板地面）才铺门前小径
		if cur == -1 or cur == 0 or cur == _palette_at(cell.x, cell.y)["ground"]:
			override_cells[cell] = _palette_at(cell.x, cell.y)["path"]
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
	_attach_building_sprite(kind, a)
	return true

func _force_place_building_prop(kind: String, a: Vector2i):
	"""城内规划摆放：跳过选址校验（城内地坪已统一压草、坐标为人工规划），直接占格+挂道具"""
	var fp: Vector2i = BUILDING_PROPS[kind]["fp"]
	for dx in range(fp.x):
		for dy in range(fp.y):
			override_cells[Vector2i(a.x + dx, a.y + dy)] = TILE_BUILDING_RESERVE
	_attach_building_sprite(kind, a)

func _attach_building_sprite(kind: String, a: Vector2i):
	"""建筑视觉/碰撞道具：Sprite(z=2实体层Y-sort) + StaticBody + 墙脚阴影，挂World"""
	var fp: Vector2i = BUILDING_PROPS[kind]["fp"]
	var def: Dictionary = BUILDING_PROPS[kind]
	var tex := TextureGen.load_png_texture(def["png"])
	if tex == null:
		push_warning("[WorldGen] 大建筑纹理缺失: " + str(def["png"]))
		return
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
	# 墙脚软阴影（demo1房屋落地感；z相对-1=地面之上、建筑之下）
	var shadow := Sprite2D.new()
	shadow.texture = _get_tree_shadow_texture()
	shadow.scale = Vector2((bw + 22.0) / 48.0, maxf(10.0, bw * 0.30) / 20.0)
	shadow.position = Vector2(0, -3.0)
	shadow.z_index = -1
	shadow.modulate = Color(0, 0, 0, 0.28)
	shadow.set_meta("shadow_base_a", 0.28)
	shadow.add_to_group("tree_shadow")
	root.add_child(shadow)
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

# ---- Phase F6: 连通性保障（饥荒式：所有可走孤岛自动开路接回主大陆） ----
# W1 算法升级：逐 pocket "最近点对暴力搜索"（183 pocket × reach 8.6万 → 卡死）改为
# 一次性全图"施工成本场"（multi-source BFS，种子=reach，可穿透碰撞计数），
# 每 pocket 取场值最小格沿梯度开路——O(全图) 替代 O(pocket×reach)。
func _ensure_connectivity():
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var total_carved := 0
	for pass_i in range(4):
		var t0 := Time.get_ticks_msec()
		var reach := _bfs_reachable_from_spawn(dirs)
		var pockets := _find_pockets(reach, dirs)
		if pockets.is_empty():
			print("[WorldGen] Connectivity OK after %d pass(es), carved=%d" % [pass_i, total_carved])
			break
		var dist := {}
		var q: Array = []
		for c in reach.keys():
			dist[c] = 0
			q.append(c)
		var head := 0
		while head < q.size():
			var c: Vector2i = q[head]
			head += 1
			var dc: int = dist[c]
			for d in dirs:
				var n: Vector2i = c + d
				if dist.has(n) or absi(n.x) > WORLD_RADIUS or absi(n.y) > WORLD_RADIUS:
					continue
				dist[n] = dc + 1
				q.append(n)
		print("[WorldGen] conn pass=%d reach=%d pockets=%d field=%dms" % [pass_i, reach.size(), pockets.size(), Time.get_ticks_msec() - t0])
		var t1 := Time.get_ticks_msec()
		for pocket in pockets:
			total_carved += _carve_via_field(pocket, dist, dirs)
		print("[WorldGen]   carved %d pockets in %dms (total=%d)" % [pockets.size(), Time.get_ticks_msec() - t1, total_carved])
	print("[WorldGen] Connectivity passes done, carved cells=", total_carved)

func _carve_via_field(pocket: Array, dist: Dictionary, dirs: Array) -> int:
	"""pocket 内取成本场最小格，沿梯度下降开路到 reach：水→桥17、碰撞→群系channel"""
	var best_a := Vector2i.ZERO
	var best_d := 1 << 30
	for c in pocket:
		var dv: int = dist.get(c, 1 << 30)
		if dv < best_d:
			best_d = dv
			best_a = c
	if best_d >= (1 << 30):
		return 0
	var carved := 0
	var c := best_a
	for _guard in range(2000):
		carved += _carve_cell(c)
		var dc: int = dist.get(c, 0)
		if dc <= 0:
			break
		var next := c
		for d in dirs:
			var n: Vector2i = c + d
			if dist.has(n) and int(dist[n]) < dc:
				next = n
				break
		if next == c:
			break
		c = next
	return carved

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
	"""找未连通的可走pocket（>=6格才算）。
	W1修复：完整洪泛——旧版BFS在4000格截断，巨pocket被重复报告几十次（每次都是同一区域的新样本），
	每个样本又触发一次6秒级carve，connectivity直接卡死。"""
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
			while h2 < q.size():
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
					visited[nn] = true
					q.append(nn)
			visited[p] = true
			if cells.size() >= 6:
				pockets.append(cells.keys())
	return pockets

func _carve_cell(c: Vector2i) -> int:
	var tid = get_tile_id(c.x, c.y)
	if tid == 5:
		override_cells[c] = 17
		return 1
	if tid in collision_tiles:
		# 开路材质按群系调色板（雪原=雪径，避免沙路穿雪）
		override_cells[c] = _palette_at(c.x, c.y)["channel"]
		return 1
	return 0

# ============ W6 可行域政策（docs/武侠世界重构规划 §6，FLAG walkability_policy） ============
# 分区：SETTLEMENT（城/镇/领地）/ ROAD（路/桥/广场）/ FARM（农田）/ WILD（其余）。
# 生成期：SETTLEMENT/ROAD/FARM 零碰撞装饰——散石只在 WILD 贴山 3 格带状聚簇；
# 走廊：2×2 块洪泛找窄喉口袋（≥20 格的 WILD 组），限量开 2 宽通道；
# 运行期唯一可行查询 is_walkable()（怪物 AI/NPC/探针统一走它，禁止各自再猜）。

var _rock_cells: Dictionary = {}   # W6 WILD 贴山聚簇散石表（desert/snow 装饰层查询）

func _tile_zone(tx: int, ty: int) -> String:
	"""格分区。ROAD=路/桥/石板/雪径；FARM=农田/湿田/雪田；SETTLEMENT=城/镇/领地；其余 WILD"""
	var t := get_tile_id(tx, ty)
	if t == 1 or t == 17 or t == 35 or t == 42:
		return "ROAD"
	if t == 16 or t == 33 or t == 41:
		return "FARM"
	if absi(tx - CITY_POS.x) <= city_half + 2 and absi(ty - CITY_POS.y) <= city_half + 2:
		return "SETTLEMENT"
	for tc in town_centers:
		if Vector2(tx, ty).distance_to(tc) < 13.0:
			return "SETTLEMENT"
	for s in sect_info.values():
		if maxi(absi(tx - s["center"].x), absi(ty - s["center"].y)) <= int(s["radius"]):
			return "SETTLEMENT"
	return "WILD"

func is_walkable(tx: int, ty: int) -> bool:
	"""运行期唯一可行查询（规划 §6）：无碰撞瓦片（建筑39/城墙40/坊墙43含于 collision_tiles）。
	怪物 AI/NPC/探针断言统一调用，禁止各自再猜"""
	if absi(tx) > WORLD_RADIUS or absi(ty) > WORLD_RADIUS:
		return false
	return get_tile_id(tx, ty) not in collision_tiles

func _build_wild_rock_clusters():
	"""散石聚簇：desert/snow 群系散石不再全图 singles——只贴山系 3 格带状出露（噪声连续天然成带），
	且仅落 WILD（SETTLEMENT/ROAD/FARM 零碰撞装饰）。mountain 群系崖壁成势不动（山体语义）"""
	_rock_cells.clear()
	var R := int(WORLD_RADIUS)
	# 1) 山系格集（mountain 群系）
	var mountain_cells := {}
	for y in range(-R + 6, R - 6):
		for x in range(-R + 6, R - 6):
			if _biome_kind(x, y) == "mountain":
				mountain_cells[Vector2i(x, y)] = true
	# 2) 山缘格（8 邻含非山）为源，向 WILD 侧 3 格带撒带状散石
	var carved_total := 0
	for mc in mountain_cells:
		var is_edge := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			if not mountain_cells.has(mc + d):
				is_edge = true
				break
		if not is_edge:
			continue
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if maxi(absi(dx), absi(dy)) == 0:
					continue
				var c: Vector2i = mc + Vector2i(dx, dy)
				if mountain_cells.has(c) or _rock_cells.has(c):
					continue
				if carved_total >= 2200:   # 总量上限（密度回归）
					return
				# 噪声带状出露（~22%）：先噪声后 biome 省调用
				var d := fposmod(detail_noise.get_noise_2d(c.x * 1.7, c.y * 2.3) + 1.0, 1.0)
				if d <= 0.78:
					continue
				var k := _biome_kind(c.x, c.y)
				if k != "desert" and k != "snow":
					continue
				# 只落 WILD（轻量分区：净空/城圈/镇圈/领地圈/官道）
				if _in_town_clearance(c.x, c.y) or _near_official_road(c.x, c.y, 1):
					continue
				if absi(c.x - CITY_POS.x) <= city_half + 3 and absi(c.y - CITY_POS.y) <= city_half + 3:
					continue
				var near_town := false
				for tc in town_centers:
					if Vector2(c.x, c.y).distance_to(tc) < 14.0:
						near_town = true
						break
				if near_town:
					continue
				var near_sect := false
				for s in sect_info.values():
					if maxi(absi(c.x - s["center"].x), absi(c.y - s["center"].y)) <= int(s["radius"]) + 2:
						near_sect = true
						break
				if near_sect:
					continue
				_rock_cells[c] = true
				carved_total += 1
	print("[WorldGen] wild rock clusters: %d cells (贴山3格带状)" % carved_total)

func _ensure_corridor_width():
	"""走廊宽度感知 BFS（规划 §6.3）：2×2 块洪泛（块锚 4 格全通行才可扩展）。
	"1格可达但 2×2 不可达"的 WILD 窄喉口袋 ≥20 格时，在缝处开 2 宽通道（_carve_cell：
	水→桥17/阻挡→群系 channel），carve 总量限 40 防凿烂地形。聚落内（SETTLEMENT/ROAD/FARM
	占多数的组）不修——走廊要求只针对野外"""
	var corridor_w: int = WorldData.WALKABILITY["corridor_width"]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var offs22 := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var reach1 := _bfs_reachable_from_spawn(dirs)
	var ok22 := func(c: Vector2i) -> bool:
		for off in offs22:
			var n: Vector2i = c + off
			if absi(n.x) > WORLD_RADIUS or absi(n.y) > WORLD_RADIUS:
				return false
			if get_tile_id(n.x, n.y) in collision_tiles:
				return false
		return true
	var start := Vector2i.ZERO
	var found := false
	for c in reach1.keys():
		if ok22.call(c):
			start = c
			found = true
			break
	if not found:
		print("[WorldGen] corridor: no 2x2 block near spawn, skip")
		return
	var reach2 := {start: true}
	var q: Array = [start]
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		for d in dirs:
			var n: Vector2i = cur + d
			if not reach2.has(n) and ok22.call(n):
				reach2[n] = true
				q.append(n)
	var covered := {}
	for c in reach2:
		for off in offs22:
			covered[c + off] = true
	# 窄喉口袋连通分组（4 连，限界内）
	var pockets := {}
	for c in reach1.keys():
		if not covered.has(c):
			pockets[c] = true
	var carved := 0
	var fixed_groups := 0
	var seen := {}
	for p in pockets:
		if seen.has(p):
			continue
		var group: Array = [p]
		seen[p] = true
		var gq: Array = [p]
		var gh := 0
		while gh < gq.size():
			var gc: Vector2i = gq[gh]
			gh += 1
			for d in dirs:
				var n: Vector2i = gc + d
				if not seen.has(n) and pockets.has(n):
					seen[n] = true
					group.append(n)
					gq.append(n)
		if group.size() < 20:
			continue
		# 聚落内组不修（采样组头 5 格分区判定）
		var in_settle := 0
		for i in range(mini(5, group.size())):
			var g: Vector2i = group[i]
			if _tile_zone(g.x, g.y) != "WILD":
				in_settle += 1
		if in_settle >= 3:
			continue
		# 缝处开 2 宽通道：找组内与 covered 相邻的缝格，把 2×2 块朝组方向推进一格（carve 阻挡）
		var opened := false
		for gcell in group:
			if opened or carved >= 40:
				break
			for d in dirs:
				var qq: Vector2i = gcell + d
				if not covered.has(qq):
					continue
				var d2: Vector2i = Vector2i(signi(gcell.x - qq.x), signi(gcell.y - qq.y))
				var anchor: Vector2i = qq + d2   # 朝组推进的新 2×2 块锚
				for off in offs22:
					var t: Vector2i = anchor + off
					if get_tile_id(t.x, t.y) in collision_tiles:
						carved += _carve_cell(t)
				opened = true
				fixed_groups += 1
				break
	if carved > 0:
		print("[WorldGen] corridor width: carved=%d (%d 组窄喉已拓 %d宽)" % [carved, fixed_groups, corridor_w])
	else:
		print("[WorldGen] corridor width: no narrow-throat pocket >=20 (WILD)")

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
				if b["kind"] == "lake" and _lake_surface_dist(x, y, b["pos"]) < float(b["r"]) + 2.0:
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
	# 回退地面按群系匹配（雪原回雪地、竹回深草），避免净空区出现异色斑块
	if (TREE_SHEETS.has(tid) or tid == 14) and _in_town_clearance(x, y):
		match kind:
			"snow": return 34
			"bamboo": return 18
			"desert", "mountain": return 6
			_: return 0
	return tid

func _biome_decor_tile(kind: String, x: int, y: int, d: float, r: float) -> int:
	# W1：树密度=f(湿度)——dens∈[0.35,1.0]，阈值随 dens 调制（沙漠0树/雪原稀雪松/竹林需湿>0.6由气候判定保证）
	var hum := _climate_hum(x, y)
	var dens := clampf(hum * 1.2, 0.35, 1.0)
	match kind:
		"forest":
			# demo2风：针叶林+蘑菇地表+紫花（基面走过渡带混铺）
			if r > 1.0 - dens * 0.14: return 4
			elif r > 1.0 - dens * 0.30: return 8
			elif r > 0.64: return 13
			elif r > 0.60: return 36
			return _ground_of(x, y)
		"bamboo":
			if r > 1.0 - dens * 0.28: return 9
			return 18 if r > 0.35 else _ground_of(x, y)
		"mountain":
			# demo2风：深色崖壁成势(r高→山体)，谷地土路走廊(r<=0.40)天然可穿行
			if r > 0.80: return 3
			elif r > 0.70: return 14
			elif r > 0.62: return 3
			elif r > 0.40: return 14
			return _ground_of(x, y)
		"desert":
			# W1 自然规律：沙漠零树；W6 岩石改 WILD 贴山聚簇表（不再全图 singles）
			if r > 0.94:
				return 14 if _rock_cells.has(Vector2i(x, y)) else _ground_of(x, y)
			return _ground_of(x, y)
		"snow":
			# demo3风：白雪地面+稀疏雪松+雪线崖壁点缀（崖用7=积雪崖，避免深色秃崖突兀）
			if r > 0.94: return 7
			elif r > 1.0 - dens * 0.12: return 4
			elif r > 0.83:
				return 14 if _rock_cells.has(Vector2i(x, y)) else _ground_of(x, y)
			return _ground_of(x, y)
		"lake":
			# W1：湖面为 override 显式水（_generate_lakes 已铺），此处只留湖缘装饰
			return 13 if r > 0.90 else _ground_of(x, y)
		_:
			# plains：橡/松疏林+紫花+雏菊（密度随湿度）
			if r > 1.0 - dens * 0.07: return 8
			elif r > 1.0 - dens * 0.10: return 4
			elif r > 0.87: return 13
			elif r > 0.845: return 37
			return _ground_of(x, y)
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
	# 注意：碰撞瓦片(3=山崖, 7=雪崖, 5=水)不在此列表，始终在layer 0
	var decor_tiles = [2, 10, 11, 12, 13, 14, 15, 36, 37, 44]

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
		# 2026-08-31：大建筑footprint底瓦不再铺路——碎石路从建筑四周露出一圈很突兀，
		# 改为落到基面取色（草/沙/雪随群系），视觉上建筑"长"在地面上
		if ov != TILE_BUILDING_RESERVE:
			return ov
	var t = get_terrain(x, y)
	match t:
		Terrain.WATER: return 5
		Terrain.MOUNTAIN: return 1  # 山区谷地铺碎石土路（demo2棕土走廊）
		_:
			# 其余群系走过渡带感知地面（雪=34、沙=6、竹=18、草=0，边界带 dither 混铺）
			return _ground_of(x, y)

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
	"""确保所有POI位置周围的chunk被加载（含青石城：城池远于玩家初始加载半径）"""
	for p in pois:
		var poi_pos: Vector2 = p["position"]
		var poi_chunk = world_to_chunk(poi_pos)
		# 加载POI所在chunk及周围1格
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var c = poi_chunk + Vector2i(dx, dy)
				if not loaded_chunks.has(c):
					_load_chunk(c)
	# 青石城chunk强制加载（v2 城圈61x61 → ±3 chunk 全覆盖）
	var city_chunk = world_to_chunk(Vector2(CITY_POS.x * TILE_SIZE_PX, CITY_POS.y * TILE_SIZE_PX))
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c2 = city_chunk + Vector2i(dx, dy)
			if not loaded_chunks.has(c2):
				_load_chunk(c2)
	# W3 门派领地chunk强制加载（界碑环 cheby=r → ±(r/16)+2 chunk）
	for s in sect_info.values():
		var sc: Vector2i = s["center"]
		var sect_chunk := world_to_chunk(Vector2(sc.x * TILE_SIZE_PX, sc.y * TILE_SIZE_PX))
		var sr: int = int(s["radius"]) / 16 + 2
		for dx in range(-sr, sr + 1):
			for dy in range(-sr, sr + 1):
				var c3 = sect_chunk + Vector2i(dx, dy)
				if not loaded_chunks.has(c3):
					_load_chunk(c3)
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
			"古堡":
				_apply_castle_terrain(tx, ty)

func _apply_castle_terrain(cx: int, cy: int):
	"""古堡POI：石板广场+石径+古堡建筑（带势力信息，点击可查看）"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cx, cy)) + WORLD_SEED
	for dx in range(-7, 8):
		for dy in range(-5, 6):
			var cell := Vector2i(cx + dx, cy + dy)
			var dist: int = max(abs(dx), abs(dy))
			if dist <= 5:
				override_cells[cell] = 35   # 石板广场
			elif dist <= 6 and (dx == 0 or dy == 0 or rng.randf() < 0.3):
				override_cells[cell] = _palette_at(cell.x, cell.y)["path"]   # 石径（群系化）
	var info := _make_castle_info(rng)
	var anchor := Vector2i(cx - 4, cy - 2)
	_place_castle_prop(anchor, info)
	_register_town_clearance(cx, cy, 8)
	print("[WorldGen] Castle[%s] @(%d,%d) faction=%s" % [info["name"], cx, cy, info["faction"]])

func _make_castle_info(rng: RandomNumberGenerator) -> Dictionary:
	"""随机生成古堡信息：名称+势力（优先取游戏内门派资源）+规模+描述"""
	var prefixes := ["黑风", "苍岚", "赤霞", "玄石", "白鹭", "青枫", "落雁", "镇岳", "寒鸦", "盘龙"]
	var suffixes := ["古堡", "要塞", "山庄"]
	var cname: String = prefixes[rng.randi() % prefixes.size()] + suffixes[rng.randi() % suffixes.size()]
	var faction := "无主之地"
	var stance := "中立"
	var clan_desc := ""
	# 优先从门派资源取真实势力
	var dir := DirAccess.open("res://resources/clans")
	if dir != null:
		var files := []
		for f in dir.get_files():
			if f.ends_with(".tres"):
				files.append(f)
		if not files.is_empty():
			var res = load("res://resources/clans/" + files[rng.randi() % files.size()])
			if res != null and res.clan_name != "":
				faction = res.clan_name
				stance = res.stance
				clan_desc = res.description
	var lords := ["萧", "慕容", "独孤", "上官", "司马", "欧阳", "尉迟", "公孙"]
	var scale_names := ["小型堡垒", "中型要塞", "大型坞堡", "雄城巨垒"]
	var descs := [
		"飞檐斗拱间刀光隐现，堡中弟子日夜操演武艺。",
		"百年前由武林先辈所筑，而今仍是号令一方的雄城。",
		"堡墙高耸箭楼林立，江湖客至此莫不低头。",
		"山下集市繁华，山上堡门森严，一静一动皆是气象。",
	]
	var desc: String = descs[rng.randi() % descs.size()]
	if clan_desc != "":
		desc = clan_desc
	return {
		"name": cname,
		"faction": faction,
		"stance": stance,
		"lord": lords[rng.randi() % lords.size()] + "氏一族",
		"scale": scale_names[rng.randi() % scale_names.size()],
		"desc": desc,
	}

func _place_castle_prop(a: Vector2i, info: Dictionary) -> bool:
	"""放置古堡：footprint占位+Sprite+StaticBody+信息meta（点击查看）"""
	var fp: Vector2i = BUILDING_PROPS["castle"]["fp"]
	if not _can_place_footprint(a, fp):
		# 古堡POI中心是选定的，footprint冲突时强清（POI选址已保证可达）
		for dx in range(fp.x):
			for dy in range(fp.y):
				override_cells.erase(Vector2i(a.x + dx, a.y + dy))
	for dx in range(fp.x):
		for dy in range(fp.y):
			override_cells[Vector2i(a.x + dx, a.y + dy)] = TILE_BUILDING_RESERVE
	var def: Dictionary = BUILDING_PROPS["castle"]
	var tex := TextureGen.load_png_texture(def["png"])
	if tex == null:
		push_warning("[WorldGen] 古堡纹理缺失: " + str(def["png"]))
		return true
	var bw := fp.x * TILE_SIZE_PX
	var base_cx := (a.x + fp.x * 0.5) * TILE_SIZE_PX
	var base_y := float((a.y + fp.y) * TILE_SIZE_PX)
	var root := Node2D.new()
	root.name = "Building_castle"
	root.z_index = 2
	root.position = Vector2(base_cx, base_y)
	root.add_to_group("building_prop")
	root.set_meta("base_y", base_y)
	# 建筑信息（BuildingInfoHUD 读取）
	root.set_meta("b_name", info["name"])
	root.set_meta("b_faction", info["faction"])
	root.set_meta("b_stance", info["stance"])
	root.set_meta("b_lord", info["lord"])
	root.set_meta("b_scale", info["scale"])
	root.set_meta("b_desc", info["desc"])
	# 墙脚软阴影
	var shadow := Sprite2D.new()
	shadow.texture = _get_tree_shadow_texture()
	shadow.scale = Vector2((bw + 26.0) / 48.0, maxf(12.0, bw * 0.26) / 20.0)
	shadow.position = Vector2(0, -3.0)
	shadow.z_index = -1
	shadow.modulate = Color(0, 0, 0, 0.30)
	shadow.set_meta("shadow_base_a", 0.30)
	shadow.add_to_group("tree_shadow")
	root.add_child(shadow)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = Vector2(0, -tex.get_size().y * 0.5 + 6.0)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(spr)
	var body := StaticBody2D.new()
	body.position = Vector2(0, -fp.y * TILE_SIZE_PX * 0.5 + 2.0)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(bw - 4, fp.y * TILE_SIZE_PX - 2)
	cs.shape = rect
	body.add_child(cs)
	root.add_child(body)
	get_parent().add_child(root)
	return true

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
					override_cells[cell] = _palette_at(cell.x, cell.y)["path"]   # 路
			elif dist <= 2:
				# 山环在十字方向留门（铺路），保证玩家可进入门派
				if dx == 0 or dy == 0:
					override_cells[cell] = _palette_at(cell.x, cell.y)["path"]   # 门口铺路
				else:
					override_cells[cell] = 3   # 山
			elif dist <= 3:
				# 外围松树
				var r = fmod(detail_noise.get_noise_2d(cx + dx, cy + dy) + 1.0, 1.0)
				if r > 0.5:
					override_cells[cell] = 4   # 松树
				else:
					override_cells[cell] = _palette_at(cell.x, cell.y)["ground"]

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
				override_cells[cell] = _palette_at(cell.x, cell.y)["path"]   # 路
			elif dist == 2:
				override_cells[cell] = _palette_at(cell.x, cell.y)["farm"]   # 农田（雪原=雪覆田）
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
			# 南侧（dx==0, dy>0）留一条可通行通道，保证玩家可接近洞口（雪原=雪面通道）
			if dx == 0 and dy > 0:
				override_cells[cell] = _palette_at(cell.x, cell.y)["ground"]   # 通道
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
				override_cells[cell] = _palette_at(cell.x, cell.y)["path"]   # 路
			elif dist <= 2:
				# 花环：雪原/沙漠不放花（违和），退化为当地地面
				var bk := _biome_kind(cell.x, cell.y)
				override_cells[cell] = 13 if (bk != "snow" and bk != "desert") else _palette_at(cell.x, cell.y)["ground"]
			else:
				override_cells[cell] = _palette_at(cell.x, cell.y)["ground"]

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

	var castle_tpl = POITemplate.new()
	castle_tpl.poi_name = "古城堡"
	castle_tpl.poi_type = "古堡"
	castle_tpl.min_height = 0.0
	castle_tpl.max_height = 0.5
	castle_tpl.min_humidity = -0.8
	castle_tpl.max_humidity = 0.8
	castle_tpl.min_distance = 30.0
	castle_tpl.spawn_weight = 3.0
	castle_tpl.icon_color = Color(0.9, 0.5, 0.2)
	castle_tpl.spawn_npcs = 2
	castle_tpl.description = "江湖势力的老巢，点击古堡可探其底细"
	poi_templates.append(castle_tpl)

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
		var wx = rng.randi_range(-(WORLD_RADIUS - 30), WORLD_RADIUS - 30)
		var wy = rng.randi_range(-(WORLD_RADIUS - 45), WORLD_RADIUS - 45)
		var h = get_height(wx, wy)
		var w = get_humidity(wx, wy)
		if h < tpl.min_height or h > tpl.max_height:
			continue
		if w < tpl.min_humidity or w > tpl.max_humidity:
			continue
		var pos = Vector2(wx * TILE_SIZE_PX, wy * TILE_SIZE_PX)
		if _too_close_to_other_poi(pos, tpl.min_distance):
			continue
		# 避让青石城（v2 城圈61x61+余量）
		if Vector2(wx, wy).distance_to(Vector2(CITY_POS)) < 46:
			continue
		# W3 避让门派领地（cheby 缘距 ≥6）
		var sect_block := false
		for s in sect_info.values():
			if maxi(absi(wx - s["center"].x), absi(wy - s["center"].y)) < int(s["radius"]) + 6:
				sect_block = true
				break
		if sect_block:
			continue
		# W5 避让官道走廊（POI 铺地半径可达 15 → margin 16，防 POI 压断官道）
		if _near_official_road(wx, wy, 16):
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

## W3：门派领地避让（cheby 缘距 ≥ margin；POI 铺地半径可达 15，margin 须 ≥16）
func _near_sect_territory(wx: int, wy: int, margin: int = 16) -> bool:
	for s in sect_info.values():
		if maxi(absi(wx - int(s["center"].x)), absi(wy - int(s["center"].y))) < int(s["radius"]) + margin:
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
			if _near_sect_territory(wx, wy):
				continue
			if _near_official_road(wx, wy, 16):
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
		var wx = rng.randi_range(-120, 120)
		var wy = rng.randi_range(-105, 105)
		var h = get_height(wx, wy)
		var w = get_humidity(wx, wy)
		if h < tpl.min_height or h > tpl.max_height:
			continue
		if w < tpl.min_humidity or w > tpl.max_humidity:
			continue
		if get_tile_id(wx, wy) in collision_tiles:
			continue
		if _near_sect_territory(wx, wy):
			continue
		if _near_official_road(wx, wy, 16):
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
	# 古堡类型：建筑已由 _apply_castle_terrain 放置（带信息meta），marker只挂标签/环境区
	if building_tile != "":
		var center_sprite = Sprite2D.new()
		var center_tex := TextureGen.load_png_texture(building_tile)
		center_sprite.texture = center_tex
		if center_tex:
			center_sprite.position = Vector2(0, -center_tex.get_size().y * 0.5)
		center_sprite.z_index = 0
		marker.add_child(center_sprite)

	# 周围建筑（相对新锚点定位；z归0并入实体层）
	for i in range((building_count - 1) if building_tile != "" else 0):
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
	env_zone.collision_mask = 2   # 只监测玩家（碰撞分层表：玩家=层2；实体换层后默认mask=1会失检）
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
		"古堡": return ""   # 古堡建筑由 _apply_castle_terrain 单独放置（带势力信息）
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
		"res://sprites/tiles/flower.png",
		"res://sprites/tiles/daisy.png",
		"res://sprites/tiles/mushroom.png",
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
