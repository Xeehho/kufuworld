@tool
extends Node

func _ready():
	_generate_tileset()
	if not Engine.is_editor_hint():
		get_tree().quit()

func _generate_tileset():
	var ts = TileSet.new()
	ts.tile_size = Vector2i(16, 16)

	var textures = {
		0: "res://sprites/tiles/grass.png",
		1: "res://sprites/tiles/path.png",
		2: "res://sprites/tiles/house.png",
		3: "res://sprites/tiles/mountain.png",
		4: "res://sprites/tiles/tree.png"
	}

	for id in textures:
		var tex = load(textures[id])
		if tex:
			var source = TileSetAtlasSource.new()
			source.texture = tex
			source.texture_region_size = Vector2i(16, 16)
			source.create_tile(Vector2i(0, 0))
			var src_id = ts.add_source(source, id)
			print("[TileSetGen] Added tile id=" + str(id) + " src=" + str(src_id))

	ResourceSaver.save(ts, "res://tilesets/ground_tiles.tres")
	print("[TileSetGen] TileSet saved")
