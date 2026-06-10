@tool
extends Node

# 星露谷/饥荒风格纹理生成器
# 使用32x32瓦片尺寸，更精细的像素风表现

const TILE_SIZE = 32
const CHAR_W = 32
const CHAR_H = 48

var _rng = RandomNumberGenerator.new()

func _ready():
	_rng.seed = 42
	if Engine.is_editor_hint():
		generate_all()

func generate_all():
	generate_tiles()
	generate_player_frames()
	generate_npc_frames()
	print("[TextureGen] All textures generated")

# ============================================================
# 瓦片纹理
# ============================================================

func generate_tiles():
	DirAccess.make_dir_recursive_absolute("res://sprites/tiles")
	_tile_grass()
	_tile_grass_dark()
	_tile_path()
	_tile_water()
	_tile_sand()
	_tile_mountain()
	_tile_mountain_snow()
	_tile_tree_pine()
	_tile_tree_oak()
	_tile_tree_bamboo()
	_tile_house_town()
	_tile_house_cottage()
	_tile_house_temple()
	_tile_house_cave()
	_tile_flower()
	_tile_rock()
	_tile_fence()
	_tile_farmland()
	_tile_bridge()
	print("[TextureGen] Tiles generated")

func _noise_pixel(x: int, y: int, seed_val: int) -> float:
	var n = sin(x * 127.1 + y * 311.7 + seed_val * 43758.5453) * 43758.5453
	return n - floor(n)

func _fill_base(img: Image, base_color: Color, variation: float = 0.05):
	for x in range(img.get_width()):
		for y in range(img.get_height()):
			var n = (_noise_pixel(x, y, 1) - 0.5) * variation
			img.set_pixel(x, y, Color(
				clamp(base_color.r + n, 0, 1),
				clamp(base_color.g + n * 0.8, 0, 1),
				clamp(base_color.b + n * 0.6, 0, 1),
				base_color.a
			))

func _tile_grass():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base = Color(0.30, 0.50, 0.22, 1.0)
	var light = Color(0.38, 0.58, 0.28, 1.0)
	var dark = Color(0.22, 0.40, 0.16, 1.0)
	_fill_base(img, base, 0.04)
	# 草丛细节 - 星露谷风格的小草叶
	for i in range(12):
		var gx = _rng.randi_range(1, TILE_SIZE - 2)
		var gy = _rng.randi_range(4, TILE_SIZE - 2)
		var h = _rng.randi_range(2, 5)
		var col = light if _rng.randf() > 0.4 else dark
		for dy in range(h):
			if gy - dy >= 0:
				img.set_pixel(gx, gy - dy, col)
				if gx + 1 < TILE_SIZE and _rng.randf() > 0.5:
					img.set_pixel(gx + 1, gy - dy, col)
	# 小花点缀
	for i in range(2):
		if _rng.randf() > 0.5:
			var fx = _rng.randi_range(4, TILE_SIZE - 5)
			var fy = _rng.randi_range(6, TILE_SIZE - 4)
			var flower_colors = [Color(0.9, 0.3, 0.3), Color(0.9, 0.8, 0.2), Color(0.6, 0.3, 0.8), Color(1.0, 0.5, 0.7)]
			img.set_pixel(fx, fy, flower_colors[_rng.randi() % flower_colors.size()])
	img.save_png("res://sprites/tiles/grass.png")

func _tile_grass_dark():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base = Color(0.20, 0.35, 0.15, 1.0)
	var dark = Color(0.15, 0.28, 0.10, 1.0)
	_fill_base(img, base, 0.03)
	for i in range(8):
		var gx = _rng.randi_range(1, TILE_SIZE - 2)
		var gy = _rng.randi_range(4, TILE_SIZE - 2)
		var h = _rng.randi_range(2, 4)
		for dy in range(h):
			if gy - dy >= 0:
				img.set_pixel(gx, gy - dy, dark)
	img.save_png("res://sprites/tiles/grass_dark.png")

func _tile_path():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base = Color(0.55, 0.45, 0.32, 1.0)
	var edge = Color(0.42, 0.34, 0.24, 1.0)
	var center = Color(0.60, 0.50, 0.38, 1.0)
	_fill_base(img, base, 0.03)
	# 路径纹理 - 泥土质感
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var d = abs(x - 16) + abs(y - 16)
			var n = _noise_pixel(x, y, 7) * 0.06
			if d < 8:
				img.set_pixel(x, y, Color(center.r + n, center.g + n * 0.8, center.b + n * 0.6, 1))
			elif d < 14:
				img.set_pixel(x, y, Color(base.r + n, base.g + n * 0.7, base.b + n * 0.5, 1))
	# 碎石
	for i in range(4):
		var rx = _rng.randi_range(4, TILE_SIZE - 5)
		var ry = _rng.randi_range(4, TILE_SIZE - 5)
		img.set_pixel(rx, ry, Color(0.5, 0.45, 0.38))
		if rx + 1 < TILE_SIZE:
			img.set_pixel(rx + 1, ry, Color(0.48, 0.43, 0.36))
	img.save_png("res://sprites/tiles/path.png")

func _tile_water():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var deep = Color(0.15, 0.30, 0.55, 0.9)
	var mid = Color(0.20, 0.40, 0.65, 0.85)
	var shallow = Color(0.30, 0.55, 0.75, 0.8)
	var foam = Color(0.70, 0.80, 0.90, 0.7)
	# 水波纹
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var wave = sin(x * 0.6 + y * 0.3) * 0.5 + 0.5
			var wave2 = sin((x + 5) * 0.4 + (y + 3) * 0.5) * 0.3 + 0.5
			var v = wave * wave2
			if v > 0.7:
				img.set_pixel(x, y, shallow)
			elif v > 0.4:
				img.set_pixel(x, y, mid)
			else:
				img.set_pixel(x, y, deep)
	# 泡沫
	for i in range(3):
		var fx = _rng.randi_range(2, TILE_SIZE - 3)
		var fy = _rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(fx, fy, foam)
		img.set_pixel(fx + 1, fy, foam)
	img.save_png("res://sprites/tiles/water.png")

func _tile_sand():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base = Color(0.76, 0.68, 0.50, 1.0)
	var light = Color(0.82, 0.74, 0.56, 1.0)
	var dark = Color(0.66, 0.58, 0.42, 1.0)
	_fill_base(img, base, 0.04)
	# 沙纹
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var stripe = sin(y * 0.8 + x * 0.2) * 0.5 + 0.5
			if stripe > 0.6:
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(min(c.r + 0.04, 1), min(c.g + 0.03, 1), min(c.b + 0.02, 1), 1))
	# 小石子
	for i in range(3):
		var rx = _rng.randi_range(2, TILE_SIZE - 3)
		var ry = _rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(rx, ry, dark)
	img.save_png("res://sprites/tiles/sand.png")

func _tile_mountain():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var rock = Color(0.35, 0.32, 0.30, 1.0)
	var highlight = Color(0.48, 0.44, 0.40, 1.0)
	var shadow = Color(0.22, 0.20, 0.18, 1.0)
	var moss = Color(0.25, 0.35, 0.20, 1.0)
	# 岩石纹理
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var h1 = sin(x * 0.5) * cos(y * 0.4)
			var h2 = sin((x + 4) * 0.6) * sin((y + 3) * 0.7)
			var v = (h1 + h2 + 2) * 0.25
			if v > 0.6:
				img.set_pixel(x, y, highlight)
			elif v > 0.35:
				img.set_pixel(x, y, rock)
			else:
				img.set_pixel(x, y, shadow)
	# 苔藓
	for i in range(6):
		var mx = _rng.randi_range(2, TILE_SIZE - 3)
		var my = _rng.randi_range(TILE_SIZE - 8, TILE_SIZE - 2)
		img.set_pixel(mx, my, moss)
	img.save_png("res://sprites/tiles/mountain.png")

func _tile_mountain_snow():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var snow = Color(0.90, 0.92, 0.95, 1.0)
	var ice = Color(0.80, 0.88, 0.95, 1.0)
	var rock = Color(0.40, 0.38, 0.36, 1.0)
	# 雪山 - 上半雪，下半岩石
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var snow_line = 12 + int(sin(x * 0.4) * 4)
			if y < snow_line:
				var n = _noise_pixel(x, y, 3) * 0.04
				img.set_pixel(x, y, Color(snow.r + n, snow.g + n, snow.b + n, 1))
			elif y < snow_line + 4:
				img.set_pixel(x, y, ice)
			else:
				var n = _noise_pixel(x, y, 5) * 0.04
				img.set_pixel(x, y, Color(rock.r + n, rock.g + n, rock.b + n, 1))
	img.save_png("res://sprites/tiles/mountain_snow.png")

func _tile_tree_pine():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var trunk = Color(0.30, 0.20, 0.12, 1.0)
	var leaf_dark = Color(0.10, 0.28, 0.12, 1.0)
	var leaf_mid = Color(0.15, 0.38, 0.15, 1.0)
	var leaf_light = Color(0.22, 0.48, 0.20, 1.0)
	# 松树 - 三角形层叠
	# 树干
	for y in range(22, 32):
		for x in range(14, 18):
			img.set_pixel(x, y, trunk)
	# 第一层（最下，最宽）
	for y in range(6, 16):
		var half_w = int((16 - y) * 0.9)
		for x in range(16 - half_w, 16 + half_w + 1):
			if x >= 0 and x < TILE_SIZE:
				var shade = leaf_mid if (x + y) % 3 != 0 else leaf_dark
				img.set_pixel(x, y, shade)
	# 第二层
	for y in range(2, 10):
		var half_w = int((10 - y) * 0.7)
		for x in range(16 - half_w, 16 + half_w + 1):
			if x >= 0 and x < TILE_SIZE:
				var shade = leaf_light if (x + y) % 4 != 0 else leaf_mid
				img.set_pixel(x, y, shade)
	# 顶部
	img.set_pixel(16, 1, leaf_light)
	img.set_pixel(15, 2, leaf_mid)
	img.set_pixel(16, 2, leaf_light)
	img.set_pixel(17, 2, leaf_mid)
	img.save_png("res://sprites/tiles/tree_pine.png")

func _tile_tree_oak():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var trunk = Color(0.32, 0.22, 0.14, 1.0)
	var leaf_dark = Color(0.12, 0.32, 0.12, 1.0)
	var leaf_mid = Color(0.18, 0.42, 0.16, 1.0)
	var leaf_light = Color(0.26, 0.52, 0.22, 1.0)
	# 橡树 - 圆形树冠
	# 树干
	for y in range(20, 32):
		for x in range(14, 18):
			img.set_pixel(x, y, trunk)
	# 圆形树冠
	for x in range(4, 28):
		for y in range(2, 22):
			var dx = (x - 16) / 12.0
			var dy = (y - 11) / 10.0
			var d = dx * dx + dy * dy
			if d < 1.0:
				var shade = leaf_mid
				if d < 0.3:
					shade = leaf_light
				elif d > 0.7:
					shade = leaf_dark
				if (x + y) % 5 == 0:
					shade = leaf_dark
				img.set_pixel(x, y, shade)
	img.save_png("res://sprites/tiles/tree_oak.png")

func _tile_tree_bamboo():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stalk = Color(0.35, 0.50, 0.25, 1.0)
	var stalk_dark = Color(0.28, 0.42, 0.20, 1.0)
	var leaf = Color(0.20, 0.45, 0.18, 1.0)
	var leaf_light = Color(0.28, 0.55, 0.24, 1.0)
	# 竹子 - 竖直竹竿+竹叶
	# 竹竿
	for x in [10, 16, 22]:
		for y in range(4, 32):
			img.set_pixel(x, y, stalk)
			if y % 6 < 2:
				img.set_pixel(x, y, stalk_dark)
	# 竹叶
	var leaf_positions = [
		[6, 4], [7, 5], [8, 3], [12, 6], [13, 5], [14, 7],
		[18, 4], [19, 6], [20, 3], [24, 5], [25, 4], [26, 6],
		[5, 10], [6, 11], [12, 12], [13, 10], [19, 11], [20, 10],
		[25, 12], [7, 16], [8, 18], [13, 17], [14, 16], [20, 18],
		[21, 16], [26, 17]
	]
	for lp in leaf_positions:
		if lp[0] < TILE_SIZE and lp[1] < TILE_SIZE:
			img.set_pixel(lp[0], lp[1], leaf if _rng.randf() > 0.3 else leaf_light)
	img.save_png("res://sprites/tiles/tree_bamboo.png")

func _tile_house_town():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wall = Color(0.72, 0.65, 0.52, 1.0)
	var wall_dark = Color(0.60, 0.54, 0.42, 1.0)
	var roof = Color(0.45, 0.22, 0.15, 1.0)
	var roof_dark = Color(0.35, 0.16, 0.10, 1.0)
	var door = Color(0.35, 0.22, 0.12, 1.0)
	var window_c = Color(0.60, 0.75, 0.85, 1.0)
	# 城镇房屋 - 白墙红瓦
	# 墙壁
	for x in range(3, 29):
		for y in range(14, 30):
			img.set_pixel(x, y, wall if (x + y) % 7 != 0 else wall_dark)
	# 屋顶
	for x in range(1, 31):
		for y in range(6, 15):
			var peak = abs(x - 16)
			if y > 6 + peak * 0.6:
				img.set_pixel(x, y, roof if x % 3 != 0 else roof_dark)
	# 门
	for x in range(13, 19):
		for y in range(22, 30):
			img.set_pixel(x, y, door)
	# 门框
	img.set_pixel(12, 22, wall_dark)
	img.set_pixel(19, 22, wall_dark)
	# 窗户
	for x in range(6, 10):
		for y in range(17, 21):
			img.set_pixel(x, y, window_c)
	for x in range(22, 26):
		for y in range(17, 21):
			img.set_pixel(x, y, window_c)
	img.save_png("res://sprites/tiles/house_town.png")

func _tile_house_cottage():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wall = Color(0.55, 0.48, 0.35, 1.0)
	var wall_dark = Color(0.45, 0.38, 0.28, 1.0)
	var roof = Color(0.30, 0.35, 0.22, 1.0)
	var door = Color(0.30, 0.18, 0.10, 1.0)
	# 茅屋 - 木墙草顶
	# 墙壁
	for x in range(4, 28):
		for y in range(16, 30):
			img.set_pixel(x, y, wall if y % 4 != 0 else wall_dark)
	# 草顶
	for x in range(2, 30):
		for y in range(8, 17):
			var peak = abs(x - 16)
			if y > 8 + peak * 0.5:
				var n = _noise_pixel(x, y, 9) * 0.06
				img.set_pixel(x, y, Color(roof.r + n, roof.g + n, roof.b + n, 1))
	# 门
	for x in range(13, 19):
		for y in range(22, 30):
			img.set_pixel(x, y, door)
	img.save_png("res://sprites/tiles/house_cottage.png")

func _tile_house_temple():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wall = Color(0.80, 0.72, 0.55, 1.0)
	var wall_dark = Color(0.68, 0.60, 0.45, 1.0)
	var roof = Color(0.25, 0.20, 0.18, 1.0)
	var roof_edge = Color(0.55, 0.30, 0.15, 1.0)
	var pillar = Color(0.65, 0.20, 0.15, 1.0)
	# 寺庙 - 飞檐翘角
	# 墙壁
	for x in range(2, 30):
		for y in range(16, 30):
			img.set_pixel(x, y, wall if x % 6 != 0 else wall_dark)
	# 屋顶 - 翘角
	for x in range(0, 32):
		for y in range(6, 17):
			var peak = abs(x - 16)
			var curve = sin(x * 0.2) * 2
			if y > 6 + peak * 0.7 - curve:
				img.set_pixel(x, y, roof)
	# 屋檐
	for x in range(0, 32):
		img.set_pixel(x, 16, roof_edge)
		if x < 4 or x > 27:
			img.set_pixel(x, 15, roof_edge)
	# 红柱
	for x in [6, 14, 18, 26]:
		for y in range(16, 30):
			img.set_pixel(x, y, pillar)
	img.save_png("res://sprites/tiles/house_temple.png")

func _tile_house_cave():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rock = Color(0.30, 0.28, 0.26, 1.0)
	var rock_dark = Color(0.18, 0.16, 0.15, 1.0)
	var opening = Color(0.05, 0.05, 0.08, 1.0)
	# 洞穴入口
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var dx = (x - 16) / 16.0
			var dy = (y - 16) / 14.0
			var d = dx * dx + dy * dy
			if d < 0.35:
				img.set_pixel(x, y, opening)
			elif d < 0.7:
				var n = _noise_pixel(x, y, 11) * 0.05
				img.set_pixel(x, y, Color(rock.r + n, rock.g + n, rock.b + n, 1))
			elif d < 1.0:
				var n = _noise_pixel(x, y, 13) * 0.04
				img.set_pixel(x, y, Color(rock_dark.r + n, rock_dark.g + n, rock_dark.b + n, 1))
	# 洞口边缘高光
	for x in range(10, 22):
		img.set_pixel(x, 8, Color(0.38, 0.36, 0.34))
	img.save_png("res://sprites/tiles/house_cave.png")

func _tile_flower():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stem = Color(0.20, 0.40, 0.15, 1.0)
	var colors = [Color(0.95, 0.30, 0.30), Color(0.95, 0.80, 0.20), Color(0.70, 0.30, 0.85), Color(1.0, 0.55, 0.70)]
	# 花朵装饰
	for i in range(3):
		var fx = 6 + i * 8 + _rng.randi_range(-1, 1)
		var fy = 10 + _rng.randi_range(-2, 2)
		# 茎
		for y in range(fy, fy + 8):
			if y < TILE_SIZE:
				img.set_pixel(fx, y, stem)
		# 花瓣
		var col = colors[_rng.randi() % colors.size()]
		img.set_pixel(fx - 1, fy, col)
		img.set_pixel(fx + 1, fy, col)
		img.set_pixel(fx, fy - 1, col)
		img.set_pixel(fx, fy + 1, col)
		img.set_pixel(fx, fy, Color(1, 0.9, 0.3))
	img.save_png("res://sprites/tiles/flower.png")

func _tile_rock():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rock = Color(0.45, 0.42, 0.38, 1.0)
	var highlight = Color(0.55, 0.52, 0.48, 1.0)
	var shadow = Color(0.30, 0.28, 0.25, 1.0)
	# 石头
	for x in range(8, 24):
		for y in range(12, 28):
			var dx = (x - 16) / 8.0
			var dy = (y - 20) / 8.0
			var d = dx * dx + dy * dy
			if d < 1.0:
				if d < 0.3:
					img.set_pixel(x, y, highlight)
				elif d < 0.7:
					img.set_pixel(x, y, rock)
				else:
					img.set_pixel(x, y, shadow)
	img.save_png("res://sprites/tiles/rock.png")

func _tile_fence():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood = Color(0.50, 0.38, 0.22, 1.0)
	var wood_dark = Color(0.40, 0.30, 0.18, 1.0)
	# 木栅栏
	for x in range(TILE_SIZE):
		# 横杆
		if x % 8 < 7:
			img.set_pixel(x, 12, wood)
			img.set_pixel(x, 20, wood)
	# 竖桩
	for y in range(8, 26):
		img.set_pixel(4, y, wood_dark)
		img.set_pixel(5, y, wood_dark)
		img.set_pixel(20, y, wood_dark)
		img.set_pixel(21, y, wood_dark)
	# 桩顶
	img.set_pixel(4, 7, wood)
	img.set_pixel(5, 7, wood)
	img.set_pixel(20, 7, wood)
	img.set_pixel(21, 7, wood)
	img.save_png("res://sprites/tiles/fence.png")

func _tile_farmland():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var soil = Color(0.40, 0.30, 0.18, 1.0)
	var soil_dark = Color(0.32, 0.24, 0.14, 1.0)
	var soil_light = Color(0.48, 0.36, 0.22, 1.0)
	# 农田 - 犁沟
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var row = y % 6
			if row < 2:
				img.set_pixel(x, y, soil_dark)
			elif row < 4:
				img.set_pixel(x, y, soil)
			else:
				img.set_pixel(x, y, soil_light)
	# 小苗
	for i in range(4):
		var sx = 4 + i * 7
		var sy = 8 + _rng.randi_range(-1, 1)
		img.set_pixel(sx, sy, Color(0.2, 0.45, 0.15))
		img.set_pixel(sx, sy - 1, Color(0.25, 0.50, 0.18))
	img.save_png("res://sprites/tiles/farmland.png")

func _tile_bridge():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var plank = Color(0.55, 0.42, 0.28, 1.0)
	var plank_dark = Color(0.45, 0.34, 0.22, 1.0)
	var rail = Color(0.42, 0.32, 0.20, 1.0)
	# 木桥
	for x in range(8, 24):
		for y in range(TILE_SIZE):
			if y % 4 < 3:
				img.set_pixel(x, y, plank if (x + y) % 5 != 0 else plank_dark)
	# 栏杆
	for y in range(TILE_SIZE):
		img.set_pixel(8, y, rail)
		img.set_pixel(23, y, rail)
	# 栏杆柱
	for y in range(0, TILE_SIZE, 8):
		img.set_pixel(7, y, rail)
		img.set_pixel(8, y, rail)
		img.set_pixel(23, y, rail)
		img.set_pixel(24, y, rail)
	img.save_png("res://sprites/tiles/bridge.png")

# ============================================================
# 玩家帧 - 4方向武侠侠客
# ============================================================

func generate_player_frames():
	DirAccess.make_dir_recursive_absolute("res://sprites/player")
	# 下(0), 左(1), 右(2), 上(3)
	for dir in range(4):
		for i in range(4):
			_save_player_idle_frame(dir, i)
		for i in range(6):
			_save_player_walk_frame(dir, i)
		for i in range(4):
			_save_player_attack_frame(dir, i)
		for i in range(2):
			_save_player_block_frame(dir, i)
	print("[TextureGen] Player frames generated")

func _draw_player_body(img: Image, dir: int, frame: int, bob: int, action: String = "idle"):
	var robe = Color(0.18, 0.22, 0.32, 1.0)
	var robe_light = Color(0.24, 0.28, 0.40, 1.0)
	var robe_dark = Color(0.12, 0.16, 0.24, 1.0)
	var skin = Color(0.78, 0.65, 0.52, 1.0)
	var hat = Color(0.25, 0.20, 0.14, 1.0)
	var hat_rim = Color(0.30, 0.25, 0.18, 1.0)
	var sword = Color(0.65, 0.65, 0.70, 1.0)
	var sword_hilt = Color(0.45, 0.30, 0.18, 1.0)
	var belt = Color(0.35, 0.20, 0.12, 1.0)
	var boot = Color(0.22, 0.16, 0.10, 1.0)

	var leg_sway = 0
	if action == "walk":
		leg_sway = [-1, 1, 2, 1, -1, -2][frame] if frame < 6 else 0

	# 靴子
	if dir == 0 or dir == 3:  # 下/上
		for y in range(40 + bob, 46 + bob):
			if y >= 0 and y < CHAR_H:
				for x in range(12, 15):
					img.set_pixel(x + leg_sway, y, boot)
				for x in range(17, 20):
					img.set_pixel(x - leg_sway, y, boot)
	else:  # 左/右
		for y in range(40 + bob, 46 + bob):
			if y >= 0 and y < CHAR_H:
				for x in range(13, 19):
					img.set_pixel(x, y, boot)

	# 身体/长袍
	for y in range(22 + bob, 40 + bob):
		if y >= 0 and y < CHAR_H:
			for x in range(11, 21):
				var col = robe
				if dir == 0 and y > 30 and x > 15:
					col = robe_light
				elif dir == 3 and y > 30 and x < 16:
					col = robe_light
				elif (x + y) % 7 == 0:
					col = robe_dark
				img.set_pixel(x, y, col)

	# 腰带
	for x in range(11, 21):
		var y = 28 + bob
		if y >= 0 and y < CHAR_H:
			img.set_pixel(x, y, belt)

	# 头部
	for y in range(14 + bob, 22 + bob):
		if y >= 0 and y < CHAR_H:
			for x in range(13, 19):
				img.set_pixel(x, y, skin)

	# 眼睛
	if dir == 0:
		img.set_pixel(14, 17 + bob, Color(0.1, 0.1, 0.1))
		img.set_pixel(17, 17 + bob, Color(0.1, 0.1, 0.1))
	elif dir == 1:
		img.set_pixel(13, 17 + bob, Color(0.1, 0.1, 0.1))
	elif dir == 2:
		img.set_pixel(18, 17 + bob, Color(0.1, 0.1, 0.1))

	# 斗笠
	for x in range(9, 23):
		for y in range(9 + bob, 15 + bob):
			if y >= 0 and y < CHAR_H:
				if abs(x - 16) + abs(y - 12 - bob) < 8:
					img.set_pixel(x, y, hat)
	# 帽檐
	for x in range(7, 25):
		var y = 14 + bob
		if y >= 0 and y < CHAR_H and x >= 8 and x <= 23:
			img.set_pixel(x, y, hat_rim)

	# 佩剑（背面/侧面可见）
	if dir == 1:  # 左面
		for y in range(20 + bob, 38 + bob):
			if y >= 0 and y < CHAR_H:
				img.set_pixel(21, y, sword)
		if 20 + bob >= 0 and 20 + bob < CHAR_H:
			for x in range(20, 23):
				img.set_pixel(x, 20 + bob, sword_hilt)
	elif dir == 2:  # 右面
		for y in range(20 + bob, 38 + bob):
			if y >= 0 and y < CHAR_H:
				img.set_pixel(11, y, sword)
		if 20 + bob >= 0 and 20 + bob < CHAR_H:
			for x in range(10, 13):
				img.set_pixel(x, 20 + bob, sword_hilt)
	elif dir == 3:  # 背面
		for y in range(18 + bob, 38 + bob):
			if y >= 0 and y < CHAR_H:
				img.set_pixel(22, y, sword)
		if 18 + bob >= 0 and 18 + bob < CHAR_H:
			for x in range(21, 24):
				img.set_pixel(x, 18 + bob, sword_hilt)

func _save_player_idle_frame(dir: int, frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bob = 0
	if frame == 1 or frame == 3:
		bob = 1
	_draw_player_body(img, dir, frame, bob, "idle")
	var dir_name = ["down", "left", "right", "up"][dir]
	img.save_png("res://sprites/player/idle_%s_%d.png" % [dir_name, frame])

func _save_player_walk_frame(dir: int, frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bob = [0, -1, 0, 1, -1, 0][frame]
	_draw_player_body(img, dir, frame, bob, "walk")
	var dir_name = ["down", "left", "right", "up"][dir]
	img.save_png("res://sprites/player/walk_%s_%d.png" % [dir_name, frame])

func _save_player_attack_frame(dir: int, frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bob = 0
	_draw_player_body(img, dir, frame, bob, "attack")
	# 剑击效果
	var slash_color = Color(0.8, 0.9, 1.0, 0.8)
	var dir_name = ["down", "left", "right", "up"][dir]
	if dir == 0:  # 下
		var slash_x = 20 + frame * 3
		for y in range(18, 30):
			if slash_x < CHAR_W:
				img.set_pixel(slash_x, y, slash_color)
				if slash_x + 1 < CHAR_W:
					img.set_pixel(slash_x + 1, y, Color(0.6, 0.7, 0.9, 0.5))
	elif dir == 1:  # 左
		var slash_x = 8 - frame * 3
		for y in range(18, 30):
			if slash_x >= 0:
				img.set_pixel(slash_x, y, slash_color)
				if slash_x - 1 >= 0:
					img.set_pixel(slash_x - 1, y, Color(0.6, 0.7, 0.9, 0.5))
	elif dir == 2:  # 右
		var slash_x = 24 + frame * 3
		for y in range(18, 30):
			if slash_x < CHAR_W:
				img.set_pixel(slash_x, y, slash_color)
				if slash_x + 1 < CHAR_W:
					img.set_pixel(slash_x + 1, y, Color(0.6, 0.7, 0.9, 0.5))
	elif dir == 3:  # 上
		var slash_x = 12 - frame * 2
		for y in range(14, 26):
			if slash_x >= 0:
				img.set_pixel(slash_x, y, slash_color)
	img.save_png("res://sprites/player/attack_%s_%d.png" % [dir_name, frame])

func _save_player_block_frame(dir: int, frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_player_body(img, dir, frame, 0, "block")
	# 格挡光盾
	var shield_color = Color(0.3, 0.5, 0.9, 0.4 + frame * 0.15)
	var dir_name = ["down", "left", "right", "up"][dir]
	if dir == 0:
		for x in range(10, 22):
			img.set_pixel(x, 20, shield_color)
			img.set_pixel(x, 28, shield_color)
		for y in range(20, 29):
			img.set_pixel(10, y, shield_color)
			img.set_pixel(21, y, shield_color)
	elif dir == 1:
		for x in range(6, 14):
			img.set_pixel(x, 18, shield_color)
			img.set_pixel(x, 28, shield_color)
		for y in range(18, 29):
			img.set_pixel(6, y, shield_color)
			img.set_pixel(13, y, shield_color)
	elif dir == 2:
		for x in range(18, 26):
			img.set_pixel(x, 18, shield_color)
			img.set_pixel(x, 28, shield_color)
		for y in range(18, 29):
			img.set_pixel(18, y, shield_color)
			img.set_pixel(25, y, shield_color)
	elif dir == 3:
		for x in range(10, 22):
			img.set_pixel(x, 12, shield_color)
			img.set_pixel(x, 22, shield_color)
		for y in range(12, 23):
			img.set_pixel(10, y, shield_color)
			img.set_pixel(21, y, shield_color)
	img.save_png("res://sprites/player/block_%s_%d.png" % [dir_name, frame])

# ============================================================
# NPC帧 - 多种外观
# ============================================================

func generate_npc_frames():
	DirAccess.make_dir_recursive_absolute("res://sprites/npc")
	var npc_types = ["warrior", "scholar", "merchant", "elder", "mysterious"]
	for npc_type in npc_types:
		for dir in range(4):
			for i in range(4):
				_save_npc_idle_frame(npc_type, dir, i)
			for i in range(6):
				_save_npc_walk_frame(npc_type, dir, i)
	print("[TextureGen] NPC frames generated")

func _draw_npc_body(img: Image, npc_type: String, dir: int, frame: int, bob: int, action: String = "idle"):
	var robe: Color
	var robe_light: Color
	var robe_dark: Color
	var hat_color: Color
	var accessory_color: Color
	var skin = Color(0.78, 0.65, 0.52, 1.0)
	var boot = Color(0.22, 0.16, 0.10, 1.0)
	var belt: Color

	match npc_type:
		"warrior":
			robe = Color(0.50, 0.18, 0.12, 1.0)
			robe_light = Color(0.60, 0.24, 0.16, 1.0)
			robe_dark = Color(0.38, 0.12, 0.08, 1.0)
			hat_color = Color(0.40, 0.15, 0.10, 1.0)
			accessory_color = Color(0.70, 0.65, 0.60, 1.0)  # 刀
			belt = Color(0.30, 0.20, 0.12, 1.0)
		"scholar":
			robe = Color(0.75, 0.72, 0.60, 1.0)
			robe_light = Color(0.82, 0.80, 0.68, 1.0)
			robe_dark = Color(0.62, 0.58, 0.48, 1.0)
			hat_color = Color(0.20, 0.18, 0.16, 1.0)  # 书生帽
			accessory_color = Color(0.55, 0.40, 0.25, 1.0)  # 书卷
			belt = Color(0.35, 0.30, 0.20, 1.0)
		"merchant":
			robe = Color(0.55, 0.40, 0.20, 1.0)
			robe_light = Color(0.65, 0.50, 0.28, 1.0)
			robe_dark = Color(0.42, 0.30, 0.15, 1.0)
			hat_color = Color(0.50, 0.38, 0.22, 1.0)
			accessory_color = Color(0.85, 0.75, 0.30, 1.0)  # 金算盘
			belt = Color(0.60, 0.50, 0.20, 1.0)
		"elder":
			robe = Color(0.40, 0.42, 0.50, 1.0)
			robe_light = Color(0.50, 0.52, 0.60, 1.0)
			robe_dark = Color(0.30, 0.32, 0.38, 1.0)
			hat_color = Color(0.35, 0.35, 0.40, 1.0)
			accessory_color = Color(0.70, 0.50, 0.30, 1.0)  # 拐杖
			belt = Color(0.30, 0.28, 0.25, 1.0)
		"mysterious":
			robe = Color(0.18, 0.15, 0.25, 1.0)
			robe_light = Color(0.25, 0.22, 0.35, 1.0)
			robe_dark = Color(0.10, 0.08, 0.18, 1.0)
			hat_color = Color(0.12, 0.10, 0.20, 1.0)
			accessory_color = Color(0.40, 0.20, 0.60, 1.0)  # 暗器
			belt = Color(0.20, 0.15, 0.28, 1.0)

	var leg_sway = 0
	if action == "walk":
		leg_sway = [-1, 1, 2, 1, -1, -2][frame] if frame < 6 else 0

	# 靴子
	if dir == 0 or dir == 3:
		for y in range(40 + bob, 46 + bob):
			if y >= 0 and y < CHAR_H:
				for x in range(12, 15):
					img.set_pixel(x + leg_sway, y, boot)
				for x in range(17, 20):
					img.set_pixel(x - leg_sway, y, boot)
	else:
		for y in range(40 + bob, 46 + bob):
			if y >= 0 and y < CHAR_H:
				for x in range(13, 19):
					img.set_pixel(x, y, boot)

	# 身体
	for y in range(22 + bob, 40 + bob):
		if y >= 0 and y < CHAR_H:
			for x in range(11, 21):
				var col = robe
				if (x + y) % 7 == 0:
					col = robe_dark
				elif dir == 0 and y > 30 and x > 15:
					col = robe_light
				elif dir == 3 and y > 30 and x < 16:
					col = robe_light
				img.set_pixel(x, y, col)

	# 腰带
	for x in range(11, 21):
		var y = 28 + bob
		if y >= 0 and y < CHAR_H:
			img.set_pixel(x, y, belt)

	# 头部
	for y in range(14 + bob, 22 + bob):
		if y >= 0 and y < CHAR_H:
			for x in range(13, 19):
				img.set_pixel(x, y, skin)

	# 眼睛
	if dir == 0:
		img.set_pixel(14, 17 + bob, Color(0.1, 0.1, 0.1))
		img.set_pixel(17, 17 + bob, Color(0.1, 0.1, 0.1))
	elif dir == 1:
		img.set_pixel(13, 17 + bob, Color(0.1, 0.1, 0.1))
	elif dir == 2:
		img.set_pixel(18, 17 + bob, Color(0.1, 0.1, 0.1))

	# 帽子
	match npc_type:
		"warrior":
			# 武士头巾
			for x in range(12, 20):
				for y in range(10 + bob, 15 + bob):
					if y >= 0 and y < CHAR_H:
						img.set_pixel(x, y, hat_color)
		"scholar":
			# 书生方巾
			for x in range(12, 20):
				for y in range(10 + bob, 14 + bob):
					if y >= 0 and y < CHAR_H:
						img.set_pixel(x, y, hat_color)
			# 方巾翅
			if 10 + bob >= 0 and 10 + bob < CHAR_H:
				img.set_pixel(10, 11 + bob, hat_color)
				img.set_pixel(11, 11 + bob, hat_color)
				img.set_pixel(20, 11 + bob, hat_color)
				img.set_pixel(21, 11 + bob, hat_color)
		"merchant":
			# 商人圆帽
			for x in range(12, 20):
				for y in range(10 + bob, 15 + bob):
					if y >= 0 and y < CHAR_H:
						var dx = abs(x - 16)
						if y - 10 - bob < 3 or dx < 4:
							img.set_pixel(x, y, hat_color)
		"elder":
			# 长者发髻
			for x in range(13, 19):
				for y in range(9 + bob, 14 + bob):
					if y >= 0 and y < CHAR_H:
						img.set_pixel(x, y, Color(0.7, 0.7, 0.72))
			# 发簪
			if 9 + bob >= 0 and 9 + bob < CHAR_H:
				img.set_pixel(16, 9 + bob, accessory_color)
				img.set_pixel(17, 9 + bob, accessory_color)
		"mysterious":
			# 面纱斗笠
			for x in range(9, 23):
				for y in range(9 + bob, 15 + bob):
					if y >= 0 and y < CHAR_H:
						if abs(x - 16) + abs(y - 12 - bob) < 8:
							img.set_pixel(x, y, hat_color)
			for x in range(7, 25):
				var y = 14 + bob
				if y >= 0 and y < CHAR_H and x >= 8 and x <= 23:
					img.set_pixel(x, y, hat_color)
			# 面纱
			for x in range(11, 21):
				for y in range(15 + bob, 20 + bob):
					if y >= 0 and y < CHAR_H:
						img.set_pixel(x, y, Color(0.15, 0.12, 0.22, 0.7))

	# 配饰
	match npc_type:
		"warrior":
			if dir == 1 or dir == 2:
				var sx = 21 if dir == 1 else 11
				for y in range(22 + bob, 36 + bob):
					if y >= 0 and y < CHAR_H:
						img.set_pixel(sx, y, accessory_color)
		"scholar":
			if dir == 1:
				for y in range(24 + bob, 32 + bob):
					if y >= 0 and y < CHAR_H:
						img.set_pixel(9, y, accessory_color)
						img.set_pixel(10, y, accessory_color)
			elif dir == 2:
				for y in range(24 + bob, 32 + bob):
					if y >= 0 and y < CHAR_H:
						img.set_pixel(22, y, accessory_color)
						img.set_pixel(23, y, accessory_color)
		"merchant":
			if dir == 0:
				for x in range(20, 24):
					for y in range(26 + bob, 32 + bob):
						if x < CHAR_W and y >= 0 and y < CHAR_H:
							img.set_pixel(x, y, accessory_color)
		"elder":
			if dir == 1 or dir == 2:
				var cx = 9 if dir == 1 else 23
				for y in range(24 + bob, 44 + bob):
					if y >= 0 and y < CHAR_H:
						img.set_pixel(cx, y, accessory_color)

func _save_npc_idle_frame(npc_type: String, dir: int, frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bob = 0
	if frame == 1 or frame == 3:
		bob = 1
	_draw_npc_body(img, npc_type, dir, frame, bob, "idle")
	var dir_name = ["down", "left", "right", "up"][dir]
	img.save_png("res://sprites/npc/%s_idle_%s_%d.png" % [npc_type, dir_name, frame])

func _save_npc_walk_frame(npc_type: String, dir: int, frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bob = [0, -1, 0, 1, -1, 0][frame]
	_draw_npc_body(img, npc_type, dir, frame, bob, "walk")
	var dir_name = ["down", "left", "right", "up"][dir]
	img.save_png("res://sprites/npc/%s_walk_%s_%d.png" % [npc_type, dir_name, frame])
