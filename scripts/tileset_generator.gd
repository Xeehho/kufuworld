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

	var textures = {
		0: "res://sprites/tiles/grass.png",
		1: "res://sprites/tiles/path.png",
		2: "res://sprites/tiles/house_town.png",
		3: "res://sprites/tiles/mountain.png",
		5: "res://sprites/tiles/water_anim.png",      # 画面改造P3.3：双帧波纹动画条（32x16）
		6: "res://sprites/tiles/sand.png",
		7: "res://sprites/tiles/mountain_snow.png",
		10: "res://sprites/tiles/house_cottage.png",
		11: "res://sprites/tiles/house_temple.png",
		12: "res://sprites/tiles/house_cave.png",
		13: "res://sprites/tiles/flower.png",
		14: "res://sprites/tiles/rock.png",
		15: "res://sprites/tiles/fence.png",
		16: "res://sprites/tiles/farmland.png",
		33: "res://sprites/tiles/farmland_wet.png",   # Phase C 浇水湿润农田（无碰撞，地面层切换用）
		17: "res://sprites/tiles/bridge.png",
		18: "res://sprites/tiles/grass_dark.png",
		34: "res://sprites/tiles/snow.png",           # Phase G重构: 雪原真雪地（demo3）
		41: "res://sprites/tiles/snow_farmland.png",  # 2026-08-31: 雪覆农田（雪原群系农田，无碰撞）
		42: "res://sprites/tiles/snow_path.png",      # 2026-08-31: 雪径（雪原群系道路，无碰撞）
		35: "res://sprites/tiles/stone.png",          # Phase G重构: 石板广场（demo1城镇）
		36: "res://sprites/tiles/mushroom.png",       # Phase G重构: 蘑菇装饰（demo2森林地表）
		37: "res://sprites/tiles/daisy.png",          # Phase G重构: 雏菊装饰
		40: "res://sprites/tiles/city_wall.png",      # 青石城城墙砖（四面围墙，有碰撞）
		43: "res://sprites/tiles/ward_wall.png",      # W2 唐制坊墙（白灰淡砖，里坊围合，有碰撞）
		44: "res://sprites/tiles/boundary_stone.png", # W3 界碑（门派领地边界标记，无碰撞装饰）
		# ---- 画面改造P1.2 地面变体（无碰撞，layer 0，由 _ground_variant 噪声抖动选入）----
		45: "res://sprites/tiles/grass_a.png",        # 草地像素变体A
		46: "res://sprites/tiles/grass_b.png",        # 草地像素变体B
		47: "res://sprites/tiles/grass_patch.png",    # 深绿色斑（草原斑驳）
		48: "res://sprites/tiles/dark_a.png",         # 竹林深草变体A
		49: "res://sprites/tiles/dark_b.png",         # 竹林深草变体B
		50: "res://sprites/tiles/snow_a.png",         # 雪地像素变体A
		51: "res://sprites/tiles/snow_b.png",         # 雪地像素变体B
		52: "res://sprites/tiles/sand_a.png",         # 沙地像素变体A
		53: "res://sprites/tiles/sand_b.png",         # 沙地像素变体B
		54: "res://sprites/tiles/dirt_patch.png",     # 深棕干土斑（沙漠斑驳）
		# ---- 画面改造P1.3 碎屑装饰（无碰撞，layer 1，decor_tiles 白名单）----
		55: "res://sprites/tiles/tuft_a.png",         # 绿草丛
		56: "res://sprites/tiles/tuft_b.png",         # 双叶草
		57: "res://sprites/tiles/tuft_c.png",         # 黄绿草丛
		58: "res://sprites/tiles/flower_white.png",   # 白色小野花
		59: "res://sprites/tiles/flower_yellow.png",  # 黄色小野花
		60: "res://sprites/tiles/leaf_litter.png",    # 橙色落叶簇
		61: "res://sprites/tiles/twig.png",           # 枯枝
		62: "res://sprites/tiles/dry_tuft.png",       # 干枯草丛
		63: "res://sprites/tiles/dry_small.png",      # 干枯小苗
		# ---- 画面改造P4b 山崖变体（碰撞同3，_paint_ground 噪声抖动选入）----
		65: "res://sprites/tiles/mountain_b.png",     # 崖壁变体B（镜像）
		66: "res://sprites/tiles/mountain_c.png",     # 崖壁变体C（翻转+压暗）
		# ---- 长安城 M0（docs/长安城地图设计.md §5.1；设计稿拟用41~56已被占，改从67起编）----
		67: "res://sprites/tiles/ward_gate_open.png",   # 坊门·开（无碰撞，宵禁态切换）
		68: "res://sprites/tiles/ward_gate_closed.png", # 坊门·闭（有碰撞）
		69: "res://sprites/tiles/changan_palace_wall.png",  # 宫墙（M2专属纹样：朱红墙+灰瓦压顶）
		70: "res://sprites/tiles/changan_outer_wall.png",   # 外郭城墙（M2专属纹样：夯土大砖）
		71: "res://sprites/tiles/changan_zhuque.png",       # 朱雀大街御道（M2专属纹样：大块石板纵列）
		72: "res://sprites/tiles/path.png",             # 主干街甬道
		73: "res://sprites/tiles/path.png",             # 坊内十字街土路
		74: "res://sprites/tiles/path.png",             # 巷路
		# ---- 长安城 M2 宅门品级（§5.1 75~80备用段：宅门A/B/C；78/79市墙市门未注册）----
		75: "res://sprites/tiles/changan_gate_a.png",   # 宅门·A 朱门金钉（亲王/公主/国寺）
		76: "res://sprites/tiles/changan_gate_b.png",   # 宅门·B 朱门铜钉（国公/郡王/士族）
		77: "res://sprites/tiles/changan_gate_c.png",   # 宅门·C 黑漆木门（官署/曲坊小宅）
	}

	# 需要碰撞的瓦片ID：5=水, 3=山崖, 7=雪崖, 2/10/11=16px房, 12=洞穴, 14=岩石, 15=栅栏, 40=城墙, 43=坊墙, 65/66=崖壁变体, 68=坊门闭, 69=宫墙, 70=外郭城墙, 75~77=宅门（M4接传送门时改）
	var collision_tile_ids = [5, 3, 7, 2, 10, 11, 12, 14, 15, 40, 43, 65, 66, 68, 69, 70, 75, 76, 77]
	# 先添加物理层（在循环之前）
	ts.add_physics_layer()

	for id in textures:
		var tex = TextureGen.load_png_texture(textures[id])
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
				if id in [2, 10, 11, 12, 14]:
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
				# 画面改造P3.3：水面双帧轮播（32x16条，帧2在x+1；0.9s/帧微光流动）
				if id == 5:
					source.set_tile_animation_frames_count(Vector2i(0, 0), 2)
					source.set_tile_animation_frame_duration(Vector2i(0, 0), 0, 0.9)
					source.set_tile_animation_frame_duration(Vector2i(0, 0), 1, 0.9)

	# 画面改造P3.2 水岸过渡（源64）：Water_tiles 首岛岸环 8 块（滩涂+泡沫+草沿），静态帧。
	# 注：环块的4组岛跨列动画曾尝试 set_tile_animation_separation(6,1)，Godot 报
	# "tiles are already present in the space the tile would cover"——占位校验不过，故用静态帧；
	# 水面动态由源5的双帧波纹动画承担。草沿像素做草地暖化同步色系
	var shore_img: Image = TextureGen._pack_image("Environment/Tilesets/Water_tiles.png")
	if shore_img != null:
		var shore_img_tinted = TextureGen._tint_veg_pixels(shore_img, 1.55, 1.16, 9.0)
		var shore = TileSetAtlasSource.new()
		shore.texture = ImageTexture.create_from_image(shore_img_tinted)
		shore.texture_region_size = Vector2i(16, 16)
		var shore_cells = [
			Vector2i(2, 4), Vector2i(2, 0), Vector2i(0, 2), Vector2i(4, 2),   # 正交：草沿朝N/E/S/W
			Vector2i(1, 4), Vector2i(3, 4), Vector2i(1, 0), Vector2i(3, 0),   # 对角：草沿朝NE/NW/SE/SW
		]
		for coords in shore_cells:
			shore.create_tile(coords)
		ts.add_source(shore, 64)
	return ts
