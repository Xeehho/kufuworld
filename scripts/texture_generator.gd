@tool
extends Node

const TILE_SIZE = 16
const CHAR_W = 32
const CHAR_H = 48

func _ready():
	if Engine.is_editor_hint():
		generate_all()

func generate_all():
	generate_player_frames()
	generate_tiles()

func generate_player_frames():
	var dir_path = "res://sprites/player"
	if DirAccess.dir_exists_absolute(dir_path):
		var files = DirAccess.get_files_at(dir_path)
		if files.size() >= 10:
			return

	DirAccess.make_dir_recursive_absolute("res://sprites/player")

	for i in range(4):
		_save_idle_frame(i)
	for i in range(6):
		_save_walk_frame(i)

	print("[TextureGen] Player frames generated")

func _save_idle_frame(frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	var base = Color(0.18, 0.20, 0.24, 1.0)
	var hat = Color(0.22, 0.18, 0.12, 1.0)
	var sword = Color(0.5, 0.5, 0.55, 1.0)
	var skin = Color(0.75, 0.65, 0.55, 1.0)

	img.fill(Color(0, 0, 0, 0))

	# 身体
	for x in range(12, 20):
		for y in range(20, 40):
			img.set_pixel(x, y, base)
	# 头部
	for x in range(13, 19):
		for y in range(14, 20):
			img.set_pixel(x, y, skin)
	# 斗笠
	for x in range(9, 23):
		for y in range(10, 16):
			if abs(x - 16) + abs(y - 13) < 9:
				img.set_pixel(x, y, hat)
	# 斗笠帽檐
	for x in range(7, 25):
		for y in range(14, 16):
			if x >= 8 and x <= 23:
				img.set_pixel(x, y, hat)
	# 佩剑
	for x in range(20, 23):
		for y in range(22, 42):
			img.set_pixel(x, y, sword)
	# 剑柄
	for x in range(19, 24):
		for y in range(21, 23):
			img.set_pixel(x, y, Color(0.4, 0.3, 0.2, 1.0))

	# 呼吸微动
	var offset = 0
	if frame == 1 or frame == 3:
		offset = 1
	var final_img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	final_img.fill(Color(0, 0, 0, 0))
	for x in range(CHAR_W):
		for y in range(CHAR_H):
			var c = img.get_pixel(x, y)
			if c.a > 0 and y >= 0 and y < CHAR_H:
				var sy = y - offset
				if sy >= 0 and sy < CHAR_H:
					final_img.set_pixel(x, sy, c)

	final_img.save_png("res://sprites/player/idle_" + str(frame) + ".png")

func _save_walk_frame(frame: int):
	var img = Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	var base = Color(0.18, 0.20, 0.24, 1.0)
	var hat = Color(0.22, 0.18, 0.12, 1.0)
	var sword = Color(0.5, 0.5, 0.55, 1.0)
	var skin = Color(0.75, 0.65, 0.55, 1.0)

	img.fill(Color(0, 0, 0, 0))

	var bob = [0, -2, 0, 2, -2, 0][frame]
	var leg_sway = [-1, 1, 2, 1, -1, -2][frame]

	# 身体 (带上下晃动)
	for x in range(12, 20):
		for y in range(20 + bob, 40 + bob):
			if y >= 0 and y < CHAR_H:
				img.set_pixel(x, y, base)
	# 腿1
	for x in range(12, 15):
		for y in range(40 + bob, 48 + bob):
			if y >= 0 and y < CHAR_H:
				var xo = x + leg_sway
				if xo >= 0 and xo < CHAR_W:
					img.set_pixel(xo, y, base * 0.85)
	# 腿2
	for x in range(17, 20):
		for y in range(40 + bob, 48 + bob):
			if y >= 0 and y < CHAR_H:
				var xo = x - leg_sway
				if xo >= 0 and xo < CHAR_W:
					img.set_pixel(xo, y, base * 0.85)
	# 头部
	for x in range(13, 19):
		for y in range(14 + bob, 20 + bob):
			if y >= 0 and y < CHAR_H:
				img.set_pixel(x, y, skin)
	# 斗笠
	for x in range(9, 23):
		for y in range(10 + bob, 16 + bob):
			if y >= 0 and y < CHAR_H:
				if abs(x - 16) + abs(y - 13 - bob) < 9:
					img.set_pixel(x, y, hat)
	# 帽檐
	for x in range(7, 25):
		for y in range(14 + bob, 16 + bob):
			if y >= 0 and y < CHAR_H:
				if x >= 8 and x <= 23:
					img.set_pixel(x, y, hat)
	# 佩剑
	for x in range(20, 23):
		for y in range(22 + bob, 42 + bob):
			if y >= 0 and y < CHAR_H:
				img.set_pixel(x, y, sword)
	# 剑柄
	for x in range(19, 24):
		for y in range(21 + bob, 23 + bob):
			if y >= 0 and y < CHAR_H:
				img.set_pixel(x, y, Color(0.4, 0.3, 0.2, 1.0))

	img.save_png("res://sprites/player/walk_" + str(frame) + ".png")

func generate_tiles():
	if DirAccess.dir_exists_absolute("res://sprites/tiles"):
		var files = DirAccess.get_files_at("res://sprites/tiles")
		if files.size() >= 5:
			return
	DirAccess.make_dir_recursive_absolute("res://sprites/tiles")

	_tile_grass()
	_tile_path()
	_tile_house()
	_tile_mountain()
	_tile_tree()

	print("[TextureGen] Tiles generated")

func _tile_grass():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base = Color(0.25, 0.35, 0.2, 1.0)
	var light = Color(0.3, 0.42, 0.24, 1.0)
	var dark = Color(0.18, 0.28, 0.15, 1.0)

	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var n = randf() * 0.1
			if (x + y) % 3 == 0:
				img.set_pixel(x, y, base + Color(n, n * 0.8, n * 0.5, 0))
			elif (x + y) % 5 == 0:
				img.set_pixel(x, y, dark + Color(n, n * 0.6, n * 0.3, 0))
			else:
				img.set_pixel(x, y, light + Color(n, n * 0.7, n * 0.4, 0))
	img.save_png("res://sprites/tiles/grass.png")

func _tile_path():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var base = Color(0.45, 0.38, 0.28, 1.0)
	var edge = Color(0.35, 0.28, 0.2, 1.0)
	var center = Color(0.5, 0.42, 0.32, 1.0)

	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var n = randf() * 0.08
			var d = abs(x - 8) + abs(y - 8)
			if d < 4:
				img.set_pixel(x, y, center + Color(n, n * 0.8, n * 0.6, 0))
			elif d < 7:
				img.set_pixel(x, y, base + Color(n, n * 0.7, n * 0.5, 0))
			else:
				img.set_pixel(x, y, edge + Color(n, n * 0.6, n * 0.4, 0))
	img.save_png("res://sprites/tiles/path.png")

func _tile_house():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var wall = Color(0.55, 0.45, 0.35, 1.0)
	var roof = Color(0.2, 0.18, 0.22, 1.0)
	var door = Color(0.3, 0.2, 0.15, 1.0)

	img.fill(Color(0, 0, 0, 0))
	# 墙壁
	for x in range(3, 13):
		for y in range(6, 16):
			img.set_pixel(x, y, wall)
	# 屋顶
	for x in range(1, 15):
		for y in range(2, 7):
			var dist = abs(x - 8)
			if y > dist * 0.8:
				img.set_pixel(x, y, roof)
	# 门
	for x in range(6, 10):
		for y in range(10, 16):
			img.set_pixel(x, y, door)
	img.save_png("res://sprites/tiles/house.png")

func _tile_mountain():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var rock = Color(0.25, 0.28, 0.32, 1.0)
	var highlight = Color(0.35, 0.38, 0.42, 1.0)
	var shadow = Color(0.15, 0.18, 0.22, 1.0)

	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var h = (sin(x * 0.5) * cos(y * 0.4) + 1.0) * 0.5
			var h2 = (sin((x + 4) * 0.6) * sin((y + 3) * 0.7) + 1.0) * 0.3
			var v = h + h2
			if v > 0.55:
				img.set_pixel(x, y, highlight)
			elif v > 0.3:
				img.set_pixel(x, y, rock)
			else:
				img.set_pixel(x, y, shadow)
	img.save_png("res://sprites/tiles/mountain.png")

func _tile_tree():
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var trunk = Color(0.28, 0.18, 0.12, 1.0)
	var leaf_dark = Color(0.15, 0.3, 0.15, 1.0)
	var leaf_mid = Color(0.2, 0.4, 0.2, 1.0)
	var leaf_light = Color(0.28, 0.48, 0.28, 1.0)

	img.fill(Color(0, 0, 0, 0))
	# 树干
	for x in range(6, 10):
		for y in range(8, 16):
			img.set_pixel(x, y, trunk)
	# 树冠
	for x in range(1, 15):
		for y in range(1, 10):
			var d = pow(abs(x - 8) / 7.0, 2) + pow(abs(y - 5) / 4.5, 2)
			if d < 1.0:
				var shade = leaf_dark.lerp(leaf_light, 1.0 - d)
				img.set_pixel(x, y, shade)
	img.save_png("res://sprites/tiles/tree.png")
