extends Node2D

const TextureGen = preload("res://scripts/texture_generator.gd")

## 城镇样板区（材质包 1:1 复刻试点）——docs/立项-城镇样板区重构.md
## P0 骨架：程序化选址（避让一切既有领地）→ 净空/chunk 登记 → 入口路 → 边界标记 → 立牌
## 铁律（立项书 §2.3）：区内内容纯视觉——prop 不占格不碰撞；不修改镇/城/门派选址行为；
## 选址失败兜底=静默关闭（不阻塞游戏）；回归 102 断言零新增。

const W := 56                  # 样板区宽（格）
const H := 44                  # 样板区高（格）

# 选址瓦片分两类（2026-09-02 实测：半径150内"零山零水"56x44 净地不存在——山611/水253/雪山147
# 是主要否决源，故允许少量自然地理瓦片并在 build 时平整为群系地面；人工领地瓦片零容忍）。
const BUILD_TILES := [2, 10, 11, 12, 15, 16, 17, 33, 35, 39, 40, 41, 42, 43]   # 建筑/栅栏/农田/桥/铺装/城墙——一票否决
const GEO_TILES := [3, 5, 7]                                                   # 山/水/雪山——平整，占比受控
const GEO_MAX_RATIO := 0.15
const SOFT_TILES := [4, 8, 9, 14]   # 软性植被：树×3+石头（chunk 加载时被 clearance 自动清掉，占比防密林）
const SOFT_MAX_RATIO := 0.26        # 区内植被占比上限（防落进密林）

var wg                         # WorldGenerator 引用（无类型，避免依赖）
var rect := Rect2i(0, 0, 0, 0) # 选定区域（瓦片坐标）
var gate_in := Vector2i.ZERO   # 区口（rect 内侧 3 格，P1 主巷由此延续）
var road_set := {}             # 官道格集合（选址避让走廊）
var plots: Array = []          # P1 地块记录制：[{kind, bounds:Rect2i(全局), door:Vector2i(全局)}]
var built := false

func setup(world_gen) -> bool:
	"""程序化选址：以出生点为锚的网格扫描（步长6、半径150），按距离从近到远取首个
	"净地+官道可接入"的 56x44 矩形（立项书 §2.2；半径放宽 40→150 为 §4.4 风险1预案）。"""
	wg = world_gen
	for road in wg.official_roads:
		for c in road["cells"]:
			road_set[c] = true
	var spawn: Vector2 = wg._spawn_tile()
	var sc := Vector2i(int(spawn.x), int(spawn.y))
	var cands: Array = []
	var R := 150
	var gy := -R
	while gy <= R:
		var gx := -R
		while gx <= R:
			if Vector2(gx, gy).length() <= float(R):
				cands.append(sc + Vector2i(gx, gy))
			gx += 6
		gy += 6
	cands.sort_custom(func(a, b):
		return (a - sc).length_squared() < (b - sc).length_squared())
	for c in cands:
		var cand := Rect2i(c.x - W / 2, c.y - H / 2, W, H)
		var why := _site_reason(cand)
		if why == "" and _gate_reachable(cand):
			rect = cand
			print("[DemoKit] 选址成功 rect=%s 中心=%s 距出生点 %.0f 格" % [
				str(rect), str(rect.position + rect.size / 2), Vector2(c - sc).length()])
			return true
		_dbg[why if why != "" else "gate"] = int(_dbg.get(why if why != "" else "gate", 0)) + 1
	print("[DemoKit] 选址否决分布(1963候选): " + str(_dbg))
	print("[DemoKit] hard瓦片计数: " + str(_dbg_tid))
	push_warning("[DemoKit] 半径150内无 56x44 可行地，样板区关闭（不阻塞游戏）")
	return false

var _dbg := {}
var _dbg_tid := {}

func _gate_reachable(r: Rect2i) -> bool:
	"""官道最近格距 rect ≤55（入口路 BFS 框+60 内可达），保证 P0 入口路必然铺成。"""
	var best := 1 << 30
	for road in wg.official_roads:
		for c in road["cells"]:
			var dx := maxf(maxf(r.position.x - c.x, c.x - (r.end.x - 1)), 0.0)
			var dy := maxf(maxf(r.position.y - c.y, c.y - (r.end.y - 1)), 0.0)
			best = mini(best, int(dx * dx + dy * dy))
	return best <= 55 * 55

func build():
	"""总入口：登记→平整→地块划分→入口路→路网→chunk→边界→立牌。
	⚠️ 顺序契约：override 写入（平整/铺路）必须先于 _load_zone_chunks——上漆只发生在 _load_chunk。"""
	if rect.size == Vector2i.ZERO:
		return
	wg.demo_zone_rect = rect   # 营地/野怪经 is_in_settlement 自动避让
	# 净空登记（复用镇 clearance 机制：树/岩不再生成，镇/POI 选址避让）——必须在 chunk 预载前
	wg._register_town_clearance(rect.position.x + rect.size.x / 2,
			rect.position.y + rect.size.y / 2, maxi(rect.size.x, rect.size.y) / 2 + 1)
	_flatten_ground()
	_stamp_plots()     # P1：地块划分（记录制，供 P2 建筑/P3 院落消费）
	_lay_gate_road()   # P0：官道→区口（2 宽）
	_lay_roads()       # P1：连接巷+主巷蜿蜒+支巷+广场（2 宽主巷/1 宽支巷三级）
	_stamp_farm_ridges()  # P3：菜圃垄行农田瓦（override，必须先于 chunk 预载）
	_load_zone_chunks()
	_place_buildings() # P2：建筑 prefab 落位（prop 不依赖瓦片上漆，chunks 后任意时机）
	_place_yards()     # P3：前院门径/围栏/作物精灵/稻草人棚架
	_mark_boundary()
	_place_sign()
	built = true
	print("[DemoKit] 样板区建成：P0 骨架+P1 路网+P2 建筑+P3 院落菜圃（%d 地块）" % plots.size())

func _flatten_ground():
	"""区内自然地理瓦片（山3/水5/雪山7）平整为群系地面——村建谷地，呼应 §三"接现状水域"。
	只写 override（在受影响 chunk 加载前执行，_load_chunk 上漆时生效）；碰撞随之消失=可达性只增不减。"""
	var n := 0
	for yy in range(rect.position.y, rect.end.y):
		for xx in range(rect.position.x, rect.end.x):
			var c := Vector2i(xx, yy)
			if wg.get_tile_id(xx, yy) in GEO_TILES:
				wg.override_cells[c] = wg._palette_at(xx, yy)["ground"]
				n += 1
	print("[DemoKit] 平整地理瓦片 %d 格（山/水/雪山→群系地面）" % n)

# ---- P1 路网与地块（立项书 §三 布局总图，局部坐标 56x44，区口北缘 lx=52） ----

func _g(p: Vector2i) -> Vector2i:
	"""局部坐标 → 全局瓦片坐标。"""
	return rect.position + p

func _stamp_plots():
	"""P1 地块划分（记录制）：布局对齐立项书 §三——北带谷仓/水井广场/温室，主巷南缘
	农舍A/长屋/农舍B/杂货铺（门直接贴巷），南带菜圃A/B。bounds 供建筑落位+院围+密度量化。"""
	plots = [
		{"kind": "barn",       "bounds": Rect2i(_g(Vector2i(4, 1)), Vector2i(11, 9)),   "door": _g(Vector2i(9, 9))},
		{"kind": "well_plaza", "bounds": Rect2i(_g(Vector2i(22, 1)), Vector2i(12, 11)), "door": _g(Vector2i(27, 11))},
		{"kind": "greenhouse", "bounds": Rect2i(_g(Vector2i(40, 1)), Vector2i(12, 8)),  "door": _g(Vector2i(45, 8))},
		{"kind": "house_a",    "bounds": Rect2i(_g(Vector2i(4, 13)), Vector2i(11, 13)), "door": _g(Vector2i(14, 13))},
		{"kind": "longhouse",  "bounds": Rect2i(_g(Vector2i(17, 13)), Vector2i(12, 13)), "door": _g(Vector2i(22, 13))},
		{"kind": "house_b",    "bounds": Rect2i(_g(Vector2i(31, 13)), Vector2i(10, 13)), "door": _g(Vector2i(35, 13))},
		{"kind": "shop",       "bounds": Rect2i(_g(Vector2i(43, 13)), Vector2i(10, 13)), "door": _g(Vector2i(47, 13))},
		{"kind": "farm_a",     "bounds": Rect2i(_g(Vector2i(5, 28)), Vector2i(14, 10)),  "door": _g(Vector2i(9, 27))},
		{"kind": "farm_b",     "bounds": Rect2i(_g(Vector2i(23, 28)), Vector2i(12, 10)), "door": _g(Vector2i(26, 27))},
	]
	for p in plots:
		print("[DemoKit]   地块[%s] bounds=%s door=%s" % [p["kind"], str(p["bounds"]), str(p["door"])])

func _lay_roads():
	"""P1 三级路网：连接巷(2宽)→主巷(2宽 4段折线蜿蜒横贯)→支巷(1宽 纵3+横1通菜圃)+水井广场石板。
	全部无碰撞瓦片（path=1 / plaza=35）；必须在 _load_zone_chunks 前调用（override 上漆一次性）。"""
	# 1 连接巷：区口（局部52,0，接 P0 入口路）向南下到主巷东端，2 宽 x=52,53
	for ly in range(0, 10):
		_pave(_g(Vector2i(52, ly)))
		_pave(_g(Vector2i(53, ly)))
	# 2 主巷：3 段大弯蜿蜒（弯幅 3 格对齐材质包样图走势；2 宽=(x,y)+(x,y+1)，段间竖向过渡 2 宽）
	for s in [[3, 20, 9], [21, 38, 12], [39, 52, 9]]:
		for lx in range(int(s[0]), int(s[1]) + 1):
			_pave(_g(Vector2i(lx, int(s[2]))))
			_pave(_g(Vector2i(lx, int(s[2]) + 1)))
	for tx in [21, 22, 39, 40]:        # 弯折竖向过渡（y 9→12→9）
		for ly in range(9, 13):
			_pave(_g(Vector2i(tx, ly)))
	# 3 支巷（1 宽）：北带谷仓门已邻主巷段1 y=9；南带纵巷×3（地块间隙）+横巷（菜圃带）
	for lx in [15, 29, 41]:            # 纵巷：主巷南缘 y=14 穿地块间隙至横巷
		for ly in range(14, 28):
			_pave(_g(Vector2i(lx, ly)))
	for lx in range(9, 48):            # 横巷 y=27：连纵巷与菜圃 A/B 北门
		_pave(_g(Vector2i(lx, 27)))
	# 4 水井广场（石板 35）：局部 (24..31, 4..11)，南缘 y=11 邻主巷段2 y=12
	for lx in range(24, 32):
		for ly in range(4, 12):
			wg.override_cells[_g(Vector2i(lx, ly))] = 35
	print("[DemoKit] 三级路网铺装完成：连接巷+主巷3段大弯(2宽)+纵巷3/横巷1(1宽)+水井广场")

# ---- P2 建筑 Prefab 落位（纹理由 texture_generator.generate_demo_buildings 生成，Main._ensure_textures 接线） ----

const DEMO_BUILDINGS := {
	"demo_barn":  {"png": "res://sprites/demo/demo_barn.png",  "fp": Vector2i(6, 5)},
	"demo_long":  {"png": "res://sprites/demo/demo_long.png",  "fp": Vector2i(6, 4)},
	"demo_green": {"png": "res://sprites/demo/demo_green.png", "fp": Vector2i(5, 4)},
	"demo_shop":  {"png": "res://sprites/demo/demo_shop.png",  "fp": Vector2i(4, 3)},
	"demo_house": {"png": "res://sprites/demo/demo_house.png", "fp": Vector2i(4, 3)},
	"demo_well":  {"png": "res://sprites/buildings/well.png",  "fp": Vector2i(1, 1)},
}

func _place_buildings():
	"""P2：按 plots 落位 prefab（锚点=局部坐标表，占位居地块内偏北留前院）；
	落位后重算 plot.door=建筑底缘中点（门朝南），供 P3 门前小径接巷。"""
	var anchor := {
		"barn":       ["demo_barn", Vector2i(6, 2)],
		"well_plaza": ["demo_well", Vector2i(27, 7)],
		"greenhouse": ["demo_green", Vector2i(43, 4)],
		"house_a":    ["demo_house", Vector2i(7, 17)],
		"longhouse":  ["demo_long", Vector2i(20, 17)],
		"house_b":    ["demo_house", Vector2i(34, 17)],
		"shop":       ["demo_shop", Vector2i(45, 17)],
	}
	var n := 0
	for p in plots:
		var k: String = p["kind"]
		if not anchor.has(k):
			continue
		var def: Array = anchor[k]
		var a: Vector2i = _g(def[1])
		var fp: Vector2i = DEMO_BUILDINGS[def[0]]["fp"]
		_stamp_building(def[0], a)
		p["door"] = Vector2i(a.x + int(fp.x / 2.0), a.y + fp.y)
		n += 1
		if k != "well_plaza":
			# 檐下道具（P2 要素4）：建筑左墙脚桶、右墙脚箱（脚底=建筑底缘行）
			var feet_y: int = a.y + fp.y - 1
			_stamp_prop("res://sprites/buildings/barrel.png", Vector2i(a.x - 1, feet_y))
			_stamp_prop("res://sprites/buildings/crate.png", Vector2i(a.x + fp.x, feet_y))
	print("[DemoKit] 建筑落位 %d 栋（四要素：木框抹灰墙/瓦顶烟囱/门窗台/檐下桶箱）" % n)

func _stamp_building(kind: String, a: Vector2i) -> bool:
	"""样板区建筑落位（铁律 §2.3：decor-prop 形态 Sprite+StaticBody，不写 override 不进瓦片碰撞）。
	Sprite z=2 底缘锚定并入 World 递归 Y-sort；墙脚软影；StaticBody 挡人（零瓦片语义）。"""
	var def: Dictionary = DEMO_BUILDINGS[kind]
	var tex := TextureGen.load_png_texture(def["png"])
	if tex == null:
		push_warning("[DemoKit] demo 建筑纹理缺失: " + kind)
		return false
	var fp: Vector2i = def["fp"]
	var bw := fp.x * 16.0
	var bh := fp.y * 16.0
	var base_cx := (a.x + fp.x * 0.5) * 16.0
	var base_y := float((a.y + fp.y) * 16.0)
	var root := Node2D.new()
	root.z_index = 2
	root.position = Vector2(base_cx, base_y)
	root.add_to_group("demo_building")
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
	add_child(root)
	return true

# ---- P3 院落与菜圃（立项书 §三：地块围栏围合、菜圃作物成行+稻草人/棚架；Farm.png 栅栏语义） ----

const FENCE_PNG := "res://sprites/demo/demo_fence.png"
const TRELLIS_PNG := "res://sprites/demo/demo_trellis.png"
const CROP_PNGS := ["res://sprites/farm/crop_1.png", "res://sprites/farm/crop_2.png", "res://sprites/farm/crop_3.png"]

func _stamp_farm_ridges():
	"""菜圃垄行：bounds 内缩 1、每 2 行铺农田瓦 16（垄），垄间草地走道——"作物成行"基底。
	override 写入必须在 chunk 预载前（上漆一次性契约）；crop 精灵由 _place_yards 撒。"""
	for p in plots:
		if p["kind"] != "farm_a" and p["kind"] != "farm_b":
			continue
		var b: Rect2i = p["bounds"]
		var yy := b.position.y + 1
		while yy <= b.end.y - 2:
			for xx in range(b.position.x + 1, b.end.x - 1):
				wg.override_cells[Vector2i(xx, yy)] = 16
			yy += 2
	print("[DemoKit] 菜圃垄行铺装（farm_a/farm_b，行距2）")

func _place_yards():
	"""P3 总入口：6 建筑地块前院（门径+碎石平台+围栏）+ 2 菜圃（围栏+作物+稻草人棚架）。"""
	var n_crop := 0
	for p in plots:
		if p["kind"] == "farm_a" or p["kind"] == "farm_b":
			n_crop += _build_farm(p)
		elif p["kind"] != "well_plaza":
			_build_yard(p)
	print("[DemoKit] 院落菜圃完成：6 前院围栏 + 2 菜圃（作物精灵 %d，行距2 密度70%%）" % n_crop)

func _build_yard(p: Dictionary):
	"""建筑地块：门径向南接巷 + 前院碎石平台 3x2 + 边界围栏（南缘门侧留口）。"""
	var b: Rect2i = p["bounds"]
	var door: Vector2i = p["door"]
	for cy in range(door.y, b.end.y + 1):          # 门径：door 南行至南缘外接巷
		_pave(Vector2i(door.x, cy))
	for dx in range(-1, 2):                        # 前院平台 3x2
		for dy in range(0, 2):
			_pave(Vector2i(door.x + dx, door.y + dy))
	var skip := {}
	for sx in range(door.x - 1, door.x + 2):       # 南缘门侧留口
		skip[Vector2i(sx, b.end.y - 1)] = true
	_fence_ring(b, skip)

func _build_farm(p: Dictionary) -> int:
	"""菜圃：边界围栏（北缘门侧留口）+ 垄格撒作物 70% + 稻草人 + 棚架x2。返回 crop 数。"""
	var b: Rect2i = p["bounds"]
	var door: Vector2i = p["door"]
	var n := 0
	var yy := b.position.y + 1
	while yy <= b.end.y - 2:
		for xx in range(b.position.x + 1, b.end.x - 1):
			var cr := fposmod(wg.detail_noise.get_noise_2d(xx * 3.7 + 5.1, yy * 4.3 + 9.9) + 1.0, 1.0)
			if cr > 0.30:
				_stamp_prop(CROP_PNGS[int(cr * 100.0) % CROP_PNGS.size()], Vector2i(xx, yy))
				n += 1
		yy += 2
	_stamp_prop("res://sprites/buildings/scarecrow.png",
			Vector2i((b.position.x + b.end.x) / 2, (b.position.y + b.end.y) / 2))
	_stamp_prop(TRELLIS_PNG, Vector2i(b.position.x + 2, b.position.y + 2))
	_stamp_prop(TRELLIS_PNG, Vector2i(b.end.x - 3, b.end.y - 3))
	var skip := {}
	for sx in range(door.x - 1, door.x + 2):       # 北缘门侧留口（door 在横巷行）
		skip[Vector2i(sx, b.position.y)] = true
	_fence_ring(b, skip)
	return n

func _fence_ring(b: Rect2i, skip: Dictionary = {}):
	"""地块边界一圈栅栏：32px 双格单元（横边步 2、竖边步 2，角点由横边覆盖）。"""
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
	"""栅栏单元：横排底缘锚定（Y-sort 正确）；竖排格中心锚定+90° 旋转（中心对称免 offset 偏移）。"""
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
	add_child(spr)

# ---- 选址检查（返回否决原因码，""=通过） ----

func _site_reason(r: Rect2i) -> String:
	# A 世界边界 + 青石城避让（城半边 + 官道缓冲）
	for p in [r.position, r.end - Vector2i(1, 1),
			Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1)]:
		if Vector2(p).length() > float(wg.WORLD_RADIUS) - 12.0:
			return "border"
	var m: int = wg.city_half + 6
	if r.position.x < wg.CITY_POS.x + m and r.end.x > wg.CITY_POS.x - m \
			and r.position.y < wg.CITY_POS.y + m and r.end.y > wg.CITY_POS.y - m:
		return "city"
	# B rect 内步长2 扫描——人工瓦片一票否决；山/水占比受控；植被占比受控
	var geo := 0
	var soft := 0
	var total := 0
	var yy := r.position.y
	while yy < r.end.y:
		var xx := r.position.x
		while xx < r.end.x:
			var t: int = wg.get_tile_id(xx, yy)
			total += 1
			if t in BUILD_TILES:
				return "build"
			if t in GEO_TILES:
				geo += 1
			if t in SOFT_TILES:
				soft += 1
			xx += 2
		yy += 2
	if geo > int(total * GEO_MAX_RATIO):
		return "geo"
	if soft > int(total * SOFT_MAX_RATIO):
		return "soft"
	# C 外扩 2 框带：官道走廊/既有净空全扫
	var hit_road := false
	var hit_clear := false
	for yy2 in range(r.position.y - 2, r.end.y + 2):
		for xx2 in range(r.position.x - 2, r.end.x + 2):
			if road_set.has(Vector2i(xx2, yy2)):
				hit_road = true
			if wg._in_town_clearance(xx2, yy2):
				hit_clear = true
	if hit_road:
		return "road_band"
	if hit_clear:
		return "clear"
	return ""

func _blocked_for_road(x: int, y: int) -> bool:
	"""入口路寻路阻挡：人工瓦片+山/水+树/石（路绕行不穿树、不入水、不上山）。"""
	var t: int = wg.get_tile_id(x, y)
	return t in BUILD_TILES or t in GEO_TILES or t in SOFT_TILES

# ---- P0 骨架内容 ----

func _load_zone_chunks():
	"""样板区 chunk 预载（玩家初始加载半径外的部分保证可见；门派领地同款先例）。"""
	var c0: Vector2i = wg.world_to_chunk(Vector2(rect.position.x * 16.0, rect.position.y * 16.0))
	var c1: Vector2i = wg.world_to_chunk(Vector2((rect.end.x) * 16.0, (rect.end.y) * 16.0))
	var n := 0
	for cx in range(c0.x - 1, c1.x + 2):
		for cy in range(c0.y - 1, c1.y + 2):
			if not wg.loaded_chunks.has(Vector2i(cx, cy)):
				wg._load_chunk(Vector2i(cx, cy))
				n += 1
	print("[DemoKit] 预载 chunks +%d" % n)

func _lay_gate_road():
	"""入口路：官道最近格 →(BFS 绕障碍)→ 区口内侧 3 格，2 宽 path 铺装（纯地面瓦片，无 17）。"""
	var best := Vector2i.ZERO
	var best_d := 1 << 30
	var found := false
	for road in wg.official_roads:
		for c in road["cells"]:
			if wg.get_tile_id(c.x, c.y) == 17:   # 桥格不做接入点
				continue
			var dx := maxf(maxf(rect.position.x - c.x, c.x - (rect.end.x - 1)), 0.0)
			var dy := maxf(maxf(rect.position.y - c.y, c.y - (rect.end.y - 1)), 0.0)
			var d := int(dx * dx + dy * dy)
			if d < best_d:
				best_d = d
				best = c
				found = true
	if not found:
		push_warning("[DemoKit] 无官道可接入，跳过入口路")
		return
	# 区口：rect 边界最近点沿主轴向内 3 格
	var gp := Vector2i(clampi(best.x, rect.position.x, rect.end.x - 1),
			clampi(best.y, rect.position.y, rect.end.y - 1))
	var center := rect.position + rect.size / 2
	var inward := Vector2i(signi(center.x - gp.x), signi(center.y - gp.y))
	if absi(center.x - gp.x) >= absi(center.y - gp.y):
		inward.y = 0
	else:
		inward.x = 0
	gate_in = gp + inward * 3
	# BFS（限外接方框+60；阻挡=硬瓦片+树/石——路绕行不穿树）
	var lo := Vector2i(mini(best.x, gate_in.x) - 60, mini(best.y, gate_in.y) - 60)
	var hi := Vector2i(maxi(best.x, gate_in.x) + 60, maxi(best.y, gate_in.y) + 60)
	var prev := {best: best}
	var q: Array = [best]
	var head := 0
	var ok := false
	while head < q.size() and q.size() < 16000:
		var cur: Vector2i = q[head]
		head += 1
		if cur == gate_in:
			ok = true
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if prev.has(n) or n.x < lo.x or n.y < lo.y or n.x > hi.x or n.y > hi.y:
				continue
			if n != gate_in and _blocked_for_road(n.x, n.y):
				continue
			prev[n] = cur
			q.append(n)
	if not ok:
		push_warning("[DemoKit] 官道→区口 BFS 不通（%s→%s），跳过入口路" % [str(best), str(gate_in)])
		return
	# 回溯铺装：主线 + 法向 1 格（2 宽；法向格遇阻挡跳过）
	var c := gate_in
	while c != best:
		_pave(c)
		var p: Vector2i = prev[c]
		var dirv := c - p
		for perp in [Vector2i(dirv.y, dirv.x), Vector2i(-dirv.y, -dirv.x)]:
			var pn: Vector2i = c + perp
			if not _blocked_for_road(pn.x, pn.y):
				_pave(pn)
				break
		c = p
	print("[DemoKit] 入口路铺装完成：官道%s → 区口%s" % [str(best), str(gate_in)])

func _pave(c: Vector2i):
	wg.override_cells[c] = wg._palette_at(c.x, c.y)["path"]

func _mark_boundary():
	"""边界标记：四角+四边中点 灯柱（纯视觉 z=2 脚底锚定；P4 换正式围界）。"""
	var mx := rect.position.x + rect.size.x / 2
	var my := rect.position.y + rect.size.y / 2
	var pts := [
		rect.position,
		Vector2i(rect.end.x - 1, rect.position.y),
		Vector2i(rect.position.x, rect.end.y - 1),
		rect.end - Vector2i(1, 1),
		Vector2i(mx, rect.position.y),
		Vector2i(mx, rect.end.y - 1),
		Vector2i(rect.position.x, my),
		Vector2i(rect.end.x - 1, my),
	]
	for p in pts:
		_stamp_prop("res://sprites/buildings/lantern.png", p)

func _place_sign():
	"""立牌："· 样 板 村 ·"（同青石城城名标样式）+ 区口旁灯柱。"""
	var inward := Vector2i(signi(rect.position.x + rect.size.x / 2 - gate_in.x),
			signi(rect.position.y + rect.size.y / 2 - gate_in.y))
	if absi(inward.x) >= absi(inward.y):
		inward.y = 0
	else:
		inward.x = 0
	var perp := Vector2i(-inward.y, inward.x)
	var sign_cell := gate_in + perp
	var lbl := Label.new()
	lbl.text = "· 样 板 村 ·"
	lbl.add_theme_font_size_override("font_size", 5)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.z_index = 20
	lbl.position = Vector2(sign_cell.x * 16.0 + 8.0 - 26.0, sign_cell.y * 16.0 - 12.0)
	add_child(lbl)
	_stamp_prop("res://sprites/buildings/lantern.png", sign_cell)

func _stamp_prop(png: String, cell: Vector2i) -> bool:
	"""脚底锚定装饰道具（原点=贴图底缘，z=2 并入 World 递归 Y-sort；不占格不碰撞）。"""
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
	var sh := TextureGen.make_shadow_sprite(clampf(tex.get_width() * 0.85, 14.0, 44.0), 0.24)
	sh.position = Vector2(0, -2)
	spr.add_child(sh)
	add_child(spr)
	return true
