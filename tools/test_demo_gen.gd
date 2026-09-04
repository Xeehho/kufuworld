extends SceneTree

## P5 调试：独立跑 generate_demo_buildings 复现合成器运行时错误（--script 模式）

func _init():
	print("[TestGen] begin")
	var g := Node.new()
	g.set_script(load("res://scripts/texture_generator.gd"))
	root.add_child(g)
	g.generate_demo_buildings()
	print("[TestGen] GEN OK")
	quit()
