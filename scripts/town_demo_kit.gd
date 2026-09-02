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
	"""P0 总入口：登记→平整→chunk→入口路→边界→立牌（P1 起在 _lay_roads/_stamp_plots 等扩展）。"""
	if rect.size == Vector2i.ZERO:
		return
	wg.demo_zone_rect = rect   # 营地/野怪经 is_in_settlement 自动避让
	# 净空登记（复用镇 clearance 机制：树/岩不再生成，镇/POI 选址避让）——必须在 chunk 预载前
	wg._register_town_clearance(rect.position.x + rect.size.x / 2,
			rect.position.y + rect.size.y / 2, maxi(rect.size.x, rect.size.y) / 2 + 1)
	_flatten_ground()
	_lay_gate_road()   # 铺路必须先于 chunk 预载——override 上漆只发生在 _load_chunk，后写不上屏
	_load_zone_chunks()
	_mark_boundary()
	_place_sign()
	built = true
	print("[DemoKit] 样板区 P0 骨架建成：入口路+边界灯柱+立牌")

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
