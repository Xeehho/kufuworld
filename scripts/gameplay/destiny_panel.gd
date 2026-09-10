class_name DestinyPanel
extends Control
## 天命面板 UI 独立件（P1-3，§4.2-1：四轨声望+天命点+糖糖等级+舞台进度）。
## 挂载与输入路由（V 键复用 CharacterSheet 语义、加入 ui_modal 组锁输入、
## 挂 $World/UI）留接线期（REQ 通过后与 game_manager 一起接）。
## 本件自包含：构造传入 DestinyCore，refresh() 读 panel_snapshot() 渲染；
## 样式全部走 UITheme（AGENTS.md UI 架构规范：禁止散落硬编码 StyleBox）。

const DestinyCoreScript := preload("res://scripts/gameplay/destiny_core.gd")
const TangtangScript := preload("res://scripts/gameplay/tangtang.gd")

const PANEL_W := 540.0
const PANEL_H := 660.0

var core: DestinyCoreScript

var _root: Panel
var _title_lbl: Label
var _tangtang_lbl: Label
var _points_lbl: Label
var _stage_lbl: Label
var _stage_unlock_lbl: Label
var _wheel_lbl: Label
var _track_rows: Array = []  # [{name, bar_bg, bar_fill, value, tier}]


func _init(destiny_core: DestinyCoreScript) -> void:
	core = destiny_core
	_build_ui()
	refresh()


func _build_ui() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_root = Panel.new()
	_root.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	add_child(_root)
	UITheme.center_panel(_root, PANEL_W, PANEL_H)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18.0
	v.offset_right = -18.0
	v.offset_top = 14.0
	v.offset_bottom = -14.0
	v.add_theme_constant_override("separation", 8)
	_root.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	v.add_child(header)
	_title_lbl = Label.new()
	_title_lbl.text = "天命"
	UITheme.style_title(_title_lbl, 20)
	header.add_child(_title_lbl)
	_tangtang_lbl = Label.new()
	_tangtang_lbl.text = ""
	UITheme.style_label(_tangtang_lbl, 13, UITheme.JADE)
	_tangtang_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tangtang_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_tangtang_lbl)

	_points_lbl = Label.new()
	_points_lbl.text = "天命点 0"
	UITheme.style_label(_points_lbl, 16, UITheme.GOLD)
	v.add_child(_points_lbl)

	_stage_lbl = Label.new()
	UITheme.style_label(_stage_lbl, 14)
	v.add_child(_stage_lbl)
	_stage_unlock_lbl = Label.new()
	UITheme.style_label(_stage_unlock_lbl, 12, UITheme.TEXT_DIM)
	v.add_child(_stage_unlock_lbl)

	var sep := HSeparator.new()
	v.add_child(sep)

	for i in 4:
		v.add_child(_build_track_row())

	_wheel_lbl = Label.new()
	UITheme.style_label(_wheel_lbl, 12, UITheme.TEXT_DIM)
	_wheel_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	v.add_child(_wheel_lbl)


func _build_track_row() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.inset_style())
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	row.add_child(head)
	var name_lbl := Label.new()
	UITheme.style_label(name_lbl, 14)
	name_lbl.custom_minimum_size = Vector2(64.0, 0.0)
	head.add_child(name_lbl)
	var value_lbl := Label.new()
	UITheme.style_label(value_lbl, 14, UITheme.GOLD)
	value_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(value_lbl)
	var tier_lbl := Label.new()
	UITheme.style_label(tier_lbl, 12, UITheme.TEXT_DIM)
	head.add_child(tier_lbl)
	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(0.0, 8.0)
	bar_bg.add_theme_stylebox_override("panel", UITheme.inset_style())
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar_bg)
	var bar_fill := ColorRect.new()
	bar_fill.color = UITheme.JADE
	bar_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	bar_fill.pivot_offset = Vector2.ZERO  # 左锚缩放：宽度比例=声望进度
	bar_bg.add_child(bar_fill)
	_track_rows.append({"name": name_lbl, "value": value_lbl, "tier": tier_lbl, "bar_bg": bar_bg, "bar_fill": bar_fill})
	return box


## 刷新面板数据（调用方：打开时/信号驱动；headless 测试直接断言文本）。
func refresh() -> void:
	var snap := core.panel_snapshot()
	var level := TangtangScript.level_for(float(snap["total"]))
	_tangtang_lbl.text = "%s·Lv%d %s" % ["糖糖", level["level"], level["form"]]
	_points_lbl.text = "天命点 %d" % int(snap["destiny_points"])
	_stage_lbl.text = "当前舞台：%s（总声望 %d）" % [String(snap["stage_name"]), int(float(snap["total"]))]
	_stage_unlock_lbl.text = "解锁：%s" % String(snap["stage_unlock"])
	for i in snap["tracks"].size():
		var t: Dictionary = snap["tracks"][i]
		var row: Dictionary = _track_rows[i]
		row["name"].text = String(t["name"])
		row["value"].text = "%d" % int(float(t["value"]))
		row["tier"].text = String(t["tier_name"])
		if bool(t["hostile"]):
			row["tier"].add_theme_color_override("font_color", UITheme.DANGER)
			row["tier"].text = "敌对"
			row["bar_fill"].color = UITheme.DANGER
		else:
			row["tier"].add_theme_color_override("font_color", UITheme.TEXT_DIM)
			row["bar_fill"].color = UITheme.JADE
		_layout_bar(row, float(t["value"]))
	_wheel_lbl.text = "天命轮盘：%s｜回响保险：%s" % [
		"已开放（糖糖Lv3）" if bool(snap["wheel_unlocked"]) else "未开放（需糖糖Lv3·总声望3000）",
		"已投保" if bool(snap["echo_insured"]) else "未投保",
	]


## 进度条用左锚缩放表达比例（fill 已锚满 bar_bg，scale.x=声望/10000）；
## 不依赖布局后的实际像素宽，headless 无渲染也能正确设置。
func _layout_bar(row: Dictionary, value: float) -> void:
	var fill: ColorRect = row["bar_fill"]
	fill.scale.x = clampf(value / 10000.0, 0.0, 1.0)


## 演出统一走 UITheme.popup_anim（AGENTS.md：弹窗 0.15s 淡入手感统一）。
func play_open_anim() -> void:
	UITheme.popup_anim(_root)
