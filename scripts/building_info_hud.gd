extends Control

const TextureGen = preload("res://scripts/texture_generator.gd")

# 建筑信息面板 - 点击古堡等大型建筑时显示（势力/领主/规模/描述）
# 非模态（不锁移动，与NPCInfoHUD同模式，互斥显示）

var bg_panel: Panel = null
var labels: Dictionary = {}
var close_btn: Button = null

const PANEL_W = 230
const PANEL_H = 210

func _ready():
	# 锚定右上，与NPC信息面板同位（互斥：打开时隐藏NPC面板）
	anchor_left = 1.0
	anchor_right = 1.0
	grow_horizontal = 0
	offset_left = -PANEL_W - 60
	offset_right = -60
	offset_top = 250
	visible = false
	_create_ui()

func _create_ui():
	bg_panel = Panel.new()
	bg_panel.size = Vector2(PANEL_W, PANEL_H)
	bg_panel.add_theme_stylebox_override("panel", UITheme.panel_style())
	add_child(bg_panel)

	var name_lbl = Label.new()
	name_lbl.position = Vector2(10, 8)
	name_lbl.size = Vector2(PANEL_W - 50, 22)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	add_child(name_lbl)
	labels["name"] = name_lbl

	close_btn = Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(PANEL_W - 34, 8)
	close_btn.size = Vector2(24, 22)
	UITheme.style_button(close_btn, 12)
	close_btn.pressed.connect(close_info)
	add_child(close_btn)

	# 建筑缩略图（占位框+纹理）
	var art_bg = Panel.new()
	art_bg.position = Vector2(12, 36)
	art_bg.size = Vector2(64, 48)
	var art_style := StyleBoxFlat.new()
	art_style.bg_color = Color(0.10, 0.10, 0.13)
	art_style.set_corner_radius_all(4)
	art_bg.add_theme_stylebox_override("panel", art_style)
	add_child(art_bg)
	labels["art_bg"] = art_bg

	var art = TextureRect.new()
	art.position = Vector2(14, 38)
	art.size = Vector2(60, 44)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(art)
	labels["art"] = art

	# 信息行
	var info_items = [
		["faction", "势力", Color(0.55, 0.85, 1.0)],
		["stance", "立场", Color(0.8, 0.8, 0.8)],
		["lord", "领主", Color(1, 0.7, 0.4)],
		["scale", "规模", Color(0.65, 0.9, 0.55)],
	]
	var y := 36.0
	for item in info_items:
		var key_lbl = Label.new()
		key_lbl.position = Vector2(88, y)
		key_lbl.size = Vector2(36, 16)
		UITheme.style_label(key_lbl, 12, UITheme.TEXT_DIM)
		key_lbl.text = item[1]
		add_child(key_lbl)
		var val_lbl = Label.new()
		val_lbl.position = Vector2(126, y)
		val_lbl.size = Vector2(PANEL_W - 136, 16)
		UITheme.style_label(val_lbl, 12, item[2])
		add_child(val_lbl)
		labels[item[0]] = val_lbl
		y += 20

	# 描述
	var desc = Label.new()
	desc.position = Vector2(12, 116)
	desc.size = Vector2(PANEL_W - 24, 60)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_label(desc, 11, UITheme.TEXT_MAIN)
	add_child(desc)
	labels["desc"] = desc

	var hint = Label.new()
	hint.text = "—— 点击 X 或再次点击建筑关闭 ——"
	hint.position = Vector2(10, PANEL_H - 26)
	hint.size = Vector2(PANEL_W - 20, 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(hint, 10, UITheme.TEXT_DIM)
	add_child(hint)

func show_building_info(bld: Node2D):
	"""展示建筑信息（从建筑节点meta读取）"""
	if not bld.has_meta("b_name"):
		return
	# 与NPC信息面板互斥
	var npc_panel = get_node_or_null("../NPCInfoHUD")
	if npc_panel:
		npc_panel.visible = false
	labels["name"].text = str(bld.get_meta("b_name"))
	labels["faction"].text = str(bld.get_meta("b_faction"))
	var stance: String = str(bld.get_meta("b_stance"))
	labels["stance"].text = stance
	var stance_color := Color(0.7, 0.7, 0.75)
	if stance == "正派":
		stance_color = Color(0.45, 0.9, 0.5)
	elif stance == "邪派":
		stance_color = Color(0.95, 0.4, 0.35)
	labels["stance"].add_theme_color_override("font_color", stance_color)
	labels["lord"].text = str(bld.get_meta("b_lord"))
	labels["scale"].text = str(bld.get_meta("b_scale"))
	labels["desc"].text = str(bld.get_meta("b_desc"))
	# 缩略图：castle 贴图
	var tex = TextureGen.load_png_texture("res://sprites/buildings/castle.png")
	labels["art"].texture = tex
	visible = true

func close_info():
	visible = false

func _unhandled_input(event):
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_info()
		get_viewport().set_input_as_handled()
