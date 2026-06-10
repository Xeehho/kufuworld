@tool
extends Node

const TILE_SIZE = 16
const CHAR_W = 32
const CHAR_H = 48

func _ready():
	generate_tiles()
	if not Engine.is_editor_hint():
		get_tree().quit()

func generate_tiles():
	DirAccess.make_dir_recursive_absolute("res://sprites/tiles")

	_tile_grass()
	_tile_path()
	_tile_house()
	_tile_mountain()
	_tile_tree()
	print("[TextureGen] Tiles regenerated")

func _tile_grass():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base = Color(0.35, 0.52, 0.28, 1.0)
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var n = (randf() - 0.5) * 0.12
			img.set_pixel(x, y, Color(
				clamp(base.r + n, 0.2, 0.6),
				clamp(base.g + n, 0.3, 0.7),
				clamp(base.b + n * 0.6, 0.15, 0.45),
				1.0
			))
	img.save_png("res://sprites/tiles/grass.png")

func _tile_path():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base = Color(0.6, 0.5, 0.35, 1.0)
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var n = (randf() - 0.5) * 0.15
			img.set_pixel(x, y, Color(
				clamp(base.r + n, 0.4, 0.8),
				clamp(base.g + n, 0.3, 0.7),
				clamp(base.b + n * 0.7, 0.2, 0.5),
				1.0
			))
	img.save_png("res://sprites/tiles/path.png")

func _tile_house():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var wall = Color(0.65, 0.55, 0.42, 1.0)
	var roof = Color(0.25, 0.22, 0.28, 1.0)
	img.fill(Color(0, 0, 0, 0))
	for x in range(2, 14):
		for y in range(5, 16):
			img.set_pixel(x, y, wall)
	for x in range(0, 16):
		for y in range(1, 6):
			var dist = abs(x - 8)
			if y > dist * 0.7:
				img.set_pixel(x, y, roof)
	for x in range(5, 11):
		for y in range(9, 16):
			img.set_pixel(x, y, Color(0.4, 0.25, 0.18, 1.0))
	img.save_png("res://sprites/tiles/house.png")

func _tile_mountain():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var h = (sin(x * 0.5) * cos(y * 0.4) + 1.0) * 0.5
			var v = clamp(h + 0.1, 0.1, 1.0)
			img.set_pixel(x, y, Color(
				v * 0.45 + 0.1,
				v * 0.42 + 0.1,
				v * 0.5 + 0.15,
				1.0
			))
	img.save_png("res://sprites/tiles/mountain.png")

func _tile_tree():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(5, 11):
		for y in range(7, 16):
			img.set_pixel(x, y, Color(0.35, 0.2, 0.12, 1.0))
	for x in range(0, 16):
		for y in range(0, 9):
			var d = pow(abs(x - 8) / 7.5, 2) + pow(abs(y - 4) / 4.5, 2)
			if d < 1.0:
				var v = 1.0 - d
				img.set_pixel(x, y, Color(0.2 + v * 0.3, 0.45 + v * 0.2, 0.15 + v * 0.15, 1.0))
	img.save_png("res://sprites/tiles/tree.png")
