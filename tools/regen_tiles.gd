extends SceneTree
# Phase B 工具：无头重生成 texture_generator.gd 管辖的瓦片。
# 刻意不调用 generate_all()/generate_tiles()：
#  - generate_player_frames/generate_npc_frames 会用程序画法覆盖素材包人物帧（陷阱）
#  - grass/grass_dark/path/farmland/water 已由 tools/import_pack_assets.py 接管
# 用法: <godot_exe> --headless --path <项目根> --script res://tools/regen_tiles.gd
const LOG := "res://tools/regen_log.txt"

func _init() -> void:
	var gen = load("res://scripts/texture_generator.gd").new()
	gen._rng.seed = 42  # 与运行时同种子，保证结果可复现
	gen._tile_sand()
	gen._tile_mountain()
	gen._tile_mountain_snow()
	gen._tile_tree_pine()
	gen._tile_tree_oak()
	gen._tile_tree_bamboo()
	gen._tile_house_town()
	gen._tile_house_cottage()
	gen._tile_house_temple()
	gen._tile_house_cave()
	gen._tile_flower()
	gen._tile_rock()
	gen._tile_fence()
	gen._tile_bridge()
	for w in [2, 3, 4, 5]:
		var parts: Array = gen.BUILDING_PARTS[w]
		for i in range(parts.size()):
			gen._draw_building_part(w, i, "res://sprites/tiles/%s.png" % parts[i])
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	if f:
		f.store_line("[Regen] generator-owned tiles regenerated OK")
		f.close()
	quit()
