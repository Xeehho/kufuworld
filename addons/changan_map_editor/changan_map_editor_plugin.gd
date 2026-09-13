@tool
extends EditorPlugin

const GRID_SIZE := 16.0
const TEMPLATE_SCENE := "res://scenes/changan_manual_map.tscn"
const MATERIAL_MANIFEST := "res://data/material_library.json"
const PACK_MANIFEST := "res://data/sckr_manifest.json"

var dock: VBoxContainer
var category_select: OptionButton
var search_edit: LineEdit
var asset_list: ItemList
var native_only_check: CheckBox
var layer_select: OptionButton
var place_button: Button
var delete_button: Button
var guide_button: Button
var status_label: Label

var assets: Array[Dictionary] = []
var categories: Array[String] = []
var selected_asset: Dictionary = {}


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	dock = VBoxContainer.new()
	dock.name = "长安手拼"
	dock.custom_minimum_size = Vector2(300, 520)
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_load_assets()
	_rebuild_categories()
	_rebuild_asset_list()


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()


func _handles(_object: Object) -> bool:
	return _manual_root() != null


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	var root := _manual_root()
	if root == null:
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		place_button.button_pressed = false
		delete_button.button_pressed = false
		_set_status("已退出放置/删除模式；现在可用 Godot 自带选择与移动。")
		return false
	if not (event is InputEventMouseButton) or not event.pressed:
		return false
	if event.button_index == MOUSE_BUTTON_LEFT and place_button.button_pressed:
		if selected_asset.is_empty():
			_set_status("请先从缩略图中选择素材。")
			return true
		_place_asset(root, event.position)
		return true
	if event.button_index == MOUSE_BUTTON_RIGHT and delete_button.button_pressed:
		var target := _asset_at_screen_position(root, event.position)
		if target != null:
			_delete_nodes([target])
		return true
	return false


func _build_dock() -> void:
	var title := Label.new()
	title.text = "长安手拼工作台"
	title.add_theme_font_size_override("font_size", 18)
	dock.add_child(title)

	var tip := Label.new()
	tip.text = "原尺寸 1:1 · 16px 网格 · 建筑底边锚\n先选素材，再在 2D 视图左键放置。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(tip)

	var open_button := Button.new()
	open_button.text = "打开长安手拼场景"
	open_button.pressed.connect(_open_template)
	dock.add_child(open_button)

	native_only_check = CheckBox.new()
	native_only_check.text = "只显示原生素材（推荐）"
	native_only_check.button_pressed = true
	native_only_check.toggled.connect(_on_native_filter_changed)
	dock.add_child(native_only_check)

	category_select = OptionButton.new()
	category_select.item_selected.connect(_on_filter_changed)
	dock.add_child(category_select)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "搜索素材名"
	search_edit.text_changed.connect(_on_search_changed)
	dock.add_child(search_edit)

	asset_list = ItemList.new()
	asset_list.custom_minimum_size = Vector2(280, 300)
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_list.icon_mode = ItemList.ICON_MODE_TOP
	asset_list.fixed_icon_size = Vector2i(96, 72)
	asset_list.max_columns = 2
	asset_list.same_column_width = true
	asset_list.allow_reselect = true
	asset_list.item_selected.connect(_on_asset_selected)
	dock.add_child(asset_list)

	var layer_label := Label.new()
	layer_label.text = "放置图层"
	dock.add_child(layer_label)
	layer_select = OptionButton.new()
	layer_select.add_item("建筑/道具（Y-sort）", 0)
	layer_select.add_item("地面", 1)
	layer_select.add_item("前景", 2)
	dock.add_child(layer_select)

	var mode_grid := GridContainer.new()
	mode_grid.columns = 2
	dock.add_child(mode_grid)
	place_button = Button.new()
	place_button.text = "放置模式"
	place_button.toggle_mode = true
	place_button.toggled.connect(_on_place_toggled)
	mode_grid.add_child(place_button)
	delete_button = Button.new()
	delete_button.text = "右键删除模式"
	delete_button.toggle_mode = true
	delete_button.toggled.connect(_on_delete_toggled)
	mode_grid.add_child(delete_button)

	var edit_grid := GridContainer.new()
	edit_grid.columns = 2
	dock.add_child(edit_grid)
	var flip_button := Button.new()
	flip_button.text = "镜像所选"
	flip_button.pressed.connect(_flip_selected)
	edit_grid.add_child(flip_button)
	var snap_button := Button.new()
	snap_button.text = "所选对齐16px"
	snap_button.pressed.connect(_snap_selected)
	edit_grid.add_child(snap_button)
	var remove_button := Button.new()
	remove_button.text = "删除所选"
	remove_button.pressed.connect(_delete_selected)
	edit_grid.add_child(remove_button)
	guide_button = Button.new()
	guide_button.text = "隐藏/显示参考底图"
	guide_button.pressed.connect(_toggle_guide)
	edit_grid.add_child(guide_button)

	status_label = Label.new()
	status_label.text = "打开手拼场景后开始。"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 72
	dock.add_child(status_label)


func _open_template() -> void:
	get_editor_interface().open_scene_from_path(TEMPLATE_SCENE)
	_set_status("已打开模板。建议先用“场景 → 另存为”保存你的版本。")


func _load_assets() -> void:
	assets.clear()
	_load_material_library()
	_load_pack_library()
	assets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["category"]) + String(a["id"]) < String(b["category"]) + String(b["id"])
	)


func _load_material_library() -> void:
	var data := _read_json(MATERIAL_MANIFEST)
	if data.is_empty():
		return
	var category_data: Dictionary = data.get("categories", {})
	for category in category_data.keys():
		var entry: Dictionary = category_data[category]
		for piece_value in entry.get("pieces", []):
			var piece: Dictionary = piece_value
			var path := "res://素材库/%s/%s" % [String(category), String(piece.get("file", ""))]
			if not FileAccess.file_exists(path):
				continue
			assets.append({
				"id": String(piece.get("id", "未命名")),
				"path": path,
				"category": String(category),
				"kind": String(entry.get("kind", "prop")),
				"native": true,
				"anchor": "top_left" if String(category).begins_with("00_") else "bottom_center",
				"w": int(piece.get("w", 0)),
				"h": int(piece.get("h", 0)),
			})


func _load_pack_library() -> void:
	var data := _read_json(PACK_MANIFEST)
	if data.is_empty():
		return
	for value in data.get("assets", []):
		var item: Dictionary = value
		var name := String(item.get("name", ""))
		var kind := String(item.get("kind", "prop"))
		var is_ai := String(item.get("source_kind", "")) == "imagegen"
		var root := "res://sprites/changan_props_sckr/"
		if is_ai:
			root = "res://sprites/changan_ai/"
		elif kind in ["tile", "composite_tile"]:
			root = "res://sprites/tiles_changan_sckr/"
		var path := root + name + ".png"
		if not FileAccess.file_exists(path):
			continue
		var box: Array = item.get("box", [0, 0, 0, 0])
		assets.append({
			"id": name,
			"path": path,
			"category": "AI补件（像素风格待定）" if is_ai else "SCKR/%s" % String(item.get("category", "道具")),
			"kind": kind,
			"native": not is_ai,
			"anchor": "top_left" if kind in ["tile", "composite_tile"] else "bottom_center",
			"w": int(box[2]) - int(box[0]),
			"h": int(box[3]) - int(box[1]),
		})


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[长安手拼] 无法读取 %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("[长安手拼] JSON 解析失败 %s" % path)
		return {}
	return parsed


func _rebuild_categories() -> void:
	var previous := "全部分类"
	if category_select.item_count > 0:
		previous = category_select.get_item_text(category_select.selected)
	categories.clear()
	for asset in assets:
		if native_only_check.button_pressed and not bool(asset["native"]):
			continue
		var category := String(asset["category"])
		if not categories.has(category):
			categories.append(category)
	categories.sort()
	category_select.clear()
	category_select.add_item("全部分类")
	for category in categories:
		category_select.add_item(category)
	var restore_index := 0
	for i in range(category_select.item_count):
		if category_select.get_item_text(i) == previous:
			restore_index = i
			break
	category_select.select(restore_index)


func _rebuild_asset_list() -> void:
	asset_list.clear()
	var category := category_select.get_item_text(category_select.selected) \
			if category_select.item_count > 0 else "全部分类"
	var query := search_edit.text.strip_edges().to_lower()
	var shown := 0
	for asset in assets:
		if native_only_check.button_pressed and not bool(asset["native"]):
			continue
		if category != "全部分类" and String(asset["category"]) != category:
			continue
		if query != "" and query not in String(asset["id"]).to_lower():
			continue
		var texture: Texture2D = load(String(asset["path"]))
		if texture == null:
			continue
		var listed_asset: Dictionary = asset.duplicate()
		listed_asset["w"] = texture.get_width()
		listed_asset["h"] = texture.get_height()
		var index := asset_list.add_item(String(asset["id"]), texture, true)
		asset_list.set_item_metadata(index, listed_asset)
		asset_list.set_item_tooltip(index, "%s\n%s\n%d×%d px" % [
				String(asset["category"]), String(asset["path"]),
				texture.get_width(), texture.get_height()])
		shown += 1
	_set_status("素材 %d/%d；原生筛选=%s。" % [shown, assets.size(),
			"开" if native_only_check.button_pressed else "关"])


func _on_native_filter_changed(_pressed: bool) -> void:
	selected_asset = {}
	place_button.button_pressed = false
	_rebuild_categories()
	_rebuild_asset_list()


func _on_filter_changed(_index: int) -> void:
	_rebuild_asset_list()


func _on_search_changed(_text: String) -> void:
	_rebuild_asset_list()


func _on_asset_selected(index: int) -> void:
	selected_asset = asset_list.get_item_metadata(index)
	place_button.button_pressed = true
	delete_button.button_pressed = false
	if String(selected_asset["anchor"]) == "top_left":
		layer_select.select(1)
	else:
		layer_select.select(0)
	_set_status("已选 %s｜%d×%d px（%.1f×%.1f 格）｜原尺寸1:1" % [
			String(selected_asset["id"]), int(selected_asset["w"]), int(selected_asset["h"]),
			float(selected_asset["w"]) / GRID_SIZE, float(selected_asset["h"]) / GRID_SIZE])


func _on_place_toggled(pressed: bool) -> void:
	if pressed:
		delete_button.button_pressed = false
		_set_status("放置模式：在 2D 视图左键放置；Esc 退出。")


func _on_delete_toggled(pressed: bool) -> void:
	if pressed:
		place_button.button_pressed = false
		_set_status("删除模式：在素材上点右键删除；支持 Ctrl+Z。")


func _place_asset(root: Node2D, screen_position: Vector2) -> void:
	var texture: Texture2D = load(String(selected_asset["path"]))
	if texture == null:
		_set_status("贴图载入失败：%s" % String(selected_asset["path"]))
		return
	var world_position := _screen_to_world(screen_position)
	var local_position := root.to_local(world_position)
	local_position = Vector2(round(local_position.x / GRID_SIZE) * GRID_SIZE,
			round(local_position.y / GRID_SIZE) * GRID_SIZE)
	var parent := _target_parent(root)
	if parent == null:
		_set_status("手拼场景缺少目标图层，请重新打开模板。")
		return
	var sprite := Sprite2D.new()
	sprite.name = String(selected_asset["id"])
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = local_position
	sprite.scale = Vector2.ONE
	if String(selected_asset["anchor"]) == "top_left":
		sprite.centered = false
	else:
		sprite.centered = true
		sprite.offset = Vector2(0.0, -texture.get_height() * 0.5)
	sprite.set_meta("changan_asset_id", String(selected_asset["id"]))
	sprite.set_meta("changan_asset_path", String(selected_asset["path"]))
	sprite.set_meta("changan_anchor", String(selected_asset["anchor"]))
	sprite.set_meta("changan_layer", layer_select.selected)
	sprite.set_meta("native_scale", Vector2.ONE)

	var undo_redo := get_undo_redo()
	undo_redo.create_action("放置长安素材：%s" % sprite.name, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(parent, "add_child", sprite, true)
	undo_redo.add_do_method(sprite, "set_owner", root)
	undo_redo.add_do_reference(sprite)
	undo_redo.add_undo_method(parent, "remove_child", sprite)
	undo_redo.commit_action()
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(sprite)
	_set_status("已放置 %s @ (%d, %d)，可 Ctrl+Z 撤销。" % [sprite.name,
			int(local_position.x), int(local_position.y)])


func _target_parent(root: Node2D) -> Node:
	match layer_select.selected:
		1: return root.get_node_or_null("ManualGround")
		2: return root.get_node_or_null("ManualForeground")
		_: return root.get_node_or_null("YSortContent")


func _screen_to_world(screen_position: Vector2) -> Vector2:
	var viewport := get_editor_interface().get_editor_viewport_2d()
	return viewport.global_canvas_transform.affine_inverse() * screen_position


func _asset_at_screen_position(root: Node2D, screen_position: Vector2) -> Sprite2D:
	var world_position := _screen_to_world(screen_position)
	var candidates: Array[Sprite2D] = []
	for node in root.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if sprite == null or not sprite.has_meta("changan_asset_id"):
			continue
		if sprite.get_rect().has_point(sprite.to_local(world_position)):
			candidates.append(sprite)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: Sprite2D, b: Sprite2D) -> bool:
		return a.global_position.y > b.global_position.y
	)
	return candidates[0]


func _selected_manual_nodes() -> Array[Node]:
	var root := _manual_root()
	var result: Array[Node] = []
	if root == null:
		return result
	for node in get_editor_interface().get_selection().get_selected_nodes():
		if node is Sprite2D and node.has_meta("changan_asset_id") and root.is_ancestor_of(node):
			result.append(node)
	return result


func _flip_selected() -> void:
	var nodes := _selected_manual_nodes()
	if nodes.is_empty():
		_set_status("请先选择一个或多个已放置素材。")
		return
	var root := _manual_root()
	var undo_redo := get_undo_redo()
	undo_redo.create_action("镜像长安素材", UndoRedo.MERGE_DISABLE, root)
	for node in nodes:
		var sprite := node as Sprite2D
		undo_redo.add_do_property(sprite, "flip_h", not sprite.flip_h)
		undo_redo.add_undo_property(sprite, "flip_h", sprite.flip_h)
	undo_redo.commit_action()
	_set_status("已镜像 %d 个素材。" % nodes.size())


func _snap_selected() -> void:
	var nodes := _selected_manual_nodes()
	if nodes.is_empty():
		_set_status("请先选择一个或多个已放置素材。")
		return
	var root := _manual_root()
	var undo_redo := get_undo_redo()
	undo_redo.create_action("对齐长安素材到16px", UndoRedo.MERGE_DISABLE, root)
	for node in nodes:
		var item := node as Node2D
		var snapped := Vector2(round(item.position.x / GRID_SIZE) * GRID_SIZE,
				round(item.position.y / GRID_SIZE) * GRID_SIZE)
		undo_redo.add_do_property(item, "position", snapped)
		undo_redo.add_undo_property(item, "position", item.position)
	undo_redo.commit_action()
	_set_status("已将 %d 个素材对齐到 16px 网格。" % nodes.size())


func _delete_selected() -> void:
	_delete_nodes(_selected_manual_nodes())


func _delete_nodes(nodes: Array) -> void:
	if nodes.is_empty():
		_set_status("没有可删除的手拼素材。")
		return
	var root := _manual_root()
	var undo_redo := get_undo_redo()
	undo_redo.create_action("删除长安素材", UndoRedo.MERGE_DISABLE, root)
	for node in nodes:
		var parent: Node = node.get_parent()
		undo_redo.add_do_method(parent, "remove_child", node)
		undo_redo.add_undo_method(parent, "add_child", node, true)
		undo_redo.add_undo_method(node, "set_owner", root)
		undo_redo.add_undo_reference(node)
	undo_redo.commit_action()
	_set_status("已删除 %d 个素材，可 Ctrl+Z 恢复。" % nodes.size())


func _toggle_guide() -> void:
	var root := _manual_root()
	if root == null:
		_set_status("请先打开长安手拼场景。")
		return
	var guide := root.get_node_or_null("Guide") as CanvasItem
	if guide == null:
		return
	var undo_redo := get_undo_redo()
	undo_redo.create_action("显示/隐藏长安参考底图", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_property(guide, "visible", not guide.visible)
	undo_redo.add_undo_property(guide, "visible", guide.visible)
	undo_redo.commit_action()


func _manual_root() -> Node2D:
	var root := get_editor_interface().get_edited_scene_root()
	if root is Node2D and bool(root.get_meta("changan_manual_map", false)):
		return root
	return null


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
