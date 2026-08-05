class_name UITheme
extends RefCounted

# 统一武侠风UI主题：墨色宣纸底 + 描金边框 + 玉色点缀
# 所有HUD通过此类获取一致样式，避免各处硬编码风格漂移

const GOLD := Color(0.94, 0.80, 0.45)
const GOLD_DIM := Color(0.60, 0.50, 0.28)
const JADE := Color(0.45, 0.78, 0.62)
const INK := Color(0.075, 0.08, 0.095, 0.95)
const INK_LIGHT := Color(0.12, 0.125, 0.15, 0.94)
const PAPER := Color(0.93, 0.90, 0.82)
const TEXT_MAIN := Color(0.93, 0.91, 0.86)
const TEXT_DIM := Color(0.64, 0.62, 0.57)
const DANGER := Color(0.9, 0.3, 0.25)

# 主面板样式（弹窗/菜单）：双层边框（外描金+内暗线）营造精致感
static func panel_style(accent := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = INK
	s.border_color = GOLD if accent else GOLD_DIM
	s.set_border_width_all(2 if accent else 1)
	s.set_corner_radius_all(10)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	# 抗锯齿让描边更细腻
	s.anti_aliasing = true
	return s

# 内嵌区域样式（详情框/列表底）
static func inset_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.055, 0.07, 0.92)
	s.border_color = Color(0.35, 0.32, 0.22, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.anti_aliasing = true
	return s

# 按钮三态样式，返回字典 {normal, hover, pressed}
static func button_styles() -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = INK_LIGHT
	normal.border_color = GOLD_DIM
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	normal.anti_aliasing = true

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.19, 0.17, 0.12, 0.96)
	hover.border_color = GOLD
	hover.set_border_width_all(2)

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(0.26, 0.21, 0.11, 0.98)
	pressed.border_color = GOLD
	pressed.set_border_width_all(2)

	return {"normal": normal, "hover": hover, "pressed": pressed}

# 一键美化按钮
static func style_button(btn: Button, font_size: int = 13) -> void:
	var styles := button_styles()
	btn.add_theme_stylebox_override("normal", styles["normal"])
	btn.add_theme_stylebox_override("hover", styles["hover"])
	btn.add_theme_stylebox_override("pressed", styles["pressed"])
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", TEXT_MAIN)
	btn.add_theme_color_override("font_hover_color", GOLD)
	btn.add_theme_color_override("font_pressed_color", GOLD)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.focus_mode = Control.FOCUS_NONE
	# 悬停微放大反馈（pivot在触发时取，避免创建时size为0）
	btn.mouse_entered.connect(func():
		btn.pivot_offset = btn.size / 2
		var t = btn.create_tween()
		t.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.08)
	)
	btn.mouse_exited.connect(func():
		btn.pivot_offset = btn.size / 2
		var t = btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, 0.08)
	)

# 标题标签
static func style_title(lbl: Label, font_size: int = 16) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", GOLD)

# 正文标签
static func style_label(lbl: Label, font_size: int = 12, color: Color = TEXT_MAIN) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)

# 居中屏幕的浮动面板（自动适配窗口尺寸）
static func center_panel(panel: Control, w: float, h: float) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(w, h)
	panel.position = Vector2(-w / 2, -h / 2)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

# 弹窗打开动画（淡入+回弹缩放），所有模态面板统一调用
static func popup_anim(panel: Control) -> void:
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = panel.size / 2
	var tween = panel.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
