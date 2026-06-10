extends Control

var icons: Dictionary = {}
var bars: Dictionary = {}
var bg_panel: Panel = null

const BAR_W = 120
const BAR_H = 12
const GAP = 18

func _ready():
	position = Vector2(10, 10)
	_create_bg_panel()
	_setup_stat("hunger", "饥饿", Color(1, 0.6, 0.2), 0)
	_setup_stat("stamina", "体力", Color(0.3, 0.8, 0.3), 1)
	_setup_stat("health", "伤势", Color(1, 0.2, 0.2), 2)
	_setup_stat("poison", "中毒", Color(0.6, 0.2, 0.8), 3)
	_setup_resource("wood", "木材", Color(0.6, 0.4, 0.2), 4)
	_setup_resource("stone", "石料", Color(0.5, 0.5, 0.5), 5)
	_setup_resource("gold", "金钱", Color(1, 0.85, 0.2), 6)
	_setup_qi_bar()

func _create_bg_panel():
	bg_panel = Panel.new()
	bg_panel.size = Vector2(180, 148)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.75)
	style.border_color = Color(0.3, 0.3, 0.4, 0.5)
	style.border_width_bottom = 1
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	bg_panel.add_theme_stylebox_override("panel", style)
	add_child(bg_panel)
	move_child(bg_panel, 0)

func _setup_stat(key: String, label_text: String, color: Color, idx: int):
	var y = 8 + idx * GAP
	var lbl = Label.new()
	lbl.text = label_text
	lbl.position = Vector2(8, y)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	add_child(lbl)
	icons[key] = lbl

	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.15, 0.8)
	bg.position = Vector2(48, y + 2)
	bg.size = Vector2(BAR_W, BAR_H)
	add_child(bg)

	var fg = ColorRect.new()
	fg.color = color
	fg.position = Vector2(48, y + 2)
	fg.size = Vector2(BAR_W, BAR_H)
	add_child(fg)
	bars[key] = fg

func _setup_resource(key: String, label_text: String, color: Color, idx: int):
	var y = 8 + idx * GAP
	var lbl = Label.new()
	lbl.text = label_text + ": 0"
	lbl.position = Vector2(8, y)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", color)
	add_child(lbl)
	icons[key] = lbl

func _setup_qi_bar():
	var y = 8 + 7 * GAP
	var lbl = Label.new()
	lbl.text = "内力"
	lbl.position = Vector2(8, y)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.8, 1))
	add_child(lbl)

	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.15, 0.8)
	bg.position = Vector2(48, y + 2)
	bg.size = Vector2(BAR_W, BAR_H)
	add_child(bg)

	var fg = ColorRect.new()
	fg.color = Color(0.3, 0.7, 1)
	fg.position = Vector2(48, y + 2)
	fg.size = Vector2(BAR_W, BAR_H)
	add_child(fg)
	bars["qi"] = fg

func _process(_delta):
	bars["hunger"].size.x = BAR_W * GameManager.hunger / 100.0
	bars["stamina"].size.x = BAR_W * GameManager.stamina / 100.0
	bars["health"].size.x = BAR_W * GameManager.health / 100.0
	bars["poison"].size.x = BAR_W * GameManager.poison / 100.0
	bars["qi"].size.x = BAR_W * GameManager.qi / GameManager.max_qi
	icons["wood"].text = "木材: " + str(GameManager.wood)
	icons["stone"].text = "石料: " + str(GameManager.stone)
	icons["gold"].text = "金钱: " + str(GameManager.gold)
