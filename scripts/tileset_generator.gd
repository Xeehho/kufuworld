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
		4: "res://sprites/tiles/tree_pine.png",
		5: "res://sprites/tiles/water.png",
		6: "res://sprites/tiles/sand.png",
		7: "res://sprites/tiles/mountain_snow.png",
		8: "res://sprites/tiles/tree_oak.png",
		9: "res://sprites/tiles/tree_bamboo.png",
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
		# 多格建筑部件（19-32）：2/3/4/5格宽中式建筑的水平拼接瓦片
		19: "res://sprites/tiles/house2_l.png",
		20: "res://sprites/tiles/house2_r.png",
		21: "res://sprites/tiles/house3_l.png",
		22: "res://sprites/tiles/house3_m.png",
		23: "res://sprites/tiles/house3_r.png",
		24: "res://sprites/tiles/house4_l.png",
		25: "res://sprites/tiles/house4_lm.png",
		26: "res://sprites/tiles/house4_rm.png",
		27: "res://sprites/tiles/house4_r.png",
		28: "res://sprites/tiles/house5_l.png",
		29: "res://sprites/tiles/house5_lm.png",
		30: "res://sprites/tiles/house5_m.png",
		31: "res://sprites/tiles/house5_rm.png",
		32: "res://sprites/tiles/house5_r.png",
	}

	# 需要碰撞的瓦片ID：5=水, 3=山, 7=雪山, 2=城镇房屋, 10=茅屋, 11=寺庙, 12=洞穴入口, 14=石头, 15=栅栏, 19-32=多格建筑
	var collision_tile_ids = [5, 3, 7, 2, 10, 11, 12, 14, 15, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]
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
				# 树木和建筑使用Y排序（含多格建筑部件19-32）
				if id in [4, 8, 9, 2, 10, 11, 12, 14, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]:
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
