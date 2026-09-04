extends Node2D

const TextureGen = preload("res://scripts/texture_generator.gd")
const TownLayoutKit = preload("res://scripts/town_layout_kit.gd")

## 城镇样板区（材质包 1:1 复刻试点）——docs/立项-城镇样板区重构.md
## v4 M0 起布局能力下放至 town_layout_kit（立项书 §3.1）：本文件只保留样板区专用逻辑
## （选址/边界立牌/昼夜灯效/河畔小景/固定锚点表），布局方法一行转发——样板区即 kit 的冒烟样本。
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

# P2 建筑锚点表（kind → [prefab key, 局部锚点]；door=锚点+(fp.x/2, fp.y) 由 _stamp_plots 统一计算）
const ANCHORS := {
	"barn":       ["demo_barn", Vector2i(5, 2)],
	"well_plaza": ["demo_well", Vector2i(27, 7)],
	"greenhouse": ["demo_green", Vector2i(43, 2)],
	"house_a":    ["demo_house", Vector2i(7, 17)],
	"longhouse":  ["demo_long", Vector2i(19, 17)],
	"house_b":    ["demo_house", Vector2i(33, 17)],
	"shop":       ["demo_shop", Vector2i(45, 17)],
}
const DEMO_BUILDINGS := {
	"demo_barn":  {"png": "res://sprites/demo/demo_barn.png",  "fp": Vector2i(8, 6)},
	"demo_long":  {"png": "res://sprites/demo/demo_long.png",  "fp": Vector2i(7, 5)},
	"demo_green": {"png": "res://sprites/demo/demo_green.png", "fp": Vector2i(6, 5)},
	"demo_shop":  {"png": "res://sprites/demo/demo_shop.png",  "fp": Vector2i(5, 4)},
	"demo_house": {"png": "res://sprites/demo/demo_house.png", "fp": Vector2i(5, 4)},
	"demo_well":  {"png": "res://sprites/buildings/well.png",  "fp": Vector2i(1, 1)},
}

var wg                         # WorldGenerator 引用（无类型，避免依赖）
var rect := Rect2i(0, 0, 0, 0) # 选定区域（瓦片坐标）
var gate_in := Vector2i.ZERO   # 区口（rect 内侧 3 格，P1 主巷由此延续）
var road_set := {}             # 官道格集合（选址避让走廊）
var kit = null                 # TownLayoutKit 实例（build 时绑定；布局能力全部经此）
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
	"""总入口：登记→平整→地块划分→入口路→路网→地面门径→chunk→建筑→院落→装点→边界立牌。
	⚠️ 顺序契约：override 写入（平整/铺路/垄/门径）必须先于 _load_zone_chunks——上漆只发生在
	_load_chunk 且只画未设置格（P3 踩坑补正：院落门径/平台自此移入 override 层，此前隐形）。"""
	if rect.size == Vector2i.ZERO:
		return
	wg.demo_zone_rect = rect   # 营地/野怪经 is_in_settlement 自动避让
	# 净空登记（复用镇 clearance 机制：树/岩不再生成，镇/POI 选址避让）——必须在 chunk 预载前
	wg._register_town_clearance(rect.position.x + rect.size.x / 2,
			rect.position.y + rect.size.y / 2, maxi(rect.size.x, rect.size.y) / 2 + 1)
	kit = TownLayoutKit.new()
	kit.bind(wg, self, rect)
	var n_flat: int = kit.flatten_ground(FLATTEN_MARGIN)   # kit 无类型——勿用 := 推断（parse 坑）
	print("[DemoKit] 平整山/雪山 %d 格（含区缘 %d 格视觉缓冲带；水保留）" % [n_flat, FLATTEN_MARGIN])
	_stamp_plots()     # P1：地块划分（记录制，供 P2 建筑/P3 院落消费）
	_lay_gate_road()   # P0：官道→区口（2 宽）
	_lay_roads()       # P1：连接巷+主巷蜿蜒+支巷+广场（2 宽主巷/1 宽支巷三级）
	for p in kit.plots:
		if p["kind"] == "farm_a" or p["kind"] == "farm_b":
			kit.farm_ridges(p)   # P3：菜圃垄行农田瓦
		elif p["kind"] != "well_plaza":
			kit.yard_ground(p)   # P3：院落门径+碎石平台（override 层，P3 踩坑补正）
	print("[DemoKit] stage: override 层完成（平整/路网/垄/门径）")
	_load_zone_chunks()
	print("[DemoKit] stage: chunks 预载完成")
	_place_buildings() # P2：建筑 prefab 落位（prop 不依赖瓦片上漆，chunks 后任意时机）
	_place_yards()     # P3：围栏/作物精灵/稻草人棚架（prop 层）
	_place_decor_density()  # P4：果树带疏林+道具组+花簇补密度+量化统计
	_mark_boundary()
	_place_sign()
	print("[DemoKit] stage: prop 层完成（建筑/院落/装点/边界）")
	built = true
	print("[DemoKit] 样板区建成：P0 骨架+P1 路网+P2 建筑+P3 院落菜圃+P4 装点（%d 地块）" % kit.plots.size())

const FLATTEN_MARGIN := 4   # 区缘视觉缓冲带（P5 终验用户反馈：区外离散山崖砖块观感）——
			# 区外 4 格内的离散山崖/雪山一并平整为草地（水保留=image2 河畔意象；崖清除=碰撞减少，可达性只增）

# ---- P1 路网与地块（立项书 §三 布局总图，局部坐标 56x44，区口北缘 lx=52） ----

func _g(p: Vector2i) -> Vector2i:
	"""局部坐标 → 全局瓦片坐标。"""
	return rect.position + p

func _stamp_plots():
	"""P1 地块划分（记录制）：布局对齐立项书 §三——北带谷仓/水井广场/温室，主巷南缘
	农舍A/长屋/农舍B/杂货铺（门直接贴巷），南带菜圃A/B。bounds 供建筑落位+院围+密度量化。
	建筑地块的 door 在此按 ANCHORS 定终值（=建筑底缘中点，门朝南），供门径铺装（override 层）。"""
	var spec := [
		{"kind": "barn",       "bounds": Rect2i(Vector2i(4, 1), Vector2i(11, 9)),   "door": Vector2i(9, 9)},
		{"kind": "well_plaza", "bounds": Rect2i(Vector2i(22, 1), Vector2i(12, 11)), "door": Vector2i(27, 11)},
		{"kind": "greenhouse", "bounds": Rect2i(Vector2i(40, 1), Vector2i(12, 8)),  "door": Vector2i(45, 8)},
		{"kind": "house_a",    "bounds": Rect2i(Vector2i(4, 13), Vector2i(11, 13)), "door": Vector2i(14, 13)},
		{"kind": "longhouse",  "bounds": Rect2i(Vector2i(17, 13), Vector2i(12, 13)), "door": Vector2i(22, 13)},
		{"kind": "house_b",    "bounds": Rect2i(Vector2i(31, 13), Vector2i(10, 13)), "door": Vector2i(35, 13)},
		{"kind": "shop",       "bounds": Rect2i(Vector2i(43, 13), Vector2i(10, 13)), "door": Vector2i(47, 13)},
		{"kind": "farm_a",     "bounds": Rect2i(Vector2i(5, 28), Vector2i(14, 10)),  "door": Vector2i(9, 27)},
		{"kind": "farm_b",     "bounds": Rect2i(Vector2i(23, 28), Vector2i(12, 10)), "door": Vector2i(26, 27)},
	]
	kit.make_plots(spec)
	for p in kit.plots:
		if ANCHORS.has(p["kind"]):
			var def: Array = ANCHORS[p["kind"]]
			var fp: Vector2i = DEMO_BUILDINGS[def[0]]["fp"]
			p["door"] = _g(def[1] + Vector2i(int(fp.x / 2.0), fp.y))
		print("[DemoKit]   地块[%s] bounds=%s door=%s" % [p["kind"], str(p["bounds"]), str(p["door"])])

func _lay_roads():
	"""P1 三级路网：连接巷(2宽)→主巷(2宽 4段折线蜿蜒横贯)→支巷(1宽 纵3+横1通菜圃)+水井广场石板。
	全部无碰撞瓦片（path=1 / plaza=35）；必须在 _load_zone_chunks 前调用（override 上漆一次性）。"""
	# 1 连接巷：区口（局部52,0，接 P0 入口路）向南下到主巷东端，2 宽 x=52,53
	for ly in range(0, 10):
		kit.pave(_g(Vector2i(52, ly)))
		kit.pave(_g(Vector2i(53, ly)))
	# 2 主巷：3 段大弯蜿蜒（弯幅 3 格对齐材质包样图走势；2 宽=(x,y)+(x,y+1)，段间竖向过渡 2 宽）
	for s in [[3, 20, 9], [21, 38, 12], [39, 52, 9]]:
		for lx in range(int(s[0]), int(s[1]) + 1):
			kit.pave(_g(Vector2i(lx, int(s[2]))))
			kit.pave(_g(Vector2i(lx, int(s[2]) + 1)))
	for tx in [21, 22, 39, 40]:        # 弯折竖向过渡（y 9→12→9）
		for ly in range(9, 13):
			kit.pave(_g(Vector2i(tx, ly)))
	# 3 支巷（1 宽）：北带谷仓门已邻主巷段1 y=9；南带纵巷×3（地块间隙）+横巷（菜圃带）
	for lx in [15, 29, 41]:            # 纵巷：主巷南缘 y=14 穿地块间隙至横巷
		for ly in range(14, 28):
			kit.pave(_g(Vector2i(lx, ly)))
	for lx in range(9, 48):            # 横巷 y=27：连纵巷与菜圃 A/B 北门
		kit.pave(_g(Vector2i(lx, 27)))
	# 4 水井广场（石板 35）：局部 (24..31, 4..11)，南缘 y=11 邻主巷段2 y=12
	kit.pave_rect(Rect2i(_g(Vector2i(24, 4)), Vector2i(8, 8)), 35)
	print("[DemoKit] 三级路网铺装完成：连接巷+主巷3段大弯(2宽)+纵巷3/横巷1(1宽)+水井广场")

# ---- P2 建筑 Prefab 落位（纹理由 texture_generator.generate_demo_buildings 生成，Main._ensure_textures 接线） ----

func _place_buildings():
	"""P2：按 plots 落位 prefab（锚点=ANCHORS 表，占位居地块内偏北留前院）；
	P5 反馈放大一档（谷仓 8x6/长屋 7x5/民居商铺 5x4/温室 6x5）。door 已在 _stamp_plots 定终值。"""
	var n := 0
	for p in kit.plots:
		var k: String = p["kind"]
		if not ANCHORS.has(k):
			continue
		var def: Array = ANCHORS[k]
		var a: Vector2i = _g(def[1])
		var fp: Vector2i = DEMO_BUILDINGS[def[0]]["fp"]
		kit.stamp_prefab_building(DEMO_BUILDINGS[def[0]]["png"], fp, a)
		n += 1
		if k != "well_plaza":
			# 檐下道具（P2 要素4）：建筑左墙脚桶、右墙脚箱（脚底=建筑底缘行）
			var feet_y: int = a.y + fp.y - 1
			kit.stamp_prop("res://sprites/buildings/barrel.png", Vector2i(a.x - 1, feet_y))
			kit.stamp_prop("res://sprites/buildings/crate.png", Vector2i(a.x + fp.x, feet_y))
	print("[DemoKit] 建筑落位 %d 栋（四要素：木框抹灰墙/瓦顶烟囱/门窗台/檐下桶箱）" % n)

# ---- P3 院落与菜圃（立项书 §三：地块围栏围合、菜圃作物成行+稻草人/棚架；Farm.png 栅栏语义） ----

func _place_yards():
	"""P3 总入口（prop 层）：6 建筑地块围栏（南缘留口）+ 2 菜圃（围栏+作物+稻草人棚架）。
	门径/平台/垄行的瓦片铺装已前移至 build() 的 override 层（P3 踩坑补正）。"""
	var n_crop := 0
	for p in kit.plots:
		if p["kind"] == "farm_a" or p["kind"] == "farm_b":
			n_crop += kit.farm_dress(p)
		elif p["kind"] != "well_plaza":
			kit.yard_fence(p)
	print("[DemoKit] 院落菜圃完成：6 前院围栏 + 2 菜圃（作物精灵 %d，行距2 密度70%%）" % n_crop)

# ---- P4 装点与密度（§1.2 量化：装饰≥25%、道具每8×8≥1组、果树带疏林；纯 prop 零瓦片语义） ----

func _place_decor_density():
	"""P4 总入口：果树带疏林 + 8×8 道具组 + 花簇补密度 + 河畔小景 + 量化统计打印。"""
	var n_tree := _stamp_orchard()
	var n_prop: int = kit.scatter_props(rect, 0.42, 424242)
	var n_flower: int = kit.scatter_flowers(rect, 0.05, 35)
	n_prop += _stamp_riverbank()
	kit.report_density(rect, "样板区P4")
	print("[DemoKit] P4 密度统计：树 %d 道具组 %d 花簇 %d" % [n_tree, n_prop, n_flower])

func _stamp_riverbank() -> int:
	"""P4.5 河畔小景：西缘临区外水域侧（v5 终验发现水面-绿地硬切突兀）——
	crate/barrel/花簇还原材质包 image2"河畔堆物"意象，软化过渡。区内侧摆放，零碰撞。"""
	var n := 0
	var props := [
		"res://sprites/buildings/crate.png", Vector2i(15, 55),
		"res://sprites/buildings/barrel.png", Vector2i(16, 57),
		"res://sprites/buildings/crate.png", Vector2i(15, 61),
		TownLayoutKit.FLOWERS_PNG, Vector2i(15, 53),
		TownLayoutKit.FLOWERS_PNG, Vector2i(16, 59),
		TownLayoutKit.FLOWERS_PNG, Vector2i(15, 63),
	]
	var i := 0
	while i < props.size():
		var c: Vector2i = _g(props[i + 1])
		if kit.cell_free(c):
			kit.stamp_prop(props[i], c)
			kit.occupied[c] = true
			n += 1
		i += 2
	return n

func _stamp_orchard() -> int:
	"""果树带疏林：北带（局部 y≤8）6%、南缘（y≥38）1.5%、其余 0——橡树 4x2 变体 sheet。"""
	var sheet := TextureGen.load_png_texture(TownLayoutKit.ORCHARD_SHEET)
	if sheet == null:
		push_warning("[DemoKit] 果树 sheet 缺失，跳过疏林")
		return 0
	var n := 0
	for ly in range(0, H):
		for lx in range(0, W):
			if n >= 30:
				return n
			var c := _g(Vector2i(lx, ly))
			if not kit.cell_free(c) or kit.near_blocked(c):
				continue
			var dens := 0.06 if ly <= 8 else (0.015 if ly >= 38 else 0.0)
			var cr := fposmod(wg.detail_noise.get_noise_2d(c.x * 2.3 + 7.7, c.y * 3.1 + 3.3) + 1.0, 1.0)
			if cr > dens:
				continue
			if kit.stamp_tree(c, sheet):
				n += 1
	return n

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
		kit.pave(c)
		var p: Vector2i = prev[c]
		var dirv := c - p
		for perp in [Vector2i(dirv.y, dirv.x), Vector2i(-dirv.y, -dirv.x)]:
			var pn: Vector2i = c + perp
			if not _blocked_for_road(pn.x, pn.y):
				kit.pave(pn)
				break
		c = p
	print("[DemoKit] 入口路铺装完成：官道%s → 区口%s" % [str(best), str(gate_in)])

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
		kit.stamp_prop("res://sprites/buildings/lantern.png", p, true)   # 边界灯柱夜景常亮

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
	kit.stamp_prop("res://sprites/buildings/lantern.png", sign_cell, true)   # 立牌灯柱夜景常亮

func _process(_delta):
	"""昼夜自适应灯效：18:00~6:30 满亮度，白天熄灭（PointLight2D 白天加法光斑过曝，P5 终验发现）。"""
	if kit == null or kit.glow_lights.is_empty():
		return
	var wc := get_node_or_null("/root/Main/World/WeatherController")
	if wc == null:
		return
	var h: float = wc.current_hour
	var e := 1.5 if (h >= 18.0 or h < 6.5) else 0.0
	for l in kit.glow_lights:
		if is_instance_valid(l):
			l.energy = e
