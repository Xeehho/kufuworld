@tool
extends Node

# 星露谷/饥荒风格纹理生成器
# 使用16x16瓦片尺寸（适配Anokolisa等16x16像素资源包）

const TILE_SIZE = 16
const CHAR_W = 16
const CHAR_H = 24

# ============================================================
# 精致武侠风调色板（参考江湖风云传：月白长袍+黛青镶边+朱红点缀）
# ============================================================
const C_HAIR = Color(0.13, 0.11, 0.10)       # 乌发
const C_RIBBON = Color(0.80, 0.24, 0.18)     # 朱红发带
const C_SKIN = Color(0.88, 0.71, 0.57)       # 肤色
const C_SKIN_D = Color(0.74, 0.57, 0.44)     # 肤阴影
const C_TRIM = Color(0.24, 0.34, 0.42)       # 黛青镶边
const C_JADE = Color(0.38, 0.68, 0.52)       # 玉佩
const C_PANTS = Color(0.24, 0.26, 0.30)      # 裤
const C_BOOT = Color(0.16, 0.14, 0.13)       # 靴
const C_SCABBARD = Color(0.20, 0.18, 0.20)   # 剑鞘
const C_HILT = Color(0.58, 0.44, 0.26)       # 剑柄缠绳
const C_OUTLINE = Color(0.10, 0.10, 0.13)    # 描边

var _rng = RandomNumberGenerator.new()

# 安全画点（越界忽略）
func _px(img: Image, x: int, y: int, c: Color):
	if x >= 0 and x < CHAR_W and y >= 0 and y < CHAR_H:
		img.set_pixel(x, y, c)

# 实心矩形（含边界）
func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color):
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_px(img, x, y, c)

func _ready():
	_rng.seed = 42
	if Engine.is_editor_hint():
		generate_all()

# ============================================================
# 运行时安全PNG加载（全局唯一入口）
# 首次运行生成的新PNG尚未进入import系统，load()/ResourceLoader.exists() 会失败，
# 因此直接从磁盘解码为 ImageTexture（对已导入文件同样适用）。带内存缓存避免重复解码。
# ============================================================
static var _tex_cache := {}

static func load_png_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	# 用绝对路径读取，避免 res:// 路径触发 "Loaded resource as image file" 警告刷屏
	var abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img = Image.load_from_file(abs_path)
	if img == null:
		return null
	var tex = ImageTexture.create_from_image(img)
	_tex_cache[path] = tex
	return tex

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
	# Phase B 备忘：grass/grass_dark/path/farmland/water 已由素材包管线接管
	# （tools/import_pack_assets.py export_terrain 选片），此处不再覆盖，
	# 避免运行时重生成把包瓦片冲回程序贴图；若缺这些文件请重跑python管线
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
	generate_buildings()
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
	# 星露谷式鲜亮草地：明快暖绿底+深浅草叶簇+三叶草+碎花
	var base = Color(0.35, 0.60, 0.24, 1.0)
	var light = Color(0.46, 0.71, 0.31, 1.0)
	var dark = Color(0.26, 0.48, 0.17, 1.0)
	var clover = Color(0.30, 0.55, 0.20, 1.0)
	_fill_base(img, base, 0.03)
	# 大块明暗斑驳（让远处看有层次而非纯色噪点）
	for i in range(3):
		var bx = _rng.randi_range(2, TILE_SIZE - 8)
		var by = _rng.randi_range(2, TILE_SIZE - 8)
		var bw = _rng.randi_range(4, 8)
		var bh = _rng.randi_range(3, 5)
		var bc = light if _rng.randf() > 0.5 else dark
		for x in range(bx, bx + bw):
			for y in range(by, by + bh):
				if x < TILE_SIZE and y < TILE_SIZE and _noise_pixel(x, y, 21) > 0.35:
					var c = img.get_pixel(x, y)
					img.set_pixel(x, y, Color(
						c.r * 0.6 + bc.r * 0.4,
						c.g * 0.6 + bc.g * 0.4,
						c.b * 0.6 + bc.b * 0.4, 1))
	# 草叶簇（人字形小叶）
	for i in range(14):
		var gx = _rng.randi_range(1, TILE_SIZE - 3)
		var gy = _rng.randi_range(5, TILE_SIZE - 2)
		var h = _rng.randi_range(2, 4)
		var col = light if _rng.randf() > 0.4 else dark
		for dy in range(h):
			if gy - dy >= 0:
				img.set_pixel(gx, gy - dy, col)
				if dy == h - 1 and gx + 1 < TILE_SIZE:
					img.set_pixel(gx + 1, gy - dy + 1, col)  # 叶尖斜挑
	# 三叶草小团
	for i in range(2):
		if _rng.randf() > 0.4:
			var cx = _rng.randi_range(3, TILE_SIZE - 4)
			var cy = _rng.randi_range(6, TILE_SIZE - 3)
			img.set_pixel(cx, cy, clover)
			img.set_pixel(cx - 1, cy, clover)
			img.set_pixel(cx + 1, cy, clover)
			img.set_pixel(cx, cy - 1, clover)
	# 碎花点缀
	for i in range(2):
		if _rng.randf() > 0.5:
			var fx = _rng.randi_range(4, TILE_SIZE - 5)
			var fy = _rng.randi_range(6, TILE_SIZE - 4)
			var flower_colors = [Color(0.95, 0.60, 0.60), Color(0.95, 0.85, 0.45), Color(0.78, 0.65, 0.88), Color(0.98, 0.98, 0.92)]
			var fc = flower_colors[_rng.randi() % flower_colors.size()]
			img.set_pixel(fx, fy, fc)
			img.set_pixel(fx, fy - 1, fc)
	img.save_png("res://sprites/tiles/grass.png")

func _tile_grass_dark():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# 深色草地同步提亮，与主草地同色系避免割裂
	var base = Color(0.24, 0.42, 0.16, 1.0)
	var dark = Color(0.18, 0.34, 0.12, 1.0)
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
	# 星露谷式清亮水面：宝石蓝主调+明亮波纹带+白沫高光
	var deep = Color(0.16, 0.38, 0.62, 1.0)
	var mid = Color(0.22, 0.52, 0.78, 1.0)
	var light = Color(0.35, 0.68, 0.88, 1.0)
	var foam = Color(0.85, 0.95, 0.98, 1.0)
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var wave = sin(x * 0.5 + y * 0.35) * 0.5 + 0.5
			var wave2 = sin((x + 5) * 0.4 + (y + 3) * 0.48) * 0.3 + 0.5
			var v = wave * wave2
			if v > 0.70:
				img.set_pixel(x, y, light)
			elif v > 0.40:
				img.set_pixel(x, y, mid)
			else:
				img.set_pixel(x, y, deep)
	# 横向波光线（星露谷水面标志性的亮带）
	for i in range(2):
		var wy = _rng.randi_range(4, TILE_SIZE - 5)
		var wx = _rng.randi_range(2, TILE_SIZE - 12)
		var wl = _rng.randi_range(6, 10)
		for dx in range(wl):
			if wx + dx < TILE_SIZE:
				img.set_pixel(wx + dx, wy, light)
				if dx > 1 and dx < wl - 2:
					img.set_pixel(wx + dx, wy, foam)
	# 涟漪白沫
	for i in range(2):
		var fx = _rng.randi_range(2, TILE_SIZE - 4)
		var fy = _rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(fx, fy, foam)
		img.set_pixel(fx + 1, fy, foam)
	img.save_png("res://sprites/tiles/water.png")

func _tile_sand():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# 暖金沙滩：柔和沙纹+沙粒噪点+零星贝壳
	var base = Color(0.84, 0.74, 0.55, 1.0)
	var light = Color(0.90, 0.81, 0.62, 1.0)
	var dark = Color(0.72, 0.62, 0.45, 1.0)
	var shell = Color(0.95, 0.90, 0.82, 1.0)
	_fill_base(img, base, 0.03)
	# 柔和波浪沙纹
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var stripe = sin(y * 0.45 + sin(x * 0.25) * 1.6) * 0.5 + 0.5
			if stripe > 0.80:
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(
					c.r * 0.75 + light.r * 0.25,
					c.g * 0.75 + light.g * 0.25,
					c.b * 0.75 + light.b * 0.25, 1))
			elif stripe < 0.12:
				var c2 = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(
					c2.r * 0.8 + dark.r * 0.2,
					c2.g * 0.8 + dark.g * 0.2,
					c2.b * 0.8 + dark.b * 0.2, 1))
	# 沙粒
	for i in range(6):
		var rx = _rng.randi_range(1, TILE_SIZE - 2)
		var ry = _rng.randi_range(1, TILE_SIZE - 2)
		img.set_pixel(rx, ry, dark)
	# 小贝壳
	if _rng.randf() > 0.5:
		var sx = _rng.randi_range(4, TILE_SIZE - 5)
		var sy = _rng.randi_range(4, TILE_SIZE - 5)
		img.set_pixel(sx, sy, shell)
		img.set_pixel(sx + 1, sy, shell)
		img.set_pixel(sx, sy + 1, dark)
	img.save_png("res://sprites/tiles/sand.png")

func _tile_mountain():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# 层叠岩壁：不规则明暗岩块+纵向裂隙+零星苔点（Phase B-2 压饱和转冷灰蓝，呼应黛青瓦）
	var rock = Color(0.45, 0.48, 0.52, 1.0)
	var highlight = Color(0.59, 0.63, 0.67, 1.0)
	var shadow = Color(0.32, 0.35, 0.39, 1.0)
	var deep = Color(0.23, 0.26, 0.30, 1.0)
	var moss = Color(0.35, 0.48, 0.28, 1.0)
	# 基础岩体（低频起伏，弱化正弦条纹感）
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var n1 = _noise_pixel(x / 3, y / 3, 11)
			var n2 = _noise_pixel(x / 2, y / 2, 23)
			var v = n1 * 0.7 + n2 * 0.3
			if v > 0.68:
				img.set_pixel(x, y, highlight)
			elif v > 0.42:
				img.set_pixel(x, y, rock)
			elif v > 0.25:
				img.set_pixel(x, y, shadow)
			else:
				img.set_pixel(x, y, deep)
	# 岩块高光棱线（左上受光）
	for i in range(3):
		var ex = _rng.randi_range(3, TILE_SIZE - 10)
		var ey = _rng.randi_range(3, TILE_SIZE - 10)
		var len_e = _rng.randi_range(4, 8)
		for d in range(len_e):
			if ex + d < TILE_SIZE and ey + d / 2 < TILE_SIZE:
				img.set_pixel(ex + d, ey + d / 2, highlight)
	# 纵向裂隙
	for i in range(3):
		var cx = _rng.randi_range(4, TILE_SIZE - 5)
		var cy = _rng.randi_range(2, TILE_SIZE - 12)
		var len_c = _rng.randi_range(5, 10)
		for dy in range(len_c):
			var wobble = int(sin(dy * 0.9) * 1.5)
			if cy + dy < TILE_SIZE and cx + wobble < TILE_SIZE:
				img.set_pixel(cx + wobble, cy + dy, deep)
	# 零星苔点（底部背阴处，不均匀分布）
	for i in range(4):
		var mx = _rng.randi_range(1, TILE_SIZE - 3)
		var my = _rng.randi_range(TILE_SIZE / 2, TILE_SIZE - 2)
		if _noise_pixel(mx, my, 37) > 0.4:
			img.set_pixel(mx, my, moss)
			img.set_pixel(mx + 1, my, moss)
			if _rng.randf() > 0.5:
				img.set_pixel(mx, my + 1, moss)
	img.save_png("res://sprites/tiles/mountain.png")

func _tile_mountain_snow():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var snow = Color(0.90, 0.92, 0.95, 1.0)
	var ice = Color(0.80, 0.88, 0.95, 1.0)
	var rock = Color(0.37, 0.39, 0.43, 1.0)  # 冷灰岩，与黛青系协调
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
	var trunk = Color(0.38, 0.26, 0.15, 1.0)
	var leaf_dark = Color(0.12, 0.34, 0.14, 1.0)
	var leaf_mid = Color(0.18, 0.46, 0.18, 1.0)
	var leaf_light = Color(0.28, 0.58, 0.24, 1.0)
	# 松树 - 三角形层叠（Phase B-2：旧版按32px绘制越界，重排为16x16）
	# 树干
	for y in range(11, TILE_SIZE):
		for x in range(7, 9):
			img.set_pixel(x, y, trunk)
	# 下层（最宽）
	for y in range(4, 12):
		var half_w = int((12 - y) * 0.62)
		for x in range(8 - half_w, 8 + half_w + 1):
			if x >= 0 and x < TILE_SIZE:
				var shade = leaf_mid if (x + y) % 3 != 0 else leaf_dark
				img.set_pixel(x, y, shade)
	# 上层
	for y in range(1, 6):
		var half_w = int((6 - y) * 0.55)
		for x in range(8 - half_w, 8 + half_w + 1):
			if x >= 0 and x < TILE_SIZE:
				var shade = leaf_light if (x + y) % 4 != 0 else leaf_mid
				img.set_pixel(x, y, shade)
	# 顶部
	img.set_pixel(8, 0, leaf_light)
	img.set_pixel(7, 1, leaf_mid)
	img.set_pixel(8, 1, leaf_light)
	img.set_pixel(9, 1, leaf_mid)
	img.save_png("res://sprites/tiles/tree_pine.png")

func _tile_tree_oak():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var trunk = Color(0.40, 0.28, 0.16, 1.0)
	var leaf_dark = Color(0.15, 0.38, 0.14, 1.0)
	var leaf_mid = Color(0.22, 0.50, 0.18, 1.0)
	var leaf_light = Color(0.33, 0.62, 0.26, 1.0)
	# 橡树 - 圆形树冠（Phase B-2：旧版按32px绘制越界，重排为16x16）
	# 树干
	for y in range(10, TILE_SIZE):
		for x in range(7, 9):
			img.set_pixel(x, y, trunk)
	# 圆形树冠：中心(8,6)，半径6.2x5.2
	for x in range(1, 16):
		for y in range(0, 12):
			var dx = (x - 8.0) / 6.4
			var dy = (y - 5.5) / 5.4
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
	# 竹子 - 竖直竹竿+竹叶（Phase B-2：旧版三竿x=10/16/22越界，重排为格内双竿）
	for x in [5, 11]:
		for y in range(2, TILE_SIZE):
			img.set_pixel(x, y, stalk)
			if y % 6 < 2:
				img.set_pixel(x, y, stalk_dark)
	# 竹叶
	var leaf_positions = [
		[2, 3], [3, 4], [7, 2], [8, 4], [9, 3],
		[1, 8], [2, 9], [7, 8], [8, 10], [12, 8], [13, 9],
		[3, 13], [8, 13], [9, 12], [13, 13], [12, 3], [13, 5],
		[6, 6], [10, 6], [4, 10], [11, 11], [6, 15]
	]
	for lp in leaf_positions:
		if lp[0] < TILE_SIZE and lp[1] < TILE_SIZE:
			img.set_pixel(lp[0], lp[1], leaf if _rng.randf() > 0.3 else leaf_light)
	img.save_png("res://sprites/tiles/tree_bamboo.png")

func _tile_house_town():
	_img_save_house("res://sprites/tiles/house_town.png", "brick", false)

func _tile_house_cottage():
	_img_save_house("res://sprites/tiles/house_cottage.png", "wood", false, "thatch")

func _tile_house_temple():
	_img_save_house("res://sprites/tiles/house_temple.png", "brick", true)

func _tile_house_cave():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rock = Color(0.42, 0.40, 0.36, 1.0)
	var rock_d = Color(0.30, 0.28, 0.25, 1.0)
	var dark = Color(0.06, 0.06, 0.08, 1.0)
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var dx = (x - 7.5) / 6.5
			var dy = (y - 6.0) / 5.5
			var d = dx * dx + dy * dy
			if d < 0.35:
				img.set_pixel(x, y, dark)
			elif d < 0.85:
				var c = rock
				if (x + y) % 4 == 0:
					c = rock_d
				img.set_pixel(x, y, c)
	for x in range(4, 12):
		img.set_pixel(x, 2, rock)
	img.save_png("res://sprites/tiles/house_cave.png")

# ============ 16x16 中式房屋绘制（黛青瓦顶/赭石茅草顶 + 米色墙 + 棕门 + 蓝窗） ============
# Phase B-1：原亮橙/高饱和绿顶与素材包色调冲突，改为低饱和黛青瓦为主，
# 茅屋(cottage)用赭石茅草顶做区分，均压低饱和度融入 Pixel Crawler 调色板
const _ROOF = Color(0.27, 0.36, 0.42, 1.0)        # 黛青瓦主色 #455C6B
const _ROOF_HI = Color(0.38, 0.49, 0.55, 1.0)     # 瓦面受光 #617D8C
const _ROOF_DARK = Color(0.17, 0.23, 0.28, 1.0)   # 檐口阴影 #2B3B47
const _ROOF_THATCH = [Color(0.58, 0.44, 0.28, 1.0), Color(0.70, 0.56, 0.37, 1.0), Color(0.42, 0.31, 0.19, 1.0)]  # 赭石茅草 #947047系
const _WALL = Color(0.94, 0.88, 0.72, 1.0)
const _WALL_D = Color(0.76, 0.68, 0.52, 1.0)
const _BRICK = Color(0.84, 0.76, 0.58, 1.0)
const _BEAM = Color(0.45, 0.30, 0.17, 1.0)
const _DOOR = Color(0.42, 0.26, 0.14, 1.0)
const _DOOR_FRAME = Color(0.58, 0.40, 0.24, 1.0)
const _WIN = Color(0.40, 0.62, 0.86, 1.0)
const _WIN_FRAME = Color(0.93, 0.92, 0.85, 1.0)
const _GOLD = Color(0.85, 0.70, 0.35, 1.0)
const _PILLAR = Color(0.62, 0.20, 0.14, 1.0)

func _img_house_roof(img: Image, roof_pal: Array = []):
	# 人字坡屋顶（y=0..6），正脊跨格连续；roof_pal=[主色,受光,檐影]，空则用黛青瓦
	var c_main: Color = roof_pal[0] if roof_pal.size() == 3 else _ROOF
	var c_hi: Color = roof_pal[1] if roof_pal.size() == 3 else _ROOF_HI
	var c_dark: Color = roof_pal[2] if roof_pal.size() == 3 else _ROOF_DARK
	for x in range(TILE_SIZE):
		for y in range(7):
			var peak = abs(x - 7.5)
			var top_y = int(peak * 0.95)
			if y >= top_y:
				var c = c_main
				if x % 3 == 1:
					c = c_hi
				if y == 6:
					c = c_dark
				img.set_pixel(x, y, c)
	for x in range(6, 10):
		img.set_pixel(x, 0, c_hi)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 7, _BEAM)

func _img_house_wall(img: Image, wall_type: String):
	for x in range(TILE_SIZE):
		for y in range(8, 15):
			img.set_pixel(x, y, _WALL)
	if wall_type == "brick":
		for x in range(TILE_SIZE):
			for y in range(9, 15):
				if (x + y) % 5 == 0:
					img.set_pixel(x, y, _BRICK)
	else:
		for x in range(TILE_SIZE):
			for y in range(9, 15):
				if x % 4 == 0:
					img.set_pixel(x, y, Color(0.82, 0.74, 0.56, 1.0))
	for x in range(TILE_SIZE):
		img.set_pixel(x, 14, _WALL_D)

func _img_house_door(img: Image, x0: int, y0: int, w: int, h: int):
	var x1 = x0 + w - 1
	var y1 = y0 + h - 1
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			img.set_pixel(x, y, _DOOR)
	for x in range(x0 - 1, x1 + 2):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, y0 - 1, _DOOR_FRAME)
			img.set_pixel(x, y1, _DOOR_FRAME)
	if x0 - 1 >= 0:
		for y in range(y0 - 1, y1 + 1):
			img.set_pixel(x0 - 1, y, _DOOR_FRAME)
	if x1 + 1 < TILE_SIZE:
		for y in range(y0 - 1, y1 + 1):
			img.set_pixel(x1 + 1, y, _DOOR_FRAME)
	if x0 + 1 < TILE_SIZE and y0 + 2 < TILE_SIZE:
		img.set_pixel(x0 + 1, y0 + 2, _GOLD)
	if x1 - 1 >= 0 and y0 + 2 < TILE_SIZE:
		img.set_pixel(x1 - 1, y0 + 2, _GOLD)

func _img_house_window(img: Image, x0: int, y0: int):
	if x0 < 0 or y0 < 0 or x0 + 4 > TILE_SIZE or y0 + 4 > TILE_SIZE:
		return
	for x in range(x0, x0 + 3):
		for y in range(y0, y0 + 3):
			img.set_pixel(x, y, _WIN)
	for x in range(x0, x0 + 3):
		img.set_pixel(x, y0 + 1, _WIN_FRAME)
	for y in range(y0, y0 + 3):
		img.set_pixel(x0 + 1, y, _WIN_FRAME)
	for x in range(x0 - 1, x0 + 4):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, y0 - 1, _WIN_FRAME)
			img.set_pixel(x, y0 + 3, _WIN_FRAME)
	for y in range(y0 - 1, y0 + 4):
		if y >= 0 and y < TILE_SIZE:
			if x0 - 1 >= 0:
				img.set_pixel(x0 - 1, y, _WIN_FRAME)
			if x0 + 3 < TILE_SIZE:
				img.set_pixel(x0 + 3, y, _WIN_FRAME)

func _img_save_house(path: String, wall_type: String, temple: bool, roof_kind: String = "tile"):
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_img_house_roof(img, _ROOF_THATCH if roof_kind == "thatch" else [])
	if temple:
		for x in [1, 14]:
			for y in range(7, 15):
				img.set_pixel(x, y, _PILLAR)
		for x in range(TILE_SIZE):
			if img.get_pixel(x, 0).a > 0.5:
				img.set_pixel(x, 0, _GOLD)
	_img_house_wall(img, wall_type)
	var door_y = 9 if temple else 10
	var door_h = 7 if temple else 6
	_img_house_door(img, 5, door_y, 6, door_h)
	_img_house_window(img, 3, door_y)
	_img_house_window(img, 9, door_y)
	img.save_png(path)

func _tile_flower():
	# Phase B-2：按16x16重排（旧版fx=6+i*8越界只画得出两朵），花色整体降饱和
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stem = Color(0.24, 0.42, 0.18, 1.0)
	var colors = [Color(0.88, 0.45, 0.42), Color(0.92, 0.78, 0.35), Color(0.66, 0.50, 0.82), Color(0.94, 0.62, 0.70)]
	var center = Color(0.95, 0.85, 0.40, 1.0)
	for i in range(3):
		var fx = 3 + i * 5
		if fx >= TILE_SIZE - 1:
			fx = TILE_SIZE - 4
		var fy = 9 + (i % 2) * 2
		# 茎（向下4px，全部落在格内）
		for y in range(fy, min(fy + 5, TILE_SIZE)):
			img.set_pixel(fx, y, stem)
		# 花瓣十字+芯
		var col = colors[_rng.randi() % colors.size()]
		if fx - 1 >= 0: img.set_pixel(fx - 1, fy, col)
		if fx + 1 < TILE_SIZE: img.set_pixel(fx + 1, fy, col)
		if fy - 1 >= 0: img.set_pixel(fx, fy - 1, col)
		if fy + 1 < TILE_SIZE: img.set_pixel(fx, fy + 1, col)
		img.set_pixel(fx, fy, center)
	img.save_png("res://sprites/tiles/flower.png")

func _tile_rock():
	# Phase B-2：旧版按32px坐标绘制，16x16下大部分越界导致石头近乎隐形；重绘为格内大石+小石
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rock = Color(0.53, 0.56, 0.60, 1.0)      # 冷灰与山岩同系
	var highlight = Color(0.72, 0.75, 0.79, 1.0)
	var shadow = Color(0.36, 0.39, 0.43, 1.0)
	var outline = Color(0.21, 0.23, 0.26, 1.0)
	var moss = Color(0.35, 0.48, 0.27, 1.0)
	# 主石：椭圆中心(6.5,10)，半径4.5x3.6，左上受光右下背光
	for x in range(1, 13):
		for y in range(5, 16):
			var dx = (x - 6.5) / 4.8
			var dy = (y - 10.0) / 3.9
			var d = dx * dx + dy * dy
			if d < 1.0:
				if d > 0.78:
					img.set_pixel(x, y, outline)
				elif x <= 5 and y <= 9 and d < 0.45:
					img.set_pixel(x, y, highlight)
				elif d > 0.55 or y >= 12:
					img.set_pixel(x, y, shadow)
				else:
					img.set_pixel(x, y, rock)
	# 小石：中心(12,12.5) 半径2.4x2.0
	for x in range(9, 16):
		for y in range(10, 16):
			var dx2 = (x - 12.0) / 2.6
			var dy2 = (y - 12.5) / 2.2
			var d2 = dx2 * dx2 + dy2 * dy2
			if d2 < 1.0:
				if d2 > 0.72:
					img.set_pixel(x, y, outline)
				elif x <= 11 and y <= 12:
					img.set_pixel(x, y, rock)
				else:
					img.set_pixel(x, y, shadow)
	# 石缝苔点（底部）
	img.set_pixel(4, 13, moss)
	img.set_pixel(5, 14, moss)
	img.set_pixel(10, 14, moss)
	img.save_png("res://sprites/tiles/rock.png")

func _tile_fence():
	# Phase B-2：旧版按32px坐标绘制越界（右桩/下半全被裁掉）；重排为16x16双杆双桩
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood = Color(0.60, 0.45, 0.29, 1.0)      # 低饱和暖木色
	var wood_hi = Color(0.72, 0.57, 0.38, 1.0)
	var wood_dark = Color(0.41, 0.30, 0.19, 1.0)
	# 双横杆（贯穿整格，上缘高光下缘压暗出厚度）
	for x in range(TILE_SIZE):
		img.set_pixel(x, 5, wood_hi)
		img.set_pixel(x, 6, wood)
		img.set_pixel(x, 7, wood_dark)
		img.set_pixel(x, 10, wood_hi)
		img.set_pixel(x, 11, wood)
		img.set_pixel(x, 12, wood_dark)
	# 竖桩两根（左2-3，右12-13），方头带顶帽，入土端收深
	for px in [2, 12]:
		for y in range(3, 15):
			img.set_pixel(px, y, wood)
			img.set_pixel(px + 1, y, wood_dark)
		img.set_pixel(px, 3, wood_hi)
		img.set_pixel(px + 1, 3, wood_hi)
		img.set_pixel(px, 14, wood_dark)
		img.set_pixel(px + 1, 14, wood_dark)
	img.save_png("res://sprites/tiles/fence.png")

func _tile_farmland():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# 星露谷式农田：疏松棕土+规整垄沟+整齐幼苗行
	var soil = Color(0.48, 0.34, 0.20, 1.0)
	var soil_dark = Color(0.36, 0.25, 0.14, 1.0)
	var soil_light = Color(0.58, 0.42, 0.26, 1.0)
	var sprout = Color(0.32, 0.62, 0.22, 1.0)
	var sprout_hi = Color(0.45, 0.75, 0.30, 1.0)
	# 垄沟（4像素一垄，明暗交替出立体感）
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var row = y % 8
			if row < 2:
				img.set_pixel(x, y, soil_dark)
			elif row < 4:
				img.set_pixel(x, y, soil)
			elif row < 6:
				img.set_pixel(x, y, soil_light)
			else:
				img.set_pixel(x, y, soil)
	# 土壤颗粒噪点
	for i in range(10):
		var nx = _rng.randi_range(0, TILE_SIZE - 1)
		var ny = _rng.randi_range(0, TILE_SIZE - 1)
		var c = img.get_pixel(nx, ny)
		img.set_pixel(nx, ny, Color(c.r * 0.9, c.g * 0.9, c.b * 0.9, 1))
	# 整齐幼苗行（每垄正中两株对叶）
	for ry in [3, 11, 19, 27]:
		for sx in range(5, TILE_SIZE - 3, 9):
			img.set_pixel(sx, ry, sprout)
			img.set_pixel(sx + 1, ry, sprout_hi)
			img.set_pixel(sx, ry - 1, sprout_hi)
			img.set_pixel(sx + 1, ry - 1, sprout)
	img.save_png("res://sprites/tiles/farmland.png")

func _tile_bridge():
	# Phase B-2：旧版按32px绘制（x=8..24）右半越界；重排为16x16竖向木桥面+双栏杆
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var plank = Color(0.63, 0.47, 0.30, 1.0)
	var plank_hi = Color(0.74, 0.59, 0.39, 1.0)
	var plank_dark = Color(0.46, 0.34, 0.21, 1.0)
	var rail = Color(0.40, 0.29, 0.18, 1.0)
	var rail_hi = Color(0.54, 0.40, 0.25, 1.0)
	# 桥面板 x=3..12 竖向通铺（板缝横线每4px + 板面条纹高光）
	for x in range(3, 13):
		for y in range(TILE_SIZE):
			if y % 4 == 3:
				img.set_pixel(x, y, plank_dark)      # 板缝
			elif (x + y / 4 * 2) % 4 == 1:
				img.set_pixel(x, y, plank_hi)        # 错缝板面高光
			else:
				img.set_pixel(x, y, plank)
	# 两侧栏杆（外深内亮双柱）
	for y in range(TILE_SIZE):
		img.set_pixel(1, y, rail)
		img.set_pixel(2, y, rail_hi)
		img.set_pixel(13, y, rail_hi)
		img.set_pixel(14, y, rail)
	# 栏柱柱头（上下各一处外扩1px）
	for py in [0, 7]:
		img.set_pixel(1, py, rail_hi)
		img.set_pixel(14, py, rail_hi)
		for px in range(2, 5):
			img.set_pixel(px, py, rail_hi)
		for px in range(12, 15):
			img.set_pixel(px, py, rail_hi)
	img.save_png("res://sprites/tiles/bridge.png")

# ============================================================
# 多格建筑系统（2/3/4/5格宽中式建筑，水平拼接瓦片）
# 瓦片ID映射：
#   19-20: 2格民居   21-23: 3格民居(带堂屋)
#   24-27: 4格大宅   28-32: 5格豪宅/客栈
# ============================================================

# 每种宽度建筑各部件的文件名
const BUILDING_PARTS = {
	2: ["house2_l", "house2_r"],
	3: ["house3_l", "house3_m", "house3_r"],
	4: ["house4_l", "house4_lm", "house4_rm", "house4_r"],
	5: ["house5_l", "house5_lm", "house5_m", "house5_rm", "house5_r"],
}

func generate_buildings():
	"""生成2/3/4/5格宽的多格建筑贴图（每格一张32x32 PNG，屋顶跨格连续）"""
	for w in [2, 3, 4, 5]:
		var parts: Array = BUILDING_PARTS[w]
		for i in range(parts.size()):
			_draw_building_part(w, i, "res://sprites/tiles/%s.png" % parts[i])
	print("[TextureGen] Multi-tile buildings generated")

# ============================================================
# Phase F5: 大型中式建筑（星露谷比例：人物约30px高，房屋远高于人）
# hut茅屋 54x48 / house民居 74x64 / manor大宅 100x84 / temple庙宇 122x100
# 墙脚线=图片底缘；footprint见 world_generator.BUILDING_PROPS
# ============================================================
const BIG_BUILDING_DEFS := {
	"hut":    {"size": Vector2i(54, 48),  "thatch": true,  "temple": false},
	"house":  {"size": Vector2i(74, 64),  "thatch": false, "temple": false},
	"manor":  {"size": Vector2i(100, 84), "thatch": false, "temple": false},
	"temple": {"size": Vector2i(122, 100),"thatch": false, "temple": true},
}

func generate_big_buildings():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sprites/buildings"))
	for kind in BIG_BUILDING_DEFS:
		var def: Dictionary = BIG_BUILDING_DEFS[kind]
		var sz: Vector2i = def["size"]
		var path := "res://sprites/buildings/%s.png" % kind
		if FileAccess.file_exists(path):
			continue
		var img = Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_big_building(img, sz.x, sz.y, def["thatch"], def["temple"])
		img.save_png(ProjectSettings.globalize_path(path))
		print("[TextureGen] big building: ", kind, " ", sz)

func _draw_big_building(img: Image, W: int, H: int, thatch: bool, temple: bool):
	var c_roof: Color = _ROOF_THATCH[0] if thatch else _ROOF
	var c_hi: Color = _ROOF_THATCH[1] if thatch else _ROOF_HI
	var c_dark: Color = _ROOF_THATCH[2] if thatch else _ROOF_DARK
	var c_wall: Color = Color(0.90, 0.84, 0.68) if not temple else Color(0.94, 0.88, 0.72)
	var c_wall_d: Color = _WALL_D
	# ---- 屋顶区段 ----
	var ry1 := int(H * 0.40)			# 主檐口线
	var ry0 := 2
	if temple:
		_draw_roof_band(img, int(W*0.20), 1, int(W*0.80), int(H*0.16), c_roof, c_hi, c_dark)
		ry0 = int(H * 0.18)
		# 宝顶
		for dx in range(-2, 3):
			for dy in range(0, 3):
				img.set_pixel(int(W/2)+dx, dy, _GOLD)
	_draw_roof_band(img, int(W*0.04), ry0, W-1-int(W*0.04), ry1, c_roof, c_hi, c_dark)
	# ---- 墙体 ----
	var wx0 := int(W * 0.10)
	var wx1 := W - 1 - int(W * 0.10)
	var wy1 := H - 1
	for x in range(wx0, wx1 + 1):
		for y in range(ry1, wy1 + 1):
			var c = c_wall
			if (x - wx0) % 6 == 0:
				c = c_wall_d
			if y == wy1 or x == wx0 or x == wx1:
				c = c_wall_d
			img.set_pixel(x, y, c)
	# 檐下木梁
	for x in range(wx0, wx1 + 1):
		img.set_pixel(x, ry1, _BEAM)
		img.set_pixel(x, ry1 + 1, _BEAM if temple else c_wall)
	# 立柱（庙宇朱红柱 / 民居木柱）
	var pillar_c: Color = _PILLAR if temple else _BEAM
	var pw := 3 if W >= 74 else 2
	for k in range(pw):
		for y in range(ry1 + 1, wy1 + 1):
			img.set_pixel(wx0 + 1 + k, y, pillar_c)
			img.set_pixel(wx1 - 1 - k, y, pillar_c)
	# ---- 门 ----
	var dw: int = clampi(int(W / 6.0), 8, 16)
	var dh: int = clampi(wy1 - ry1 - 8, 14, 26)
	var dx0 := int((W - dw) / 2)
	var dy0 := wy1 - dh
	for x in range(dx0, dx0 + dw):
		for y in range(dy0, wy1 + 1):
			var edge = (x == dx0 or x == dx0+dw-1 or y == dy0)
			img.set_pixel(x, y, _DOOR_FRAME if edge else _DOOR)
	# 门钉/门环
	img.set_pixel(dx0+2, dy0+int(dh*0.4), _GOLD)
	img.set_pixel(dx0+dw-3, dy0+int(dh*0.4), _GOLD)
	# 匾额（庙宇金框）
	if W >= 74:
		for x in range(dx0-1, dx0+dw+1):
			img.set_pixel(x, dy0-5, _BEAM)
			img.set_pixel(x, dy0-1, _BEAM)
		for y in range(dy0-5, dy0):
			img.set_pixel(dx0-1, y, _BEAM)
			img.set_pixel(dx0+dw, y, _BEAM)
		if temple:
			for x in range(dx0, dx0+dw):
				img.set_pixel(x, dy0-3, _GOLD)
	# ---- 窗 ----
	var win_w := 9
	var win_h := 7
	var win_y := ry1 + 5
	var slots := [int(W*0.24), int(W*0.66)] if W >= 74 else [int(W*0.30)]
	for sx in slots:
		if abs(sx + win_w/2 - W/2) < dw/2 + win_w:
			continue	# 与门重叠跳过
		for x in range(sx, sx + win_w):
			for y in range(win_y, win_y + win_h):
				var edge = (x == sx or x == sx+win_w-1 or y == win_y or y == win_y+win_h-1)
				img.set_pixel(x, y, _WIN_FRAME if edge else _WIN)
			img.set_pixel(x, win_y + int(win_h/2), _WIN_FRAME)	# 棂条
		for y in range(win_y, win_y + win_h):
			img.set_pixel(sx + int(win_w/2), y, _WIN_FRAME)

func _draw_roof_band(img: Image, x0: int, y0: int, x1: int, y1: int, c_main: Color, c_hi: Color, c_dark: Color):
	"""黛青瓦顶带：脊线暗、瓦沟每3行、受光斜面、檐口双行阴影、翘边"""
	if y1 <= y0:
		return
	var wspan = x1 - x0 + 1
	for x in range(x0, x1 + 1):
		var t = float(x - x0) / maxf(1.0, float(wspan - 1))	# 0左1右
		for y in range(y0, y1 + 1):
			var v = float(y - y0) / maxf(1.0, float(y1 - y0))
			var c = c_main
			if y == y0:
				c = c_dark					# 正脊
			elif (y - y0) % 3 == 2:
				c = c_dark					# 瓦沟
			elif (t < 0.18 and v > 0.25) or (t > 0.82 and v > 0.25):
				c = c_hi					# 两端受光（翘檐感）
			if y >= y1 - 1:
				c = c_dark					# 檐口阴影
			img.set_pixel(x, y, c)

func _draw_building_part(total: int, index: int, path: String):
	"""绘制多格建筑的一个部件。total=建筑总格数，index=当前部件序号(0=最左)
	16x16 绿顶房（匹配参考图）：正脊跨格连续、绿顶+米墙、中心格放门、其余格放窗"""
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var is_left = index == 0
	var is_right = index == total - 1
	var door_idx = int((total - 1) / 2)  # 门所在格（居中）

	# 人字坡绿顶 y=0..6（每格独立但正脊跨格连续）
	for x in range(TILE_SIZE):
		for y in range(7):
			var peak = abs(x - 7.5)
			var top_y = int(peak * 0.95)
			if y >= top_y:
				var c = _ROOF
				if x % 3 == 1:
					c = _ROOF_HI
				if y == 6:
					c = _ROOF_DARK
				img.set_pixel(x, y, c)
	# 正脊高光
	for x in range(6, 10):
		img.set_pixel(x, 0, _ROOF_HI)
	# 边缘格山墙垂脊收边
	if is_left:
		for y in range(1, 7):
			img.set_pixel(0, y, _ROOF_DARK)
			img.set_pixel(1, y, _ROOF_HI if y % 2 == 0 else _ROOF_DARK)
		img.set_pixel(0, 0, _ROOF_HI)
	if is_right:
		for y in range(1, 7):
			img.set_pixel(TILE_SIZE - 1, y, _ROOF_DARK)
			img.set_pixel(TILE_SIZE - 2, y, _ROOF_HI if y % 2 == 0 else _ROOF_DARK)
		img.set_pixel(TILE_SIZE - 1, 0, _ROOF_HI)
	# 檐下木梁
	for x in range(TILE_SIZE):
		img.set_pixel(x, 7, _BEAM)
	# 墙体 y=8..14
	for x in range(TILE_SIZE):
		for y in range(8, 15):
			img.set_pixel(x, y, _WALL)
	# 砖纹
	for x in range(TILE_SIZE):
		for y in range(9, 15):
			if (x + y) % 5 == 0:
				img.set_pixel(x, y, _BRICK)
	# 墙基
	for x in range(TILE_SIZE):
		img.set_pixel(x, 14, _WALL_D)
	# 边缘立柱（建筑两端收口）
	if is_left:
		for y in range(7, 15):
			img.set_pixel(0, y, _PILLAR)
	if is_right:
		for y in range(7, 15):
			img.set_pixel(TILE_SIZE - 1, y, _PILLAR)
	# 门窗：中心格放门，其它格放窗
	if index == door_idx:
		_img_house_door(img, 5, 10, 6, 5)
	else:
		_img_house_window(img, 3, 10)
		_img_house_window(img, 9, 10)

	img.save_png(path)

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
	# 侠客：束发朱红发带 + 交领月白长袍 + 黛青腰带玉佩 + 背负长剑
	var robe = Color(0.90, 0.88, 0.82)
	var robe_d = Color(0.68, 0.70, 0.70)
	var b = bob

	var leg_sway = 0
	if action == "walk":
		leg_sway = [-1, 1, 2, 1, -1, -2][frame] if frame < 6 else 0

	# ---------- 裤腿与靴（先画，下摆会盖住上部） ----------
	if dir == 0 or dir == 3:
		_rect(img, 12 + leg_sway, 38 + b, 14 + leg_sway, 43 + b, C_PANTS)
		_rect(img, 17 - leg_sway, 38 + b, 19 - leg_sway, 43 + b, C_PANTS)
		# 靴
		_rect(img, 11 + leg_sway, 44 + b, 14 + leg_sway, 46 + b, C_BOOT)
		_rect(img, 17 - leg_sway, 44 + b, 20 - leg_sway, 46 + b, C_BOOT)
		# 靴口镶边
		_rect(img, 11 + leg_sway, 44 + b, 14 + leg_sway, 44 + b, C_TRIM)
		_rect(img, 17 - leg_sway, 44 + b, 20 - leg_sway, 44 + b, C_TRIM)
	else:
		_rect(img, 13, 38 + b, 18, 43 + b, C_PANTS)
		_rect(img, 12 + leg_sway, 44 + b, 19 + leg_sway, 46 + b, C_BOOT)
		_rect(img, 12 + leg_sway, 44 + b, 19 + leg_sway, 44 + b, C_TRIM)

	# ---------- 长袍主体 ----------
	_rect(img, 11, 21 + b, 20, 31 + b, robe)
	# 右侧面阴影（左光源）
	_rect(img, 19, 24 + b, 20, 31 + b, robe_d)
	# 下摆（微喇，两侧描边）
	_rect(img, 10, 32 + b, 21, 40 + b, robe)
	_rect(img, 20, 32 + b, 21, 40 + b, robe_d)
	_rect(img, 10, 32 + b, 10, 40 + b, C_OUTLINE)
	_rect(img, 21, 32 + b, 21, 40 + b, C_OUTLINE)
	_rect(img, 10, 40 + b, 21, 40 + b, robe_d)
	# 下摆开衩（露出裤腿）
	if dir == 0:
		_rect(img, 15, 38 + b, 16, 40 + b, Color(0, 0, 0, 0))
		_px(img, 15, 38 + b, C_PANTS); _px(img, 16, 38 + b, C_PANTS)
		_px(img, 15, 39 + b, C_PANTS); _px(img, 16, 39 + b, C_PANTS)
	# 下摆褶皱
	_px(img, 13, 35 + b, robe_d); _px(img, 13, 37 + b, robe_d)
	_px(img, 17, 36 + b, robe_d); _px(img, 17, 38 + b, robe_d)

	# ---------- 腰带与玉佩 ----------
	_rect(img, 11, 30 + b, 20, 31 + b, C_TRIM)
	_rect(img, 15, 31 + b, 16, 32 + b, C_JADE)
	# 腰带垂带
	_rect(img, 18, 32 + b, 18, 36 + b, C_TRIM)

	# ---------- 交领（左襟压右襟V领） ----------
	_rect(img, 12, 21 + b, 19, 21 + b, C_TRIM)
	_px(img, 13, 22 + b, C_TRIM); _px(img, 18, 22 + b, C_TRIM)
	_px(img, 14, 23 + b, C_TRIM); _px(img, 17, 23 + b, C_TRIM)
	_px(img, 15, 24 + b, C_TRIM); _px(img, 16, 24 + b, C_TRIM)

	# ---------- 宽袖 ----------
	if action == "attack":
		# 攻击：主臂向前挥出
		if dir == 0:
			_rect(img, 20, 23 + b, 24, 25 + b, robe)
			_rect(img, 24, 24 + b, 25, 25 + b, C_SKIN)  # 持剑手
			_rect(img, 7, 24 + b, 10, 27 + b, robe)   # 左臂后摆
			_rect(img, 7, 26 + b, 8, 27 + b, C_SKIN)
		elif dir == 1:
			_rect(img, 7, 23 + b, 12, 25 + b, robe)
			_rect(img, 6, 24 + b, 7, 25 + b, C_SKIN)
		elif dir == 2:
			_rect(img, 19, 23 + b, 24, 25 + b, robe)
			_rect(img, 24, 24 + b, 25, 25 + b, C_SKIN)
		else:
			_rect(img, 20, 20 + b, 24, 22 + b, robe)
			_rect(img, 24, 21 + b, 25, 22 + b, C_SKIN)
	else:
		# 常态：宽袖垂于体侧，袖口黛青镶边
		_rect(img, 9, 22 + b, 10, 28 + b, robe)
		_rect(img, 21, 22 + b, 22, 28 + b, robe)
		_rect(img, 9, 27 + b, 10, 28 + b, C_TRIM)
		_rect(img, 21, 27 + b, 22, 28 + b, C_TRIM)
		# 手部
		_px(img, 9, 29 + b, C_SKIN); _px(img, 22, 29 + b, C_SKIN)

	# ---------- 颈 ----------
	_rect(img, 15, 19 + b, 16, 20 + b, C_SKIN_D)

	# ---------- 头部 ----------
	if dir == 3:
		# 背面：满头乌发
		_rect(img, 13, 10 + b, 18, 19 + b, C_HAIR)
		_rect(img, 12, 12 + b, 12, 17 + b, C_HAIR)
		_rect(img, 19, 12 + b, 19, 17 + b, C_HAIR)
		# 后脑发分界
		_px(img, 15, 12 + b, C_OUTLINE); _px(img, 16, 12 + b, C_OUTLINE)
		_rect(img, 13, 19 + b, 18, 19 + b, C_SKIN_D)  # 后颈发际
	else:
		# 面部
		_rect(img, 13, 12 + b, 18, 18 + b, C_SKIN)
		# 下颌阴影
		_rect(img, 14, 18 + b, 17, 18 + b, C_SKIN_D)
		# 眉眼
		if dir == 0:
			_px(img, 14, 15 + b, C_HAIR); _px(img, 17, 15 + b, C_HAIR)
			_px(img, 14, 16 + b, C_OUTLINE); _px(img, 17, 16 + b, C_OUTLINE)
		elif dir == 1:
			_px(img, 13, 15 + b, C_HAIR)
			_px(img, 13, 16 + b, C_OUTLINE)
			_px(img, 12, 16 + b, C_SKIN)  # 鼻梁
		elif dir == 2:
			_px(img, 18, 15 + b, C_HAIR)
			_px(img, 18, 16 + b, C_OUTLINE)
			_px(img, 19, 16 + b, C_SKIN)
		# 头顶发
		_rect(img, 13, 10 + b, 18, 12 + b, C_HAIR)
		# 鬓发
		_rect(img, 12, 11 + b, 12, 15 + b, C_HAIR)
		_rect(img, 19, 11 + b, 19, 15 + b, C_HAIR)

	# ---------- 发髻与朱红发带 ----------
	_rect(img, 14, 7 + b, 17, 9 + b, C_HAIR)
	_px(img, 15, 6 + b, C_HAIR); _px(img, 16, 6 + b, C_HAIR)
	_rect(img, 13, 9 + b, 18, 10 + b, C_RIBBON)
	# 发带飘带
	_px(img, 12, 10 + b, C_RIBBON); _px(img, 12, 11 + b, C_RIBBON)
	_px(img, 19, 10 + b, C_RIBBON); _px(img, 19, 11 + b, C_RIBBON)

	# ---------- 背负长剑 ----------
	if dir == 3:
		# 背面：剑鞘斜背全貌
		_rect(img, 19, 16 + b, 20, 33 + b, C_SCABBARD)
		_rect(img, 19, 14 + b, 22, 15 + b, C_HILT)
		_px(img, 22, 16 + b, C_RIBBON); _px(img, 23, 17 + b, C_RIBBON)  # 剑穗
		_px(img, 19, 33 + b, C_TRIM)  # 鞘尾
	elif dir == 1:
		_rect(img, 21, 16 + b, 22, 32 + b, C_SCABBARD)
		_rect(img, 20, 14 + b, 23, 15 + b, C_HILT)
		_px(img, 23, 16 + b, C_RIBBON)
	elif dir == 2:
		_rect(img, 9, 16 + b, 10, 32 + b, C_SCABBARD)
		_rect(img, 8, 14 + b, 11, 15 + b, C_HILT)
		_px(img, 8, 16 + b, C_RIBBON)
	else:
		# 正面：剑柄自右肩后探出
		_rect(img, 19, 7 + b, 21, 9 + b, C_HILT)
		_px(img, 22, 8 + b, C_RIBBON); _px(img, 22, 9 + b, C_RIBBON)

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
	_draw_player_body(img, dir, frame, 0, "attack")
	# 挥剑轨迹：蓄力→挥出→剑光巅峰→消散
	var swing = [0.0, 0.4, 1.0, 0.5][frame]  # 挥剑进度
	var alpha = [0.0, 0.5, 0.9, 0.35][frame] # 剑光强度
	var blade = Color(0.75, 0.88, 1.0)
	var blade_edge = Color(0.95, 0.99, 1.0)
	var glow = Color(0.5, 0.75, 1.0, alpha * 0.4)
	var dir_name = ["down", "left", "right", "up"][dir]

	if frame == 0:
		# 蓄力：剑举于身后上方
		_draw_blade(img, Vector2(24, 24), Vector2(30, 12), blade)
	elif frame >= 1:
		# 弧形剑光（沿攻击方向的扇形扫掠）
		var cx = 16.0
		var cy = 26.0
		var radius = 14.0 + swing * 3.0
		var arc_range = 70.0 + swing * 40.0
		var base_angle: float
		match dir:
			0: base_angle = 90.0   # 下
			1: base_angle = 180.0  # 左
			2: base_angle = 0.0    # 右
			3: base_angle = 270.0  # 上
		# 扫掠角随帧推进
		var sweep = base_angle - arc_range / 2 + swing * arc_range
		var a0 = sweep - arc_range / 2
		var a1 = sweep + arc_range / 2
		for ad in range(int(a0), int(a1) + 1, 3):
			var ar = deg_to_rad(ad)
			for r in range(int(radius) - 4, int(radius) + 1):
				var px_x = int(round(cx + cos(ar) * r))
				var px_y = int(round(cy + sin(ar) * r))
				var c = blade_edge if r > radius - 2 else blade
				c.a = alpha
				_px(img, px_x, px_y, c)
		# 外围光晕
		for ad in range(int(a0), int(a1) + 1, 5):
			var ar2 = deg_to_rad(ad)
			var gx = int(round(cx + cos(ar2) * (radius + 2)))
			var gy = int(round(cy + sin(ar2) * (radius + 2)))
			_px(img, gx, gy, glow)
		# 手中剑身
		var hand = Vector2(24, 24)
		var tip_r = radius + 2
		var tip = Vector2(cx + cos(deg_to_rad(sweep)) * tip_r, cy + sin(deg_to_rad(sweep)) * tip_r)
		if dir == 1: hand = Vector2(7, 24)
		elif dir == 2: hand = Vector2(24, 24)
		elif dir == 3: hand = Vector2(24, 21)
		_draw_blade(img, hand, tip, blade)
	img.save_png("res://sprites/player/attack_%s_%d.png" % [dir_name, frame])

# 画剑身直线（带刃口高光）
func _draw_blade(img: Image, from: Vector2, to: Vector2, c: Color):
	var steps = int(max(abs(to.x - from.x), abs(to.y - from.y))) + 1
	for i in range(steps + 1):
		var t = float(i) / steps
		var x = int(round(lerp(from.x, to.x, t)))
		var y = int(round(lerp(from.y, to.y, t)))
		_px(img, x, y, c)
		# 刃口亮线偏移一格
		var edge = Color(min(c.r + 0.2, 1.0), min(c.g + 0.15, 1.0), c.b, c.a)
		_px(img, x + 1, y, edge)

func _save_player_block_frame(dir: int, frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_player_body(img, dir, frame, 0, "block")
	# 内力气盾：圆形气劲护罩（玉色，带呼吸脉动）
	var pulse = 0.45 + frame * 0.2
	var shield = Color(0.45, 0.85, 0.75, pulse)
	var shield_edge = Color(0.75, 0.98, 0.92, pulse + 0.25)
	var cx = 16.0
	var cy = 26.0
	var radius = 15.0 + frame * 1.0
	for ad in range(0, 360, 4):
		var ar = deg_to_rad(ad)
		var x = int(round(cx + cos(ar) * radius))
		var y = int(round(cy + sin(ar) * radius))
		_px(img, x, y, shield_edge)
		var xi = int(round(cx + cos(ar) * (radius - 1)))
		var yi = int(round(cy + sin(ar) * (radius - 1)))
		_px(img, xi, yi, shield)
	var dir_name = ["down", "left", "right", "up"][dir]
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
	# 精致武侠风NPC：统一身体模板，按类型差异化配色/头饰/手持物
	var b = bob
	var robe: Color
	var robe_d: Color
	var belt: Color

	match npc_type:
		"warrior":    # 武士：玄红劲装
			robe = Color(0.36, 0.17, 0.13); robe_d = Color(0.26, 0.12, 0.09); belt = Color(0.72, 0.30, 0.16)
		"scholar":    # 书生：青衫
			robe = Color(0.70, 0.78, 0.80); robe_d = Color(0.52, 0.60, 0.63); belt = Color(0.30, 0.38, 0.42)
		"merchant":   # 商人：锦袍金棕
			robe = Color(0.64, 0.49, 0.25); robe_d = Color(0.48, 0.36, 0.18); belt = Color(0.78, 0.62, 0.28)
		"elder":      # 长者：灰白道袍
			robe = Color(0.58, 0.59, 0.63); robe_d = Color(0.42, 0.43, 0.47); belt = Color(0.32, 0.30, 0.34)
		"mysterious": # 神秘人：夜行衣
			robe = Color(0.17, 0.15, 0.24); robe_d = Color(0.11, 0.10, 0.17); belt = Color(0.38, 0.22, 0.50)

	var leg_sway = 0
	if action == "walk":
		leg_sway = [-1, 1, 2, 1, -1, -2][frame] if frame < 6 else 0

	# ---------- 裤腿与靴 ----------
	if dir == 0 or dir == 3:
		_rect(img, 12 + leg_sway, 38 + b, 14 + leg_sway, 43 + b, C_PANTS)
		_rect(img, 17 - leg_sway, 38 + b, 19 - leg_sway, 43 + b, C_PANTS)
		_rect(img, 11 + leg_sway, 44 + b, 14 + leg_sway, 46 + b, C_BOOT)
		_rect(img, 17 - leg_sway, 44 + b, 20 - leg_sway, 46 + b, C_BOOT)
	else:
		_rect(img, 13, 38 + b, 18, 43 + b, C_PANTS)
		_rect(img, 12 + leg_sway, 44 + b, 19 + leg_sway, 46 + b, C_BOOT)

	# ---------- 长袍主体 ----------
	_rect(img, 11, 21 + b, 20, 31 + b, robe)
	_rect(img, 19, 24 + b, 20, 31 + b, robe_d)
	_rect(img, 10, 32 + b, 21, 40 + b, robe)
	_rect(img, 20, 32 + b, 21, 40 + b, robe_d)
	_rect(img, 10, 32 + b, 10, 40 + b, C_OUTLINE)
	_rect(img, 21, 32 + b, 21, 40 + b, C_OUTLINE)
	_rect(img, 10, 40 + b, 21, 40 + b, robe_d)

	# ---------- 腰带 ----------
	_rect(img, 11, 30 + b, 20, 31 + b, belt)

	# ---------- 交领 ----------
	_rect(img, 12, 21 + b, 19, 21 + b, robe_d)
	_px(img, 13, 22 + b, robe_d); _px(img, 18, 22 + b, robe_d)
	_px(img, 14, 23 + b, robe_d); _px(img, 17, 23 + b, robe_d)

	# ---------- 袖 ----------
	if npc_type == "warrior":
		# 武士收口袖+护腕
		_rect(img, 9, 22 + b, 10, 27 + b, robe)
		_rect(img, 21, 22 + b, 22, 27 + b, robe)
		_rect(img, 9, 26 + b, 10, 27 + b, C_HILT)
		_rect(img, 21, 26 + b, 22, 27 + b, C_HILT)
	else:
		_rect(img, 9, 22 + b, 10, 28 + b, robe)
		_rect(img, 21, 22 + b, 22, 28 + b, robe)
		_rect(img, 9, 27 + b, 10, 28 + b, robe_d)
		_rect(img, 21, 27 + b, 22, 28 + b, robe_d)
	_px(img, 9, 29 + b, C_SKIN); _px(img, 22, 29 + b, C_SKIN)

	# ---------- 颈 ----------
	_rect(img, 15, 19 + b, 16, 20 + b, C_SKIN_D)

	# ---------- 头部与头饰 ----------
	var hair_c = C_HAIR if npc_type != "elder" else Color(0.75, 0.75, 0.78)
	if npc_type == "mysterious":
		# 斗笠+面纱：看不清面容
		_rect(img, 13, 12 + b, 18, 18 + b, C_SKIN_D)
		# 斗笠
		_rect(img, 10, 10 + b, 21, 12 + b, Color(0.30, 0.25, 0.17))
		_rect(img, 12, 8 + b, 19, 9 + b, Color(0.35, 0.29, 0.20))
		_px(img, 15, 7 + b, Color(0.35, 0.29, 0.20)); _px(img, 16, 7 + b, Color(0.35, 0.29, 0.20))
		# 斗笠檐描边
		_rect(img, 10, 12 + b, 21, 12 + b, C_OUTLINE)
		# 面纱
		_rect(img, 12, 13 + b, 19, 19 + b, Color(0.13, 0.11, 0.20, 0.75))
	else:
		# 面部
		_rect(img, 13, 12 + b, 18, 18 + b, C_SKIN)
		_rect(img, 14, 18 + b, 17, 18 + b, C_SKIN_D)
		if dir == 0:
			_px(img, 14, 15 + b, C_HAIR); _px(img, 17, 15 + b, C_HAIR)
			_px(img, 14, 16 + b, C_OUTLINE); _px(img, 17, 16 + b, C_OUTLINE)
		elif dir == 1:
			_px(img, 13, 15 + b, C_HAIR); _px(img, 13, 16 + b, C_OUTLINE)
		elif dir == 2:
			_px(img, 18, 15 + b, C_HAIR); _px(img, 18, 16 + b, C_OUTLINE)
		# 头饰按类型
		match npc_type:
			"warrior":
				# 束发+红头巾
				_rect(img, 13, 10 + b, 18, 12 + b, hair_c)
				_rect(img, 13, 11 + b, 18, 11 + b, C_RIBBON)
				_rect(img, 14, 7 + b, 17, 9 + b, hair_c)
				_px(img, 12, 12 + b, C_RIBBON)
			"scholar":
				# 儒巾（方帽带翅）
				_rect(img, 13, 9 + b, 18, 12 + b, Color(0.20, 0.19, 0.18))
				_px(img, 11, 10 + b, Color(0.20, 0.19, 0.18)); _px(img, 20, 10 + b, Color(0.20, 0.19, 0.18))
				_rect(img, 13, 12 + b, 18, 12 + b, hair_c)
			"merchant":
				# 圆顶瓜皮帽
				_rect(img, 13, 9 + b, 18, 12 + b, Color(0.36, 0.24, 0.14))
				_px(img, 15, 8 + b, Color(0.55, 0.38, 0.20)); _px(img, 16, 8 + b, Color(0.55, 0.38, 0.20))
			"elder":
				# 白发髻+木簪
				_rect(img, 13, 10 + b, 18, 12 + b, hair_c)
				_rect(img, 14, 8 + b, 17, 9 + b, hair_c)
				_rect(img, 15, 7 + b, 18, 7 + b, C_HILT)
				# 长眉
				if dir == 0:
					_px(img, 13, 15 + b, hair_c); _px(img, 18, 15 + b, hair_c)

	# ---------- 手持物/配件 ----------
	match npc_type:
		"warrior":
			# 背负大刀
			if dir == 3 or dir == 1:
				_rect(img, 20, 15 + b, 21, 32 + b, C_SCABBARD)
				_rect(img, 19, 13 + b, 22, 14 + b, C_HILT)
			elif dir == 2:
				_rect(img, 10, 15 + b, 11, 32 + b, C_SCABBARD)
				_rect(img, 9, 13 + b, 12, 14 + b, C_HILT)
		"scholar":
			# 手持书卷
			if dir == 0:
				_rect(img, 20, 26 + b, 23, 29 + b, Color(0.85, 0.80, 0.62))
				_rect(img, 20, 26 + b, 23, 26 + b, Color(0.60, 0.50, 0.32))
		"merchant":
			# 金算盘
			if dir == 0:
				_rect(img, 20, 27 + b, 24, 30 + b, Color(0.80, 0.66, 0.26))
				_px(img, 21, 28 + b, C_OUTLINE); _px(img, 23, 29 + b, C_OUTLINE)
		"elder":
			# 拐杖
			var cx2 = 8 if dir == 1 else 23
			_rect(img, cx2, 24 + b, cx2, 45 + b, C_HILT)
			_px(img, cx2 - 1, 24 + b, C_HILT); _px(img, cx2 + 1, 24 + b, C_HILT)
		"mysterious":
			# 腰间暗器囊
			_rect(img, 19, 30 + b, 20, 32 + b, Color(0.40, 0.24, 0.55))

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
