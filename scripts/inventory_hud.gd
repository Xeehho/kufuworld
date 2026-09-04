extends Control

# Phase I: 背包面板（I键开关；9x5=45格，点格子使用消耗品/装备武器防具饰品）
# 数据源：/root/Main/InventoryManager（inventory_changed信号驱动刷新）

const PANEL_W := 480.0
const PANEL_H := 420.0
const COLS := 9
const ROWS := 5
const CELL := 44.0
const CELL_GAP := 6.0

# 物品类型底色（与inventory_manager类型常量对应）
const TYPE_COLORS := {
	0: Color(0.75, 0.30, 0.28),  # 武器-赤
	1: Color(0.30, 0.45, 0.75),  # 防具-青蓝
	2: Color(0.30, 0.68, 0.40),  # 消耗品-草绿
	3: Color(0.62, 0.50, 0.34),  # 材料-赭石
	4: Color(0.85, 0.70, 0.25),  # 秘籍-金
	5: Color(0.66, 0.40, 0.80),  # 饰品-紫
}
const TYPE_NAMES := {0: "武器", 1: "防具", 2: "消耗品", 3: "材料", 4: "秘籍", 5: "饰品"}

var panel: Panel = null
var title_lbl: Label = null
var grid_box: GridContainer = null
var detail_lbl: Label = null
var cells: Array = []          # 45个格子Panel
var cell_slots: Array = []     # 每格当前数据 {item, count} 或 null
var selected_idx: int = -1

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("ui_modal")
	_build_ui()
	var inv = _inv()
	if inv:
		inv.inventory_changed.connect(refresh)

func _inv():
	return get_node_or_null("/root/Main/InventoryManager")

func _build_ui():
	panel = Panel.new()
	panel.name = "InvPanel"
	UITheme.center_panel(panel, PANEL_W, PANEL_H)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	add_child(panel)

	var title = Label.new()
	title.text = "· 行 囊 ·"
	title.position = Vector2(0, 12)
	title.size = Vector2(PANEL_W, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(title, 16)
	panel.add_child(title)

	title_lbl = Label.new()
	title_lbl.position = Vector2(0, 38)
	title_lbl.size = Vector2(PANEL_W, 18)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(title_lbl, 12, UITheme.GOLD_DIM)
	panel.add_child(title_lbl)

	grid_box = GridContainer.new()
	grid_box.columns = COLS
	grid_box.add_theme_constant_override("h_separation", CELL_GAP)
	grid_box.add_theme_constant_override("v_separation", CELL_GAP)
	var grid_w = COLS * CELL + (COLS - 1) * CELL_GAP
	grid_box.position = Vector2((PANEL_W - grid_w) / 2, 62)
	panel.add_child(grid_box)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.11, 1.0)
	sb.border_color = Color(0.28, 0.26, 0.20)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)

	for i in range(COLS * ROWS):
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.focus_mode = Control.FOCUS_NONE
		cell.add_theme_stylebox_override("normal", sb)
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.14, 0.13, 0.10, 1.0)
		hover.border_color = UITheme.GOLD_DIM
		hover.set_border_width_all(1)
		hover.set_corner_radius_all(5)
		cell.add_theme_stylebox_override("hover", hover)
		var press := StyleBoxFlat.new()
		press.bg_color = Color(0.18, 0.16, 0.12, 1.0)
		press.border_color = UITheme.GOLD
		press.set_border_width_all(1)
		press.set_corner_radius_all(5)
		cell.add_theme_stylebox_override("pressed", press)
		cell.pressed.connect(_on_cell_click.bind(i))
		cell.mouse_entered.connect(_on_cell_hover.bind(i))
		grid_box.add_child(cell)
		cells.append(cell)
		cell_slots.append(null)

	detail_lbl = Label.new()
	detail_lbl.position = Vector2(24, PANEL_H - 76)
	detail_lbl.size = Vector2(PANEL_W - 48, 52)
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_label(detail_lbl, 12, UITheme.TEXT_DIM)
	panel.add_child(detail_lbl)

	var hint = Label.new()
	hint.text = "[I]/[ESC] 关闭   左键点格子：使用/装备"
	hint.position = Vector2(24, PANEL_H - 24)
	hint.size = Vector2(PANEL_W - 48, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(hint, 10, UITheme.TEXT_DIM)
	panel.add_child(hint)

# ---- 刷新与交互 ----

func refresh():
	if panel == null:
		return
	var inv = _inv()
	var used := 0
	if inv:
		used = inv.inventory.size()
	title_lbl.text = "%d / %d" % [used, inv.max_slots if inv else 45]
	var list: Array = inv.inventory if inv else []
	for i in range(cells.size()):
		var slot = list[i] if i < list.size() else null
		cell_slots[i] = slot
		_paint_cell(i)
	if selected_idx >= 0:
		if selected_idx < list.size():
			_show_detail(list[selected_idx]["item"])
		else:
			selected_idx = -1
			detail_lbl.text = ""

func _paint_cell(i: int):
	var cell = cells[i]
	# 清旧内容
	for child in cell.get_children():
		child.queue_free()
	var slot = cell_slots[i]
	if slot == null:
		return
	var item = slot["item"]
	var col: Color = TYPE_COLORS.get(item.item_type, Color(0.5, 0.5, 0.5))
	# 物品色块
	var block := ColorRect.new()
	block.color = Color(col.r, col.g, col.b, 0.85)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.position = Vector2(8, 8)
	block.size = Vector2(CELL - 16, CELL - 16)
	block.rotation = PI / 4.0  # 菱形，更有物品栏感
	block.position = Vector2(CELL / 2 - (CELL - 16) / 2 * 0.707, CELL / 2 - (CELL - 16) / 2 * 0.707)
	block.size = Vector2(CELL - 16, CELL - 16)
	cell.add_child(block)
	# 数量角标
	if slot["count"] > 1:
		var cnt := Label.new()
		cnt.text = str(slot["count"])
		cnt.position = Vector2(CELL - 22, CELL - 20)
		cnt.size = Vector2(20, 14)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.add_theme_font_size_override("font_size", 10)
		cnt.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
		cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		cnt.add_theme_constant_override("outline_size", 3)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cnt)

func _on_cell_hover(i: int):
	var slot = cell_slots[i]
	if slot:
		_show_detail(slot["item"])
	elif selected_idx < 0:
		detail_lbl.text = ""

func _on_cell_click(i: int):
	var slot = cell_slots[i]
	if slot == null:
		selected_idx = -1
		detail_lbl.text = ""
		return
	var inv = _inv()
	if inv == null:
		return
	var item = slot["item"]
	var t: int = item.item_type
	if t == 2 or t == 4:  # 消耗品/秘籍 → 使用
		if inv.use_item(item.item_id):
			_show_detail_msg("使用了「%s」" % item.item_name, UITheme.JADE)
		else:
			_show_detail_msg("「%s」无法使用" % item.item_name, UITheme.DANGER)
	elif t == 0 or t == 1 or t == 5:  # 武器/防具/饰品 → 装备
		if inv.equip_item(item.item_id):
			_show_detail_msg("装备了「%s」" % item.item_name, UITheme.JADE)
		else:
			_show_detail_msg("「%s」无法装备" % item.item_name, UITheme.DANGER)
	else:
		selected_idx = i
		_show_detail(item)

func _show_detail(item):
	var tname: String = TYPE_NAMES.get(item.item_type, "未知")
	var eff: String = item.get_effect_description() if item.has_method("get_effect_description") else ""
	detail_lbl.text = "[%s] %s  ×%s\n%s%s" % [tname, item.item_name, str(_count_of(item.item_id)), item.description, ("\n" + eff) if eff != "" else ""]

func _show_detail_msg(msg: String, col: Color):
	detail_lbl.text = msg
	UITheme.style_label(detail_lbl, 12, col)
	# 2秒后回归暗色（下次hover会重刷样式）
	var tw = create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func():
		if detail_lbl:
			UITheme.style_label(detail_lbl, 12, UITheme.TEXT_DIM))

func _count_of(item_id: String) -> int:
	var inv = _inv()
	return inv.get_item_count(item_id) if inv else 0

# ---- 开关 ----

func toggle():
	visible = not visible
	if visible:
		refresh()
		panel.modulate = Color(1, 1, 1, 0)
		var tw = create_tween()
		tw.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.15)

func close():
	if visible:
		visible = false

func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed):
		return
	if visible:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_I:
			# 面板已开：I/ESC 关闭（对话/商店优先）
			if DialogManager.is_dialog_open():
				return
			var shop_hud = get_node_or_null("/root/Main/World/UI/ShopHUD")
			if shop_hud and shop_hud.is_open:
				return
			close()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_I:
		# 面板未开：I 打开（避开对话/商店/建造/奇遇）
		if DialogManager.is_dialog_open() or GameManager.is_build_mode:
			return
		var shop_hud2 = get_node_or_null("/root/Main/World/UI/ShopHUD")
		if shop_hud2 and shop_hud2.is_open:
			return
		var quick_menu = get_node_or_null("/root/Main/World/UI/QuickMenu")
		if quick_menu and quick_menu.is_panel_open():
			return
		toggle()
		get_viewport().set_input_as_handled()
