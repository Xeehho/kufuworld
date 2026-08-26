extends Control

const TextureGen = preload("res://scripts/texture_generator.gd")

# Phase F7: 人物面板（按V或ESC关闭；居中弹窗，游戏式属性总览）
# 数据源：GameManager单例 + 玩家精灵头像

var panel: Panel = null
var portrait: TextureRect = null
var title_lbl: Label = null
var bars: Dictionary = {}      # key -> {bar, val}
var attr_labels: Dictionary = {}

const PANEL_W := 460.0
const PANEL_H := 430.0

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("ui_modal")
	_build_ui()

func _build_ui():
	panel = Panel.new()
	panel.name = "SheetPanel"
	UITheme.center_panel(panel, PANEL_W, PANEL_H)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	add_child(panel)

	var title = Label.new()
	title.text = "· 侠 者 档 案 ·"
	title.position = Vector2(0, 12)
	title.size = Vector2(PANEL_W, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(title, 16)
	panel.add_child(title)

	var div = ColorRect.new()
	div.color = UITheme.GOLD_DIM
	div.position = Vector2(24, 44)
	div.size = Vector2(PANEL_W - 48, 1)
	panel.add_child(div)

	# 头像框（玩家着装后头部特写，nearest放大）
	var av_bg := Panel.new()
	av_bg.position = Vector2(26, 62)
	av_bg.size = Vector2(92, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.13, 1.0)
	sb.border_color = UITheme.GOLD_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	av_bg.add_theme_stylebox_override("panel", sb)
	panel.add_child(av_bg)
	portrait = TextureRect.new()
	portrait.position = Vector2(4, 4)
	portrait.size = Vector2(84, 84)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	av_bg.add_child(portrait)

	title_lbl = Label.new()
	title_lbl.position = Vector2(24, 158)
	title_lbl.size = Vector2(96, 40)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_label(title_lbl, 11, UITheme.GOLD)
	panel.add_child(title_lbl)

	# 左列：状态条
	var stat_defs := [
		["health", "伤势", Color(0.9, 0.25, 0.25), 100.0],
		["hunger", "饥饿", Color(0.95, 0.6, 0.2), 100.0],
		["qi", "内力", Color(0.3, 0.7, 1.0), 100.0],
		["poison", "中毒", Color(0.6, 0.2, 0.8), 100.0],
	]
	var y := 62.0
	for d in stat_defs:
		_make_bar(d[0], d[1], d[2], 140.0, y)
		y += 46.0

	# 右列：江湖履历（两列小网格）
	var attrs := [
		["morality", "道德"], ["reputation", "声望"],
		["gold", "盘缠"], ["wood", "木料"],
		["stone", "石料"], ["clan", "门派"],
		["rank", "职位"], ["contribution", "贡献"],
		["inner", "内功"], ["env", "环境"],
	]
	var ax0 := 300.0
	var ay0 := 66.0
	for i in range(attrs.size()):
		var col := i % 2
		var row := int(i / 2)
		var lbl := Label.new()
		lbl.name = "Attr_" + attrs[i][0]
		lbl.position = Vector2(ax0 + col * 82.0, ay0 + row * 52.0)
		lbl.size = Vector2(80, 48)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", UITheme.TEXT_MAIN)
		panel.add_child(lbl)
		attr_labels[attrs[i][0]] = {"lbl": lbl, "name": attrs[i][1]}

	var hint = Label.new()
	hint.text = "[V] 或 [ESC] 关闭"
	hint.position = Vector2(0, PANEL_H - 26)
	hint.size = Vector2(PANEL_W, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(hint, 9, UITheme.TEXT_DIM)
	panel.add_child(hint)

func _make_bar(key: String, disp: String, color: Color, x: float, y: float):
	var lbl := Label.new()
	lbl.text = disp
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(120, 14)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	panel.add_child(lbl)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.position = Vector2(x, y + 15)
	bar.size = Vector2(130, 13)
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
	panel.add_child(bar)
	var val := Label.new()
	val.position = Vector2(x + 134, y + 14)
	val.size = Vector2(50, 14)
	val.add_theme_font_size_override("font_size", 9)
	val.add_theme_color_override("font_color", color)
	panel.add_child(val)
	bars[key] = {"bar": bar, "val": val}

func open():
	if portrait.texture == null:
		var tex = TextureGen.load_png_texture("res://sprites/player/idle_down_0.png")
		if tex:
			var img := tex.get_image()
			var head := img.get_region(Rect2i(24, 15, 16, 17))
			portrait.texture = ImageTexture.create_from_image(head)
	refresh_values()
	visible = true
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.94, 0.94)
	panel.pivot_offset = panel.size / 2
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close():
	visible = false

func is_open() -> bool:
	return visible

func _title_for(rep: float) -> String:
	if rep >= 200: return "「武林泰斗」"
	if rep >= 100: return "「名动一方」"
	if rep >= 50: return "「小有名气」"
	if rep >= 0: return "「无名少侠」"
	return "「恶名远扬」"

func refresh_values():
	bars["health"]["bar"].max_value = 100
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
	var clan_txt: String = "无" if GameManager.player_clan == null else str(GameManager.player_clan.name)
	var rank_names := ["外门弟子", "内门弟子", "核心弟子", "长老", "首座"]
	var rank_txt := "—"
	if GameManager.player_clan != null:
		rank_txt = rank_names[clampi(GameManager.player_rank, 0, rank_names.size() - 1)]
	var inner_txt := "未修炼"
	if GameManager.active_inner_skill != null:
		inner_txt = GameManager.active_inner_skill.skill_name
	var env_txt := "江湖" if GameManager.current_environment == "" else GameManager.current_environment
	attr_labels["morality"]["lbl"].text = attr_labels["morality"]["name"] + "\n" + str(int(GameManager.morality))
	attr_labels["reputation"]["lbl"].text = attr_labels["reputation"]["name"] + "\n" + str(int(GameManager.reputation))
	attr_labels["gold"]["lbl"].text = attr_labels["gold"]["name"] + "\n" + str(GameManager.gold) + " 两"
	attr_labels["wood"]["lbl"].text = attr_labels["wood"]["name"] + "\n" + str(GameManager.wood)
	attr_labels["stone"]["lbl"].text = attr_labels["stone"]["name"] + "\n" + str(GameManager.stone)
	attr_labels["clan"]["lbl"].text = attr_labels["clan"]["name"] + "\n" + clan_txt
	attr_labels["rank"]["lbl"].text = attr_labels["rank"]["name"] + "\n" + rank_txt
	attr_labels["contribution"]["lbl"].text = attr_labels["contribution"]["name"] + "\n" + str(GameManager.contribution)
	attr_labels["inner"]["lbl"].text = attr_labels["inner"]["name"] + "\n" + inner_txt
	attr_labels["env"]["lbl"].text = attr_labels["env"]["name"] + "\n" + env_txt

func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed):
		return
	if visible:
		# 面板已开：V/ESC关闭（对话/商店优先）
		if DialogManager.is_dialog_open():
			return
		var shop_hud = get_node_or_null("/root/Main/World/UI/ShopHUD")
		if shop_hud and shop_hud.is_open:
			return
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_V:
			close()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_V:
		# 面板未开：V打开（避免与对话/商店/建造/奇遇冲突）
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
