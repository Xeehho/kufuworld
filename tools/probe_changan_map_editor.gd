extends SceneTree

const TEMPLATE := "res://scenes/changan_manual_map.tscn"
const PLUGIN := "res://addons/changan_map_editor/changan_map_editor_plugin.gd"


func _initialize() -> void:
	var fails: Array[String] = []
	var scene: PackedScene = load(TEMPLATE)
	if scene == null:
		fails.append("手拼模板无法加载")
	else:
		var root := scene.instantiate()
		if not bool(root.get_meta("changan_manual_map", false)):
			fails.append("模板缺 changan_manual_map 标记")
		for path in ["Guide", "ManualGround", "YSortContent", "ManualForeground"]:
			if root.get_node_or_null(path) == null:
				fails.append("模板缺节点 %s" % path)
		if root.get_node_or_null("YSortContent") != null and not root.get_node("YSortContent").y_sort_enabled:
			fails.append("YSortContent 未开启 Y-sort")
		root.free()
	var plugin_script: Script = load(PLUGIN)
	if plugin_script == null or not plugin_script.can_instantiate():
		fails.append("编辑器插件脚本无法加载")
	var material_count := _count_materials()
	var pack_count := _count_pack_assets()
	if material_count < 100:
		fails.append("原生材质少于100件（实=%d）" % material_count)
	if pack_count < 200:
		fails.append("SCKR材质少于200件（实=%d）" % pack_count)
	if fails.is_empty():
		print("[ChanganMapEditor][PASS] 模板/脚本齐备 原生=%d SCKR=%d" % [
				material_count, pack_count])
		quit(0)
	else:
		for fail in fails:
			print("[ChanganMapEditor][FAIL] %s" % fail)
		quit(1)


func _count_materials() -> int:
	var data := _read_json("res://data/material_library.json")
	var total := 0
	for category in Dictionary(data.get("categories", {})).values():
		total += Array(category.get("pieces", [])).size()
	return total


func _count_pack_assets() -> int:
	var data := _read_json("res://data/sckr_manifest.json")
	return Array(data.get("assets", [])).size()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
