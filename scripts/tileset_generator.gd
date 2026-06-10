@tool
extends Node

func _ready():
	_generate_tileset()
	if not Engine.is_editor_hint():
		get_tree().quit()

func _generate_tileset():
	var ts = TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.y_sort_origin = 8

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

	for id in textures:
		var tex = load(textures[id])
		if tex:
			var source = TileSetAtlasSource.new()
			source.texture = tex
			source.texture_region_size = Vector2i(32, 32)
			source.create_tile(Vector2i(0, 0))
			# 树木和建筑使用Y排序
			if id in [4, 8, 9, 2, 10, 11, 12, 14]:
				source.set_tile_y_sort_origin(Vector2i(0, 0), 16)
				source.set_tile_z_index(Vector2i(0, 0), 1)
			ts.add_source(source, id)
			print("[TileSetGen] Added tile id=" + str(id))

	ResourceSaver.save(ts, "res://tilesets/ground_tiles.tres")
	print("[TileSetGen] TileSet saved with " + str(textures.size()) + " tiles")
