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
	var floors := _pack_image("Environment/Tilesets/Floors_Tiles.png")
	var water_sheet := _pack_image("Environment/Tilesets/Water_tiles.png")
	var wall_sheet := _pack_image("Environment/Tilesets/Wall_Tiles.png")
	var veg := _pack_image("Environment/Props/Static/Vegetation.png")
	var rocks := _pack_image("Environment/Props/Static/Rocks.png")
	var bprops := _pack_image("Environment/Structures/Buildings/Props.png")
	# ---- 地表（素材包原版裁切，色调与demo三图一致）----
	_save_tile(_crop_tile(floors, 2, 10), "grass")
	_save_tile(_crop_tile(floors, 1, 11), "grass_dark")
	_save_tile(_crop_tile(floors, 6, 10), "path")
	_save_tile(_crop_tile(water_sheet, 6, 7), "water")
	_save_tile(_crop_tile(floors, 6, 23), "sand")
	_save_tile(_whiten_img(_crop_tile(floors, 2, 24), 1.0), "snow")
	_save_tile(_snow_farmland_img(), "snow_farmland")   # 41 雪覆农田（群系调色板）
	_save_tile(_snow_path_img(), "snow_path")           # 42 雪径（群系调色板）
	_save_tile(_crop_tile(floors, 17, 1), "stone")
	# ---- 悬崖岩壁（demo2/3 深色崖壁）----
	_save_tile(_crop_tile(wall_sheet, 8, 2), "mountain")
	_save_tile(_snow_capped_cliff(wall_sheet, floors), "mountain_snow")
	# ---- 农田（泥土压暗+垄沟）----
	_save_tile(_furrow(_darken_img(_crop_tile(floors, 6, 10), 0.62)), "farmland")
	_save_tile(_furrow(_darken_img(_crop_tile(floors, 6, 10), 0.45)), "farmland_wet")
	# ---- 植被/岩石装饰 ----
	_save_tile(_crop_tile(veg, 12, 10), "flower")
	_save_tile(_crop_tile(veg, 6, 23), "daisy")
	_save_tile(_crop_tile(veg, 7, 21), "mushroom")
	_save_tile(_crop_tile(rocks, 8, 2), "rock")
	_save_tile(_crop_tile(bprops, 1, 9), "fence")
	# ---- 建筑瓦片 ----
	_save_tile(_crop_tile(wall_sheet, 1, 21), "house_cave")
	_save_tile(_pack_bridge(wall_sheet), "bridge")
	_save_tile(_mini_house(wall_sheet, bprops, "town"), "house_town")
	_save_tile(_mini_house(wall_sheet, bprops, "cottage"), "house_cottage")
	_save_tile(_mini_house(wall_sheet, bprops, "temple"), "house_temple")
	# ---- 青石城：城墙砖（程序化，素材包无城墙）----
	_save_tile(_city_wall_tile(), "city_wall")
	print("[TextureGen] Tiles generated (Pixel Crawler pack crops)")

# 城墙砖瓦片：青灰砖+错缝砖线+顶部压光，四面围墙用（tile id 40）
func _city_wall_tile() -> Image:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# 2026-08-31：大城砖重砌——8px高砖行×2、错缝、细灰缝（旧4px小碎砖视觉似石子）
	var base := Color(0.46, 0.46, 0.47)   # 青砖
	var mortar := Color(0.30, 0.30, 0.31)
	var hi := Color(0.56, 0.56, 0.57)
	var lo := Color(0.37, 0.37, 0.38)
	img.fill(base)
	for y in range(TILE_SIZE):
		var yy := y % 8
		var off := ((y / 8) % 2) * 4   # 行间错缝半砖
		for x in range(TILE_SIZE):
			if yy == 7:
				img.set_pixel(x, y, mortar)               # 横灰缝
			elif (x + off) % 8 == 7:
				img.set_pixel(x, y, mortar)               # 竖灰缝
			elif yy == 0:
				img.set_pixel(x, y, hi)                   # 砖顶棱受光
			elif yy == 6:
				img.set_pixel(x, y, lo)                   # 砖底压暗
	return img

# ============ 青石城市集道具（程序化） ============
# 市摊：20x24，木柱+条纹布棚+摊台
func _market_stall(awning: Color) -> Image:
	var img := Image.create(20, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.48, 0.33, 0.19)
	var wood_d := Color(0.36, 0.24, 0.13)
	var stripe := Color(0.92, 0.90, 0.84)
	# 摊台
	for x in range(2, 18):
		for y in range(15, 19):
			img.set_pixel(x, y, wood if y < 17 else wood_d)
	# 柱
	for y in range(4, 22):
		img.set_pixel(2, y, wood_d)
		img.set_pixel(17, y, wood_d)
	# 布棚（条纹）
	for x in range(0, 20):
		for y in range(0, 6):
			var c := awning if (x / 3) % 2 == 0 else stripe
			img.set_pixel(x, y, c)
		img.set_pixel(x, 6, wood_d)   # 檐口
	# 棚下货物点缀
	for x in range(4, 8):
		img.set_pixel(x, 14, Color(0.85, 0.55, 0.30))
	for x in range(11, 15):
		img.set_pixel(x, 14, Color(0.55, 0.75, 0.45))
	return img

# 水井：18x22，石圈+木架小顶
func _city_well() -> Image:
	var img := Image.create(18, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stone := Color(0.46, 0.45, 0.44)
	var stone_d := Color(0.32, 0.31, 0.31)
	var wood := Color(0.48, 0.33, 0.19)
	var roof := Color(0.52, 0.28, 0.20)
	# 木架
	for y in range(2, 14):
		img.set_pixel(3, y, wood)
		img.set_pixel(14, y, wood)
	for x in range(2, 16):
		img.set_pixel(x, 1, roof)
		img.set_pixel(x, 2, roof.darkened(0.2))
	# 石圈
	for x in range(2, 16):
		for y in range(14, 20):
			var c := stone if y < 18 else stone_d
			img.set_pixel(x, y, c)
	for x in range(4, 14):
		for y in range(15, 17):
			img.set_pixel(x, y, Color(0.12, 0.15, 0.18))   # 井口深色
	img.set_pixel(8, 8, Color(0.30, 0.22, 0.14))
	img.set_pixel(9, 9, Color(0.30, 0.22, 0.14))           # 吊绳
	img.set_pixel(7, 11, Color(0.42, 0.30, 0.18))
	img.set_pixel(8, 11, Color(0.42, 0.30, 0.18))          # 木桶
	return img

# ============================================================
# 素材包裁切基础设施（Pixel Crawler / anokolisa 16x16）
# 管线权属变更：terrain 五件套与全部瓦片改由本生成器从素材包直接裁切，
# 与 tools/import_pack_assets.py 同源；程序化绘制瓦片全部移除
# ============================================================
const PACK_DIR := "res://downloaded_assets/Pixel Crawler - Free Pack"
static var _pack_cache := {}

static func _pack_image(rel: String) -> Image:
	if _pack_cache.has(rel):
		return _pack_cache[rel]
	var abs_path := ProjectSettings.globalize_path(PACK_DIR + "/" + rel)
	if not FileAccess.file_exists(abs_path):
		push_warning("[TextureGen] 素材包文件缺失: " + rel)
		_pack_cache[rel] = null
		return null
	var img := Image.load_from_file(abs_path)
	_pack_cache[rel] = img
	return img

static func _crop_tile(img: Image, tx: int, ty: int, ts: int = 16) -> Image:
	var out := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	if img != null:
		out.blit_rect(img, Rect2i(tx * ts, ty * ts, ts, ts), Vector2i.ZERO)
	return out

static func _darken_img(src: Image, factor: float) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c := src.get_pixel(x, y)
			out.set_pixel(x, y, Color(c.r * factor, c.g * factor, c.b * factor, c.a))
	return out

# 雪地提纯：去米黄底色，向demo3的净白雪靠拢
static func _whiten_img(src: Image, strength: float) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c := src.get_pixel(x, y)
			var lum := c.r * 0.3 + c.g * 0.6 + c.b * 0.1
			var w := lum * 0.65 + 0.35
			out.set_pixel(x, y, Color(
				lerpf(c.r, w, strength),
				lerpf(c.g, w, strength),
				lerpf(c.b, minf(w * 1.04, 1.0), strength), c.a))
	return out

func _save_tile(img: Image, tile_name: String):
	img.save_png("res://sprites/tiles/" + tile_name + ".png")

func _tile_grass():
	_save_tile(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 2, 10), "grass")

func _tile_grass_dark():
	_save_tile(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 1, 11), "grass_dark")

func _tile_path():
	_save_tile(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 6, 10), "path")

func _tile_water():
	_save_tile(_crop_tile(_pack_image("Environment/Tilesets/Water_tiles.png"), 6, 7), "water")

# 雪线锯齿崖壁：上部积雪+下部深灰崖面（demo3 雪原悬崖）
func _snow_capped_cliff(wall_sheet: Image, floors: Image) -> Image:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var cliff := _crop_tile(wall_sheet, 8, 2)
	var snow := _whiten_img(_crop_tile(floors, 2, 24), 1.0)
	img.blit_rect(cliff, Rect2i(0, 0, 16, 16), Vector2i.ZERO)
	img.blit_rect(snow, Rect2i(0, 0, 16, 5), Vector2i.ZERO)
	for x in range(TILE_SIZE):
		var jag := 5 + (x * 7 + 3) % 3
		for y in range(5, jag + 1):
			img.set_pixel(x, y, snow.get_pixel(x, 4))
	return img

# 农田垄沟：横向两道压暗槽
func _furrow(img: Image) -> Image:
	for y in [3, 4, 11, 12]:
		for x in range(TILE_SIZE):
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * 0.78, c.g * 0.78, c.b * 0.78, 1.0))
	return img

# 木桥：棕色板墙横铺桥面+两侧深色栏杆（demo1 河畔木码头质感）
func _pack_bridge(wall_sheet: Image) -> Image:
	var img := _crop_tile(wall_sheet, 6, 2)
	var rail := Color(0.28, 0.19, 0.11)
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, rail)
		img.set_pixel(1, y, rail)
		img.set_pixel(14, y, rail)
		img.set_pixel(15, y, rail)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, rail)
	return img

func _tile_sand():
	_save_tile(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 6, 23), "sand")

func _tile_snow():
	_save_tile(_whiten_img(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 2, 24), 1.0), "snow")

# 2026-08-31 群系调色板新瓦片：雪覆农田（41）与雪径（42）
# 农田底图去饱和提亮成积雪覆田，隐约露出深色垄沟；雪径为踩实灰白雪面
func _snow_farmland_img() -> Image:
	var base := _furrow(_darken_img(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 6, 10), 0.62))
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var c := base.get_pixel(x, y)
			var lum: float = c.r * 0.3 + c.g * 0.6 + c.b * 0.1
			var w: float = minf(lum * 0.38 + 0.66, 1.0)   # 高亮低对比：雪下隐约见田
			img.set_pixel(x, y, Color(lerpf(c.r, w, 0.74), lerpf(c.g, w, 0.74), lerpf(c.b, w, 0.74), 1.0))
	return img

func _tile_snow_farmland():
	_save_tile(_snow_farmland_img(), "snow_farmland")

func _snow_path_img() -> Image:
	var base := _crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 6, 10)
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var c := base.get_pixel(x, y)
			var lum: float = c.r * 0.3 + c.g * 0.6 + c.b * 0.1
			var w: float = clampf(lum * 0.55 + 0.40, 0.0, 1.0)   # 比雪面暗一档：踩实雪径
			img.set_pixel(x, y, Color(lerpf(c.r, w, 0.85), lerpf(c.g, w, 0.85), lerpf(c.b, w, 0.85), 1.0))
	# 边缘两行轻微压暗，暗示车辙/踩踏边
	for x in range(TILE_SIZE):
		for yy in [0, 15]:
			var c2 := img.get_pixel(x, yy)
			img.set_pixel(x, yy, Color(c2.r * 0.92, c2.g * 0.92, c2.b * 0.94, 1.0))
	return img

func _tile_snow_path():
	_save_tile(_snow_path_img(), "snow_path")

func _tile_stone():
	_save_tile(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 17, 1), "stone")

func _tile_mountain():
	_save_tile(_crop_tile(_pack_image("Environment/Tilesets/Wall_Tiles.png"), 8, 2), "mountain")

func _tile_mountain_snow():
	_save_tile(_snow_capped_cliff(_pack_image("Environment/Tilesets/Wall_Tiles.png"), _pack_image("Environment/Tilesets/Floors_Tiles.png")), "mountain_snow")

# Phase G重构：松/橡/竹16px小树瓦片已废弃——野外大树由素材包大树道具
# （world_generator.TREE_SHEETS）承担，POI装饰改用花/雏菊/蘑菇/岩石瓦片

func _tile_house_town():
	_save_tile(_mini_house(_pack_image("Environment/Tilesets/Wall_Tiles.png"), _pack_image("Environment/Structures/Buildings/Props.png"), "town"), "house_town")

func _tile_house_cottage():
	_save_tile(_mini_house(_pack_image("Environment/Tilesets/Wall_Tiles.png"), _pack_image("Environment/Structures/Buildings/Props.png"), "cottage"), "house_cottage")

func _tile_house_temple():
	_save_tile(_mini_house(_pack_image("Environment/Tilesets/Wall_Tiles.png"), _pack_image("Environment/Structures/Buildings/Props.png"), "temple"), "house_temple")

func _tile_house_cave():
	_save_tile(_crop_tile(_pack_image("Environment/Tilesets/Wall_Tiles.png"), 1, 21), "house_cave")

# ============ 16x16 mini房屋（2026-08-31 中式化重制：黛瓦垄条+凹曲翘角+白墙朱柱+格扇窗）============
func _mini_house(wall_sheet: Image, bprops: Image, kind: String) -> Image:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color(0.18, 0.20, 0.24)
	var red := Color(0.60, 0.17, 0.13)        # 朱红柱
	var gold := Color(0.85, 0.70, 0.35)       # 金脊/庙宇
	var thatch_c := Color(0.55, 0.42, 0.22)   # 茅草
	var tile_c := Color(0.42, 0.47, 0.54)     # 黛瓦青灰（2026-08-31提亮，避免晨光下发黑）
	var plaster := _crop_tile(wall_sheet, 22, 12)
	var plaster_w := _whiten_img(plaster, 0.85)   # 白灰墙
	# ---- 屋顶色与瓦垄条纹 ----
	var roof_base := thatch_c if kind == "cottage" else tile_c
	var roof_px := func(x: int, y: int) -> Color:
		var v: float = 0.90 + 0.10 * float((x * 7 + y * 13) % 4) / 3.0
		var stripe: float = 1.0 if (x % 4) < 2 else 0.86   # 竖向瓦垄
		if kind == "cottage":
			stripe = 1.0   # 茅草无瓦垄，横向质感
			v = 0.88 + 0.12 * float((y * 5 + x * 3) % 4) / 3.0
		return Color(minf(roof_base.r * v * stripe, 1.0), minf(roof_base.g * v * stripe, 1.0), minf(roof_base.b * v * stripe, 1.0))
	# ---- 墙体 x1..14（白墙+朱红角柱+墙基）----
	for x in range(1, 15):
		for y in range(7, 16):
			img.set_pixel(x, y, plaster_w.get_pixel(2 + ((x + 5) % 12), 4 + ((y + 7) % 9)))
	for y in range(7, 16):
		img.set_pixel(1, y, red.darkened(0.15) if kind != "cottage" else Color(0.42, 0.28, 0.16))
		img.set_pixel(14, y, red if kind != "cottage" else Color(0.48, 0.33, 0.19))
	for x in range(1, 15):
		var cb := img.get_pixel(x, 14)
		img.set_pixel(x, 14, Color(cb.r * 0.8, cb.g * 0.8, cb.b * 0.8, 1.0))
		var cb2 := img.get_pixel(x, 15)
		img.set_pixel(x, 15, Color(cb2.r * 0.55, cb2.g * 0.55, cb2.b * 0.55, 1.0))
	# ---- 屋顶反曲轮廓 rows0..6（2026-08-31：pow(t,1.9)脊陡檐展，脊部起始half=2.5保证正脊有宽度）----
	for y in range(7):
		var t := float(y) / 6.0
		var half := 2.5 + 5.5 * pow(t, 1.9)   # 反曲：脊下坡陡、檐口展宽
		var x0f := 7.5 - half
		var x1f := 7.5 + half
		for x in range(maxi(0, int(x0f)), mini(16, int(x1f) + 1)):
			var c: Color = roof_px.call(x, y)
			if float(x) < x0f + 1.0 or float(x) > x1f - 1.0:
				c = edge
			img.set_pixel(x, y, c)
	# 翘角：底部两行檐端外挑1px
	for x in [0, 15]:
		for y in [5, 6]:
			img.set_pixel(x, y, roof_px.call(x, y) if y == 6 else edge)
	# ---- 正脊 rows0..1（固定宽度脊带，与屋面曲线解耦；庙宇金脊，民居黛色脊条）----
	for x in range(4, 12):
		for y in range(0, 2):
			if float(x) >= 7.5 - 3.2 and float(x) <= 7.5 + 3.2:
				if kind == "temple":
					img.set_pixel(x, y, gold if y == 0 else gold.darkened(0.25))
				elif kind == "cottage":
					img.set_pixel(x, y, Color(0.45, 0.30, 0.17) if y == 0 else Color(0.34, 0.22, 0.12))
				else:
					img.set_pixel(x, y, Color(0.22, 0.24, 0.28) if y == 0 else Color(0.16, 0.18, 0.22))
	# 脊端鸱吻：row0 两端1px金色小凸（庙宇）/深色小凸（民居）
	img.set_pixel(4, 0, gold if kind == "temple" else Color(0.16, 0.18, 0.22))
	img.set_pixel(11, 0, gold if kind == "temple" else Color(0.16, 0.18, 0.22))
	# 檐口阴影：row6描边+row7墙投影
	for x in range(TILE_SIZE):
		if img.get_pixel(x, 6).a > 0.0 and x != 0 and x != 15:
			img.set_pixel(x, 6, edge)
		var cs := img.get_pixel(x, 7)
		img.set_pixel(x, 7, Color(cs.r * 0.75, cs.g * 0.75, cs.b * 0.75, 1.0))
	# ---- 中央板门 4宽（竖板+门框，门底到墙基 y15）----
	var door_c := Color(0.30, 0.20, 0.12)
	var door_d := Color(0.22, 0.14, 0.08)
	for x in range(6, 10):
		for y in range(9, 15):
			img.set_pixel(x, y, door_d if (x % 2) == 0 else door_c)   # 竖板拼缝
	for x in range(5, 11):
		img.set_pixel(x, 8, red.darkened(0.2) if kind != "cottage" else Color(0.34, 0.22, 0.12))
	for y in range(9, 15):
		img.set_pixel(5, y, edge)
		img.set_pixel(10, y, edge)
	# 门钉（庙宇/民居金点两列）
	if kind != "cottage":
		for yy in [10, 13]:
			img.set_pixel(7, yy, gold)
			img.set_pixel(8, yy, gold.darkened(0.2))
	# ---- 双侧格扇窗 2x2（窗纸+十字棂），庙宇留白 ----
	if kind != "temple":
		for wx in [3, 11]:
			for dx in range(2):
				for dy in range(2):
					img.set_pixel(wx + dx, 10 + dy, Color(0.90, 0.86, 0.74))
			img.set_pixel(wx, 10, Color(0.42, 0.28, 0.16))   # 棂线
			img.set_pixel(wx + 1, 11, Color(0.42, 0.28, 0.16))
			for i in range(-1, 3):
				img.set_pixel(wx + i, 9, edge)
				img.set_pixel(wx + i, 12, edge)
			img.set_pixel(wx - 1, 10, edge)
			img.set_pixel(wx - 1, 11, edge)
			img.set_pixel(wx + 2, 10, edge)
			img.set_pixel(wx + 2, 11, edge)
	return img

func _tile_flower():
	_save_tile(_crop_tile(_pack_image("Environment/Props/Static/Vegetation.png"), 12, 10), "flower")

func _tile_daisy():
	_save_tile(_crop_tile(_pack_image("Environment/Props/Static/Vegetation.png"), 6, 23), "daisy")

func _tile_mushroom():
	_save_tile(_crop_tile(_pack_image("Environment/Props/Static/Vegetation.png"), 7, 21), "mushroom")

func _tile_rock():
	_save_tile(_crop_tile(_pack_image("Environment/Props/Static/Rocks.png"), 8, 2), "rock")

func _tile_fence():
	_save_tile(_crop_tile(_pack_image("Environment/Structures/Buildings/Props.png"), 1, 9), "fence")

func _tile_farmland():
	_save_tile(_furrow(_darken_img(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 6, 10), 0.62)), "farmland")

func _tile_farmland_wet():
	_save_tile(_furrow(_darken_img(_crop_tile(_pack_image("Environment/Tilesets/Floors_Tiles.png"), 6, 10), 0.45)), "farmland_wet")

func _tile_bridge():
	_save_tile(_pack_bridge(_pack_image("Environment/Tilesets/Wall_Tiles.png")), "bridge")

# ============================================================
# Phase G重构: 大型建筑全部改用素材包部件拼装
# （绿瓦顶=Roofs平瓦 / 灰泥墙+顶梁=Walls(21,12) / 原木=Walls(2,2) / 木门+蓝窗=Props）
# hut茅屋 54x48 / house民居 74x64 / manor大宅 100x84 / temple庙宇 122x100
# 墙脚线=图片底缘；footprint见 world_generator.BUILDING_PROPS
# ============================================================
const BIG_BUILDING_DEFS := {
	"hut":    {"size": Vector2i(54, 48),  "thatch": true,  "temple": false},
	"house":  {"size": Vector2i(74, 64),  "thatch": false, "temple": false},
	"manor":  {"size": Vector2i(100, 84), "thatch": false, "temple": false},
	"temple": {"size": Vector2i(122, 100),"thatch": false, "temple": true},
	"castle": {"size": Vector2i(176, 128),"thatch": false, "temple": false},
	# ---- 青石城功能建筑（accent=幌子/镶边主题色，结构复用大建筑拼装）----
	"yamen":      {"size": Vector2i(126, 96), "thatch": false, "temple": true,  "accent": Color(0.62, 0.16, 0.13)},  # 府衙：朱红
	"tavern":     {"size": Vector2i(104, 84), "thatch": false, "temple": false, "accent": Color(0.16, 0.42, 0.30)},  # 酒楼：酒绿
	"apothecary": {"size": Vector2i(84, 70),  "thatch": false, "temple": false, "accent": Color(0.20, 0.45, 0.48)},  # 药坊：药青
	"shop_a":     {"size": Vector2i(64, 54),  "thatch": false, "temple": false, "accent": Color(0.45, 0.30, 0.16)},  # 铁匠铺：铁木棕
	"shop_b":     {"size": Vector2i(64, 54),  "thatch": false, "temple": false, "accent": Color(0.36, 0.26, 0.48)},  # 布庄：紫
}

func generate_big_buildings():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sprites/buildings"))
	for kind in BIG_BUILDING_DEFS:
		var def: Dictionary = BIG_BUILDING_DEFS[kind]
		var sz: Vector2i = def["size"]
		var path := "res://sprites/buildings/%s.png" % kind
		if FileAccess.file_exists(path):
			continue
		var img: Image
		if kind == "castle":
			img = _compose_castle(sz.x, sz.y)
		else:
			img = _compose_big_building(sz.x, sz.y, def["thatch"], def["temple"], def.get("accent", Color(0, 0, 0, 0)))
		img.save_png(ProjectSettings.globalize_path(path))
		print("[TextureGen] big building: ", kind, " ", sz)

# 城市小道具：市摊×2配色 + 水井（缺失才生成）
func generate_city_props():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sprites/buildings"))
	var outs := {
		"stall_red": _market_stall(Color(0.72, 0.22, 0.18)),
		"stall_teal": _market_stall(Color(0.18, 0.48, 0.45)),
		"well": _city_well(),
	}
	for pname in outs:
		var path := "res://sprites/buildings/%s.png" % pname
		if not FileAccess.file_exists(path):
			outs[pname].save_png(ProjectSettings.globalize_path(path))
			print("[TextureGen] city prop: ", pname)

# 原木条填充（横梁/角柱/脊梁共用；logw=横原木墙瓦片）
static func _fill_logs(img: Image, x0: int, x1: int, y0: int, h: int, logw: Image, seed_off: int = 0):
	for x in range(x0, x1 + 1):
		for y in range(y0, mini(y0 + h, img.get_height())):
			img.set_pixel(x, y, logw.get_pixel((x + seed_off) % 16, (y + 3) % 16))

# ============ 大建筑中式化重制（2026-08-31） ============
# 凹曲屋面+飞檐翘角（幂曲线轮廓）+ 竖向瓦垄 + 檐口瓦当 + 正脊鸱吻
# + 白灰墙 + 朱红/主题色梁柱角柱 + 檐下斗拱带 + 格扇窗 + 门钉板门 + 匾额 + 石台基台阶
# accent非透明时：梁柱/门框染主题色 + 右檐挂幌子（招牌），区分府衙/酒楼/药坊等功能建筑
# 茅屋(thatch)保持草顶质朴风：无瓦当/斗拱/匾额/门钉，木色柱
func _compose_big_building(W: int, H: int, thatch: bool, temple: bool, accent: Color = Color(0, 0, 0, 0)) -> Image:
	var use_accent := accent.a > 0.0
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color(0.16, 0.18, 0.22)
	var red := Color(0.60, 0.17, 0.13)         # 朱红
	var gold := Color(0.85, 0.70, 0.35)        # 金（庙脊/门钉/匾字）
	var beam_c := accent if use_accent else red
	var col_d := beam_c.darkened(0.3)
	var roof_base := Color(0.55, 0.42, 0.22) if thatch else (Color(0.36, 0.44, 0.40) if temple else Color(0.43, 0.48, 0.55))
	var roof_edge := Color(0.30, 0.22, 0.10) if thatch else edge
	var paper := Color(0.90, 0.86, 0.74)       # 窗纸
	var lattice := Color(0.42, 0.28, 0.16)     # 窗棂木色
	var stone := Color(0.52, 0.50, 0.47)
	var wall_c := Color(0.90, 0.87, 0.80)      # 白灰墙

	var cxm := (W - 1) * 0.5
	var ridge_y := 2
	var eave_row := int(H * 0.42)              # 2026-08-31：屋顶压扁（0.46→0.42），墙身比例加大去"帽感"
	var ridge_half := maxf(4.0, W * 0.16)      # 正脊加宽：反曲屋面脊部应有足够宽度，不再是尖顶
	var eave_half := W * 0.5
	var over := 6 if W >= 74 else 5            # 出檐（墙比屋顶每侧窄的像素）
	var wx0 := over
	var wx1 := W - 1 - over
	var wall_top := eave_row + 2               # 檐口阴影1行 + 斗拱2行之下起算（斗拱叠画在墙上部）
	var wall_bot := H - 4                      # 底部3行留给台基

	# ---- 墙体：白灰墙（2026-08-31：哈希点噪替换线性取模噪——旧(x*7+y*13)%4产生斜向条纹，视觉似碎石席纹）----
	for x in range(wx0, wx1 + 1):
		for y in range(wall_top, wall_bot + 1):
			var h := float(((x * 73856093) ^ (y * 19349663)) % 997) / 997.0   # 异或混合点噪（线性取模会产生斜条纹）
			var grad := 1.0 - 0.05 * float(y - wall_top) / maxf(1.0, float(wall_bot - wall_top))   # 上亮下沉微渐变
			var f := (0.965 + 0.05 * h) * grad
			img.set_pixel(x, y, Color(minf(wall_c.r * f, 1.0), minf(wall_c.g * f, 1.0), minf(wall_c.b * f, 1.0)))
	# 檐枋（墙上部横梁3行，主题色/朱红）
	for y in range(wall_top, wall_top + 3):
		for x in range(wx0, wx1 + 1):
			img.set_pixel(x, y, beam_c if y < wall_top + 2 else col_d)
	# 檐下斗拱带（茅屋跳过）：交错小拱块
	if not thatch:
		var by := wall_top + 3
		var x := wx0 + 1
		while x <= wx1 - 2:
			for bx in range(x, mini(x + 2, wx1)):
				for yy in range(by, by + 2):
					img.set_pixel(bx, yy, beam_c.darkened(0.35))
			for yy in range(by, by + 2):
				img.set_pixel(mini(x + 2, wx1), yy, col_d)
			x += 4
	# 角柱（3px，朱红/主题色）+ 大开间中柱
	var col_w := 3
	for y in range(wall_top, wall_bot + 1):
		for k in range(col_w):
			img.set_pixel(wx0 + k, y, beam_c if k < col_w - 1 else col_d)
			img.set_pixel(wx1 - k, y, beam_c if k < col_w - 1 else col_d)
	if W >= 80:
		for mx in [int(W * 0.33), int(W * 0.67)]:
			for y in range(wall_top + 3, wall_bot + 1):
				img.set_pixel(mx, y, beam_c)
				img.set_pixel(mx + 1, y, col_d)
	# ---- 台基（底部3行石作+中央台阶）----
	for x in range(wx0, wx1 + 1):
		for y in range(H - 3, H):
			var sc := stone
			if y == H - 3:
				sc = Color(0.62, 0.60, 0.57)   # 台基压顶石
			elif y == H - 1:
				sc = Color(0.40, 0.38, 0.36)
			img.set_pixel(x, y, sc)
	var st_w := 8
	var st_x0 := int(cxm) - st_w / 2
	for x in range(st_x0, st_x0 + st_w):
		for y in range(H - 3, H):
			img.set_pixel(x, y, Color(0.68, 0.66, 0.62) if y < H - 1 else Color(0.56, 0.54, 0.52))
		img.set_pixel(x, H - 3, Color(0.74, 0.72, 0.68))
	for xx in [st_x0 - 1, st_x0 + st_w]:
		if xx >= wx0 and xx <= wx1:
			for y in range(H - 3, H):
				img.set_pixel(xx, y, Color(0.34, 0.32, 0.30))

	# ---- 屋顶：反曲屋面（2026-08-31：pow(t,2.1)脊陡檐展，替换旧1-pow(1-t,1.8)的穹顶轮廓）+ 竖向瓦垄 ----
	for y in range(ridge_y, eave_row + 1):
		var t := float(y - ridge_y) / maxf(1.0, float(eave_row - ridge_y))
		var half := ridge_half + (eave_half - ridge_half) * pow(t, 2.1)
		var x0f := cxm - half
		var x1f := cxm + half
		for x in range(maxi(0, int(ceil(x0f))), mini(W - 1, int(x1f)) + 1):
			var hh := float(((x * 73856093) ^ (y * 19349663)) % 997) / 997.0   # 异或混合点噪
			var vv := 0.95 + 0.07 * hh
			var stripe := 1.0 if thatch or (x % 4) < 2 else 0.87
			if thatch:
				vv = 0.88 + 0.14 * hh
			var c := Color(minf(roof_base.r * vv * stripe, 1.0), minf(roof_base.g * vv * stripe, 1.0), minf(roof_base.b * vv * stripe, 1.0))
			if float(x) < x0f + 1.5 or float(x) > x1f - 1.5:
				c = roof_edge
			img.set_pixel(x, y, c)
	# 瓦当：檐口一行每4px一枚浅色圆钉（茅屋省略）
	if not thatch:
		var dot := Color(minf(roof_base.r * 1.45, 1.0), minf(roof_base.g * 1.45, 1.0), minf(roof_base.b * 1.45, 1.0))
		var x0e := int(cxm - eave_half) + 1
		var x1e := int(cxm + eave_half) - 1
		var dx2 := x0e
		while dx2 <= x1e:
			img.set_pixel(dx2, eave_row, dot)
			dx2 += 4
	# 飞檐翘角：两端外侧4列向上挑起
	for k in range(4):
		var lift := 4 - k
		var xa := k
		var xb := W - 1 - k
		for y2 in range(maxi(ridge_y, eave_row - lift + 1), eave_row + 1):
			var vv2 := 0.92 + 0.08 * float((xa * 7 + y2 * 13) % 4) / 3.0
			var c2 := Color(minf(roof_base.r * vv2, 1.0), minf(roof_base.g * vv2, 1.0), minf(roof_base.b * vv2, 1.0))
			img.set_pixel(xa, y2, c2)
			img.set_pixel(xb, y2, c2)
		# 翘角上缘描边
		img.set_pixel(xa, maxi(ridge_y, eave_row - lift + 1), roof_edge)
		img.set_pixel(xb, maxi(ridge_y, eave_row - lift + 1), roof_edge)
	# 檐口投影（檐下一行墙面压暗）
	for x in range(wx0, wx1 + 1):
		var cs := img.get_pixel(x, eave_row + 1)
		img.set_pixel(x, eave_row + 1, Color(cs.r * 0.72, cs.g * 0.72, cs.b * 0.72, 1.0))
	# ---- 正脊 + 鸱吻 ----
	var ridge_c := Color(0.20, 0.22, 0.26)
	if temple:
		ridge_c = gold
	elif thatch:
		ridge_c = Color(0.42, 0.28, 0.14)
	var r_half := int(ridge_half) + 1
	for x in range(maxi(0, int(cxm) - r_half), mini(W - 1, int(cxm) + r_half) + 1):
		img.set_pixel(x, 0, ridge_c.lightened(0.12))
		img.set_pixel(x, 1, ridge_c)
	var cw_x0 := clampi(int(cxm) - r_half - 1, 0, W - 1)
	var cw_x1 := clampi(int(cxm) + r_half + 1, 0, W - 1)
	for y2 in range(0, 3):
		img.set_pixel(cw_x0, y2, ridge_c if y2 > 0 else ridge_c.lightened(0.2))
		img.set_pixel(cw_x1, y2, ridge_c if y2 > 0 else ridge_c.lightened(0.2))

	# ---- 中央板门（竖板拼缝+门钉+石门槛）----
	var dw := 14 if W >= 74 else 12
	var dh := clampi(wall_bot - (wall_top + 9), 12, 26)
	var dx0 := int(cxm) - int(dw / 2.0)
	var door_top := wall_bot - dh
	var door_c := Color(0.30, 0.20, 0.12)
	var door_d := Color(0.22, 0.14, 0.08)
	for x in range(dx0, dx0 + dw):
		for y in range(door_top, wall_bot + 1):
			img.set_pixel(x, y, door_d if (x % 2) == 0 else door_c)
	for y in range(door_top + 2, wall_bot - 1, 4):      # 门钉两列
		img.set_pixel(dx0 + int(dw * 0.3), y, gold)
		img.set_pixel(dx0 + int(dw * 0.7), y, gold.darkened(0.2))
	for xx in [dx0 - 1, dx0 + dw]:                      # 门框
		if xx >= wx0 and xx <= wx1:
			for y in range(door_top - 1, wall_bot + 1):
				img.set_pixel(xx, y, beam_c)
	for x in range(dx0, dx0 + dw):                      # 石门槛
		img.set_pixel(x, wall_bot, Color(0.44, 0.42, 0.40))

	# ---- 匾额（茅屋无）：门上方深底金边+金字块 ----
	if not thatch:
		var bw := dw + 4
		var bh := 6
		var bx := int(cxm) - int(bw / 2.0)
		var by := door_top - 8
		for x in range(maxi(wx0, bx), mini(wx1 + 1, bx + bw)):
			for y in range(maxi(wall_top, by), mini(wall_bot, by + bh)):
				var border := x == bx or x == bx + bw - 1 or y == by or y == by + bh - 1
				img.set_pixel(x, y, gold.darkened(0.15) if border else Color(0.10, 0.09, 0.14))
		# 金字块（3块示意题字）
		var n_blob := 3 if bw >= 18 else 2
		for i in range(n_blob):
			var blx := bx + int(bw * (0.5 + (i - (n_blob - 1) * 0.5) * 0.28)) - 1
			for gx in range(3):
				for gy in range(4):
					if (gx == 1 and gy == 1) or (gx == 1 and gy == 2):
						continue   # 字口留白
					img.set_pixel(blx + gx, by + 2 + gy, gold)

	# ---- 格扇窗（茅屋无）：木框+窗纸+棂格 ----
	if not thatch:
		var ww := 10
		var wh := 8
		var wyy := wall_top + int((wall_bot - wall_top) * 0.45)
		var slots: Array = []
		if W >= 100:
			slots = [int(W * 0.16), int(W * 0.74)]
		elif W >= 74:
			slots = [int(W * 0.14), int(W * 0.76)]
		else:
			slots = [int(W * 0.10)]
		for sx in slots:
			if sx < wx0 + col_w + 3 or sx + ww > wx1 - col_w - 2:
				continue
			# 外框1px + 木边框
			for i in range(-1, ww + 1):
				img.set_pixel(sx + i, wyy - 1, edge)
				img.set_pixel(sx + i, wyy + wh, edge)
			for y3 in range(-1, wh + 1):
				img.set_pixel(sx - 1, wyy + y3, edge)
				img.set_pixel(sx + ww, wyy + y3, edge)
			for x in range(ww):
				for y in range(wh):
					var inner := x == 0 or y == 0 or x == ww - 1 or y == wh - 1
					img.set_pixel(sx + x, wyy + y, beam_c.darkened(0.15) if inner else paper)
			# 棂格：竖3横3
			for x in range(3, ww - 1, 3):
				for y in range(1, wh - 1):
					img.set_pixel(sx + x, wyy + y, lattice)
			for y in range(3, wh - 1, 3):
				for x in range(1, ww - 1):
					img.set_pixel(sx + x, wyy + y, lattice)
			# 窗台
			for x in range(ww):
				img.set_pixel(sx + x, wyy + wh + 1, beam_c)

	# ---- 幌子（招牌）：右檐下挂竖幅，accent亮底+米白滚边+挂杆 ----
	if use_accent:
		var bfx := wx1 - 9
		var bfy := eave_row + 1
		var bfw := 10
		var bfh := clampi(int((H - eave_row) * 0.42), 14, 28)
		var fill := accent.lightened(0.18)
		for y2 in range(bfy - 4, bfy):                          # 挂杆
			if bfx + 1 < W:
				img.set_pixel(bfx + 1, y2, Color(0.24, 0.16, 0.10))
		for y2 in range(bfy, mini(H - 4, bfy + bfh)):
			for x2 in range(bfx, mini(W - 1, bfx + bfw)):
				var c := fill if x2 > bfx and x2 < bfx + bfw - 1 else Color(0.95, 0.90, 0.75)
				img.set_pixel(x2, y2, c)
	return img

# ============ 旧版大建筑拼装（demo1西式风，已被中式化重制取代，保留作回退参考） ============
func _compose_big_building_legacy(W: int, H: int, thatch: bool, temple: bool, accent: Color = Color(0, 0, 0, 0)) -> Image:
	var use_accent := accent.a > 0.0
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var roofs := _pack_image("Environment/Structures/Buildings/Roofs.png")
	var walls_sheet := _pack_image("Environment/Structures/Buildings/Walls.png")
	var bprops := _pack_image("Environment/Structures/Buildings/Props.png")
	var shingle := _crop_tile(roofs, 2, 12) if thatch else _crop_tile(roofs, 11, 12)
	var plaster := _crop_tile(walls_sheet, 22, 12)
	var logw := _crop_tile(walls_sheet, 2, 2)
	var door_t := _crop_tile(bprops, 6, 2)
	var door_b := _crop_tile(bprops, 6, 3)
	var win := _crop_tile(bprops, 7, 4)
	var edge := Color(0.24, 0.16, 0.10)
	var gold := Color(0.85, 0.70, 0.35)

	var roof_h := int(H * 0.44)                  # 坡顶高度（demo1约占整屋44%）
	var over := 6 if W >= 74 else 5              # 出檐（屋顶比墙每侧宽的像素）
	var wx0 := over
	var wx1 := W - 1 - over
	var wy0 := roof_h - 3                        # 墙顶藏进檐下
	var apex := (W - 1) * 0.5
	# 主题色梁柱：accent存在时以accent木纹替换原木梁（府衙朱红/酒楼酒绿…）
	var beam_img := logw
	if use_accent:
		beam_img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for yy in range(16):
			for xx in range(16):
				var f := 0.82 + 0.18 * float((xx * 7 + yy * 3) % 4) / 3.0
				beam_img.set_pixel(xx, yy, Color(accent.r * f, accent.g * f, accent.b * f))

	# ---- 墙体：灰泥+木架（角柱/檐下横梁/中腰横梁/墙基）----
	for x in range(wx0, wx1 + 1):
		for y in range(wy0, H):
			img.set_pixel(x, y, plaster.get_pixel(2 + ((x - wx0 + 5) % 12), 4 + ((y - wy0 + 7) % 9)))
	_fill_logs(img, wx0, wx1, wy0, 3, beam_img, 3)             # 檐下横梁
	var mid_y := wy0 + int((H - wy0) * 0.55)
	_fill_logs(img, wx0, wx1, mid_y, 2, beam_img, 8)           # 中腰横梁
	for y in range(H - 3, H):                                  # 墙基压暗
		for x in range(wx0, wx1 + 1):
			var f := 0.55 if y >= H - 2 else 0.8
			var cb := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(cb.r * f, cb.g * f, cb.b * f, 1.0))
	var pw := 3                                                # 两侧角柱（圆木）
	for y in range(wy0, H):
		for k in range(pw):
			img.set_pixel(wx0 + k, y, beam_img.get_pixel((k * 5 + 2) % 16, (y + 5) % 16))
			img.set_pixel(wx1 - k, y, beam_img.get_pixel((k * 5 + 6) % 16, (y + 5) % 16))

	# ---- 屋顶：正面三角坡（檐口到达全宽=出檐效果）----
	for y in range(roof_h):
		var t := float(y) / maxf(1.0, float(roof_h - 1))
		var half := t * (W * 0.5)
		var x0f := apex - half
		var x1f := apex + half
		for x in range(maxi(0, int(ceil(x0f))), mini(W - 1, int(x1f)) + 1):
			var c := shingle.get_pixel(x % 16, (y + 2) % 16)
			if float(x) < x0f + 2.0 or float(x) > x1f - 2.0:
				c = edge                                       # 坡边描边
			img.set_pixel(x, y, c)
	# 脊梁圆木（顶部4行；茅屋用深棕杆与坡顶衔接、庙宇换金脊）
	for y in range(4):
		var rhalf := float(y) / maxf(1.0, float(roof_h - 1)) * (W * 0.5)
		for x in range(maxi(0, int(ceil(apex - rhalf)) + 1), mini(W - 1, int(apex + rhalf) - 1) + 1):
			if temple and not use_accent:
				img.set_pixel(x, y, gold)
			elif thatch:
				img.set_pixel(x, y, edge if y >= 2 else Color(0.45, 0.30, 0.17))
			else:
				img.set_pixel(x, y, beam_img.get_pixel((x + 1) % 16, 2))
	# 檐口描边行 + 墙面投影2行
	for x in range(W):
		if img.get_pixel(x, roof_h - 1).a > 0.0:
			img.set_pixel(x, roof_h - 1, edge)
		for s in range(1, 3):
			var sy := roof_h - 1 + s
			if sy < H:
				var cs := img.get_pixel(x, sy)
				img.set_pixel(x, sy, Color(cs.r * 0.75, cs.g * 0.75, cs.b * 0.75, 1.0))

	# ---- 中央木门（含楣梁+门框，门底接墙基）----
	var dw := 14 if W >= 74 else 12
	var dh := clampi(H - wy0 - 6, 14, 28)
	var dx0 := int((W - dw) / 2)
	var dy0 := H - dh
	for x in range(dw):
		for y in range(dh):
			var src := door_t if y < 16 else door_b
			img.set_pixel(dx0 + x, dy0 + y, src.get_pixel(x % 16, y % 16))
	for x in range(dx0 - 2, dx0 + dw + 2):                     # 楣梁
		for y in range(dy0 - 3, dy0):
			img.set_pixel(x, y, beam_img.get_pixel((x + 5) % 16, 2))
	for y in range(dy0 - 1, H):
		if dx0 - 2 >= 0:
			img.set_pixel(dx0 - 2, y, edge)
		if dx0 + dw + 1 < W:
			img.set_pixel(dx0 + dw + 1, y, edge)

	# ---- 蓝窗（带框+窗台，门两侧对称）----
	if not thatch:
		var ww := 10
		var wh := 8
		var wyy := mid_y + 5
		var slots: Array = []
		if W >= 100:
			slots = [int(W * 0.16), int(W * 0.74)]
		elif W >= 74:
			slots = [int(W * 0.14), int(W * 0.76)]
		else:
			slots = [int(W * 0.10)]
		for sx in slots:
			if sx < wx0 + pw + 3 or sx + ww > wx1 - pw - 2:
				continue
			for x in range(ww):
				for y in range(wh):
					img.set_pixel(sx + x, wyy + y, win.get_pixel(3 + x, 4 + y))
			for i in range(-1, ww + 1):                         # 框
				img.set_pixel(sx + i, wyy - 1, edge)
				img.set_pixel(sx + i, wyy + wh, edge)
			for y2 in range(-1, wh + 1):
				img.set_pixel(sx - 1, wyy + y2, edge)
				img.set_pixel(sx + ww, wyy + y2, edge)
			for x in range(ww):                                 # 窗台
				img.set_pixel(sx + x, wyy + wh + 1, beam_img.get_pixel((sx + x) % 16, 2))

	# ---- 幌子（招牌）：右檐下挂竖幅，accent亮底+米白滚边+挂杆，功能建筑辨识 ----
	if use_accent:
		var bfx := wx1 - 9
		var bfy := roof_h + 1
		var bfw := 10
		var bfh := clampi(int((H - roof_h) * 0.42), 14, 28)
		var fill := accent.lightened(0.18)
		for y2 in range(bfy - 4, bfy):                          # 挂杆
			if bfx + 1 < W:
				img.set_pixel(bfx + 1, y2, Color(0.24, 0.16, 0.10))
		for y2 in range(bfy, mini(H - 4, bfy + bfh)):
			for x2 in range(bfx, mini(W - 1, bfx + bfw)):
				var c := fill if x2 > bfx and x2 < bfx + bfw - 1 else Color(0.95, 0.90, 0.75)
				img.set_pixel(x2, y2, c)
	return img

# ============ 古堡（demo风扩大建筑：双石塔+城垛+旗帜 + 中央绿瓦主楼）============
# 结构：左右石砖高塔（窄蓝窗+城垛+红旗）夹中央主楼（三角绿瓦坡顶+木架灰泥墙+拱形木门）
static func _compose_castle(W: int, H: int) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var floors := _pack_image("Environment/Tilesets/Floors_Tiles.png")
	var roofs := _pack_image("Environment/Structures/Buildings/Roofs.png")
	var walls_sheet := _pack_image("Environment/Structures/Buildings/Walls.png")
	var bprops := _pack_image("Environment/Structures/Buildings/Props.png")
	var brick := _crop_tile(floors, 17, 1)          # 灰石砖（塔墙，干净砖纹）
	var shingle := _crop_tile(roofs, 11, 12)        # 绿瓦（主楼顶）
	var plaster := _crop_tile(walls_sheet, 22, 12)  # 灰泥墙（主楼）
	var logw := _crop_tile(walls_sheet, 2, 2)
	var door_t := _crop_tile(bprops, 6, 2)
	var door_b := _crop_tile(bprops, 6, 3)
	var win := _crop_tile(bprops, 7, 4)
	var edge := Color(0.22, 0.15, 0.10)
	var dark_edge := Color(0.14, 0.15, 0.17)
	var flag_red := Color(0.72, 0.22, 0.18)

	var tower_w := 44
	var keep_x0 := tower_w + 4
	var keep_x1 := W - 1 - tower_w - 4
	var tower_top := int(H * 0.16)                  # 塔顶城垛线
	var keep_roof_h := int(H * 0.26)                # 主楼坡顶高
	var keep_wy0 := tower_top + keep_roof_h - 3     # 主楼墙顶（藏檐下）

	# ---- 左右石塔 ----
	for side in [[0, tower_w - 1], [W - tower_w, W - 1]]:
		var tx0: int = side[0]
		var tx1: int = side[1]
		# 塔身石砖
		for x in range(tx0, tx1 + 1):
			for y in range(tower_top, H):
				img.set_pixel(x, y, brick.get_pixel(x % 16, y % 16))
		# 塔身左右棱描边+受光
		for y in range(tower_top, H):
			img.set_pixel(tx0, y, dark_edge)
			img.set_pixel(tx1, y, dark_edge)
			img.set_pixel(tx0 + 1, y, brick.get_pixel((tx0 + 1) % 16, y % 16).lightened(0.12))
		# 横向砖缝（每8行压暗）
		for y in range(tower_top + 7, H, 8):
			for x in range(tx0 + 1, tx1):
				var cb := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(cb.r * 0.8, cb.g * 0.8, cb.b * 0.8, 1.0))
		# 箭窗（每塔2扇竖窗：深色窗洞+木棂条，2026-08-31中式化）
		for wx in [tx0 + 9, tx1 - 13]:
			for x in range(wx, wx + 5):
				for y in range(tower_top + 16, tower_top + 30):
					var cwl := Color(0.42, 0.28, 0.16) if (x - wx) % 2 == 1 else Color(0.16, 0.13, 0.11)
					img.set_pixel(x, y, cwl)
			for i in range(-1, 6):
				img.set_pixel(wx + i, tower_top + 15, dark_edge)
				img.set_pixel(wx + i, tower_top + 30, dark_edge)
			for y2 in range(tower_top + 15, tower_top + 31):
				img.set_pixel(wx - 1, y2, dark_edge)
				img.set_pixel(wx + 5, y2, dark_edge)
		# 城垛（齿状：凸4凹3）
		var mx := tx0
		while mx <= tx1:
			for x in range(mx, mini(mx + 3, tx1 + 1)):
				for y in range(tower_top - 5, tower_top):
					img.set_pixel(x, y, brick.get_pixel(x % 16, y % 16))
				for xx in [mx, mini(mx + 3, tx1)]:
					if xx == mx or xx == mini(mx + 3, tx1):
						img.set_pixel(xx, tower_top - 5, dark_edge)
			mx += 7
		for x in range(tx0, tx1 + 1):                # 垛下檐线
			img.set_pixel(x, tower_top, dark_edge)
		# 旗杆+三角旗（塔中线，旗面加大到11px高）
		var fcx := int((tx0 + tx1) / 2.0)
		for y in range(1, tower_top - 4):
			img.set_pixel(fcx, y, Color(0.35, 0.24, 0.14))
			img.set_pixel(fcx + 1, y, Color(0.25, 0.17, 0.10))
		for y in range(1, 13):                       # 直角三角旗（顶尖朝右下收）
			var fy := y
			var span := 10 - int((y - 1) * 8.0 / 11.0)
			for x in range(fcx + 2, mini(fcx + 2 + span, fcx + 13)):
				img.set_pixel(x, fy, flag_red)
		for x in range(fcx + 2, fcx + 12):           # 旗底描边
			img.set_pixel(x, 12, Color(0.45, 0.13, 0.10))
	# ---- 中央主楼：凹曲黛瓦坡顶（2026-08-31中式化，檐口铺到两塔之间全宽）----
	var apex := (W - 1) * 0.5
	var cn_roof := Color(0.34, 0.38, 0.44)
	var cn_edge := Color(0.16, 0.18, 0.22)
	var roof_span := float(keep_x1 - keep_x0 + 4) * 0.5
	for y in range(keep_roof_h):
		var t := float(y) / maxf(1.0, float(keep_roof_h - 1))
		var half := roof_span * (1.0 - pow(1.0 - t, 1.8))
		var x0f := apex - half
		var x1f := apex + half
		for x in range(maxi(keep_x0 - 4, int(ceil(x0f))), mini(keep_x1 + 4, int(x1f)) + 1):
			var vv := 0.90 + 0.10 * float((x * 7 + y * 13) % 4) / 3.0
			var stripe := 1.0 if (x % 4) < 2 else 0.87
			var c := Color(minf(cn_roof.r * vv * stripe, 1.0), minf(cn_roof.g * vv * stripe, 1.0), minf(cn_roof.b * vv * stripe, 1.0))
			if float(x) < x0f + 2.0 or float(x) > x1f - 2.0:
				c = cn_edge
			img.set_pixel(x, y + tower_top, c)
	# 瓦当（檐口每4px浅色圆钉）
	for x in range(int(apex - roof_span) + 1, int(apex + roof_span), 4):
		if x >= keep_x0 - 3 and x <= keep_x1 + 3:
			img.set_pixel(x, tower_top + keep_roof_h - 1, Color(0.49, 0.55, 0.64))
	# 飞檐翘角（两端外挑）
	for k in range(4):
		var lift := 3 - k
		var xa := int(apex - roof_span) + k
		var xb := int(apex + roof_span) - k
		for y2 in range(maxi(0, keep_roof_h - lift), keep_roof_h):
			img.set_pixel(xa, y2 + tower_top, cn_roof)
			img.set_pixel(xb, y2 + tower_top, cn_roof)
	# 主楼正脊+鸱吻（金吻）
	var ridge_half := int(roof_span * 0.22)
	for x in range(int(apex) - ridge_half, int(apex) + ridge_half + 1):
		img.set_pixel(x, tower_top, Color(0.20, 0.22, 0.26).lightened(0.12))
		img.set_pixel(x, tower_top + 1, Color(0.20, 0.22, 0.26))
	for xx in [int(apex) - ridge_half - 1, int(apex) + ridge_half + 1]:
		for y2 in range(tower_top, mini(tower_top + 3, tower_top + keep_roof_h)):
			img.set_pixel(xx, y2, Color(0.85, 0.70, 0.35))
	# 主楼檐口描边+墙面投影
	for x in range(keep_x0 - 2, keep_x1 + 3):
		if img.get_pixel(x, tower_top + keep_roof_h - 1).a > 0.0:
			img.set_pixel(x, tower_top + keep_roof_h - 1, edge)
	# ---- 主楼墙：白灰墙+朱红角柱（2026-08-31中式化）----
	var cn_plaster := _whiten_img(plaster, 0.85)
	var cn_red := Color(0.60, 0.17, 0.13)
	for x in range(keep_x0, keep_x1 + 1):
		for y in range(keep_wy0, H):
			img.set_pixel(x, y, cn_plaster.get_pixel(2 + ((x - keep_x0 + 5) % 12), 4 + ((y - keep_wy0 + 7) % 9)))
	for y in range(H - 3, H):
		for x in range(keep_x0, keep_x1 + 1):
			var f := 0.55 if y >= H - 2 else 0.8
			var cb := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(cb.r * f, cb.g * f, cb.b * f, 1.0))
	for y in range(keep_wy0, H):
		for k in range(3):
			var cc := cn_red if k < 2 else cn_red.darkened(0.3)
			img.set_pixel(keep_x0 + k, y, cc)
			img.set_pixel(keep_x1 - k, y, cc)
	# ---- 拱形大门（石框+双开木门）----
	var dw := 18
	var dh := clampi(H - keep_wy0 - 4, 18, 34)
	var dx0 := int((W - dw) / 2)
	var dy0 := H - dh
	for x in range(dw):
		var arc := int(sqrt(maxf(0.0, 1.0 - pow((x - dw * 0.5 + 0.5) / (dw * 0.5), 2.0)) ) * 5.0)
		for y in range(dh - arc):
			var src := door_t if y < 16 else door_b
			img.set_pixel(dx0 + x, dy0 + y, src.get_pixel(x % 16, y % 16))
		# 石砌门拱
		for y in range(dh - arc - 3, dh - arc):
			img.set_pixel(dx0 + x, dy0 + y, brick.get_pixel(x % 16, (y + 2) % 16))
	# 门框描边
	for y in range(dy0 - 3, H):
		if dx0 - 1 >= 0:
			img.set_pixel(dx0 - 1, y, dark_edge)
		if dx0 + dw < W:
			img.set_pixel(dx0 + dw, y, dark_edge)
	# ---- 主楼双格扇窗（2026-08-31中式化，门两侧）----
	var ww := 10
	var wh := 8
	var wyy := keep_wy0 + 10
	for sx in [int(W * 0.34), int(W * 0.58)]:
		for x in range(ww):
			for y in range(wh):
				var inner := x == 0 or y == 0 or x == ww - 1 or y == wh - 1
				img.set_pixel(sx + x, wyy + y, cn_red.darkened(0.15) if inner else Color(0.90, 0.86, 0.74))
		for x in range(3, ww - 1, 3):
			for y in range(1, wh - 1):
				img.set_pixel(sx + x, wyy + y, Color(0.42, 0.28, 0.16))
		for y in range(3, wh - 1, 3):
			for x in range(1, ww - 1):
				img.set_pixel(sx + x, wyy + y, Color(0.42, 0.28, 0.16))
		for i in range(-1, ww + 1):
			img.set_pixel(sx + i, wyy - 1, edge)
			img.set_pixel(sx + i, wyy + wh, edge)
		for y2 in range(-1, wh + 1):
			img.set_pixel(sx - 1, wyy + y2, edge)
			img.set_pixel(sx + ww, wyy + y2, edge)
	return img

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
		_:
			# 兜底：新增npc类型（tavern_f/herbalist_f等，实际帧由python管线导出）漏配时防崩溃
			robe = Color(0.70, 0.78, 0.80); robe_d = Color(0.52, 0.60, 0.63); belt = Color(0.30, 0.38, 0.42)

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

# ============================================================
# 打坐盘坐帧（素材包无坐姿，程序化绘制）
# 画布64x64对齐Body_A约定：坐姿底缘=y48（与站姿脚线一致，offset-16直接复用）
# 侠客同款配色（月白长袍+黛青镶边+乌发发髻+朱红发带），两帧呼吸起伏
# ============================================================
const M_ROBE := Color(0.90, 0.88, 0.82)
const M_ROBE_D := Color(0.76, 0.74, 0.68)
const M_TRIM := Color(0.24, 0.34, 0.42)
const M_BELT := Color(0.30, 0.26, 0.24)
const M_HAIR := Color(0.13, 0.11, 0.10)
const M_RIBBON := Color(0.80, 0.24, 0.18)
const M_SKIN := Color(0.88, 0.71, 0.57)
const M_SKIN_D := Color(0.74, 0.57, 0.44)
const M_BOOT := Color(0.16, 0.14, 0.13)
const M_OUT := Color(0.10, 0.10, 0.13)

func generate_meditate_frames():
	DirAccess.make_dir_recursive_absolute("res://sprites/player")
	for f in range(2):
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_meditate_pose(img, f)
		img.save_png("res://sprites/player/meditate_down_%d.png" % f)
	print("[TextureGen] meditate frames generated (2)")

func _mpx(img: Image, x: int, y: int, c: Color):
	if x >= 0 and x < 64 and y >= 0 and y < 64:
		img.set_pixel(x, y, c)

func _mrect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color):
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_mpx(img, x, y, c)

func _draw_meditate_pose(img: Image, frame: int):
	var bob := 1 if frame == 1 else 0   # 呼吸：第二帧身体下沉1px
	# ---- 盘腿下摆（贴地加宽，盘坐轮廓）----
	_mrect(img, 22, 44, 42, 47, M_ROBE_D)          # 下摆贴地
	_mrect(img, 24, 42, 40, 44, M_ROBE)            # 腿盘上沿
	_mpx(img, 23, 43, M_OUT); _mpx(img, 41, 43, M_OUT)
	_mrect(img, 27, 45, 30, 46, M_BOOT)            # 交叠脚尖
	_mrect(img, 34, 45, 37, 46, M_BOOT)
	# ---- 躯干（压缩至盘坐比例）----
	_mrect(img, 27, 36 + bob, 37, 43, M_ROBE)
	_mrect(img, 34, 38 + bob, 37, 43, M_ROBE_D)    # 侧影
	_mpx(img, 26, 37 + bob, M_OUT); _mpx(img, 26, 42, M_OUT); _mpx(img, 38, 38 + bob, M_OUT); _mpx(img, 38, 42, M_OUT)
	# ---- 腰带 ----
	_mrect(img, 27, 40 + bob, 37, 41 + bob, M_BELT)
	_mpx(img, 31, 40 + bob, Color(0.38, 0.68, 0.52))   # 玉佩扣
	# ---- 交领 ----
	_mrect(img, 30, 36 + bob, 34, 37 + bob, M_TRIM)
	_mpx(img, 32, 38 + bob, M_TRIM); _mpx(img, 31, 39 + bob, M_TRIM); _mpx(img, 33, 39 + bob, M_TRIM)
	# ---- 搭膝的手臂与手 ----
	_mrect(img, 23, 39 + bob, 27, 43 + bob, M_ROBE)
	_mrect(img, 37, 39 + bob, 41, 43 + bob, M_ROBE)
	_mpx(img, 23, 42 + bob, M_ROBE_D); _mpx(img, 41, 42 + bob, M_ROBE_D)
	_mrect(img, 25, 43 + bob, 27, 44 + bob, M_SKIN)    # 左手搭膝
	_mrect(img, 37, 43 + bob, 39, 44 + bob, M_SKIN)    # 右手搭膝
	# ---- 颈与头 ----
	_mrect(img, 30, 34 + bob, 33, 35 + bob, M_SKIN_D)
	_mrect(img, 28, 26 + bob, 36, 34 + bob, M_SKIN)    # 脸
	_mrect(img, 29, 33 + bob, 35, 34 + bob, M_SKIN_D)  # 下颌影
	# 闭目吐纳（细横线）
	_mpx(img, 30, 30 + bob, M_OUT); _mpx(img, 34, 30 + bob, M_OUT)
	# ---- 乌发+发髻+发带 ----
	_mrect(img, 27, 22 + bob, 37, 27 + bob, M_HAIR)
	_mrect(img, 26, 26 + bob, 27, 31 + bob, M_HAIR)    # 左鬓
	_mrect(img, 37, 26 + bob, 38, 31 + bob, M_HAIR)    # 右鬓
	_mrect(img, 29, 18 + bob, 34, 22 + bob, M_HAIR)    # 发髻
	_mrect(img, 29, 21 + bob, 34, 21 + bob, M_RIBBON)  # 朱红发带
	_mpx(img, 28, 19 + bob, M_HAIR); _mpx(img, 35, 19 + bob, M_HAIR)
