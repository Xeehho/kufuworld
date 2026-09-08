extends Node
## Tiled 导入验证探针（2026-09-08）：SubViewport 全图渲染导入场景 → 存 PNG
## 与 docs/参考/tiled_work/_parsed_rebuild.png（python 端 D→H→V 复刻渲染）逐像素对比
## 运行: godot --headless --path . res://tools/probe_tiled_import.tscn

const MAP_W := 100
const MAP_H := 60
const TS := 16

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/tiled_outer_city_wall.tscn")
	if scene == null:
		print("[TiledImport][FAIL] 场景加载失败")
		get_tree().quit(2)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(MAP_W * TS, MAP_H * TS)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var holder := Node2D.new()
	vp.add_child(holder)
	holder.add_child(scene.instantiate())
	var cam := Camera2D.new()
	cam.position = Vector2(MAP_W * TS / 2.0, MAP_H * TS / 2.0)
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	cam.position = Vector2(0, 0)
	holder.add_child(cam)
	cam.make_current()
	# 等构建（_ready 同步）+ 渲染两帧
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = vp.get_texture().get_image()
	var out := "res://docs/shots/tiled_import_render.png"
	img.save_png(out)
	print("[TiledImport] 渲染 %dx%d -> %s" % [img.get_width(), img.get_height(), out])
	# 统计非空像素（应远大于 0；地图含地面层铺装）
	var n := 0
	for y in range(0, img.get_height(), 7):
		for x in range(0, img.get_width(), 7):
			if img.get_pixel(x, y).a > 0.1:
				n += 1
	print("[TiledImport] 采样非空像素=%d/737" % [n])
	if n < 600:
		print("[TiledImport][FAIL] 画面大部分为空（图层未铺上）")
		get_tree().quit(2)
		return
	print("[TiledImport][PASS] 地图已渲染")
	get_tree().quit(0)
