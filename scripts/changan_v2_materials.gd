extends Node2D
# 长安v2 材质层（第 2 轮 2026-09-09：先路后区再建模——地面区带由生成器负责，本层只做坊内建模）
# 布局规矩（changan_city_v2.json v2.2 = GPT 蓝图谈话合并产物 + 范式v3）：
#   kind_qc——palace 中轴/对称/大前庭；temple 山门→庭→殿→塔+绿化簇；noble 围合府邸/前庭/多层；
#             market 临街面连续/中央开放/忌同款连排；residential 合院簇/绿缓冲/背靠背巷排
#   import_qc——建筑链≤3 道具链≤2 间距≥1 退线1~3
# 遮挡关系（用户要求）：本层 y_sort_enabled + 件底边锚（origin=底缘）→ 南件压北件，画序正确；
#   玩家(z=5)沿 v1 约定恒在建筑之上。合理性：占位矩形查重，新件与已放件 bbox 相交即拒——零穿模。
# 拼板整块铺（用户拍板）：仅晋昌坊 272×288（17×18 格恰入坊）；超宽拼板受街网格约束跳过。
# 素材库 pieces 为 gitignore 派生件：缺失整层跳过（克隆机自动回灰盒）。

const TextureGen = preload("res://scripts/texture_generator.gd")

const CAT_BY_BLOCK := {
	"banzheng": "01_民居坊", "huaiyuan": "01_民居坊", "yanshou": "01_民居坊",
	"tongji": "01_民居坊", "fengan": "01_民居坊", "changming": "01_民居坊",
	"yongxing": "02_官宅清流",
	"chongren": "03_贵戚府", "changshou": "03_贵戚府", "wuben": "03_贵戚府",
	"chongyi": "03_贵戚府", "shengye": "03_贵戚府",
	"yankang": "04_亲王公主府", "xuanyang": "04_亲王公主府",
	"huangcheng": "05_官署", "anyi": "05_官署",
	"gongcheng": "06_宫城", "donggong": "06_宫城",
	"xiude": "07_寺观", "chongye": "07_寺观", "jingshan": "07_寺观", "jinchang": "07_寺观",
	"xishi": "08_市铺", "dongshi": "08_市铺",
}
# 有整块府邸（estate）的贵戚坊——estate 池按序分配，其余贵戚坊用 04 亲王门面件回退
const ESTATE_BLOCKS := ["yongxing", "chongren", "changshou", "wuben"]

var gen: Node2D = null
var lib := {}
var placed := 0
var rejected := 0
var _tex := {}
var _occ: Array = []   # 当前坊的占位矩形（px，世界坐标）


func setup(host: Node2D) -> void:
	gen = host
	z_index = 1                    # 灰盒地面之上、玩家(z5)之下（v1 约定：玩家恒在建筑上）
	y_sort_enabled = true          # 遮挡关键：按 origin(=底缘) y 排序，南件压北件
	if not _load_manifest():
		return
	var t0 := Time.get_ticks_msec()
	for b in gen.blocks:
		var cat: String = CAT_BY_BLOCK.get(String(b["id"]), "")
		if cat == "" or not lib.has(cat):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(b["id"]))
		var rect: Rect2i = gen._block_rect(b)
		_occ = []
		match String(b["kind"]):
			"residential": _layout_residential(cat, rect, rng, String(b["id"]))
			"noble": _layout_noble(rect, rng, String(b["id"]))
			"palace", "palace_east": _layout_palace(cat, rect)
			"office", "yamen": _layout_office(cat, rect, rng)
			"temple", "taoist": _layout_temple(cat, rect, rng, String(b["id"]))
			"market": _layout_market(cat, rect, rng)
	print("[ChangAnV2材质] 建模 %d 件（占位拒入 %d）%dms" %
			[placed, rejected, Time.get_ticks_msec() - t0])


func _load_manifest() -> bool:
	var f := FileAccess.open("res://data/material_library.json", FileAccess.READ)
	if f == null:
		print("[ChangAnV2材质] material_library.json 缺失——保持灰盒")
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed.has("categories"):
		return false
	for cat: String in parsed["categories"]:
		var arr: Array = []
		for p in parsed["categories"][cat]["pieces"]:
			var rec := {
				"id": String(p["id"]), "w": int(p["w"]), "h": int(p["h"]),
				"file": String(p["file"]), "cls": String(p["class"]),
			}
			if FileAccess.file_exists("res://素材库/%s/%s" % [cat, rec["file"]]):
				arr.append(rec)
		if not arr.is_empty():
			lib[cat] = arr
	if lib.is_empty():
		print("[ChangAnV2材质] 素材库 pieces 不在本机（gitignore 派生件）——保持灰盒")
		return false
	return true


# ---- 件池：按尺寸/类别筛 ----
func _pool(cat: String, min_w: int, max_w: int, min_h: int, max_h: int, cls := "unit") -> Array:
	var out: Array = []
	for p in lib.get(cat, []):
		if p["cls"] == cls and p["w"] >= min_w and p["w"] <= max_w \
				and p["h"] >= min_h and p["h"] <= max_h:
			out.append(p)
	return out


func _pick(pool: Array, rng: RandomNumberGenerator, avoid: String = "") -> Dictionary:
	if pool.is_empty():
		return {}
	for _i in range(4):
		var p: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if String(p["id"]) != avoid:
			return p
	return pool[0]


# ---- 摆件（合理性核心）：cell=左上格，底缘贴 anchor_bottom_row 下缘；
# ---- 占位矩形（件实际像素 bbox）与已放件相交即拒（零穿模），越界/退线不足亦拒 ----
func _put(cat: String, p: Dictionary, cell: Vector2i, bottom_row: int, rect: Rect2i,
		flip := false) -> bool:
	if p.is_empty():
		return false
	var w_px := int(p["w"])
	var h_px := int(p["h"])
	var px := Rect2(cell.x * 16.0, (bottom_row + 1) * 16.0 - h_px, w_px, h_px)
	if px.position.x < (rect.position.x + 1) * 16.0 \
			or px.position.y < rect.position.y * 16.0 \
			or px.end.x > (rect.position.x + rect.size.x) * 16.0 \
			or px.end.y > (rect.position.y + rect.size.y) * 16.0:
		rejected += 1
		return false
	for r in _occ:
		if px.intersects(r):
			rejected += 1
			return false
	var tex: Texture2D = _tex.get(p["file"])
	if tex == null:
		tex = TextureGen.load_png_texture("res://素材库/%s/%s" % [cat, p["file"]])
		if tex == null:
			rejected += 1
			return false
		_tex[p["file"]] = tex
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = true
	sp.flip_h = flip
	# 底边锚 + y-sort：origin 放在件底缘中心，画面向上展开；南件 origin 大 → 压住北件
	sp.position = Vector2(px.position.x + w_px / 2.0, px.end.y)
	sp.offset = Vector2(0, -h_px / 2.0)
	add_child(sp)
	_occ.append(px)
	placed += 1
	return true


func _try_tree(rect: Rect2i, cell: Vector2i, rng: RandomNumberGenerator, bottom_off := 5) -> void:
	_put("11_街饰过渡", _pick(_pool("11_街饰过渡", 32, 52, 38, 70, "prop"), rng),
			cell, cell.y + bottom_off, rect)


# ---- residential：两版式轮换（背靠背巷排 / 合院簇），绿缓冲补角 ----
func _layout_residential(cat: String, rect: Rect2i, rng: RandomNumberGenerator, id: String):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var small := _pool(cat, 80, 110, 80, 110)
	var estate := _pool(cat, 140, 200, 140, 200, "estate")
	if not estate.is_empty() and hash(id) % 2 == 0:
		_put(cat, estate[rng.randi_range(0, estate.size() - 1)],
				Vector2i(x0 + 4, y0 + 1), y0 + 12, rect)
		_try_tree(rect, Vector2i(x0 + 1, y0 + 2), rng)
		_try_tree(rect, Vector2i(x0 + 16, y0 + 2), rng)
		_put("11_街饰过渡", _pick(_pool("11_街饰过渡", 30, 50, 24, 38, "prop"), rng),
				Vector2i(x0 + 7, y0 + 16), y0 + 18, rect)
		_try_tree(rect, Vector2i(x0 + 16, y0 + 14), rng)
	else:
		var last := ""
		var s := _pick(small, rng)
		_put(cat, s, Vector2i(x0 + 1, y0 + 2), y0 + 7, rect)
		last = String(s["id"])
		_put(cat, _pick(small, rng, last), Vector2i(x0 + 8, y0 + 2), y0 + 7, rect, true)
		var s2 := _pick(small, rng, last)
		_put(cat, s2, Vector2i(x0 + 1, y0 + 13), y0 + 18, rect, true)
		_put(cat, _pick(small, rng, String(s2["id"])), Vector2i(x0 + 8, y0 + 13), y0 + 18, rect)
		_try_tree(rect, Vector2i(x0 + 15, y0 + 3), rng)
		_try_tree(rect, Vector2i(x0 + 16, y0 + 13), rng)


# ---- noble：estate 坊=府邸居北+前庭；其余用 04 亲王门面件（南北两排+中庭）----
func _layout_noble(rect: Rect2i, rng: RandomNumberGenerator, id: String):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var cat := String(CAT_BY_BLOCK.get(id, ""))
	if ESTATE_BLOCKS.has(id):
		var pool := _pool(cat, 140, 200, 140, 200, "estate")
		var idx := ESTATE_BLOCKS.find(id)
		if not pool.is_empty():
			_put(cat, pool[idx % pool.size()], Vector2i(x0 + 4, y0 + 1), y0 + 12, rect)
			# 前庭两翼石狮/灯笼架（各一，道具链=1）
			var flank := _pool("11_街饰过渡", 28, 50, 38, 55, "prop")
			if flank.size() >= 2:
				_put("11_街饰过渡", flank[0], Vector2i(x0 + 1, y0 + 16), y0 + 18, rect)
				_put("11_街饰过渡", flank[1], Vector2i(x0 + 16, y0 + 16), y0 + 18, rect, true)
			_try_tree(rect, Vector2i(x0 + 16, y0 + 1), rng)
			return
	# 04 门面件坊（yankang/xuanyang/贵戚回退）：南门面排 + 北楼阁排 + 中庭开放
	var units := _pool("04_亲王公主府", 80, 110, 80, 110)
	if units.size() >= 2:
		_put("04_亲王公主府", units[0], Vector2i(x0 + 1, y0 + 13), y0 + 18, rect)
		_put("04_亲王公主府", units[1 % units.size()], Vector2i(x0 + 8, y0 + 13), y0 + 18, rect, true)
		_put("04_亲王公主府", units[0], Vector2i(x0 + 1, y0 + 2), y0 + 7, rect, true)
		_put("04_亲王公主府", units[1 % units.size()], Vector2i(x0 + 8, y0 + 2), y0 + 7, rect)
	_try_tree(rect, Vector2i(x0 + 16, y0 + 2), rng)
	_put("11_街饰过渡", _pick(_pool("11_街饰过渡", 30, 50, 24, 38, "prop"), rng),
			Vector2i(x0 + 15, y0 + 15), y0 + 18, rect)


# ---- palace：中轴（门楼→大前庭→大殿）+ 像素级对称配殿（左右同款镜像）----
func _layout_palace(cat: String, rect: Rect2i):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var w_px := rect.size.x * 16
	var cx_cell := x0 + rect.size.x / 2
	var gate := _pool(cat, 130, 150, 85, 100)
	var pav := _pool(cat, 80, 110, 80, 100)
	if gate.is_empty():
		return
	_put(cat, gate[0], Vector2i(cx_cell - 4, y0 + 13), y0 + 18, rect)
	if gate.size() >= 2:
		_put(cat, gate[1], Vector2i(cx_cell - 4, y0 + 3), y0 + 8, rect)
	# 对称配殿：左右同款镜像，边缘距按像素对齐（北排一对+南排一对）
	if not pav.is_empty():
		var margin_px := 48.0
		for row_bottom in [y0 + 8, y0 + 17]:
			var pi := 0 if row_bottom == y0 + 8 else mini(1, pav.size() - 1)
			var p: Dictionary = pav[pi]
			var w_p := float(p["w"])
			var bottom_px: float = (float(row_bottom) + 1.0) * 16.0
			var top_px: float = bottom_px - float(p["h"])
			var lx := x0 * 16.0 + margin_px
			var rx := x0 * 16.0 + w_px - margin_px - w_p
			_put(cat, p, Vector2i(int(lx / 16.0), int(top_px / 16.0)), row_bottom, rect)
			_put(cat, p, Vector2i(int(rx / 16.0), int(top_px / 16.0)), row_bottom, rect, true)


# ---- office/yamen：临街门面排 + 中央开放；步进留白+树打破机械连排 ----
func _layout_office(cat: String, rect: Rect2i, rng: RandomNumberGenerator):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var w := rect.size.x
	var units := _pool(cat, 75, 110, 80, 110)
	if units.is_empty():
		return
	var i := 0
	var xx := x0 + 3
	var flip := false
	while xx + 6 <= x0 + w - 3:
		if i % 3 == 2:
			_try_tree(rect, Vector2i(xx + 1, y0 + 3), rng)   # 每 3 位插树破连排
		else:
			_put(cat, units[i % units.size()], Vector2i(xx, y0 + 2), y0 + 7, rect, flip)
		i += 1
		flip = not flip
		xx += 7
	xx = x0 + 6
	flip = true
	while xx + 6 <= x0 + w - 3:
		_put(cat, units[i % units.size()], Vector2i(xx, y0 + 13), y0 + 18, rect, flip)
		i += 1
		flip = not flip
		xx += 9


# ---- temple：山门→庭→殿→塔 纵序（塔限高防压殿）+ 四角绿化簇 ----
func _layout_temple(cat: String, rect: Rect2i, rng: RandomNumberGenerator, id: String):
	var x0 := rect.position.x
	var y0 := rect.position.y
	if id == "jinchang":
		# 拼板整块铺（用户拍板）：272×288=17×18 格恰入坊内
		for p in lib[cat]:
			if int(p["w"]) >= 260 and int(p["w"]) <= 280 and int(p["h"]) >= 270:
				_put(cat, p, Vector2i(x0 + 1, y0 + 1), y0 + 18, rect)
				break
		return
	var gate := _pool(cat, 75, 110, 85, 100)       # 牌坊/山门
	var hall := _pool(cat, 75, 110, 80, 100)       # 殿
	var pagoda := _pool(cat, 30, 70, 85, 120)      # 塔（限高 120px 防压殿）
	if not gate.is_empty():
		_put(cat, gate[0], Vector2i(x0 + 7, y0 + 13), y0 + 18, rect)
	if not hall.is_empty():
		_put(cat, hall[hall.size() - 1], Vector2i(x0 + 7, y0 + 5), y0 + 10, rect)
	if not pagoda.is_empty():
		var t: Dictionary = pagoda[rng.randi_range(0, pagoda.size() - 1)]
		var tw := (int(t["w"]) + 15) / 16
		_put(cat, t, Vector2i(x0 + 10 - tw / 2, y0 + 1), y0 + 6, rect, rng.randf() < 0.5)
	for c in [Vector2i(x0 + 1, y0 + 2), Vector2i(x0 + 16, y0 + 2),
			Vector2i(x0 + 1, y0 + 15), Vector2i(x0 + 16, y0 + 15)]:
		_try_tree(rect, c, rng)


# ---- market：南北临街店面 + 中央开放集市（摊位带在两排之间，不与店面重叠）----
func _layout_market(cat: String, rect: Rect2i, rng: RandomNumberGenerator):
	var x0 := rect.position.x
	var y0 := rect.position.y
	var shops := _pool(cat, 75, 110, 60, 100)
	var wide := _pool(cat, 150, 200, 80, 100)
	if shops.size() >= 1:
		_put(cat, shops[0], Vector2i(x0 + 1, y0 + 2), y0 + 7, rect)
	if shops.size() >= 2:
		_put(cat, shops[1], Vector2i(x0 + 8, y0 + 2), y0 + 7, rect, true)
	if not wide.is_empty():
		_put(cat, wide[0], Vector2i(x0 + 1, y0 + 13), y0 + 18, rect)
	if shops.size() >= 3:
		_put(cat, shops[2], Vector2i(x0 + 14, y0 + 13), y0 + 18, rect, true)
	# 中央摊位带 y+9..12（北排底 y+7、南排顶 y+13 之间），变体轮换不相连
	var stalls := _pool("11_街饰过渡", 36, 50, 40, 56, "prop")
	var last := ""
	for c in [Vector2i(x0 + 4, y0 + 9), Vector2i(x0 + 8, y0 + 9),
			Vector2i(x0 + 12, y0 + 9), Vector2i(x0 + 6, y0 + 12)]:
		if not stalls.is_empty():
			var st: Dictionary = _pick(stalls, rng, last)
			last = String(st["id"])
			_put("11_街饰过渡", st, c, c.y + 2, rect)
	_try_tree(rect, Vector2i(x0 + 16, y0 + 9), rng)
