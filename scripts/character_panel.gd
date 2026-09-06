extends Control

const TextureGen = preload("res://scripts/texture_generator.gd")

# 统一角色面板 v2（剑网三/易水寒式左右结构）：
#   左区「侠者」= 头像/称号/门派职位 + 四状态条 + 装备三槽横排 + 装备加成
#   右区「行囊」= 45格背包 + 物品详情 + 江湖履历
# 打开入口：V键 / I键 / 左上角头像点击（SurvivalHUD）；ESC或V/I关闭
# 数据源：GameManager + /root/Main/InventoryManager（装备槽/背包）

const PANEL_W := 980.0
const PANEL_H := 620.0
const COLS := 9
const ROWS := 5
const CELL := 44.0
const CELL_GAP := 6.0

const TYPE_COLORS := {
	0: Color(0.75, 0.30, 0.28), 1: Color(0.30, 0.45, 0.75), 2: Color(0.30, 0.68, 0.40),
	3: Color(0.62, 0.50, 0.34), 4: Color(0.85, 0.70, 0.25), 5: Color(0.66, 0.40, 0.80),
}
const TYPE_NAMES := {0: "武器", 1: "防具", 2: "消耗品", 3: "材料", 4: "秘籍", 5: "饰品"}

var panel: Panel = null
var portrait: TextureRect = null
var title_lbl: Label = null
var faction_lbl: Label = null
var bars: Dictionary = {}
var attr_labels: Dictionary = {}
var bag_title: Label = null
var detail_lbl: Label = null
var grid_box: GridContainer = null
var cells: Array = []
var cell_slots: Array = []
var equip_slots: Dictionary = {}
var stat_lbl: Label = null
var selected_idx: int = -1

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("ui_modal")
	_build_ui()
	# 双外观切换：清空头像缓存，下次 open() 按新外观重裁
	GameManager.player_appearance_changed.connect(func(_app): portrait.texture = null)
	var inv = _inv()
	if inv:
		inv.inventory_changed.connect(refresh_all)
		inv.equipment_changed.connect(refresh_all)
	# 手持工具变化实时刷新（面板常开时）
	var pl = get_node_or_null("/root/Main/World/Player")
	if pl and pl.has_signal("tool_changed"):
		pl.tool_changed.connect(func(_n): refresh_equips())

func _inv():
	return get_node_or_null("/root/Main/InventoryManager")

# ---------- 总布局 ----------

func _build_ui():
	panel = Panel.new()
	panel.name = "CharacterPanelRoot"
	UITheme.center_panel(panel, PANEL_W, PANEL_H)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	add_child(panel)

	var title = Label.new()
	title.text = "· 侠 者 ·"
	title.position = Vector2(0, 10)
	title.size = Vector2(PANEL_W, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(title, 18)
	panel.add_child(title)

	# 左区：侠者档案（人物+装备）
	var left := Panel.new()
	left.name = "LeftZone"
	left.position = Vector2(24, 50)
	left.size = Vector2(452, 546)
	left.add_theme_stylebox_override("panel", UITheme.inset_style())
	panel.add_child(left)
	_build_left(left)

	# 右区：行囊 + 江湖履历
	var right := Panel.new()
	right.name = "RightZone"
	right.position = Vector2(492, 50)
	right.size = Vector2(464, 546)
	right.add_theme_stylebox_override("panel", UITheme.inset_style())
	panel.add_child(right)
	_build_right(right)

	var hint = Label.new()
	hint.text = "[V]/[I]/[ESC] 关闭 · 左键物品：使用/装备 · 点击装备槽：卸下"
	hint.position = Vector2(0, PANEL_H - 26)
	hint.size = Vector2(PANEL_W, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(hint, 10, UITheme.TEXT_DIM)
	panel.add_child(hint)

func _zone_header(parent: Control, text: String, w: float, y: float = 12.0):
	"""分区金色标题+分隔线（左右区统一风格）"""
	var t := Label.new()
	t.text = text
	t.position = Vector2(0, y)
	t.size = Vector2(w, 22)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(t, 15)
	parent.add_child(t)
	var div := ColorRect.new()
	div.color = UITheme.GOLD_DIM
	div.position = Vector2(20, y + 24)
	div.size = Vector2(w - 40, 1)
	parent.add_child(div)

# ---------- 左区：侠者 ----------

func _build_left(left: Panel):
	_zone_header(left, "侠 者", 452)

	# 头像框
	var av_bg := Panel.new()
	av_bg.position = Vector2(20, 48)
	av_bg.size = Vector2(104, 104)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.13, 1.0)
	sb.border_color = UITheme.GOLD_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	av_bg.add_theme_stylebox_override("panel", sb)
	left.add_child(av_bg)
	portrait = TextureRect.new()
	portrait.position = Vector2(6, 6)
	portrait.size = Vector2(92, 92)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	av_bg.add_child(portrait)

	title_lbl = Label.new()
	title_lbl.position = Vector2(140, 62)
	title_lbl.size = Vector2(290, 30)
	UITheme.style_label(title_lbl, 17, UITheme.GOLD)
	left.add_child(title_lbl)
	faction_lbl = Label.new()
	faction_lbl.position = Vector2(140, 98)
	faction_lbl.size = Vector2(290, 44)
	faction_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_label(faction_lbl, 12, UITheme.TEXT_DIM)
	left.add_child(faction_lbl)

	# 状态条
	var stat_defs := [
		["health", "伤势", Color(0.9, 0.25, 0.25)],
		["hunger", "饥饿", Color(0.95, 0.6, 0.2)],
		["qi", "内力", Color(0.3, 0.7, 1.0)],
		["poison", "中毒", Color(0.6, 0.2, 0.8)],
	]
	var y := 166.0
	for d in stat_defs:
		_make_bar(left, d[0], d[1], d[2], 24.0, y)
		y += 44.0

	# 装备小节
	var eq_t := Label.new()
	eq_t.text = "—— 装 备 ——"
	eq_t.position = Vector2(0, 348)
	eq_t.size = Vector2(452, 20)
	eq_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(eq_t, 13, UITheme.GOLD_DIM)
	left.add_child(eq_t)

	var slot_defs := [
		["weapon", "武器", Color(0.75, 0.30, 0.28)],
		["armor", "防具", Color(0.30, 0.45, 0.75)],
		["accessory", "饰品", Color(0.66, 0.40, 0.80)],
	]
	var x := 30.0
	for d in slot_defs:
		var slot := Panel.new()
		slot.position = Vector2(x, 378)
		slot.size = Vector2(76, 76)
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Color(0.09, 0.09, 0.11, 1.0)
		ssb.border_color = Color(0.28, 0.26, 0.20)
		ssb.set_border_width_all(1)
		ssb.set_corner_radius_all(6)
		slot.add_theme_stylebox_override("panel", ssb)
		slot.tooltip_text = d[1] + "槽 · 点击卸下"
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_equip_slot_click.bind(d[0]))
		btn.mouse_entered.connect(_on_equip_slot_hover.bind(d[0]))
		slot.add_child(btn)
		left.add_child(slot)

		var name_lbl := Label.new()
		name_lbl.position = Vector2(x - 12, 460)
		name_lbl.size = Vector2(100, 40)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		left.add_child(name_lbl)
		equip_slots[d[0]] = {"slot": slot, "lbl": name_lbl, "disp": d[1], "color": d[2]}
		x += 140.0

	# 装备加成 + 手持工具（两行）
	stat_lbl = Label.new()
	stat_lbl.position = Vector2(0, 498)
	stat_lbl.size = Vector2(452, 46)
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_label(stat_lbl, 12, UITheme.JADE)
	left.add_child(stat_lbl)

func _make_bar(parent: Control, key: String, disp: String, color: Color, x: float, y: float):
	var lbl := Label.new()
	lbl.text = disp
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(200, 14)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	parent.add_child(lbl)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.position = Vector2(x, y + 16)
	bar.size = Vector2(360, 14)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.09, 0.09, 0.12, 0.95)
	bg_sb.set_corner_radius_all(3)
	bg_sb.border_color = Color(0.25, 0.22, 0.15)
	bg_sb.set_border_width_all(1)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = color
	fill_sb.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg_sb)
	bar.add_theme_stylebox_override("fill", fill_sb)
	parent.add_child(bar)
	var val := Label.new()
	val.position = Vector2(x + 366, y + 15)
	val.size = Vector2(50, 14)
	val.add_theme_font_size_override("font_size", 9)
	val.add_theme_color_override("font_color", color)
	parent.add_child(val)
	bars[key] = {"bar": bar, "val": val}

# ---------- 右区：行囊 + 履历 ----------

func _build_right(right: Panel):
	bag_title = Label.new()
	bag_title.text = "行 囊 0/45"
	bag_title.position = Vector2(0, 12)
	bag_title.size = Vector2(464, 22)
	bag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(bag_title, 15)
	right.add_child(bag_title)
	var div0 := ColorRect.new()
	div0.color = UITheme.GOLD_DIM
	div0.position = Vector2(20, 36)
	div0.size = Vector2(424, 1)
	right.add_child(div0)

	grid_box = GridContainer.new()
	grid_box.columns = COLS
	grid_box.add_theme_constant_override("h_separation", CELL_GAP)
	grid_box.add_theme_constant_override("v_separation", CELL_GAP)
	grid_box.position = Vector2(10, 46)
	right.add_child(grid_box)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.11, 1.0)
	sb.border_color = Color(0.28, 0.26, 0.20)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.14, 0.13, 0.10, 1.0)
	hover.border_color = UITheme.GOLD_DIM
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(5)
	var press := StyleBoxFlat.new()
	press.bg_color = Color(0.18, 0.16, 0.12, 1.0)
	press.border_color = UITheme.GOLD
	press.set_border_width_all(1)
	press.set_corner_radius_all(5)

	for i in range(COLS * ROWS):
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.focus_mode = Control.FOCUS_NONE
		cell.add_theme_stylebox_override("normal", sb)
		cell.add_theme_stylebox_override("hover", hover)
		cell.add_theme_stylebox_override("pressed", press)
		cell.pressed.connect(_on_cell_click.bind(i))
		cell.mouse_entered.connect(_on_cell_hover.bind(i))
		grid_box.add_child(cell)
		cells.append(cell)
		cell_slots.append(null)

	detail_lbl = Label.new()
	detail_lbl.position = Vector2(20, 302)
	detail_lbl.size = Vector2(424, 66)
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_label(detail_lbl, 12, UITheme.TEXT_DIM)
	right.add_child(detail_lbl)

	var div1 := ColorRect.new()
	div1.color = UITheme.GOLD_DIM
	div1.position = Vector2(20, 378)
	div1.size = Vector2(424, 1)
	right.add_child(div1)
	var his_t := Label.new()
	his_t.text = "—— 江 湖 履 历 ——"
	his_t.position = Vector2(0, 386)
	his_t.size = Vector2(464, 20)
	his_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(his_t, 13, UITheme.GOLD_DIM)
	right.add_child(his_t)

	var attrs := [
		["morality", "道德"], ["reputation", "声望"],
		["gold", "盘缠"], ["wood", "木料"],
		["stone", "石料"], ["clan", "门派"],
		["rank", "职位"], ["contribution", "贡献"],
		["inner", "内功"], ["env", "环境"],
	]
	var ay := 414.0
	for i in range(attrs.size()):
		var col := i % 2
		var row := int(i / 2)
		var lbl := Label.new()
		lbl.name = "Attr_" + attrs[i][0]
		lbl.position = Vector2(34 + col * 216.0, ay + row * 24.0)
		lbl.size = Vector2(210, 22)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", UITheme.TEXT_MAIN)
		right.add_child(lbl)
		attr_labels[attrs[i][0]] = {"lbl": lbl, "name": attrs[i][1]}

# ---------- 刷新 ----------

func refresh_all():
	if not visible:
		return
	refresh_values()
	refresh_bag()
	refresh_equips()

func refresh_values():
	bars["health"]["bar"].value = GameManager.health
	bars["health"]["val"].text = str(int(GameManager.health))
	bars["hunger"]["bar"].value = GameManager.hunger
	bars["hunger"]["val"].text = str(int(GameManager.hunger))
	bars["qi"]["bar"].max_value = maxf(1.0, GameManager.max_qi)
	bars["qi"]["bar"].value = GameManager.qi
	bars["qi"]["val"].text = "%d/%d" % [int(GameManager.qi), int(GameManager.max_qi)]
	bars["poison"]["bar"].value = GameManager.poison
	bars["poison"]["val"].text = str(int(GameManager.poison))

	title_lbl.text = _title_for(GameManager.reputation)
	var clan_txt: String = "无门无派 · 江湖散人" if GameManager.player_clan == null else str(GameManager.player_clan.clan_name)
	var rank_txt := ""
	if GameManager.player_clan != null:
		rank_txt = " · " + GameManager.CLAN_RANKS[clampi(GameManager.player_rank, 0, GameManager.CLAN_RANKS.size() - 1)]
	faction_lbl.text = clan_txt + rank_txt
	var inner_txt := "未修炼"
	if GameManager.active_inner_skill != null:
		inner_txt = GameManager.active_inner_skill.skill_name
	var env_txt := "江湖" if GameManager.current_environment == "" else GameManager.current_environment
	attr_labels["morality"]["lbl"].text = attr_labels["morality"]["name"] + "：" + str(int(GameManager.morality))
	attr_labels["reputation"]["lbl"].text = attr_labels["reputation"]["name"] + "：" + str(int(GameManager.reputation))
	attr_labels["gold"]["lbl"].text = attr_labels["gold"]["name"] + "：" + str(GameManager.gold) + " 两"
	attr_labels["wood"]["lbl"].text = attr_labels["wood"]["name"] + "：" + str(GameManager.wood)
	attr_labels["stone"]["lbl"].text = attr_labels["stone"]["name"] + "：" + str(GameManager.stone)
	attr_labels["clan"]["lbl"].text = attr_labels["clan"]["name"] + "：" + clan_txt
	attr_labels["rank"]["lbl"].text = attr_labels["rank"]["name"] + "：" + rank_txt.lstrip(" · ")
	attr_labels["contribution"]["lbl"].text = attr_labels["contribution"]["name"] + "：" + str(GameManager.contribution)
	attr_labels["inner"]["lbl"].text = attr_labels["inner"]["name"] + "：" + inner_txt
	attr_labels["env"]["lbl"].text = attr_labels["env"]["name"] + "：" + env_txt

func _title_for(rep: float) -> String:
	if rep >= 200: return "「武林泰斗」"
	if rep >= 100: return "「名动一方」"
	if rep >= 50: return "「小有名气」"
	if rep >= 0: return "「无名少侠」"
	return "「恶名远扬」"

func refresh_bag():
	var inv = _inv()
	var used := 0
	if inv:
		used = inv.inventory.size()
	bag_title.text = "行 囊 %d/%d" % [used, inv.max_slots if inv else 45]
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
	for child in cell.get_children():
		child.queue_free()
	var slot = cell_slots[i]
	if slot == null:
		return
	var item = slot["item"]
	var col: Color = TYPE_COLORS.get(item.item_type, Color(0.5, 0.5, 0.5))
	var block := ColorRect.new()
	block.color = Color(col.r, col.g, col.b, 0.85)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.rotation = PI / 4.0
	block.position = Vector2(CELL / 2 - (CELL - 16) / 2 * 0.707, CELL / 2 - (CELL - 16) / 2 * 0.707)
	block.size = Vector2(CELL - 16, CELL - 16)
	cell.add_child(block)
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

func refresh_equips():
	var inv = _inv()
	for key in equip_slots.keys():
		var info: Dictionary = equip_slots[key]
		var item = null
		if inv:
			match key:
				"weapon": item = inv.equipped_weapon
				"armor": item = inv.equipped_armor
				"accessory": item = inv.equipped_accessory
		for child in info["slot"].get_children():
			if child is Button:
				continue
			child.queue_free()
		if item != null:
			var col: Color = TYPE_COLORS.get(item.item_type, Color(0.5, 0.5, 0.5))
			var block := ColorRect.new()
			block.color = Color(col.r, col.g, col.b, 0.9)
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.rotation = PI / 4.0
			block.position = Vector2(38 - 30 * 0.707, 38 - 30 * 0.707)
			block.size = Vector2(60, 60)
			info["slot"].add_child(block)
			var tname: String = TYPE_NAMES.get(item.item_type, "")
			info["lbl"].text = "[%s]\n%s" % [tname, item.item_name]
			info["lbl"].add_theme_color_override("font_color", UITheme.TEXT_MAIN)
		else:
			info["lbl"].text = "（空）"
			info["lbl"].add_theme_color_override("font_color", UITheme.TEXT_DIM)
	if inv:
		# 手持工具（含遇袭自动收起状态）随面板实时可见
		var hand := "徒手"
		var pl = get_node_or_null("/root/Main/World/Player")
		if pl:
			hand = str(pl._tool_name(pl.equipped_tool))
		stat_lbl.text = "装备加成：攻击 +%d   防御 +%d   内力 +%d\n手持工具：%s（武器/防具/饰品在上方槽位）" % [
			int(inv.get_total_attack()), int(inv.get_total_defense()), int(inv.get_total_qi_bonus()), hand]

# ---------- 交互 ----------

func _on_cell_hover(i: int):
	var slot = cell_slots[i]
	if slot:
		_show_detail(slot["item"])

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
	if t == 2 or t == 4:
		if inv.use_item(item.item_id):
			_show_detail_msg("使用了「%s」" % item.item_name, UITheme.JADE)
		else:
			_show_detail_msg("「%s」无法使用" % item.item_name, UITheme.DANGER)
	elif t == 0 or t == 1 or t == 5:
		if inv.equip_item(item.item_id):
			_show_detail_msg("装备了「%s」" % item.item_name, UITheme.JADE)
		else:
			_show_detail_msg("「%s」无法装备" % item.item_name, UITheme.DANGER)
	else:
		selected_idx = i
		_show_detail(item)

func _on_equip_slot_hover(slot_type: String):
	var inv = _inv()
	if inv == null:
		return
	var item = null
	match slot_type:
		"weapon": item = inv.equipped_weapon
		"armor": item = inv.equipped_armor
		"accessory": item = inv.equipped_accessory
	if item != null:
		_show_detail(item)

func _on_equip_slot_click(slot_type: String):
	var inv = _inv()
	if inv == null:
		return
	inv.unequip_slot(slot_type)
	_show_detail_msg("已卸下%s" % equip_slots[slot_type]["disp"], UITheme.JADE)

func _show_detail(item):
	var tname: String = TYPE_NAMES.get(item.item_type, "未知")
	var eff: String = item.get_effect_description() if item.has_method("get_effect_description") else ""
	detail_lbl.text = "[%s] %s  ×%s\n%s%s" % [tname, item.item_name, str(_count_of(item.item_id)), item.description, ("\n" + eff) if eff != "" else ""]

func _show_detail_msg(msg: String, col: Color):
	detail_lbl.text = msg
	UITheme.style_label(detail_lbl, 12, col)
	var tw = create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func():
		if detail_lbl:
			UITheme.style_label(detail_lbl, 12, UITheme.TEXT_DIM))

func _count_of(item_id: String) -> int:
	var inv = _inv()
	return inv.get_item_count(item_id) if inv else 0

# ---------- 开关 ----------

func open():
	if portrait.texture == null:
		var tex = TextureGen.load_png_texture(GameManager.player_skin_root() + "idle_down_0.png")
		if tex:
			var img := tex.get_image()
			var head := img.get_region(Rect2i(17, 17, 16, 18))   # MW 48x48帧头位
			portrait.texture = ImageTexture.create_from_image(head)
	selected_idx = -1
	detail_lbl.text = ""
	refresh_values()
	refresh_bag()
	refresh_equips()
	visible = true
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	panel.pivot_offset = panel.size / 2
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close():
	if visible:
		visible = false

func is_open() -> bool:
	return visible

func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed):
		return
	var key = event.keycode
	if visible:
		if DialogManager.is_dialog_open():
			return
		var shop_hud = get_node_or_null("/root/Main/World/UI/ShopHUD")
		if shop_hud and shop_hud.is_open:
			return
		if key == KEY_ESCAPE or key == KEY_V or key == KEY_I:
			close()
			get_viewport().set_input_as_handled()
	elif key == KEY_V or key == KEY_I:
		if DialogManager.is_dialog_open() or GameManager.is_build_mode:
			return
		var shop_hud2 = get_node_or_null("/root/Main/World/UI/ShopHUD")
		if shop_hud2 and shop_hud2.is_open:
			return
		var quick_menu = get_node_or_null("/root/Main/World/UI/QuickMenu")
		if quick_menu and quick_menu.is_panel_open():
			return
		open()
		get_viewport().set_input_as_handled()
