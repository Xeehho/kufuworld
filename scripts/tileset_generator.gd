@tool
extends Node

const TextureGen = preload("res://scripts/texture_generator.gd")

func _ready():
	_generate_tileset()

func _generate_tileset():
	var ts = build_tileset()
	if ts:
		ResourceSaver.save(ts, "res://tilesets/ground_tiles.tres")
		print("[TileSetGen] TileSet saved")

# 运行时内存构建TileSet（纹理直接解码PNG，不依赖import系统）
static func build_tileset() -> TileSet:
	var ts = TileSet.new()
	ts.tile_size = Vector2i(16, 16)

	# ---- 瓦片路径：[MW付费版派生(首选), 自绘(回退)] 双列——MW 素材 gitignore 本地生成，
	# 缺失时自动落回 texture_generator 自绘版（克隆即玩不受影响）。MW 换血 Slice B
	var textures = {
		0: ["res://sprites/tiles_mw22/grass.png", "res://sprites/tiles/grass.png"],
		1: ["res://sprites/tiles_mw22/path.png", "res://sprites/tiles/path.png"],
		2: "res://sprites/tiles/house_town.png",
		3: ["res://sprites/tiles_mw22/mountain.png", "res://sprites/tiles/mountain.png"],
		5: ["res://sprites/tiles_mw22/water_anim.png", "res://sprites/tiles/water_anim.png"],      # MW水色+程序化微光 六帧动画条（96x16）
		6: ["res://sprites/tiles_mw22/sand.png", "res://sprites/tiles/sand.png"],
		7: "res://sprites/tiles/mountain_snow.png",
		10: "res://sprites/tiles/house_cottage.png",
		11: "res://sprites/tiles/house_temple.png",
		12: "res://sprites/tiles/house_cave.png",
		13: ["res://sprites/tiles_mw22/flower.png", "res://sprites/tiles/flower.png"],
		14: ["res://sprites/tiles_mw22/rock.png", "res://sprites/tiles/rock.png"],
		15: ["res://sprites/tiles_mw22/fence.png", "res://sprites/tiles/fence.png"],
		16: ["res://sprites/tiles_mw22/farmland.png", "res://sprites/tiles/farmland.png"],
		33: ["res://sprites/tiles_mw22/farmland_wet.png", "res://sprites/tiles/farmland_wet.png"],  # Phase C 浇水湿润农田（无碰撞，地面层切换用）
		17: ["res://sprites/tiles_mw22/bridge.png", "res://sprites/tiles/bridge.png"],
		18: ["res://sprites/tiles_mw22/grass_dark.png", "res://sprites/tiles/grass_dark.png"],
		34: "res://sprites/tiles/snow.png",           # Phase G重构: 雪原真雪地（demo3，MW无雪暂自绘）
		41: "res://sprites/tiles/snow_farmland.png",  # 2026-08-31: 雪覆农田（雪原群系农田，无碰撞）
		42: "res://sprites/tiles/snow_path.png",      # 2026-08-31: 雪径（雪原群系道路，无碰撞）
		35: ["res://sprites/tiles_mw22/stone.png", "res://sprites/tiles/stone.png"],                # Phase G重构: 石板广场（demo1城镇）
		36: ["res://sprites/tiles_mw22/mushroom.png", "res://sprites/tiles/mushroom.png"],          # Phase G重构: 蘑菇装饰（demo2森林地表）
		37: ["res://sprites/tiles_mw22/daisy.png", "res://sprites/tiles/daisy.png"],                # Phase G重构: 雏菊装饰
		40: "res://sprites/tiles/city_wall.png",      # 青石城城墙砖（四面围墙，有碰撞）
		43: "res://sprites/tiles/ward_wall.png",      # W2 唐制坊墙（白灰淡砖，里坊围合，有碰撞）
		44: "res://sprites/tiles/boundary_stone.png", # W3 界碑（门派领地边界标记，无碰撞装饰）
		# ---- 画面改造P1.2 地面变体（无碰撞，layer 0，由 _ground_variant 噪声抖动选入）----
		45: ["res://sprites/tiles_mw22/grass_a.png", "res://sprites/tiles/grass_a.png"],   # 草地像素变体A
		46: ["res://sprites/tiles_mw22/grass_b.png", "res://sprites/tiles/grass_b.png"],   # 草地像素变体B
		47: ["res://sprites/tiles_mw22/grass_patch.png", "res://sprites/tiles/grass_patch.png"],  # 深绿色斑（草原斑驳）
		48: ["res://sprites/tiles_mw22/grass_dark.png", "res://sprites/tiles/dark_a.png"], # 竹林深草变体A
		49: ["res://sprites/tiles_mw22/grass_dark.png", "res://sprites/tiles/dark_b.png"], # 竹林深草变体B
		50: "res://sprites/tiles/snow_a.png",         # 雪地像素变体A
		51: "res://sprites/tiles/snow_b.png",         # 雪地像素变体B
		52: ["res://sprites/tiles_mw22/sand_a.png", "res://sprites/tiles/sand_a.png"],     # 沙地像素变体A
		53: ["res://sprites/tiles_mw22/sand_b.png", "res://sprites/tiles/sand_b.png"],     # 沙地像素变体B
		54: ["res://sprites/tiles_mw22/dirt_patch.png", "res://sprites/tiles/dirt_patch.png"],     # 深棕干土斑（沙漠斑驳）
		# ---- 画面改造P1.3 碎屑装饰（无碰撞，layer 1，decor_tiles 白名单）----
		55: ["res://sprites/tiles_mw22/tuft_a.png", "res://sprites/tiles/tuft_a.png"],     # 绿草丛
		56: ["res://sprites/tiles_mw22/tuft_b.png", "res://sprites/tiles/tuft_b.png"],     # 双叶草
		57: ["res://sprites/tiles_mw22/tuft_c.png", "res://sprites/tiles/tuft_c.png"],     # 黄绿草丛
		58: ["res://sprites/tiles_mw22/flower_white.png", "res://sprites/tiles/flower_white.png"], # 白色小野花
		59: ["res://sprites/tiles_mw22/flower_yellow.png", "res://sprites/tiles/flower_yellow.png"], # 黄色小野花
		60: "res://sprites/tiles/leaf_litter.png",    # 橙色落叶簇
		61: "res://sprites/tiles/twig.png",           # 枯枝
		62: "res://sprites/tiles/dry_tuft.png",       # 干枯草丛
		63: "res://sprites/tiles/dry_small.png",      # 干枯小苗
		# ---- 画面改造P4b 山崖变体（碰撞同3，_paint_ground 噪声抖动选入）----
		65: ["res://sprites/tiles_mw22/mountain_b.png", "res://sprites/tiles/mountain_b.png"],  # 崖壁变体B
		66: ["res://sprites/tiles_mw22/mountain_c.png", "res://sprites/tiles/mountain_c.png"],  # 崖壁变体C（翻转+压暗）
		# ---- 长安城 M0（docs/长安城地图设计.md §5.1；设计稿拟用41~56已被占，改从67起编）----
		67: "res://sprites/tiles/ward_gate_open.png",   # 坊门·开（无碰撞，宵禁态切换）
		68: "res://sprites/tiles/ward_gate_closed.png", # 坊门·闭（有碰撞）
		# ---- 长安视觉重构（SCKR中式包首选，gen_changan_tiles 自绘回退；切片管线 tools/import_sckr_changan.py）----
		69: ["res://sprites/tiles_changan_sckr/wall_palace.png", "res://sprites/tiles/changan_palace_wall.png"],  # 宫墙（金瓦顶红墙身石基）
		70: ["res://sprites/tiles_changan_sckr/wall_city.png", "res://sprites/tiles/changan_outer_wall.png"],     # 外郭城墙（垛口顶+城砖身）
		71: ["res://sprites/tiles_changan_sckr/street_zhuque.png", "res://sprites/tiles/changan_zhuque.png"],     # 朱雀大街御道（大石板）
		72: ["res://sprites/tiles_changan_sckr/street_main.png", "res://sprites/tiles/path.png"],        # 主干街甬道（顺砖）
		73: ["res://sprites/tiles_changan_sckr/street_ward.png", "res://sprites/tiles/path.png"],        # 坊内十字街（竖砖）
		74: ["res://sprites/tiles_changan_sckr/street_lane.png", "res://sprites/tiles/path.png"],        # 巷路（人字纹）
		# ---- 长安城 M2 宅门品级（§5.1 75~80备用段：宅门A/B/C；78/79市墙市门未注册）----
		75: "res://sprites/tiles/changan_gate_a.png",   # 宅门·A 朱门金钉（亲王/公主/国寺）
		76: "res://sprites/tiles/changan_gate_b.png",   # 宅门·B 朱门铜钉（国公/郡王/士族）
		77: "res://sprites/tiles/changan_gate_c.png",   # 宅门·C 黑漆木门（官署/曲坊小宅）
		# ---- 长安视觉重构 新瓦片（100 起；90~99 已预留现代族 M6 勿占）----
		100: ["res://sprites/tiles_changan_sckr/wall_ward.png", "res://sprites/tiles/ward_wall.png"],     # 长安坊墙（白灰墙+灰瓦顶+砖脚）
		101: ["res://sprites/tiles_changan_sckr/pave_market.png", "res://sprites/tiles_mw22/stone.png"],  # 长安方砖（两市/宫院丹墀铺装）
		102: ["res://sprites/tiles_changan_sckr/foot.png", "res://sprites/tiles/house_town.png"],        # 建筑足印（全透明带碰撞；回退=可见16px小屋）
		103: ["res://sprites/tiles_changan_sckr/wall_city_face_v.png", "res://sprites/tiles/changan_outer_wall.png"], # 外郭墙·竖立面（E/W 段，描边双列厚墙）
		104: ["res://sprites/tiles_changan_sckr/wall_palace_v.png", "res://sprites/tiles/changan_palace_wall.png"],  # 宫墙·竖立面（E/W 段）
		105: ["res://sprites/tiles_changan_sckr/wall_ward_v.png", "res://sprites/tiles/ward_wall.png"],   # 长安坊墙·竖立面
		106: ["res://sprites/tiles_changan_sckr/wall_city_body.png", "res://sprites/tiles/changan_outer_wall.png"],  # 外郭城墙·砖身行（横缝）
		108: ["res://sprites/tiles_changan_sckr/wall_city_cap_w.png", "res://sprites/tiles/changan_outer_wall.png"], # 外郭城墙·垛口齿西列（竖段外列，齿朝西）
		109: ["res://sprites/tiles_changan_sckr/wall_city_cap_e.png", "res://sprites/tiles/changan_outer_wall.png"], # 外郭城墙·垛口齿东列（竖段外列，齿朝东）
		111: ["res://sprites/tiles_changan_sckr/quay_stone.png", "res://sprites/tiles_mw22/stone.png"],   # 岸石·渠岸顶面（范式v3）
		112: ["res://sprites/tiles_changan_sckr/water_canal.png", "res://sprites/tiles/water.png"],       # 渠水/护城河·江南蓝（碰撞，范式v3）
			# ---- 长安城 M4 内景瓦片族 80~89（§5.3 interior_tiles，独立小场景复用；M6 现代场景换皮肤）----
		80: "res://sprites/tiles/interior_floor_wood.png",   # 木地板
		81: "res://sprites/tiles/interior_floor_brick.png",  # 砖地板
		82: "res://sprites/tiles/interior_carpet.png",       # 毯
		83: "res://sprites/tiles/interior_wall.png",         # 内墙（碰撞）
		84: "res://sprites/tiles/interior_screen.png",       # 屏风（碰撞）
		85: "res://sprites/tiles/interior_lamp.png",         # 灯烛
		86: "res://sprites/tiles/interior_desk.png",         # 案（碰撞）
		87: "res://sprites/tiles/interior_couch.png",        # 榻
		88: "res://sprites/tiles/interior_cabinet.png",      # 柜（碰撞）
		89: "res://sprites/tiles/interior_shelf.png",        # 架（碰撞）
	}

	# 需要碰撞的瓦片ID：5=水, 3=山崖, 7=雪崖, 2/10/11=16px房, 12=洞穴, 14=岩石, 15=栅栏, 40=城墙, 43=坊墙, 65/66=崖壁变体, 68=坊门闭, 69=宫墙, 70=外郭城墙, 100=长安坊墙, 102=建筑足印（透明碰撞）；75~77=宅门（M4起无碰撞接传送门）；83/84/86/88/89=内景墙/屏风/案/柜/架
	var collision_tile_ids = [5, 3, 7, 2, 10, 11, 12, 14, 15, 40, 43, 65, 66, 68, 69, 70, 83, 84, 86, 88, 89, 100, 102, 103, 104, 105, 106, 108, 109, 112]
	# 先添加物理层（在循环之前）
	ts.add_physics_layer()

	for id in textures:
		# [MW首选, 自绘回退] 双列路径依次尝试；字符串=单路径
		var candidates: Array = textures[id] if textures[id] is Array else [textures[id]]
		var tex: Texture2D = null
		for p in candidates:
			tex = TextureGen.load_png_texture(p)
			if tex:
				break
		if tex:
			var source = TileSetAtlasSource.new()
			source.texture = tex
			source.texture_region_size = Vector2i(16, 16)
			source.create_tile(Vector2i(0, 0))
			# 必须先add_source，TileData才关联TileSet的物理层，否则碰撞设置会报越界错误
			ts.add_source(source, id)
			var tile_data = source.get_tile_data(Vector2i(0, 0), 0)
			if tile_data:
				# 建筑类瓦片使用Y排序
				if id in [2, 10, 11, 12, 14, 84, 86, 87, 88, 89]:   # M4 内景家具同走 y-sort（屏风/案/榻/柜/架）
					tile_data.y_sort_origin = 8
					tile_data.z_index = 1
				# 为水域和山脉瓦片添加物理碰撞
				if id in collision_tile_ids:
					# 碰撞多边形以瓦片中心为原点
					var poly = PackedVector2Array([
						Vector2(-8, -8),
						Vector2(8, -8),
						Vector2(8, 8),
						Vector2(-8, 8)
					])
					tile_data.set_collision_polygons_count(0, 1)
					tile_data.set_collision_polygon_points(0, 0, poly)
				# MW换血：水面六帧微光轮播（96x16条，帧i在x+i；0.9s/帧流动）
				if id == 5:
					source.set_tile_animation_frames_count(Vector2i(0, 0), 6)
					for fi in range(6):
						source.set_tile_animation_frame_duration(Vector2i(0, 0), fi, 0.9)

	# 水岸过渡（源64）：MW池塘边块八向岸环（滩涂+草沿，唐风色板已烘焙进 shore.png）。
	# MW 缺失时回退 Pixel Crawler Water_tiles（_pack_image + 植被暖化 tint，旧管线）
	var shore = null
	var mw_shore_tex = TextureGen.load_png_texture("res://sprites/tiles_mw22/shore.png")
	if mw_shore_tex != null:
		shore = TileSetAtlasSource.new()
		shore.texture = mw_shore_tex
		shore.texture_region_size = Vector2i(16, 16)
	else:
		var pc_img: Image = TextureGen._pack_image("Environment/Tilesets/Water_tiles.png")
		if pc_img != null:
			var shore_img_tinted = TextureGen._tint_veg_pixels(pc_img, 1.55, 1.16, 9.0)
			shore = TileSetAtlasSource.new()
			shore.texture = ImageTexture.create_from_image(shore_img_tinted)
			shore.texture_region_size = Vector2i(16, 16)
	if shore != null:
		var shore_cells = [
			Vector2i(2, 4), Vector2i(2, 0), Vector2i(0, 2), Vector2i(4, 2),   # 正交：草沿朝N/E/S/W
			Vector2i(1, 4), Vector2i(3, 4), Vector2i(1, 0), Vector2i(3, 0),   # 对角：草沿朝NE/NW/SE/SW
		]
		for coords in shore_cells:
			shore.create_tile(coords)
		ts.add_source(shore, 64)
	return ts
