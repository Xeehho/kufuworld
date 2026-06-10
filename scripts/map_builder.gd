@tool
extends Node2D

func _ready():
	if has_node("WorldGenerator"):
		return
	_build_map()

func _build_map():
	var tile_map = $"TileMap" as TileMap
	if not tile_map or not tile_map.tile_set:
		return

	if tile_map.get_used_cells(0).size() > 0:
		return

	var w = 25
	var h = 20

	for x in range(w):
		for y in range(h):
			tile_map.set_cell(0, Vector2i(x, y), 0, Vector2i(0, 0))

	var path_coords = [
		Vector2i(0,8), Vector2i(1,8), Vector2i(2,8), Vector2i(3,8),
		Vector2i(4,7), Vector2i(5,7), Vector2i(6,7),
		Vector2i(7,6), Vector2i(8,6), Vector2i(9,6), Vector2i(10,6),
		Vector2i(11,5), Vector2i(12,5), Vector2i(13,5),
		Vector2i(14,6), Vector2i(15,6), Vector2i(16,6),
		Vector2i(17,7), Vector2i(18,7), Vector2i(19,7),
		Vector2i(20,8), Vector2i(21,8), Vector2i(22,8), Vector2i(23,8), Vector2i(24,8)
	]
	for coord in path_coords:
		tile_map.set_cell(0, coord, 1, Vector2i(0, 0))

	var main_path = [
		Vector2i(8,12), Vector2i(8,11), Vector2i(8,10), Vector2i(8,9), Vector2i(9,9),
		Vector2i(10,10), Vector2i(10,11), Vector2i(10,12), Vector2i(10,13),
		Vector2i(10,14), Vector2i(10,15), Vector2i(10,16), Vector2i(10,17),
		Vector2i(10,18), Vector2i(10,19)
	]
	for coord in main_path:
		tile_map.set_cell(0, coord, 1, Vector2i(0, 0))

	var side_path = [
		Vector2i(11,12), Vector2i(12,12), Vector2i(13,12), Vector2i(14,12),
		Vector2i(15,12), Vector2i(16,12), Vector2i(17,12),
		Vector2i(18,11), Vector2i(19,11), Vector2i(20,10), Vector2i(21,10)
	]
	for coord in side_path:
		tile_map.set_cell(0, coord, 1, Vector2i(0, 0))

	var house1 = [Vector2i(14,8), Vector2i(15,8), Vector2i(14,9), Vector2i(15,9), Vector2i(14,10), Vector2i(15,10)]
	for coord in house1:
		tile_map.set_cell(0, coord, 2, Vector2i(0, 0))

	var house2 = [Vector2i(21,6), Vector2i(22,6), Vector2i(21,7), Vector2i(22,7)]
	for coord in house2:
		tile_map.set_cell(0, coord, 2, Vector2i(0, 0))

	var house3 = [Vector2i(4,12), Vector2i(5,12), Vector2i(4,13), Vector2i(5,13)]
	for coord in house3:
		tile_map.set_cell(0, coord, 2, Vector2i(0, 0))

	var mountains = [
		Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(22,0), Vector2i(23,0), Vector2i(24,0),
		Vector2i(0,1), Vector2i(24,1), Vector2i(24,2), Vector2i(0,2),
		Vector2i(24,3), Vector2i(0,3), Vector2i(24,4),
		Vector2i(18,3), Vector2i(19,3),
		Vector2i(3,15), Vector2i(4,15),
		Vector2i(20,14), Vector2i(21,14)
	]
	for coord in mountains:
		tile_map.set_cell(0, coord, 3, Vector2i(0, 0))

	var trees = [
		Vector2i(3,3), Vector2i(6,3), Vector2i(12,2), Vector2i(13,3), Vector2i(21,2),
		Vector2i(2,5), Vector2i(5,5), Vector2i(12,4), Vector2i(20,5),
		Vector2i(0,10), Vector2i(1,10), Vector2i(6,10),
		Vector2i(18,13), Vector2i(19,13),
		Vector2i(16,15), Vector2i(17,15),
		Vector2i(3,17), Vector2i(5,17),
		Vector2i(0,16), Vector2i(0,17),
		Vector2i(15,18), Vector2i(16,18),
		Vector2i(22,14), Vector2i(23,14),
		Vector2i(6,14), Vector2i(7,14)
	]
	for coord in trees:
		tile_map.set_cell(0, coord, 4, Vector2i(0, 0))

	print("[MapBuilder] Map built - " + str(tile_map.get_used_cells(0).size()) + " tiles placed")
