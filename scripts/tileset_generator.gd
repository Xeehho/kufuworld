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
		5: "res://sprites/tiles/water.png",
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
	}

	# 需要碰撞的瓦片ID：5=水, 3=山崖, 7=雪崖, 2/10/11=16px房, 12=洞穴, 14=岩石, 15=栅栏, 40=城墙, 43=坊墙
	var collision_tile_ids = [5, 3, 7, 2, 10, 11, 12, 14, 15, 40, 43]
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
	return ts
