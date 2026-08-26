extends Control

const TextureGen = preload("res://scripts/texture_generator.gd")

# 圆形人物信息HUD - 中间头像（仅头部），周围环形属性条，下方可展开任务日志

var avatar_texture: Texture2D = null
var stat_arcs: Dictionary = {}
var resource_labels: Dictionary = {}
var name_label: Label = null

# Phase F7: 任务日志已迁出至独立 quest_log_hud.gd（游戏化页签+卡片），此处不再承载

# 布局常量
const CENTER_X = 90.0
const CENTER_Y = 90.0
const RING_OUTER_R = 72.0
const RING_INNER_R = 58.0
const AVATAR_R = 46.0
const ARC_GAP_DEG = 8.0
const ARC_SEGMENTS = 32
const RING_MASK_SEGS = 48

# 头部裁剪区域（Phase F1着装后：64x64帧中发髻+头部位于 x24..39 y15..31）
const HEAD_CROP_X = 24
const HEAD_CROP_Y = 15
const HEAD_CROP_W = 16
const HEAD_CROP_H = 17

# 属性配置: key -> [标签, 颜色, 最大值]
# 起始角度和弧度在_draw中动态计算
var stat_config = {
	"health": ["伤势", Color(1, 0.2, 0.2),  100.0],
	"hunger": ["饥饿", Color(1, 0.6, 0.2),  100.0],
	"poison": ["中毒", Color(0.6, 0.2, 0.8), 100.0],
	"qi":     ["内力", Color(0.3, 0.7, 1),   0.0],
}

# 属性显示顺序（决定环形排列顺序）
var stat_order = ["health", "hunger", "poison", "qi"]

# 内圈背景色
const INNER_BG = Color(0.08, 0.08, 0.1, 0.95)

# 任务面板宽度（与按钮一致）
const QUEST_W = 140.0

# 操作指南
var help_btn: Button = null
var help_panel: Panel = null
var help_expanded: bool = false

# 时辰天气
var datetime_label: Label = null

func _ready():
	# 全屏锚定以便子元素使用底部锚点；自身不拦截鼠标
	# 注意：必须用 set_anchors_and_offsets_preset，否则0尺寸节点会永远保持0尺寸（底部锚点失效）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_avatar()
	_create_name_label()
	_create_resource_labels()
	_create_help_section()
	_create_datetime_label()
	stat_arcs = {
		"health": GameManager.health / 100.0,
		"hunger": GameManager.hunger / 100.0,
		"poison": GameManager.poison / 100.0,
		"qi": GameManager.qi / GameManager.max_qi if GameManager.max_qi > 0 else 0.0,
	}

func _load_avatar():
	var full_tex = TextureGen.load_png_texture("res://sprites/player/idle_down_0.png")
	if full_tex:
		var img = full_tex.get_image()
		var head_img = img.get_region(Rect2i(HEAD_CROP_X, HEAD_CROP_Y, HEAD_CROP_W, HEAD_CROP_H))
		avatar_texture = ImageTexture.create_from_image(head_img)

func _create_name_label():
	name_label = Label.new()
	name_label.text = "少侠"
	name_label.position = Vector2(CENTER_X - 30, CENTER_Y - 8)
	name_label.size = Vector2(60, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	add_child(name_label)

func _create_resource_labels():
	var res_y = CENTER_Y + RING_OUTER_R + 16
	var resources = [
		["wood",  "木", Color(0.6, 0.4, 0.2)],
		["stone", "石", Color(0.5, 0.5, 0.5)],
		["gold",  "金", Color(1, 0.85, 0.2)],
	]
	for i in range(resources.size()):
		var key = resources[i][0]
		var icon = resources[i][1]
		var color = resources[i][2]
		var lbl = Label.new()
		lbl.text = icon + ":0"
		lbl.position = Vector2(15 + i * 55, res_y)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", color)
		add_child(lbl)
		resource_labels[key] = lbl

func _create_help_section():
	# 左下角操作指南（可折叠）
	help_btn = Button.new()
	help_btn.text = "  操作指南  ▲"
	help_btn.size = Vector2(140, 24)
	help_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_btn.position = Vector2(10, -34)
	UITheme.style_button(help_btn, 11)
	help_btn.add_theme_color_override("font_color", UITheme.GOLD)
	help_btn.pressed.connect(_toggle_help)
	add_child(help_btn)

	help_panel = Panel.new()
	help_panel.size = Vector2(250, 210)
	help_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_panel.position = Vector2(10, -248)
	help_panel.visible = false
	help_panel.add_theme_stylebox_override("panel", UITheme.inset_style())
	add_child(help_panel)

	var help_text = Label.new()
	help_text.position = Vector2(10, 8)
	help_text.size = Vector2(230, 194)
	UITheme.style_label(help_text, 11, UITheme.TEXT_MAIN)
	help_text.text = "WASD / 方向键  移动\n左键  轻击/使用工具    右键  重击\nQ  格挡    空格  闪避/疾跑\nE  打坐修炼    F  与人交谈\nB  建造    K  商店    V  人物面板\n左键点击路人  查看其姓名属性\n数字键1-4  锄头/水壶/菜种/采集\nZ / X / C  攻击/防御/中立架势\nJ  加入门派  P  门派信息\n奇遇触发时会自动弹出面板"
	help_panel.add_child(help_text)

func _toggle_help():
	help_expanded = !help_expanded
	help_panel.visible = help_expanded
	help_btn.text = "  操作指南  ▼" if help_expanded else "  操作指南  ▲"

func _create_datetime_label():
	datetime_label = Label.new()
	datetime_label.position = Vector2(370, 14)
	datetime_label.size = Vector2(160, 20)
	UITheme.style_label(datetime_label, 13, UITheme.GOLD_DIM)
	add_child(datetime_label)

func _update_datetime():
	var hour = int(GameManager.world_hour) % 24
	var shichen = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"][int(hour / 2) % 12]
	var weather = "雪" if GameManager.is_snowing else ("雨" if GameManager.is_raining else "晴")
	var daynight = "" if GameManager.is_daytime else " · 夜"
	datetime_label.text = shichen + "时 · " + weather + daynight

# 获取当前活跃的属性列表（中毒>0时包含，否则不包含）
func _get_active_stats() -> Array:
	var result = []
	for key in stat_order:
		if key == "poison" and GameManager.poison <= 0:
			continue
		result.append(key)
	return result

func _draw():
	# 1. 外圈背景
	draw_circle(Vector2(CENTER_X, CENTER_Y), RING_OUTER_R + 3, Color(0.2, 0.2, 0.25, 0.4))
	draw_circle(Vector2(CENTER_X, CENTER_Y), RING_OUTER_R + 1, Color(0.05, 0.05, 0.08, 0.9))

	# 2. 动态计算弧段：3个属性均分120度，4个属性均分90度
	var active_stats = _get_active_stats()
	var count = active_stats.size()
	var seg_deg = 360.0 / count  # 3→120, 4→90

	for i in range(count):
		var key = active_stats[i]
		var cfg = stat_config[key]
		var start_deg = i * seg_deg
		var ratio = stat_arcs.get(key, 0.0)
		_draw_arc_segment(start_deg, ARC_GAP_DEG, cfg[1], ratio, seg_deg)

	# 3. 内圈背景
	draw_circle(Vector2(CENTER_X, CENTER_Y), RING_INNER_R - 1, INNER_BG)

	# 4. 绘制头像（仅头部）
	if avatar_texture:
		var img_size = avatar_texture.get_size()
		var scale_factor = (AVATAR_R * 2) / max(img_size.x, img_size.y)
		var draw_size = img_size * scale_factor
		var draw_pos = Vector2(CENTER_X - draw_size.x / 2, CENTER_Y - draw_size.y / 2)
		draw_texture_rect(avatar_texture, Rect2(draw_pos, draw_size), false)
		_draw_full_ring(AVATAR_R, RING_INNER_R - 1, INNER_BG)
	else:
		draw_circle(Vector2(CENTER_X, CENTER_Y), AVATAR_R, Color(0.15, 0.15, 0.2, 1.0))
		draw_string(_get_default_font(), Vector2(CENTER_X - 12, CENTER_Y + 4), "侠", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(1, 0.9, 0.7))

	# 5. 边框
	draw_arc(Vector2(CENTER_X, CENTER_Y), RING_INNER_R - 1, 0, TAU, 64, Color(0.4, 0.35, 0.2, 0.5), 1.5)
	draw_arc(Vector2(CENTER_X, CENTER_Y), RING_OUTER_R + 1, 0, TAU, 64, Color(0.4, 0.35, 0.2, 0.5), 1.5)

	# 6. 属性标签（在弧段外侧）
	for i in range(count):
		var key = active_stats[i]
		var cfg = stat_config[key]
		var label_text = cfg[0]
		var start_deg = i * seg_deg
		var mid_deg = start_deg + (seg_deg - ARC_GAP_DEG) / 2.0
		var mid_rad = deg_to_rad(mid_deg - 90)
		var label_r = RING_OUTER_R + 16
		var lx = CENTER_X + cos(mid_rad) * label_r
		var ly = CENTER_Y + sin(mid_rad) * label_r
		var ratio = stat_arcs.get(key, 0.0)
		var val_text = str(int(ratio * 100)) if key != "qi" else str(int(ratio * GameManager.max_qi))
		draw_string(_get_default_font(), Vector2(lx - 10, ly + 2), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.9, 0.9, 0.9, 0.9))
		draw_string(_get_default_font(), Vector2(lx - 8, ly + 13), val_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, cfg[1])

func _draw_arc_segment(start_deg: float, gap_deg: float, color: Color, ratio: float, total_deg: float):
	var arc_deg = total_deg - gap_deg
	var actual_start = start_deg + gap_deg / 2.0
	_draw_filled_arc(actual_start, arc_deg, RING_INNER_R, RING_OUTER_R, Color(0.15, 0.15, 0.18, 0.8))
	if ratio > 0.001:
		var fill_deg = arc_deg * clamp(ratio, 0, 1)
		_draw_filled_arc(actual_start, fill_deg, RING_INNER_R, RING_OUTER_R, color)

func _draw_filled_arc(start_deg: float, arc_deg: float, inner_r: float, outer_r: float, color: Color):
	if arc_deg <= 0:
		return
	var points = []
	var start_rad = deg_to_rad(start_deg - 90)
	var end_rad = deg_to_rad(start_deg + arc_deg - 90)
	for i in range(ARC_SEGMENTS + 1):
		var t = float(i) / ARC_SEGMENTS
		var angle = start_rad + (end_rad - start_rad) * t
		points.append(Vector2(CENTER_X + cos(angle) * outer_r, CENTER_Y + sin(angle) * outer_r))
	for i in range(ARC_SEGMENTS, -1, -1):
		var t = float(i) / ARC_SEGMENTS
		var angle = start_rad + (end_rad - start_rad) * t
		points.append(Vector2(CENTER_X + cos(angle) * inner_r, CENTER_Y + sin(angle) * inner_r))
	draw_colored_polygon(points, color)

func _draw_full_ring(inner_r: float, outer_r: float, color: Color):
	for i in range(RING_MASK_SEGS):
		var a1 = (i * TAU) / RING_MASK_SEGS
		var a2 = ((i + 1) * TAU) / RING_MASK_SEGS
		var p1 = Vector2(CENTER_X + cos(a1) * outer_r, CENTER_Y + sin(a1) * outer_r)
		var p2 = Vector2(CENTER_X + cos(a2) * outer_r, CENTER_Y + sin(a2) * outer_r)
		var p3 = Vector2(CENTER_X + cos(a2) * inner_r, CENTER_Y + sin(a2) * inner_r)
		var p4 = Vector2(CENTER_X + cos(a1) * inner_r, CENTER_Y + sin(a1) * inner_r)
		draw_colored_polygon([p1, p2, p3, p4], color)

func _get_default_font() -> Font:
	return ThemeDB.fallback_font

func _process(_delta):
	stat_arcs["health"] = GameManager.health / 100.0
	stat_arcs["hunger"] = GameManager.hunger / 100.0
	stat_arcs["poison"] = GameManager.poison / 100.0
	stat_arcs["qi"] = GameManager.qi / GameManager.max_qi if GameManager.max_qi > 0 else 0.0
	resource_labels["wood"].text = "木:" + str(GameManager.wood)
	resource_labels["stone"].text = "石:" + str(GameManager.stone)
	resource_labels["gold"].text = "金:" + str(GameManager.gold)
	queue_redraw()
	_update_datetime()

# Phase F7: 旧任务日志渲染与快捷键处理已整体迁至 quest_log_hud.gd
