extends Control

const TextureGen = preload("res://scripts/texture_generator.gd")

# NPC信息面板 - 右上角展示，点击NPC时显示

var current_npc: CharacterBody2D = null
var avatar_texture: Texture2D = null
var info_labels: Dictionary = {}
var close_btn: Button = null
var bg_panel: Panel = null
var visible_timer: float = 0.0

# 布局常量
const PANEL_W = 200
const PANEL_H = 220
const AVATAR_SIZE = 64
const AVATAR_X = 68
const AVATAR_Y = 30

func _ready():
	# 锚定右侧，位于江湖风云事件栏下方，避免重叠
	anchor_left = 1.0
	anchor_right = 1.0
	grow_horizontal = 0  # GROW_DIRECTION_LEFT
	offset_left = -PANEL_W - 60
	offset_right = -60
	offset_top = 250
	visible = false
	_create_ui()

func _create_ui():
	# 背景面板
	bg_panel = Panel.new()
	bg_panel.size = Vector2(PANEL_W, PANEL_H)
	bg_panel.add_theme_stylebox_override("panel", UITheme.panel_style())
	add_child(bg_panel)

	# NPC名字
	var name_lbl = Label.new()
	name_lbl.name = "NPCName"
	name_lbl.position = Vector2(10, 6)
	name_lbl.size = Vector2(PANEL_W - 20, 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	add_child(name_lbl)
	info_labels["name"] = name_lbl

	# 头像占位（圆形背景）
	var avatar_bg = Panel.new()
	avatar_bg.name = "AvatarBG"
	avatar_bg.position = Vector2(AVATAR_X, AVATAR_Y)
	avatar_bg.size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	var avatar_style = StyleBoxFlat.new()
	avatar_style.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	avatar_style.corner_radius_top_left = AVATAR_SIZE / 2
	avatar_style.corner_radius_top_right = AVATAR_SIZE / 2
	avatar_style.corner_radius_bottom_left = AVATAR_SIZE / 2
	avatar_style.corner_radius_bottom_right = AVATAR_SIZE / 2
	avatar_bg.add_theme_stylebox_override("panel", avatar_style)
	add_child(avatar_bg)
	info_labels["avatar_bg"] = avatar_bg

	# 头像纹理
	var avatar_sprite = TextureRect.new()
	avatar_sprite.name = "AvatarSprite"
	avatar_sprite.position = Vector2(AVATAR_X + 2, AVATAR_Y + 2)
	avatar_sprite.size = Vector2(AVATAR_SIZE - 4, AVATAR_SIZE - 4)
	avatar_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_sprite.clip_contents = true
	add_child(avatar_sprite)
	info_labels["avatar"] = avatar_sprite

	# 信息行
	var info_items = [
		["personality", "性格", Color(0.8, 0.8, 0.8)],
		["relation", "好感", Color(1, 0.6, 0.3)],
		["rel_type", "关系", Color(0.6, 0.8, 1)],
		["likes", "喜好", Color(0.4, 0.9, 0.4)],
		["dislikes", "厌恶", Color(0.9, 0.4, 0.4)],
		["state", "状态", Color(0.7, 0.7, 0.7)],
	]
	var start_y = AVATAR_Y + AVATAR_SIZE + 12
	for i in range(info_items.size()):
		var key = info_items[i][0]
		var title = info_items[i][1]
		var color = info_items[i][2]
		var y = start_y + i * 18
		var lbl = Label.new()
		lbl.name = "Info_" + key
		lbl.position = Vector2(12, y)
		lbl.size = Vector2(PANEL_W - 24, 16)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", color)
		lbl.text = title + ": --"
		add_child(lbl)
		info_labels[key] = lbl

	# 关闭按钮
	close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.position = Vector2(PANEL_W - 28, 4)
	close_btn.size = Vector2(22, 20)
	UITheme.style_button(close_btn, 10)
	close_btn.pressed.connect(_on_close)
	add_child(close_btn)

func show_npc_info(npc: CharacterBody2D):
	if npc == null or npc.npc_data == null:
		return
	current_npc = npc
	visible = true
	visible_timer = 0.0
	_refresh_info()

func hide_npc_info():
	visible = false
	current_npc = null

func _on_close():
	hide_npc_info()

func _refresh_info():
	if current_npc == null or current_npc.npc_data == null:
		hide_npc_info()
		return
	var nd = current_npc.npc_data
	# 名字
	info_labels["name"].text = nd.npc_name
	# 头像
	_load_npc_avatar(current_npc.npc_type)
	# 性格
	info_labels["personality"].text = "性格: " + nd.personality
	# 好感度
	var favor = GameManager.get_relation(nd.npc_name, "玩家")
	var favor_str = str(int(favor))
	if favor > 50:
		info_labels["relation"].add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	elif favor > 0:
		info_labels["relation"].add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	else:
		info_labels["relation"].add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	info_labels["relation"].text = "好感: " + favor_str
	# 关系类型
	var rel_type = GameManager.get_relation_type(nd.npc_name, "玩家")
	info_labels["rel_type"].text = "关系: " + rel_type
	# 喜好
	info_labels["likes"].text = "喜好: " + str(nd.likes).replace("[", "").replace("]", "").replace('"', "")
	# 厌恶
	info_labels["dislikes"].text = "厌恶: " + str(nd.dislikes).replace("[", "").replace("]", "").replace('"', "")
	# 状态
	var state_name = "待机"
	match current_npc.schedule_state:
		0: state_name = "待机"
		1: state_name = "行走"
		2: state_name = "工作"
		3: state_name = "休息"
	if current_npc.is_homestead:
		state_name = "劳作"
	info_labels["state"].text = "状态: " + state_name

func _load_npc_avatar(npc_type: String):
	var tex_path = "res://sprites/npc/%s_idle_down_0.png" % npc_type
	avatar_texture = TextureGen.load_png_texture(tex_path)
	info_labels["avatar"].texture = avatar_texture

func _process(delta):
	if not visible:
		return
	# 检查NPC是否还在可视范围内
	if current_npc != null:
		var player = get_node_or_null("/root/Main/World/Player")
		if player != null:
			var dist = player.global_position.distance_to(current_npc.global_position)
			if dist > 300.0:
				hide_npc_info()
				return
	# 持续刷新NPC信息（状态可能变化）
	visible_timer += delta
	if visible_timer >= 0.5:
		visible_timer = 0.0
		_refresh_info()
