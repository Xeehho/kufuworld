extends RefCounted

## v4 城镇全量重构——聚落布局工具类（docs/立项-v4城镇全量重构.md §3.1）
## 样板区 town_demo_kit 验证过的布局能力下放；M1~M4 镇/城坊/门派殿堂以 spec 表驱动消费。
## 消费方式（项目惯例 preload，勿加 class_name——P0.1 踩坑）：
##   const TownLayoutKit = preload("res://scripts/town_layout_kit.gd")
##   var kit := TownLayoutKit.new(); kit.bind(world_gen, host_node, origin_rect)
##   host=prop 挂载点：样板区=demo kit 自身（Node2D，World 递归 Y-sort 吸收）；镇/城=WorldGenerator 父级 World。
## ⚠️ 语义契约（立项书 §3.6，P0/P3 踩坑已证）：
## 1) override 层方法（pave/pave_rect/flatten_ground/farm_ridges/yard_ground）**必须先于 chunk 预载**
##    ——上漆只发生在 _load_chunk 且只画未设置格，后写不上屏（样板区 P3 院门径曾因此隐形）
## 2) prop 层方法（建筑/围栏/装点）在 chunk 预载后任意时机可用
## 3) 镇/城建筑必须走 place_building_39（39 占格进 collision_tiles：可达性/官道截断/连通性全依赖），
##    kit 不提供关闭入口；stamp_prefab_building 仅限纯视觉建筑（样板区语义）
## 4) plot["job"] 岗位槽位随 spec 走——town_info.buildings[].job 是 npc_spawner 落位链硬依赖

const TextureGen = preload("res://scripts/texture_generator.gd")

# ---- 配套纹理（sprites/demo 缺失时 Main._ensure_textures 补生成） ----
const FENCE_PNG := "res://sprites/demo/demo_fence.png"
const TRELLIS_PNG := "res://sprites/demo/demo_trellis.png"
const FLOWERS_PNG := "res://sprites/demo/demo_flowers.png"
const CROP_PNGS := ["res://sprites/farm/crop_1.png", "res://sprites/farm/crop_2.png", "res://sprites/farm/crop_3.png"]
const ORCHARD_SHEET := "res://sprites/tiles_mw22/tree_oak.png"  # MW橡树表（4x2变体，帧64x64；MW换血Slice B）
const ORCHARD_SHEET_FALLBACK := "res://downloaded_assets/Pixel Crawler - Free Pack/Environment/Props/Static/Trees/Model_01/Size_02.png"  # MW素材缺失回退PC包
const DECO_TILES := [13, 55, 56, 57, 58, 59, 60, 61, 62, 63]   # 密度统计口径：花卉/碎屑层瓦片

var wg                        # WorldGenerator 引用（无类型）
var host: Node = null         # prop 挂载点
var origin := Rect2i(0, 0, 0, 0)  # 工作区（局部→全局变换基准）
var occupied := {}            # 占用格（建筑/围栏/树/道具/花簇）——撒点避让
var plots: Array = []         # 地块记录制 [{kind, bounds:Rect2i(全局), door:Vector2i(全局), job}]
var glow_lights: Array = []   # glow 灯光列表（宿主 _process 按昼夜调 energy）
var _glow_tex: ImageTexture = null

func bind(world_gen, host_node, origin_rect) -> void:
	wg = world_gen
	host = host_node
	origin = origin_rect

func g(p: Vector2i) -> Vector2i:
	"""局部坐标 → 全局瓦片坐标。"""
	return origin.position + p

# ================= override 层（必须先于 chunk 预载） =================

func pave(c: Vector2i) -> void:
	"""铺 path（群系调色板）；水面跳过（路不入水）。"""
	if wg.get_tile_id(c.x, c.y) == 5:
		return
	wg.override_cells[c] = wg._palette_at(c.x, c.y)["path"]

func pave_rect(r: Rect2i, tile: int) -> void:
	"""矩形铺装（广场 35/垄行 16 等整瓦片）；水面与建筑占格(39)跳过（M2：market 广场
	在建筑之后铺，不得覆盖 39 占格——否则可达性/碰撞语义被静默破坏）。"""
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			var t: int = wg.get_tile_id(xx, yy)
			if t == 5 or t == wg.TILE_BUILDING_RESERVE:
				continue
			wg.override_cells[Vector2i(xx, yy)] = tile

func flatten_ground(margin := 0) -> int:
	"""工作区(+外扩 margin 视觉缓冲带)内 山(3)/雪山(7) 平整为群系地面；水(5) 保留
	（崖清除=碰撞减少，可达性只增不减）。返回平整格数。"""
	var n := 0
	for yy in range(origin.position.y - margin, origin.end.y + margin):
		for xx in range(origin.position.x - margin, origin.end.x + margin):
			var c := Vector2i(xx, yy)
			var t: int = wg.get_tile_id(xx, yy)
			if t == 3 or t == 7:
				wg.override_cells[c] = wg._palette_at(xx, yy)["ground"]
				n += 1
	return n

func make_plots(spec: Array) -> Array:
	"""地块记录制：spec=[{kind, bounds:Rect2i(局部), door:Vector2i(局部), job(可选)}]
	→ 全局化 plots（plot["job"]=岗位槽位，npc_spawner 落位链消费）。返回 plots。"""
	plots = []
	for s in spec:
		var b: Rect2i = s["bounds"]
		plots.append({
			"kind": s["kind"],
			"bounds": Rect2i(g(b.position), b.size),
			"door": g(s["door"]),
			"job": s.get("job", ""),
		})
	return plots

func farm_ridges(plot: Dictionary) -> void:
	"""菜圃垄行：bounds 内缩 1、每 2 行铺农田瓦 16（垄间草地走道="作物成行"基底）。override 层！"""
	var b: Rect2i = plot["bounds"]
	var yy := b.position.y + 1
	while yy <= b.end.y - 2:
		for xx in range(b.position.x + 1, b.end.x - 1):
			wg.override_cells[Vector2i(xx, yy)] = 16
		yy += 2

func yard_ground(plot: Dictionary) -> void:
	"""建筑地块地面：门径 door→南缘外 1 格接巷 + 前院碎石平台 3x2。override 层！
	（P3 踩坑补正：铺装晚于 chunk 预载则永不上漆——门径必须在本阶段写入。）"""
	var b: Rect2i = plot["bounds"]
	var door: Vector2i = plot["door"]
	for cy in range(door.y, b.end.y + 1):          # 门径：door 南行至南缘外接巷
		pave(Vector2i(door.x, cy))
	for dx in range(-1, 2):                        # 前院平台 3x2
		for dy in range(0, 2):
			pave(Vector2i(door.x + dx, door.y + dy))

# ================= prop 层（chunk 预载后任意时机） =================

func place_building_39(kind: String, a: Vector2i) -> bool:
	"""镇/城建筑标准落位：39 占格(进 collision_tiles) + 现行精灵 + StaticBody——
	委托 wg._place_building_prop（单一事实源，kit 不重复实现）；成功后登记 occupied。"""
	if not wg._place_building_prop(kind, a):
		return false
	var fp: Vector2i = wg.BUILDING_PROPS[kind]["fp"]
	for dx in range(fp.x):
		for dy in range(fp.y):
			occupied[Vector2i(a.x + dx, a.y + dy)] = true
	return true

func stamp_prefab_building(png: String, fp: Vector2i, a: Vector2i, group := "demo_building") -> bool:
	"""纯视觉 prefab 建筑落位（样板区语义：Sprite z=2 底缘锚定并入 World 递归 Y-sort +
	墙脚软影 + StaticBody 挡人，零瓦片语义不写 39）。
	⚠️ 镇/城建筑必须走 place_building_39（39 占格语义不可断）。"""
	var tex := TextureGen.load_png_texture(png)
	if tex == null:
		push_warning("[LayoutKit] prefab 建筑纹理缺失: " + png)
		return false
	for dx in range(fp.x):
		for dy in range(fp.y):
			occupied[Vector2i(a.x + dx, a.y + dy)] = true   # 撒点避让
	var bw := fp.x * 16.0
	var bh := fp.y * 16.0
	var base_cx := (a.x + fp.x * 0.5) * 16.0
	var base_y := float((a.y + fp.y) * 16.0)
	var root := Node2D.new()
	root.z_index = 2
	root.position = Vector2(base_cx, base_y)
	root.add_to_group(group)
	var shadow := Sprite2D.new()
	shadow.texture = TextureGen.get_shadow_texture()
	shadow.scale = Vector2((bw + 24.0) / 48.0, maxf(12.0, bw * 0.30) / 20.0)
	shadow.position = Vector2(0, -3)
	shadow.z_index = -1
	shadow.modulate = Color(0, 0, 0, 0.28)
	shadow.add_to_group("tree_shadow")
	root.add_child(shadow)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = Vector2(0, -tex.get_height() * 0.5 + 4.0)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(spr)
	var body := StaticBody2D.new()
	body.position = Vector2(0, -bh * 0.5 + 2.0)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(bw - 4, bh - 4)
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	host.add_child(root)
	return true

func fence_ring(b: Rect2i, skip: Dictionary = {}) -> void:
	"""地块边界一圈栅栏：32px 双格单元（横边步 2、竖边步 2，角点由横边覆盖）；skip=留口格。"""
	var x0 := b.position.x
	var x1 := b.end.x - 1
	var y0 := b.position.y
	var y1 := b.end.y - 1
	var cx := x0
	while cx <= x1:
		if not skip.has(Vector2i(cx, y0)):
			_stamp_fence(Vector2i(cx, y0), false)
		if not skip.has(Vector2i(cx, y1)):
			_stamp_fence(Vector2i(cx, y1), false)
		cx += 2
	var cy := y0 + 2
	while cy <= y1 - 2:
		if not skip.has(Vector2i(x0, cy)):
			_stamp_fence(Vector2i(x0, cy), true)
		if not skip.has(Vector2i(x1, cy)):
			_stamp_fence(Vector2i(x1, cy), true)
		cy += 2

func _stamp_fence(cell: Vector2i, vertical: bool):
	"""栅栏单元：横排底缘锚定（Y-sort 正确）；竖排格中心锚定+90° 旋转（中心对称免 offset 偏移）。
	occupied 守卫：建筑/既有 prop 格跳过（紧凑地块防围栏穿墙角）。"""
	if occupied.has(cell):
		return
	var tex := TextureGen.load_png_texture(FENCE_PNG)
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.z_index = 2
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if vertical:
		spr.position = Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)
		spr.rotation_degrees = 90.0
	else:
		spr.position = Vector2(cell.x * 16.0 + 8.0, (cell.y + 1) * 16.0 - 2.0)
		spr.offset = Vector2(0, -tex.get_height() * 0.5)
	occupied[cell] = true
	host.add_child(spr)

func yard_fence(plot: Dictionary) -> void:
	"""建筑地块围栏：南缘 door±1 留口（prop 层）。"""
	var b: Rect2i = plot["bounds"]
	var door: Vector2i = plot["door"]
	var skip := {}
	for sx in range(door.x - 1, door.x + 2):
		skip[Vector2i(sx, b.end.y - 1)] = true
	fence_ring(b, skip)

func farm_dress(plot: Dictionary) -> int:
	"""菜圃装点：垄格撒作物 70% + 稻草人 + 棚架x2 + 围栏（北缘 door±1 留口）。返回 crop 数。prop 层。"""
	var b: Rect2i = plot["bounds"]
	var door: Vector2i = plot["door"]
	var n := 0
	var yy := b.position.y + 1
	while yy <= b.end.y - 2:
		for xx in range(b.position.x + 1, b.end.x - 1):
			var cr := fposmod(wg.detail_noise.get_noise_2d(xx * 3.7 + 5.1, yy * 4.3 + 9.9) + 1.0, 1.0)
			if cr > 0.30:
				stamp_prop(CROP_PNGS[int(cr * 100.0) % CROP_PNGS.size()], Vector2i(xx, yy))
				n += 1
		yy += 2
	stamp_prop("res://sprites/buildings/scarecrow.png",
			Vector2i((b.position.x + b.end.x) / 2, (b.position.y + b.end.y) / 2))
	stamp_prop(TRELLIS_PNG, Vector2i(b.position.x + 2, b.position.y + 2))
	stamp_prop(TRELLIS_PNG, Vector2i(b.end.x - 3, b.end.y - 3))
	var skip := {}
	for sx in range(door.x - 1, door.x + 2):       # 北缘门侧留口（door 在横巷行）
		skip[Vector2i(sx, b.position.y)] = true
	fence_ring(b, skip)
	return n

func stamp_tree(c: Vector2i, sheet: Texture2D = null) -> bool:
	"""橡树 prop：AtlasTexture 切 4 变体（**仅上排 0..3 春夏绿树**——下排雪/枯会季节错乱），
	脚底入土锚定 + 树影。sheet 可外部传入免重复加载。"""
	if sheet == null:
		sheet = TextureGen.load_png_texture(ORCHARD_SHEET)
	if sheet == null:
		sheet = TextureGen.load_png_texture(ORCHARD_SHEET_FALLBACK)
	if sheet == null:
		return false
	var variant := int(fposmod(wg.detail_noise.get_noise_2d(c.x * 5.1, c.y * 7.3) + 1.0, 1.0) * 4.0) % 4
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(float(variant % 4) * 64.0, float(variant / 4) * 64.0, 64.0, 64.0)
	var spr := Sprite2D.new()
	spr.texture = atlas
	spr.z_index = 2
	spr.position = Vector2(c.x * 16.0 + 8.0, c.y * 16.0 + 20.0)
	spr.offset = Vector2(0, -32.0)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sh := TextureGen.make_shadow_sprite(40.0, 0.30)
	sh.position = Vector2(0, -4)
	sh.z_index = -1
	spr.add_child(sh)
	host.add_child(spr)
	occupied[c] = true
	return true

func stamp_prop(png: String, cell: Vector2i, glow: bool = false, group: String = "") -> bool:
	"""脚底锚定装饰道具（原点=贴图底缘，z=2 并入 World 递归 Y-sort；不占格不碰撞）。
	glow=true 挂 PointLight2D 暖光晕（UNSHADED 免疫不了 CanvasModulate，必须走 Light2D；
	energy 由宿主 _process 按 kit.glow_lights 昼夜自适应）。group 非空时入组（预算统计用）。"""
	var tex := TextureGen.load_png_texture(png)
	if tex == null:
		return false
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.z_index = 2
	var pos := Vector2(cell.x * 16.0 + 8.0, (cell.y + 1) * 16.0 - 2.0)
	spr.position = pos
	spr.offset = Vector2(0, -tex.get_height() * 0.5)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.set_meta("base_y", pos.y)
	if group != "":
		spr.add_to_group(group)
	if glow:
		var light := PointLight2D.new()
		light.texture = _glow_texture()
		light.energy = 1.5
		light.color = Color(1.0, 0.72, 0.38)
		light.texture_scale = 2.0
		light.position = Vector2(0, -tex.get_height() * 0.5)
		spr.add_child(light)
		glow_lights.append(light)
	var sh := TextureGen.make_shadow_sprite(clampf(tex.get_width() * 0.85, 14.0, 44.0), 0.24)
	sh.position = Vector2(0, -2)
	spr.add_child(sh)
	host.add_child(spr)
	return true

func _glow_texture() -> ImageTexture:
	"""灯笼光晕径向渐变（96x96，运行时内存生成不落盘）。"""
	if _glow_tex != null:
		return _glow_tex
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in range(96):
		for x in range(96):
			var d := Vector2(x - 48.0, y - 48.0).length() / 48.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * 0.9))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex

# ---- 撒点闸门与装点 ----

func cell_free(c: Vector2i) -> bool:
	"""撒点闸门：非占用（建筑/围栏/已放 prop）且非铺装/垄（平整后的地面格允许）。"""
	if occupied.has(c):
		return false
	if wg.override_cells.has(c):
		var ov: int = wg.override_cells[c]
		if ov != wg._palette_at(c.x, c.y)["ground"]:   # 平整产物=可种，铺装/垄=拒
			return false
	var t: int = wg.get_tile_id(c.x, c.y)
	return not (t in BUILD_TILES) and not (t in GEO_TILES)

func near_paved(c: Vector2i, r: int = 1) -> bool:
	"""冠幅避让：锚点周围 r 格内有铺装/垄 override → 树冠悬伸会压石板/路，拒种。"""
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var n: Vector2i = c + Vector2i(dx, dy)
			if wg.override_cells.has(n) and wg.override_cells[n] != wg._palette_at(n.x, n.y)["ground"]:
				return true
	return false

func near_blocked(c: Vector2i, r: int = 1) -> bool:
	"""冠幅避让（扩展）：周围 r 格内有铺装/垄 **或已占用（含围栏）** → 拒种。"""
	if near_paved(c, r):
		return true
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if occupied.has(c + Vector2i(dx, dy)):
				return true
	return false

func scatter_props(area: Rect2i, ratio: float = 0.42, seedv: int = 424242) -> int:
	"""8×8 网格道具组：ratio 概率放灯笼（glow）或桶+箱组合。返回组数。"""
	var n := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seedv
	for gy in range(0, int(area.size.y / 8.0) + 1):
		for gx in range(0, int(area.size.x / 8.0) + 1):
			if rng.randf() > ratio:
				continue
			var base := area.position + Vector2i(gx * 8 + 3 + rng.randi() % 3,
					gy * 8 + 3 + rng.randi() % 3)
			if not cell_free(base):
				continue
			if rng.randi() % 3 == 0:
				stamp_prop("res://sprites/buildings/lantern.png", base, true)   # glow：夜景常亮
			else:
				stamp_prop("res://sprites/buildings/barrel.png", base)
				var c2 := base + Vector2i(1, 0)
				if cell_free(c2):
					stamp_prop("res://sprites/buildings/crate.png", c2)
			occupied[base] = true
			n += 1
	return n

func scatter_flowers(area: Rect2i, ratio: float = 0.05, cap: int = 35) -> int:
	"""花簇：区内空格 ratio 噪声撒（上限 cap 簇），补装饰密度。返回簇数。"""
	var n := 0
	for yy in range(area.position.y, area.end.y):
		for xx in range(area.position.x, area.end.x):
			if n >= cap:
				return n
			var c := Vector2i(xx, yy)
			if not cell_free(c):
				continue
			var cr := fposmod(wg.detail_noise.get_noise_2d(c.x * 4.9 + 1.7, c.y * 2.9 + 8.8) + 1.0, 1.0)
			if cr > ratio:
				continue
			stamp_prop(FLOWERS_PNG, c)
			occupied[c] = true
			n += 1
	return n

func report_density(area: Rect2i, tag: String) -> float:
	"""装饰密度量化=（碎屑瓦片格+占用格）/自然格（铺装/垄/建筑/山水除外）；样板区标准 ≥25%。
	仅统计打印，供回归密度报告消费。返回百分比。"""
	var natural := 0
	var decorated := 0
	for yy in range(area.position.y, area.end.y):
		for xx in range(area.position.x, area.end.x):
			var c := Vector2i(xx, yy)
			var t: int = wg.get_tile_id(xx, yy)
			if t in BUILD_TILES or t in GEO_TILES or wg.override_cells.has(c):
				continue
			natural += 1
			if t in DECO_TILES or occupied.has(c):
				decorated += 1
	var dens := float(decorated) / maxf(1.0, float(natural)) * 100.0
	print("[LayoutKit] 密度[%s]：装饰 %.1f%%（目标≥25%%）自然格 %d" % [tag, dens, natural])
	return dens

# ---- 瓦片分类（撒点闸门用；与 town_demo_kit 选址口径一致） ----
# 建筑/栅栏/农田/桥/铺装/城墙——一票否决
const BUILD_TILES := [2, 10, 11, 12, 15, 16, 17, 33, 35, 39, 40, 41, 42, 43]
const GEO_TILES := [3, 5, 7]   # 山/水/雪山
