extends SceneTree
# 2026-08-31 大建筑中式化重制后的窄域重生成：
# 只调用 generate_big_buildings()/generate_city_props()（缺失才写），
# 禁止 generate_all()（会覆盖素材包人物帧，见 docs/开发必读-陷阱备忘.md §一1）
# 用法: 先删除 sprites/buildings/ 下需要重制的建筑PNG，再执行
#   <godot_exe> --headless --path <项目根> --script res://tools/regen_cn_buildings.gd
const LOG := "res://tools/regen_log.txt"

func _init() -> void:
	var gen = load("res://scripts/texture_generator.gd").new()
	gen.generate_big_buildings()
	gen.generate_city_props()
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	if f:
		f.store_line("[Regen] cn buildings regenerated OK")
		f.close()
	quit()
