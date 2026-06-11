@tool
extends Node

func _ready():
	_generate_tileset()

func _generate_tileset():
	var ts = TileSet.new()
	ts.tile_size = Vector2i(32, 32)

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
		17: "res://sprites/tiles/bridge.png",
		18: "res://sprites/tiles/grass_dark.png",
	}

	# 需要碰撞的瓦片ID：5=水, 3=山, 7=雪山, 2=城镇房屋, 10=茅屋, 11=寺庙, 12=洞穴入口, 14=石头, 15=栅栏
	var collision_tile_ids = [5, 3, 7, 2, 10, 11, 12, 14, 15]
	# 先添加物理层（在循环之前）
	ts.add_physics_layer()

	for id in textures:
		var tex = load(textures[id])
		if tex:
			var source = TileSetAtlasSource.new()
			source.texture = tex
			source.texture_region_size = Vector2i(32, 32)
			source.create_tile(Vector2i(0, 0))
			# 树木和建筑使用Y排序
			if id in [4, 8, 9, 2, 10, 11, 12, 14]:
				var tile_data = source.get_tile_data(Vector2i(0, 0), 0)
				if tile_data:
					tile_data.y_sort_origin = 16
					tile_data.z_index = 1
			# 为水域和山脉瓦片添加物理碰撞
			if id in collision_tile_ids:
				var tile_data = source.get_tile_data(Vector2i(0, 0), 0)
				if tile_data:
					# 碰撞多边形以瓦片中心为原点
					var poly = PackedVector2Array([
						Vector2(-16, -16),
						Vector2(16, -16),
						Vector2(16, 16),
						Vector2(-16, 16)
					])
					tile_data.set_collision_polygons_count(0, 1)
					tile_data.set_collision_polygon_points(0, 0, poly)
			ts.add_source(source, id)
			print("[TileSetGen] Added tile id=" + str(id))

	ResourceSaver.save(ts, "res://tilesets/ground_tiles.tres")
	print("[TileSetGen] TileSet saved with " + str(textures.size()) + " tiles")
