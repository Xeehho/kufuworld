extends Control

# 江湖舆图（M键开关）：全图模式——世界全域 320x320 瓦片 + 滚轮缩放 + 右键拖拽平移
# 缩放以鼠标位置为锚点；面板 STOP 拦截鼠标（大图范围内不误触攻击/重击）
# 标注：POI金点/城镇绿点/营地紫菱/敌人红点/路人蓝点/玩家白点/主线目标青虚线
# 非模态HUD（不锁移动，不在ui_modal组）

const BIG_TILES := 400
const BIG_WORLD_HALF := 200          # WORLD_RADIUS
const PANEL_SIZE := Vector2(692, 736)
const VIEW_POS := Vector2(26, 40)    # 地图显示区左上（面板内）
const VIEW_SIZE := Vector2(640, 640)
const ZOOM_MIN := 1.0                # 1px=1瓦片（整图缩略）
const ZOOM_MAX := 5.0                # 5px=1瓦片（局部详查）
const REFRESH_INTERVAL := 0.8

const TILE_COLORS := {
	0: Color(0.36, 0.56, 0.26), 1: Color(0.66, 0.53, 0.37), 2: Color(0.78, 0.46, 0.30),
	3: Color(0.36, 0.35, 0.38), 4: Color(0.16, 0.38, 0.20), 5: Color(0.26, 0.50, 0.80),
	6: Color(0.83, 0.69, 0.47), 7: Color(0.52, 0.54, 0.58), 8: Color(0.24, 0.45, 0.20),
	9: Color(0.42, 0.55, 0.28), 10: Color(0.70, 0.52, 0.33), 11: Color(0.74, 0.48, 0.30),
	12: Color(0.16, 0.14, 0.13), 13: Color(0.72, 0.45, 0.70), 14: Color(0.52, 0.52, 0.54),
	15: Color(0.62, 0.48, 0.31), 16: Color(0.52, 0.38, 0.23), 17: Color(0.68, 0.51, 0.31),
	18: Color(0.27, 0.43, 0.20), 33: Color(0.42, 0.31, 0.19), 34: Color(0.90, 0.92, 0.95),
	35: Color(0.58, 0.58, 0.56), 36: Color(0.72, 0.53, 0.30), 37: Color(0.82, 0.77, 0.58),
	39: Color(0.66, 0.42, 0.26), 40: Color(0.60, 0.58, 0.56),   # 40=青石城城墙
	41: Color(0.82, 0.86, 0.88), 42: Color(0.78, 0.82, 0.85),   # 41=雪覆农田 42=雪径
	43: Color(0.74, 0.71, 0.66),                                 # 43=唐制坊墙（W2）
	44: Color(0.72, 0.71, 0.68),                                 # 44=界碑（W3）
	# 画面改造P1：地面变体随基色、碎屑装饰近基色调（45-54变体/55-63碎屑）
	45: Color(0.36, 0.56, 0.26), 46: Color(0.36, 0.56, 0.26), 47: Color(0.30, 0.48, 0.22),
	48: Color(0.27, 0.43, 0.20), 49: Color(0.27, 0.43, 0.20), 50: Color(0.90, 0.92, 0.95),
	51: Color(0.90, 0.92, 0.95), 52: Color(0.83, 0.69, 0.47), 53: Color(0.83, 0.69, 0.47),
	54: Color(0.62, 0.48, 0.30),
	55: Color(0.32, 0.52, 0.24), 56: Color(0.32, 0.52, 0.24), 57: Color(0.40, 0.54, 0.24),
	58: Color(0.75, 0.75, 0.68), 59: Color(0.80, 0.72, 0.40), 60: Color(0.62, 0.44, 0.26),
	61: Color(0.48, 0.38, 0.24), 62: Color(0.58, 0.50, 0.30), 63: Color(0.56, 0.48, 0.30),
}
const DEFAULT_COLOR := Color(0.30, 0.44, 0.24)
const STORY_LINE_COLOR := Color(0.3, 0.95, 0.85)   # 主线引导线青色

var panel: Panel = null
var big_rect: TextureRect = null
var big_label: Label = null
var _opened := false
var _acc := 0.0
var _dragging := false
var big_zoom := 2.0                  # 显示像素/瓦片
var pan := Vector2.ZERO              # 地图中心相对显示区中心的偏移（显示像素）
var _big_terrain: Image = null       # 全图地形缓存（只采样一次）
var _big_view: Image = null          # 合成图（地形+动态标记）
var _big_tex: ImageTexture = null
var _big_built := false

func _ready():
	# HUD根节点必须全屏锚定且不拦截鼠标（项目UI规范）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()

func _build_panel():
	panel = Panel.new()
	panel.name = "WorldMapPanel"
	panel.size = PANEL_SIZE
	panel.position = Vector2((1920 - PANEL_SIZE.x) / 2.0, (1080 - PANEL_SIZE.y) / 2.0)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	panel.clip_contents = true
	# STOP：面板矩形内拦截鼠标（滚轮缩放/右键拖拽/防误攻击）
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_panel_gui_input)
	add_child(panel)

	var title := Label.new()
	title.text = "江湖全图（M关闭 · 滚轮缩放 · 拖拽平移 · 青线=主线目标）"
	title.position = Vector2(26, 10)
	title.size = Vector2(640, 22)
	UITheme.style_title(title, 15)
	panel.add_child(title)

	big_rect = TextureRect.new()
	big_rect.position = VIEW_POS
	big_rect.size = VIEW_SIZE
	big_rect.stretch_mode = TextureRect.STRETCH_SCALE
	big_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	big_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(big_rect)

	big_label = Label.new()
	big_label.position = Vector2(26, 688)
	big_label.size = Vector2(640, 20)
	big_label.clip_text = true
	big_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.style_label(big_label, 12, UITheme.TEXT_DIM)
	panel.add_child(big_label)

	var legend := Label.new()
	legend.text = "●地点 ●城镇 ◆营地 ●敌 ●路 ○自己 ◈主线目标"
	legend.position = Vector2(26, 710)
	legend.size = Vector2(640, 16)
	UITheme.style_label(legend, 10, UITheme.TEXT_DIM)
	panel.add_child(legend)

	_big_view = Image.create(BIG_TILES, BIG_TILES, false, Image.FORMAT_RGBA8)
	_big_tex = ImageTexture.create_from_image(_big_view)
	big_rect.texture = _big_tex
	_apply_view_transform()
	panel.visible = false

# ---------- 开关与输入 ----------

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M or event.physical_keycode == KEY_M:
			_toggle()
			get_viewport().set_input_as_handled()
		# ESC 支持关闭舆图（用户要求）
		elif _opened and event.keycode == KEY_ESCAPE:
			_toggle()
			get_viewport().set_input_as_handled()

func _toggle():
	_opened = not _opened
	panel.visible = _opened
	_acc = 0.0
	if _opened:
		_refresh()

func _on_panel_gui_input(event):
	# 滚轮缩放（鼠标位置为锚点）
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_zoom_at(mb.position - VIEW_POS, dir)
			get_viewport().set_input_as_handled()
			return
	# 左键/右键均可拖拽平移
	if event is InputEventMouseButton:
		var mb2 := event as InputEventMouseButton
		if mb2.button_index == MOUSE_BUTTON_LEFT or mb2.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb2.pressed
			return
	# 按住拖动平移
	if event is InputEventMouseMotion and _dragging:
		pan += (event as InputEventMouseMotion).relative
		_apply_view_transform()

func _zoom_at(local_pos: Vector2, dir: float):
	var old_zoom := big_zoom
	var new_zoom := clampf(big_zoom * (1.0 - 0.15 * dir), ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old_zoom, new_zoom):
		return
	# 保持鼠标下的瓦片不动：tile = (mp - tl)/zoom；tl' = mp - tile*zoom'
	var tl := _img_top_left()
	var tile := (local_pos - tl) / old_zoom
	pan += (local_pos - tile * new_zoom) - (local_pos - tile * old_zoom)
	big_zoom = new_zoom
	_apply_view_transform()
	_refresh()

# 地图图片在显示区内的左上角位置（显示区局部坐标，已钳制在有效范围内）
func _img_top_left() -> Vector2:
	var size := Vector2(BIG_TILES, BIG_TILES) * big_zoom
	var tl := VIEW_SIZE / 2.0 + pan - size / 2.0
	# 边界钳制：地图边缘不得进入显示区内部（杜绝无地形灰区）
	if size.x <= VIEW_SIZE.x:
		tl.x = (VIEW_SIZE.x - size.x) / 2.0   # 地图窄于视口：水平居中
	else:
		tl.x = clampf(tl.x, VIEW_SIZE.x - size.x, 0.0)
	if size.y <= VIEW_SIZE.y:
		tl.y = (VIEW_SIZE.y - size.y) / 2.0
	else:
		tl.y = clampf(tl.y, VIEW_SIZE.y - size.y, 0.0)
	return tl

func _apply_view_transform():
	if big_rect == null:
		return
	# 先钳制pan再落位，保证拖拽/缩放都不会把无效区域拖进视口
	var size := Vector2(BIG_TILES, BIG_TILES) * big_zoom
	var tl := _img_top_left()
	pan = tl + size / 2.0 - VIEW_SIZE / 2.0
	big_rect.position = VIEW_POS + tl
	big_rect.size = size

func _world_gen() -> Node2D:
	return get_node_or_null("/root/Main/World/WorldGenerator")

func _player() -> Node2D:
	return get_node_or_null("/root/Main/World/Player")

func _refresh():
	var wg := _world_gen()
	var pl := _player()
	if wg == null or pl == null:
		return
	if not _big_built:
		_build_big_terrain(wg)
	_big_view = _big_terrain.duplicate()   # 深拷贝地形底图
	var pt := Vector2i(int(floor(pl.global_position.x / 16.0)), int(floor(pl.global_position.y / 16.0)))
	# 静态与动态标注
	for p in wg.pois:
		_dot_on(_big_view, _to_big(p["position"]), 2, Color(1.0, 0.82, 0.25))
	for tc in wg.town_centers:
		var tv := Vector2(tc.x * 16.0 + 8.0, tc.y * 16.0 + 8.0)
		_dot_on(_big_view, _to_big(tv), 2, Color(0.35, 0.85, 0.55))
	# 青石城地标（金色菱形）
	var city_info: Dictionary = wg.get("city_info") if wg.get("city_info") != null else {}
	if not city_info.is_empty() and city_info.has("center_px"):
		_diamond_on(_big_view, _to_big(city_info["center_px"]), Color(1.0, 0.92, 0.5))
	_draw_camps(_big_view)
	for mob in get_tree().get_nodes_in_group("mobs"):
		_dot_on(_big_view, _to_big(mob.global_position), 1, Color(0.90, 0.25, 0.20))
	for npc in get_tree().get_nodes_in_group("npc"):
		_dot_on(_big_view, _to_big(npc.global_position), 1, Color(0.45, 0.75, 0.95))
	# 主线目标引导线
	var target: Dictionary = _story_target()
	if not target.is_empty():
		var from := _to_big(pl.global_position)
		var to := _to_big(target["pos"])
		_draw_dashed_line(_big_view, from, to)
		_diamond_on(_big_view, to, STORY_LINE_COLOR)
		big_label.text = "坐标 (%d, %d) · 缩放 %.1fx · 主线「%s」◈青线导向" % [pt.x, pt.y, big_zoom, str(target.get("name", ""))]
	else:
		big_label.text = "坐标 (%d, %d) · 缩放 %.1fx · 暂无主线目标标注" % [pt.x, pt.y, big_zoom]
	_dot_on(_big_view, _to_big(pl.global_position), 2, Color(0, 0, 0))
	_dot_on(_big_view, _to_big(pl.global_position), 1, Color(1, 1, 1))
	_big_tex.update(_big_view)

func _build_big_terrain(wg: Node2D):
	_big_terrain = Image.create(BIG_TILES, BIG_TILES, false, Image.FORMAT_RGBA8)
	for y in range(BIG_TILES):
		var wy: int = y - BIG_WORLD_HALF
		for x in range(BIG_TILES):
			var tid: int = wg.get_tile_id(x - BIG_WORLD_HALF, wy)
			_big_terrain.set_pixel(x, y, TILE_COLORS.get(tid, DEFAULT_COLOR))
	_big_built = true
	print("[Minimap] 全图地形采样完成（%dx%d 瓦片）" % [BIG_TILES, BIG_TILES])

func _to_big(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / 16.0) + BIG_WORLD_HALF,
		int(world_pos.y / 16.0) + BIG_WORLD_HALF)

func _story_target() -> Dictionary:
	var story = get_node_or_null("/root/Main/MainStory")
	if story and story.has_method("get_story_target"):
		return story.get_story_target()
	return {}

# ---------- 标注绘制 ----------

func _draw_camps(img: Image):
	var ms := get_node_or_null("/root/Main/World/MobSpawner")
	if ms == null:
		return
	for camp in ms.camps_runtime:
		_diamond_on(img, _to_big(camp["center"]), Color(0.85, 0.30, 0.60))
	for scamp in ms.story_camps:
		_diamond_on(img, _to_big(scamp["center"]), Color(0.85, 0.30, 0.60))

func _dot_on(img: Image, m: Vector2i, r: int, c: Color):
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x: int = m.x + dx
			var y: int = m.y + dy
			if x >= 0 and x < BIG_TILES and y >= 0 and y < BIG_TILES:
				img.set_pixel(x, y, c)

func _diamond_on(img: Image, m: Vector2i, c: Color):
	for d in range(0, 4):
		for s in [-1, 1]:
			var sx: int = s
			var x: int = m.x + sx * d
			var y: int = m.y - (3 - d)
			if x >= 0 and x < BIG_TILES and y >= 0 and y < BIG_TILES:
				img.set_pixel(x, y, c)
			y = m.y + (3 - d)
			if x >= 0 and x < BIG_TILES and y >= 0 and y < BIG_TILES:
				img.set_pixel(x, y, c)

func _draw_dashed_line(img: Image, from: Vector2i, to: Vector2i):
	var dist := from.distance_to(to)
	if dist < 3.0:
		return
	var steps := int(dist / 4.0)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := Vector2(from).lerp(Vector2(to), t)
		var x := int(p.x)
		var y := int(p.y)
		if x >= 0 and x < BIG_TILES and y >= 0 and y < BIG_TILES:
			img.set_pixel(x, y, STORY_LINE_COLOR)

func _process(delta):
	if not _opened:
		return
	_acc += delta
	if _acc >= REFRESH_INTERVAL:
		_acc = 0.0
		_refresh()
