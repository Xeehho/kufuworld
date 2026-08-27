extends Control

# 小地图（M键开关）：以玩家为中心，1像素=1瓦片采样渲染
# 非模态HUD（不锁移动，不在ui_modal组）；M键在 _unhandled_input 中处理
# 数据源：WorldGenerator.get_tile_id / pois / town_centers + npc/mobs 分组

const MAP_TILES := 160          # 采样边长（瓦片）
const HALF := 80                # 采样半径
const PANEL_SIZE := Vector2(216, 274)
const REFRESH_INTERVAL := 0.8

var panel: Panel = null
var map_rect: TextureRect = null
var pos_label: Label = null
var _opened := false
var _acc := 0.0
var _img: Image = null
var _tex: ImageTexture = null

# 瓦片ID -> 小地图颜色（取素材包主色调）
const TILE_COLORS := {
	0: Color(0.36, 0.56, 0.26), 1: Color(0.66, 0.53, 0.37), 2: Color(0.78, 0.46, 0.30),
	3: Color(0.36, 0.35, 0.38), 4: Color(0.16, 0.38, 0.20), 5: Color(0.26, 0.50, 0.80),
	6: Color(0.83, 0.69, 0.47), 7: Color(0.52, 0.54, 0.58), 8: Color(0.24, 0.45, 0.20),
	9: Color(0.42, 0.55, 0.28), 10: Color(0.70, 0.52, 0.33), 11: Color(0.74, 0.48, 0.30),
	12: Color(0.16, 0.14, 0.13), 13: Color(0.72, 0.45, 0.70), 14: Color(0.52, 0.52, 0.54),
	15: Color(0.62, 0.48, 0.31), 16: Color(0.52, 0.38, 0.23), 17: Color(0.68, 0.51, 0.31),
	18: Color(0.27, 0.43, 0.20), 33: Color(0.42, 0.31, 0.19), 34: Color(0.90, 0.92, 0.95),
	35: Color(0.58, 0.58, 0.56), 36: Color(0.72, 0.53, 0.30), 37: Color(0.82, 0.77, 0.58),
	39: Color(0.66, 0.42, 0.26),
}
const DEFAULT_COLOR := Color(0.30, 0.44, 0.24)

func _ready():
	# HUD根节点必须全屏锚定且不拦截鼠标（项目UI规范）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()

func _build_panel():
	panel = Panel.new()
	panel.name = "MinimapPanel"
	panel.size = PANEL_SIZE
	panel.position = Vector2(1424, 52)
	panel.add_theme_stylebox_override("panel", UITheme.inset_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var title := Label.new()
	title.text = "江湖舆图（M关闭）"
	title.position = Vector2(10, 6)
	title.size = Vector2(196, 20)
	UITheme.style_title(title, 13)
	panel.add_child(title)

	map_rect = TextureRect.new()
	map_rect.position = Vector2(14, 30)
	map_rect.size = Vector2(188, 188)
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(map_rect)

	pos_label = Label.new()
	pos_label.position = Vector2(14, 222)
	pos_label.size = Vector2(188, 16)
	UITheme.style_label(pos_label, 11, UITheme.TEXT_DIM)
	panel.add_child(pos_label)

	var legend := Label.new()
	legend.text = "●地点 ●城镇 ●敌人 ●路人 ○自己"
	legend.position = Vector2(14, 242)
	legend.size = Vector2(188, 16)
	UITheme.style_label(legend, 10, UITheme.TEXT_DIM)
	panel.add_child(legend)

	_img = Image.create(MAP_TILES, MAP_TILES, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	map_rect.texture = _tex
	panel.visible = false

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M or event.physical_keycode == KEY_M:
			_toggle()
			get_viewport().set_input_as_handled()

func _toggle():
	_opened = not _opened
	panel.visible = _opened
	if _opened:
		_acc = 0.0
		_refresh()

func _process(delta):
	if not _opened:
		return
	_acc += delta
	if _acc >= REFRESH_INTERVAL:
		_acc = 0.0
		_refresh()

func _world_gen() -> Node2D:
	return get_node_or_null("/root/Main/World/WorldGenerator")

func _player() -> Node2D:
	return get_node_or_null("/root/Main/World/Player")

func _refresh():
	var wg := _world_gen()
	var pl := _player()
	if wg == null or pl == null or _img == null:
		return
	var pt := Vector2i(int(floor(pl.global_position.x / 16.0)), int(floor(pl.global_position.y / 16.0)))
	# 1) 地形采样（1px=1瓦片）
	for my in range(MAP_TILES):
		var wy: int = pt.y - HALF + my
		var row_out := my
		for mx in range(MAP_TILES):
			var wx: int = pt.x - HALF + mx
			var tid: int = wg.get_tile_id(wx, wy)
			_img.set_pixel(mx, row_out, TILE_COLORS.get(tid, DEFAULT_COLOR))
	# 2) 标记点
	for p in wg.pois:
		var m := _to_map(p["position"], pt)
		_dot(m.x, m.y, 2, Color(1.0, 0.82, 0.25))
	for tc in wg.town_centers:
		var tv := Vector2(tc.x * 16.0 + 8.0, tc.y * 16.0 + 8.0)
		var m2 := _to_map(tv, pt)
		_dot(m2.x, m2.y, 2, Color(0.35, 0.85, 0.55))
	for mob in get_tree().get_nodes_in_group("mobs"):
		var m3 := _to_map(mob.global_position, pt)
		_dot(m3.x, m3.y, 1, Color(0.90, 0.25, 0.20))
	for npc in get_tree().get_nodes_in_group("npc"):
		var m4 := _to_map(npc.global_position, pt)
		_dot(m4.x, m4.y, 1, Color(0.45, 0.75, 0.95))
	# 3) 玩家（中心白点+黑描边）
	_dot(HALF, HALF, 2, Color(0, 0, 0))
	_dot(HALF, HALF, 1, Color(1, 1, 1))
	pos_label.text = "坐标 (%d, %d)   比例 1:16" % [pt.x, pt.y]
	_tex.update(_img)

func _to_map(world_pos: Vector2, pt: Vector2i) -> Vector2i:
	return Vector2i(
		int(world_pos.x / 16.0) - pt.x + HALF,
		int(world_pos.y / 16.0) - pt.y + HALF)

func _dot(cx: int, cy: int, r: int, c: Color):
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and x < MAP_TILES and y >= 0 and y < MAP_TILES:
				_img.set_pixel(x, y, c)
