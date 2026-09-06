extends Node2D
# 长安城独立场景生成器（M0 灰盒）—— docs/长安城地图设计.md
# L1 外城层：外郭城墙/宫皇区/108坊/街网/两市，全部由 data/changan_city.json 驱动
# M0 验收：全图分帧生成 ≤3s；BFS 断言明德门可达全部 stage0 坊与两市；regress 无新 FAIL
# 注意：设计稿§5.1拟用ID 41~56 已被注册表占用，坊墙复用43（唐制坊墙），新瓦片从67起编

signal generation_done
signal exit_requested(gate_id: String)   # M1：玩家触碰城内出城触发区（city_visit 接管回开放世界）
signal interior_requested(ref: String)   # M4：玩家触碰门面前触发区（city_visit 载入内景子地图）

const TilesetGen = preload("res://scripts/tileset_generator.gd")

# ---- 瓦片 ID（tileset_generator.gd 注册表）----
const T_GRASS = 0
const T_STONE = 35
const T_HOUSE = 2           # 旧建筑占格（退役保留常量）
const T_FOOT = 102          # 建筑footprint占格（全透明带碰撞；SCKR prop 视觉承担外观）
const T_WARD_WALL = 100     # 长安坊墙（SCKR白灰墙+瓦顶，带碰撞；43 旧唐制坊墙退役）
const T_PAVE = 101          # 长安方砖（两市地面/宫院丹墀）
const T_WARD_WALL_V = 105   # 坊墙·竖（E/W 走向段，墙身竖缝）
const T_PALACE_WALL_V = 104 # 宫墙·竖
const T_WALL_BODY = 106     # 外郭城墙·砖身行（横缝，N/S 段）——两行制：垛口行70+砖身行106
const T_WALL_FACE_V = 103   # 外郭城墙·竖立面内列（E/W 段低对比砖纹）
const T_WALL_CAP_W = 108    # 外郭城墙·竖段外列西齿（齿朝西）
const T_WALL_CAP_E = 109    # 外郭城墙·竖段外列东齿（齿朝东）
const T_GATE_OPEN = 67      # 坊门·开（无碰撞）
const T_GATE_CLOSED = 68    # 坊门·闭（宵禁/未解锁，带碰撞）
const T_PALACE_WALL = 69    # 宫墙
const T_OUTER_WALL = 70     # 外郭城墙
const T_ZHUQUE = 71         # 朱雀大街御道
const T_MAIN_ROAD = 72      # 主干街
const T_WARD_STREET = 73    # 坊内十字街
const T_LANE = 74           # 巷路
const T_WATER = 5           # M3 三渠水（复用开放世界水瓦，碰撞）
const T_BRIDGE = 17         # M3 渠桥（复用开放世界桥瓦，无碰撞）

# ---- M3 宵禁（§六-2）：暮鼓戌时闭坊门/市门，晨鼓卯时开；四城门/宫门不闭 ----
const CURFEW_START := 19.0
const CURFEW_END := 5.0

# ---- M3 三渠（龙首/清明/永安）：街缝内1宽水带，跨路处铺桥 ----
const CANALS := [{"name": "清明渠", "seam": 1}, {"name": "龙首渠", "seam": 7}, {"name": "永安渠", "seam": 10}]

const COLLIDING := [5, 3, 7, 2, 10, 11, 12, 14, 15, 40, 100, 102, 103, 104, 105, 106, 108, 109, 65, 66, 68, 69, 70, 83, 84, 86, 88, 89]   # 坊墙43→100、足印=T_FOOT(102)（透明碰撞）；宅门75~77已去碰撞（M4传送门）；83~89=内景瓦碰撞段

# ---- 网格参数（JSON 解析后类型化）----
var bw := 26
var bh := 26
var main_s := 5
var zq_s := 9
var ring := 4
var wall := 1
var margin := 10
var cols := 12
var rows := 9
var palace_cols := Vector2i(4, 7)
var palace_rows := Vector2i(0, 1)

var blocks: Array = []
var markets: Array = []
var W := 0
var H := 0
var ground: PackedByteArray
var decor: PackedByteArray
var done := false
var stats := {}
var bfs_failures: Array = []
var tile_map: TileMap = null
# ---- M1 四城门注册表（side -> {name, gap_cells, inside}）----
# 明德门(南中)/玄武门(北中)/春明门(东中)/开远门(西中)，豁口均3格与城内街网对齐
var gate_info := {}
var portals_node: Node2D = null
# ---- M3 宵禁/锚点/NPC/阶段 ----
var curfew := false                     # 当前宵禁状态（坊门/市门闭）
var curfew_gates: Array = []            # 宵禁册：{cells, kind("ward"/"market"), ward}——仅 stage0 坊与两市
var ward_gate_cells := {}               # 坊id -> 门格数组（unlock_stage 用）
var canal_cells := {}                   # 渠名 -> 水格数（探针统计）
var bridge_count := 0
var anchors := {}                       # 日程锚点 ref -> 本地px（坊门/市门/plaza；城门走 gate_info）
var npc_list: Array = []
var night_bfs_failures: Array = []
var interior_portals := {}               # M4/M5 内景传送门：ref -> 门前景格（"area:ref"=Area2D已挂标记）
var grid_palace_interiors: Array = []    # 宫区非标杆内景（两仪殿/东宫，数据驱动）
var unlocked_wards := {}                 # 已解锁坊登记（防 unlock_stage 递进调用重复填充/开门）
const NPC_SCENE = preload("res://scenes/npc.tscn")

# 城内NPC（city_npc_configs 模式：legs=[state, ref, start, end, off]，锚点见 get_anchor_px）
const CITY_NPC_CONFIGS := [
	{"id": "ca01", "name": "明德武侯", "personality": "刚正", "npc_type": "guard",
	 "legs": [["idle", "citygate:S", 6, 22, Vector2(1, 0)]]},
	{"id": "ca02", "name": "西市门吏", "personality": "沉稳", "npc_type": "guard",
	 "legs": [["idle", "marketgate:西市:S", 6, 19, Vector2(0, -1)]]},
	{"id": "ca03", "name": "东市门吏", "personality": "沉稳", "npc_type": "guard",
	 "legs": [["idle", "marketgate:东市:S", 6, 19, Vector2(0, -1)]]},
	{"id": "ca04", "name": "更夫老赵", "personality": "阴沉", "npc_type": "elder",
	 "legs": [["wander", "plaza", 18, 24, Vector2(2, 0)], ["wander", "citygate:N", 0, 6, Vector2(0, 1)], ["idle", "plaza", 6, 10, Vector2(-1, 0)]]},
	{"id": "ca05", "name": "货郎陈四", "personality": "市侩", "npc_type": "merchant",
	 "legs": [["wander", "marketgate:西市:W", 8, 18, Vector2(1, 0)], ["leisure", "plaza", 18, 21, Vector2(0, 0)]]},
	{"id": "ca06", "name": "闲汉刘二", "personality": "狡诈", "npc_type": "mysterious",
	 "legs": [["wander", "plaza", 10, 20, Vector2(0, 0)]]},
	{"id": "ca07", "name": "游学书生", "personality": "儒雅", "npc_type": "scholar",
	 "legs": [["wander", "citygate:E", 8, 16, Vector2(-1, 0)], ["leisure", "marketgate:东市:N", 16, 19, Vector2(0, 1)]]},
	{"id": "ca08", "name": "浆洗王大娘", "personality": "慈悲", "npc_type": "peasant_f",
	 "legs": [["wander", "citygate:W", 7, 18, Vector2(1, 0)], ["idle", "citygate:W", 18, 21, Vector2(2, 0)]]},
]

func _ready():
	y_sort_enabled = true   # M1：与 World 递归 y-sort 对齐（玩家/坊墙按 y 排序）
	if _load_data():
		_paint_layout()
		_fill_tilemap_async()

func _load_data() -> bool:
	var f = FileAccess.open("res://data/changan_city.json", FileAccess.READ)
	if f == null:
		push_error("[ChangAn] data/changan_city.json 缺失，先跑 python tools/make_changan_data.py")
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("[ChangAn] changan_city.json 解析失败")
		return false
	var g: Dictionary = parsed["grid"]
	bw = int(g["block"][0])
	bh = int(g["block"][1])
	main_s = int(g["street"]["main"])
	zq_s = int(g["street"]["zhunque"])
	ring = int(g["street"]["ring"])
	wall = int(g["wall"])
	margin = int(g["margin"])
	cols = int(g["cols"])
	rows = int(g["rows"])
	palace_cols = Vector2i(int(g["palace_zone"]["cols"][0]), int(g["palace_zone"]["cols"][1]))
	palace_rows = Vector2i(int(g["palace_zone"]["rows"][0]), int(g["palace_zone"]["rows"][1]))
	markets = g["markets"]
	grid_palace_interiors = g["palace_zone"].get("interiors", [])
	blocks = parsed["blocks"]
	W = margin * 2 + wall * 2 + ring * 2 + cols * bw + (cols - 1) * main_s + (zq_s - main_s)
	H = margin * 2 + wall * 2 + ring * 2 + rows * bh + (rows - 1) * main_s
	return true

func _origin() -> Vector2i:
	return Vector2i(margin + wall + ring, margin + wall + ring)

func col_x(c: int) -> int:
	return _origin().x + c * (bw + main_s) + (4 if c >= 5 else 0)   # 4=朱雀加宽补偿

func row_y(r: int) -> int:
	return _origin().y + r * (bh + main_s)

func block_span_x() -> int:
	return col_x(cols - 1) + bw - _origin().x

func block_span_y() -> int:
	return row_y(rows - 1) + bh - _origin().y

func _paint_layout():
	ground = PackedByteArray()
	ground.resize(W * H)          # 默认0=草
	decor = PackedByteArray()
	decor.resize(W * H)
	# 外郭城墙两行制：垛口行（70）在外 + 砖身行（106/107 按走向）在内——城墙视觉加高
	_set_rect(decor, margin, margin, W - margin * 2, 1, T_OUTER_WALL)
	_set_rect(decor, margin, H - margin - 1, W - margin * 2, 1, T_OUTER_WALL)
	_set_rect(decor, margin + 1, margin + 1, W - margin * 2 - 2, 1, T_WALL_BODY)
	_set_rect(decor, margin + 1, H - margin - 2, W - margin * 2 - 2, 1, T_WALL_BODY)
	# E/W 竖段双列：外列=垛口齿（西墙齿朝西/东墙齿朝东，与横墙垛口转角衔接），内列=砖纹立面
	_set_rect(decor, margin, margin + 1, 1, H - margin * 2 - 2, T_WALL_CAP_W)
	_set_rect(decor, margin + 1, margin + 1, 1, H - margin * 2 - 2, T_WALL_FACE_V)
	_set_rect(decor, W - margin - 1, margin + 1, 1, H - margin * 2 - 2, T_WALL_CAP_E)
	_set_rect(decor, W - margin - 2, margin + 1, 1, H - margin * 2 - 2, T_WALL_FACE_V)
	_set_rect(decor, margin + 2, margin + 2, W - margin * 2 - 4, H - margin * 2 - 4, 0)
	# 环路（贴城墙内侧，4宽土路）
	var m := margin + wall
	_set_rect(ground, m, m, W - m * 2, ring, T_MAIN_ROAD)
	_set_rect(ground, m, H - m - ring, W - m * 2, ring, T_MAIN_ROAD)
	_set_rect(ground, m, m, ring, H - m * 2, T_MAIN_ROAD)
	_set_rect(ground, W - m - ring, m, ring, H - m * 2, T_MAIN_ROAD)
	# 纵向街道缝 i=1..cols-1；i=5 为朱雀大街（宽9，恰在 col4|col5 之间）
	for i in range(1, cols):
		if i == 5:
			_set_rect(ground, col_x(5) - zq_s, _origin().y, zq_s, block_span_y(), T_ZHUQUE)
		else:
			_set_rect(ground, col_x(i) - main_s, _origin().y, main_s, block_span_y(), T_MAIN_ROAD)
	# 横向街道缝 j=1..rows-1
	for j in range(1, rows):
		_set_rect(ground, _origin().x, row_y(j) - main_s, block_span_x(), main_s, T_MAIN_ROAD)
	# 宫皇区（合并8街区，覆盖已铺街道）
	_paint_palace()
	# 坊与市
	for b in blocks:
		if String(b["type"]) != "ward":
			continue
		if _in_palace(int(b["col"]), int(b["row"])):
			continue
		_paint_ward(b)
	for mk in markets:
		_paint_market(mk)
	# M2 坊内填充：剧情坊按 lots 铺宅邸门面，非剧情 stage0 坊程序化院落（未解锁坊留白，§六-3）
	# 市占坊（西市/东市格位同时登记为大通坊/怀贞坊）整坊铺市，坊内容不填——否则盖掉市内门面
	for b in blocks:
		if String(b["type"]) != "ward" or _in_palace(int(b["col"]), int(b["row"])):
			continue
		if _in_market(int(b["col"]), int(b["row"])):
			continue
		if int(b["stage_unlock"]) != 0:
			continue
		_fill_ward_contents(b)
	_paint_canals()
	# 视觉重构：四城门楼 prop + 街巷点缀（牌坊/街灯/行道树/渠柳）——放在渠之后可避开水格
	_spawn_city_gates_all()
	_paint_street_dressing()
	# M3 锚点：朱雀大街中段为全城"广场"（日程汇合点）
	anchors["plaza"] = cell_to_px(Vector2i(col_x(5) - zq_s + zq_s / 2, _origin().y + block_span_y() / 2))

# ---- M2 宅门品级瓦片（§5.1）----
const GATE_TILE_BY_GRADE := {"A": 75, "B": 76, "C": 77}

# ---- SCKR prop 框架（视觉重构 2026-09-06）：切片由 tools/import_sckr_changan.py 产出，
#      克隆仓库未跑切片时 _prop_tex 返回 null → 各处自动跳过（结构不受影响）。
#      footprint 占格=T_HOUSE(2)（TileMap 碰撞+BFS 一致），prop 只做视觉，禁小瓦片拼大件（§5.2）----
const TextureGen = preload("res://scripts/texture_generator.gd")
const PROP_ROOT := "res://sprites/changan_props_sckr/"
# 宅门楼品级：A=朱金大门（亲王/公主）B=白墙院门楼（国公/士族）C=石门楼（官署/小宅）
const GATE_PROP_BY_GRADE := {"A": "gate_red_gold", "B": "compound_gate", "C": "gate_stone_small"}
# 民居变体池（散院/小宅随机取，hash 种子定）
const HOUSE_PROPS := ["house_win_a", "house_door_a", "house_win_small", "house_small_door"]
# 城门楼：明德门用大骑楼，其余三门用中型
const CITY_GATE_PROP := {"S": "gate_tower_big", "N": "gate_tower_mid", "E": "gate_tower_mid", "W": "gate_tower_mid"}
var _prop_tex_cache := {}

func _prop_tex(pname: String) -> Texture2D:
	if _prop_tex_cache.has(pname):
		return _prop_tex_cache[pname]
	var tex: Texture2D = TextureGen.load_png_texture(PROP_ROOT + pname + ".png")
	_prop_tex_cache[pname] = tex
	return tex

# 通用 prop 生成：底边中点锚（y-sort 与玩家自然遮挡），缺失切片静默跳过
func _spawn_prop(pname: String, center_x: float, bottom_y: float, z := 2) -> Sprite2D:
	var tex := _prop_tex(pname)
	if tex == null:
		return null
	var prop := Sprite2D.new()
	prop.texture = tex
	prop.position = Vector2(center_x, bottom_y)
	prop.offset = Vector2(0, -tex.get_height() / 2.0)
	prop.z_index = z
	if pname != "":
		prop.add_to_group("changan_prop")
		prop.set_meta("prop", pname)   # 探针按名断言
	add_child(prop)
	return prop

# 建筑 prop：footprint 占格（T_FOOT 透明碰撞，镂空 prop 不露身后画）+ 底边中点锚 sprite
func _spawn_building(pname: String, foot: Rect2i):
	for yy in range(foot.position.y, foot.position.y + foot.size.y):
		for xx in range(foot.position.x, foot.position.x + foot.size.x):
			decor[yy * W + xx] = T_FOOT
	var tex := _prop_tex(pname)
	if tex == null:
		return
	var cx := (foot.position.x + foot.size.x / 2.0) * 16.0
	var by := (foot.position.y + foot.size.y) * 16.0
	_spawn_prop(pname, cx, by)

# 城门楼 prop + 门垛碰撞（拱门走廊净宽≥26px，出城触发区仍在豁口格）
func _spawn_city_gate(side: String):
	var pname: String = CITY_GATE_PROP.get(side, "gate_tower_mid")
	if _prop_tex(pname) == null:
		return
	var g: Dictionary = gate_info[side]
	var cells: Array = g["gap_cells"]
	var c0: Vector2i = cells[0]
	var c1: Vector2i = cells[cells.size() - 1]
	var center_px := Vector2((c0.x + c1.x) * 0.5 + 0.5, (c0.y + c1.y) * 0.5 + 0.5) * 16.0
	_spawn_prop(pname, center_px.x, center_px.y + 8.0)
	var body := StaticBody2D.new()
	body.position = center_px
	var vertical := (side == "E" or side == "W")
	for sgn in [-1.0, 1.0]:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		# 门垛盖两行墙（垛口+砖身），拱门净宽 32px ≥ 玩家 24px
		shape.size = Vector2(8, 30) if not vertical else Vector2(30, 8)
		cs.shape = shape
		cs.position = Vector2(sgn * 20.0, -6.0) if not vertical else Vector2(0, sgn * 20.0 - 6.0)
		body.add_child(cs)
	add_child(body)
# M4 内景家具瓦（与 changan_interior.gd 一致；门面店铺陈设用）
const T_SHELF = 89
const T_CABINET = 88
const T_DESK = 86

# M3 三渠：水带走在纵向街缝正中（缝本身是主干街，水占中1格、两侧各留2格可走），桥只铺在横街缝/环路带穿过处。
# 龙首渠缝7北段穿宫皇区（cols4~7），从宫区南侧横街起渠；清明/永安两渠纵贯全城。
func _paint_canals():
	var palace_bottom := row_y(palace_rows.y + 1) - main_s
	# 桥位带：环路+横街缝（缝身整条都是主干街，桥只铺在横路穿过处）
	var bands: Array = []
	var m := margin + wall
	bands.append([m, m + ring])
	bands.append([H - m - ring, H - m])
	for j in range(1, rows):
		bands.append([row_y(j) - main_s, row_y(j)])
	for canal in CANALS:
		var seam := int(canal["seam"])
		var x := col_x(seam) - main_s + main_s / 2
		var y0 := palace_bottom if seam >= palace_cols.x and seam <= palace_cols.y + 1 else margin + wall
		var cells := 0
		for y in range(y0, H - margin - wall):
			var in_band := false
			for band in bands:
				if y >= band[0] and y < band[1]:
					in_band = true
					break
			if in_band:
				ground[y * W + x] = T_BRIDGE
				bridge_count += 1
			else:
				ground[y * W + x] = T_WATER
				cells += 1
		canal_cells[String(canal["name"])] = cells

func _fill_ward_contents(b: Dictionary):
	var lots: Array = b.get("lots", [])
	if lots.is_empty():
		_fill_ward_generic(b)
		return
	# 剧情坊：先铺 lots，再对四象限空位补散院（M2 遗留①：剧情坊非 lot 象限留白）
	var x0 := col_x(int(b["col"]))
	var y0 := row_y(int(b["row"]))
	var occupied: Array = []
	for lot in lots:
		_paint_lot(x0, y0, lot)
		occupied.append(Rect2(x0 + int(lot["at"][0]) - 1, y0 + int(lot["at"][1]) - 1,
				int(lot["size"][0]) + 2, int(lot["size"][1]) + 2))
	_fill_ward_generic(b, occupied)

# 剧情坊 lot：院墙圈 + 品级宅门（SCKR 门楼 prop，75~77 门面瓦保留=传送垫+探针基准）+ 门前甬道 + 后部正屋
func _paint_lot(x0: int, y0: int, lot: Dictionary):
	var lx := x0 + int(lot["at"][0])
	var ly := y0 + int(lot["at"][1])
	var w := int(lot["size"][0])
	var h := int(lot["size"][1])
	var x1 := lx + w - 1
	var y1 := ly + h - 1
	var kind := String(lot["kind"])
	var grade := String(lot["grade"])
	var ref := String(lot["ref"])
	var gate_id: int = GATE_TILE_BY_GRADE[grade]
	# 院墙圈（方向感知）
	_set_wall_ring(lx, ly, w, h, T_WARD_WALL, T_WARD_WALL_V)
	_set_rect(decor, lx + 1, ly + 1, w - 2, h - 2, 0)
	# 寺观/风月场所院内满铺方砖（体面），宅邸留草
	if kind == "temple" or kind == "venue":
		_set_rect(ground, lx + 1, ly + 1, w - 2, h - 2, T_PAVE)
	# 院门（门侧墙正中2格，品级瓦）+ 门前石板甬道 + SCKR 门楼 prop
	var gcx := lx + w / 2
	var gcy := ly + h / 2
	match String(lot.get("gate", "S")):
		"S":
			_set_rect(decor, gcx - 1, y1, 2, 1, gate_id)
			_set_rect(ground, gcx - 1, ly + 2, 2, y1 - (ly + 2) + 1, T_PAVE)
			_spawn_prop(GATE_PROP_BY_GRADE[grade], gcx * 16.0, (y1 + 1) * 16.0)
		"N":
			_set_rect(decor, gcx - 1, ly, 2, 1, gate_id)
			_set_rect(ground, gcx - 1, ly, 2, y1 - 2 - ly + 1, T_PAVE)
			_spawn_prop(GATE_PROP_BY_GRADE[grade], gcx * 16.0, (ly + 1) * 16.0)
		"E":
			_set_rect(decor, x1, gcy - 1, 1, 2, gate_id)
			_set_rect(ground, lx + 2, gcy - 1, x1 - (lx + 2) + 1, 2, T_PAVE)
			_spawn_prop(GATE_PROP_BY_GRADE[grade], x1 * 16.0 + 8.0, (gcy + 1) * 16.0)
		"W":
			_set_rect(decor, lx, gcy - 1, 1, 2, gate_id)
			_set_rect(ground, lx, gcy - 1, x1 - 2 - lx + 1, 2, T_PAVE)
			_spawn_prop(GATE_PROP_BY_GRADE[grade], lx * 16.0 + 8.0, (gcy + 1) * 16.0)
	# 正屋（SCKR 建筑 prop + T_HOUSE footprint）：形制按 kind/grade；名寺配塔
	var hall_prop := "house_door_a"
	var foot_w := 3
	match kind:
		"temple":
			hall_prop = "hall_grey"
			foot_w = 5
		"venue":
			hall_prop = "lou_blue"
			foot_w = 5
		"office":
			hall_prop = "hall_grey"
			foot_w = 5
		"mansion":
			match grade:
				"A":
					hall_prop = "hall_red"
					foot_w = 5
				"B":
					hall_prop = "house_door_a"
				_:
					hall_prop = "house_small_door"
	match String(lot.get("gate", "S")):
		"S":
			_spawn_building(hall_prop, Rect2i(gcx - foot_w / 2, ly + 1, foot_w, 2))
		"N":
			_spawn_building(hall_prop, Rect2i(gcx - foot_w / 2, y1 - 3, foot_w, 2))
		"E":
			_spawn_building(hall_prop, Rect2i(lx + 1, gcy - 1, 5, 2))
		"W":
			_spawn_building(hall_prop, Rect2i(x1 - 5, gcy - 1, 5, 2))
	# 名寺宝塔（大慈恩寺=大雁塔青塔，大兴善寺=金塔）：正屋北侧
	if ref == "daciensi":
		_spawn_building("pagoda_blue", Rect2i(lx + 3, gcy - 6, 3, 2))
	elif ref == "daxingshan_si":
		_spawn_building("pagoda_gold", Rect2i(lx + 3, gcy - 6, 3, 2))
	elif kind == "temple":
		_spawn_building("pagoda_small", Rect2i(gcx - 1, ly + 4, 2, 2))

# 非剧情坊程序化填充：四象限小院（朝十字街开敞口，不留封闭死角）+ SCKR 民居 prop + 低密度坊散树
# occupied：lot 占用矩形（全局格坐标 Rect2），相交象限跳过（剧情坊补散院用）
func _fill_ward_generic(b: Dictionary, occupied: Array = []):
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(b["id"]))
	var high := String(b["fill"]) == "residential_high"
	var x0 := col_x(int(b["col"]))
	var y0 := row_y(int(b["row"]))
	var boxes := [Vector2i(2, 2), Vector2i(15, 2), Vector2i(2, 16), Vector2i(15, 16)]
	for q in range(4):
		var chance := 0.85 if high else 0.55
		if rng.randf() > chance:
			continue
		var bx: Vector2i = boxes[q]
		var lw := 9
		var lh := 7
		var lx := x0 + bx.x + rng.randi_range(0, 1)
		var ly := y0 + bx.y + rng.randi_range(0, 1)
		var skip := false
		for oc in occupied:
			if oc.intersects(Rect2(lx, ly, lw, lh)):
				skip = true
				break
		if skip:
			continue
		_set_wall_ring(lx, ly, lw, lh, T_WARD_WALL, T_WARD_WALL_V)
		_set_rect(decor, lx + 1, ly + 1, lw - 2, lh - 2, 0)
		var hx := lx + lw / 2
		# SCKR 民居（foot 4×2 压 T_FOOT，匹配 ~95px 檐宽：檐口恰贴院墙内缘不越墙），hash 定变体
		var variant: String = HOUSE_PROPS[rng.randi_range(0, HOUSE_PROPS.size() - 1)]
		if q < 2:   # 北象限小院：屋坐北朝南，敞口在南墙
			_spawn_building(variant, Rect2i(hx - 2, ly + 1, 4, 2))
			_set_rect(decor, hx, ly + lh - 1, 1, 1, 0)
			_set_rect(ground, hx, ly + lh - 1, 1, 1, T_WARD_STREET)
		else:       # 南象限小院：屋坐南朝北，敞口在北墙
			_spawn_building(variant, Rect2i(hx - 2, ly + lh - 3, 4, 2))
			_set_rect(decor, hx, ly, 1, 1, 0)
			_set_rect(ground, hx, ly, 1, 1, T_WARD_STREET)
	if not high:   # 低密度坊散树（橡树瓦，可行走装饰）
		for i in range(rng.randi_range(2, 5)):
			var tx := x0 + rng.randi_range(2, 23)
			var ty := y0 + rng.randi_range(2, 23)
			if int(decor[ty * W + tx]) == 0 and int(ground[ty * W + tx]) == 0:
				decor[ty * W + tx] = 8
	# 临街店面带（前店后院坊市肌理）：坊南墙内 1 行店排面南，sprite 95~100px step 6 格近接成排
	if rng.randf() < 0.7:
		var shop_vars := ["house_shop_open", "house_door_a", "gable_ma"]
		for k in range(3):
			var sx := x0 + 4 + k * 6
			var blocked := false
			for xx in range(sx, sx + 2):
				if int(decor[(y0 + 24) * W + xx]) != 0:
					blocked = true
			if not blocked:
				_spawn_building(shop_vars[rng.randi_range(0, shop_vars.size() - 1)], Rect2i(sx, y0 + 24, 2, 1))
	# 坊内地标（破天际线）：临横街北侧 35% 立 2 层楼/殿，hash 定
	if rng.randf() < 0.35:
		var lm: String = ["lou_brown", "lou_blue", "hall_grey"][rng.randi_range(0, 2)]
		_spawn_building(lm, Rect2i(x0 + 17, y0 + 10, 3, 2))
	# 明德门：南城墙朱雀轴线开3格（两行制：垛口行+砖身行都挖开）
	var cx := col_x(5) - zq_s + zq_s / 2
	_set_rect(decor, cx - 1, H - margin - wall, 3, 1, T_GATE_OPEN)
	_set_rect(decor, cx - 1, H - margin - wall - 1, 3, 1, T_GATE_OPEN)
	# M1 四城门：豁口+注册（明德门S已有，玄武门N/春明门E/开远门W，均对齐街网轴线）
	_register_gate("S", "明德门", [Vector2i(cx - 1, H - margin - wall), Vector2i(cx, H - margin - wall), Vector2i(cx + 1, H - margin - wall)], Vector2i(cx, H - margin - wall - 2))
	_set_rect(decor, cx - 1, margin, 3, 1, T_GATE_OPEN)
	_set_rect(decor, cx - 1, margin + 1, 3, 1, T_GATE_OPEN)
	_register_gate("N", "玄武门", [Vector2i(cx - 1, margin), Vector2i(cx, margin), Vector2i(cx + 1, margin)], Vector2i(cx, margin + wall + 1))
	var cyc := _center_seam_y()
	_set_rect(decor, W - margin - wall, cyc - 1, 1, 3, T_GATE_OPEN)
	_set_rect(decor, W - margin - wall - 1, cyc - 1, 1, 3, T_GATE_OPEN)
	_register_gate("E", "春明门", [Vector2i(W - margin - wall, cyc - 1), Vector2i(W - margin - wall, cyc), Vector2i(W - margin - wall, cyc + 1)], Vector2i(W - margin - wall - 2, cyc))
	_set_rect(decor, margin, cyc - 1, 1, 3, T_GATE_OPEN)
	_set_rect(decor, margin + 1, cyc - 1, 1, 3, T_GATE_OPEN)
	_register_gate("W", "开远门", [Vector2i(margin, cyc - 1), Vector2i(margin, cyc), Vector2i(margin, cyc + 1)], Vector2i(margin + wall + 1, cyc))

# 中央横街缝（rows=9 → row4|row5 之间 j=5 缝的y中心），东西门与其对齐
func _center_seam_y() -> int:
	return row_y(5) - main_s + main_s / 2

func _register_gate(side: String, gname: String, gap: Array, inside: Vector2i):
	gate_info[side] = {"name": gname, "gap_cells": gap, "inside": inside}

# ---- 视觉重构：四城门楼 prop（明德门大骑楼，余三门中楼）+ 门垛碰撞 ----
func _spawn_city_gates_all():
	for side in ["S", "N", "E", "W"]:
		if gate_info.has(side):
			_spawn_city_gate(side)

# ---- 视觉重构：街巷点缀（放在水系之后：逐格校验避水/避墙）----
func _paint_street_dressing():
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260906
	var zq_x0 := col_x(5) - zq_s
	var zq_x1 := col_x(5) - 1
	# 朱雀大街：红灯笼街灯两侧对列 + 国槐行道树（props 无碰撞，落在御道边缘格）
	var y := _origin().y + 6
	var alt := 0
	while y < H - margin - wall - 4:
		var lx := zq_x0 + 1 if alt % 2 == 0 else zq_x1 - 1
		if _dressing_cell_free(lx, y):
			_spawn_prop("lamp_red", lx * 16.0 + 8.0, (y + 1) * 16.0)
		var tx := zq_x1 - 1 if alt % 2 == 0 else zq_x0 + 1
		if y % 16 == 6 and _dressing_cell_free(tx, y - 3):
			_spawn_prop("tree_lush_a" if alt % 3 == 0 else "tree_lush_b", tx * 16.0 + 8.0, (y - 2) * 16.0)
		alt += 1
		y += 12
	# 三渠沿岸柳：水带两侧各 2 格路，每隔 14 格一棵（避桥带）
	for canal in CANALS:
		var cxx := col_x(int(canal["seam"])) - main_s + main_s / 2
		for wy in range(margin + wall + 4, H - margin - wall - 4, 14):
			for dx in [-2, 2]:
				if _dressing_cell_free(cxx + dx, wy) and int(ground[wy * W + cxx + dx]) != T_BRIDGE:
					_spawn_prop("willow_a" if (wy / 14) % 2 == 0 else "willow_b", (cxx + dx) * 16.0 + 8.0, (wy + 1) * 16.0)
	# 主干街行道槐带（"槐衙"）：纵/横缝两侧列植橡树瓦（可行走 decor，零节点成本），每 4 格一株
	for i in range(1, cols):
		if i == 5:
			continue   # 朱雀已用 prop 大树
		var sx0 := col_x(i) - main_s
		for wy in range(_origin().y + 3, _origin().y + block_span_y(), 4):
			for sx in [sx0, col_x(i) - 1]:
				if _dressing_cell_free(sx, wy):
					decor[wy * W + sx] = 8
	for j in range(1, rows):
		var sy0 := row_y(j) - main_s
		for wx in range(_origin().x + 3, _origin().x + block_span_x(), 4):
			for sy in [sy0, row_y(j) - 1]:
				if _dressing_cell_free(wx, sy):
					decor[sy * W + wx] = 8
	# 环路行道大树
	for wy in range(margin + wall + ring, H - margin - wall - ring, 24):
		for xx in [margin + wall + 2, W - margin - wall - ring - 2]:
			if _dressing_cell_free(xx, wy):
				_spawn_prop("tree_big", xx * 16.0 + 8.0, (wy + 1) * 16.0)
	# 牌坊：承天门外金大牌坊 + 明德门内石牌坊（朱雀轴线礼制门户）
	var pcx := col_x(5) - zq_s + zq_s / 2
	var palace_south := row_y(palace_rows.y) + bh
	_spawn_prop("paifang_big_gold", (pcx + 0.5) * 16.0, (palace_south + 3) * 16.0)
	_spawn_prop("paifang_stone_g", (pcx + 0.5) * 16.0, (H - margin - wall - 4) * 16.0)
	# 明德门内石狮
	_spawn_prop("lion_white_a", (pcx - 2) * 16.0 + 8.0, (H - margin - wall - 2) * 16.0)
	_spawn_prop("lion_white_b", (pcx + 3) * 16.0 + 8.0, (H - margin - wall - 2) * 16.0)

# 点缀落格校验：格内须为可走地面且无装饰（避水/避墙/避坊内）
func _dressing_cell_free(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return false
	var g := int(ground[y * W + x])
	var d := int(decor[y * W + x])
	return d == 0 and (g == T_MAIN_ROAD or g == T_ZHUQUE or g == T_LANE)

func _in_market(c: int, r: int) -> bool:
	for mk in markets:
		if int(mk["col"]) == c and int(mk["row"]) == r:
			return true
	return false

func _in_palace(c: int, r: int) -> bool:
	return c >= palace_cols.x and c <= palace_cols.y and r >= palace_rows.x and r <= palace_rows.y

func _paint_palace():
	var px0 := col_x(palace_cols.x)
	var py0 := row_y(palace_rows.x)
	var px1 := col_x(palace_cols.y) + bw - 1
	var py1 := row_y(palace_rows.y) + bh - 1
	_set_rect(ground, px0, py0, px1 - px0 + 1, py1 - py0 + 1, T_GRASS)
	_set_wall_ring(px0, py0, px1 - px0 + 1, py1 - py0 + 1, T_PALACE_WALL, T_PALACE_WALL_V)
	_set_rect(decor, px0 + 1, py0 + 1, px1 - px0 - 1, py1 - py0 - 1, 0)
	# 丹墀广场：院内满铺方砖（金砖漫地），中轴御道直抵太极殿
	_set_rect(ground, px0 + 1, py0 + 1, px1 - px0 - 1, py1 - py0 - 1, T_PAVE)
	var pcx := col_x(5) - zq_s + zq_s / 2
	_set_rect(ground, pcx - 1, py0 + 1, 3, py1 - py0 - 1, T_ZHUQUE)
	# 太极殿（重檐金顶，foot 9×3 压 T_HOUSE）坐北朝南；两仪殿/东宫东西对峙
	_spawn_building("hall_taiji", Rect2i(pcx - 4, py0 + 2, 9, 3))
	var mid_y := py0 + (py1 - py0) / 2
	_spawn_building("hall_gold2", Rect2i(px1 - 9, mid_y - 3, 5, 2))
	_spawn_building("hall_gold3", Rect2i(px0 + 4, mid_y - 3, 5, 2))
	# 四角金亭（角楼意象）+ 承天门内石狮一对
	for corner in [Vector2i(px0 + 2, py0 + 2), Vector2i(px1 - 3, py0 + 2), Vector2i(px0 + 2, py1 - 3), Vector2i(px1 - 3, py1 - 3)]:
		_spawn_building("ting_gold", Rect2i(corner.x - 1, corner.y - 1, 2, 2))
	_spawn_prop("lion_white_a", (pcx - 2) * 16.0 + 8.0, (py1 - 1) * 16.0)
	_spawn_prop("lion_white_b", (pcx + 2) * 16.0 + 8.0, (py1 - 1) * 16.0)
	# 四门：南中3（承天门，对朱雀轴线）、北中2、东西各2
	var cx := col_x(5) - zq_s + zq_s / 2
	var my := py0 + (py1 - py0) / 2
	_set_rect(decor, cx - 1, py1, 3, 1, T_GATE_OPEN)
	_set_rect(decor, cx - 1, py0, 2, 1, T_GATE_OPEN)
	_set_rect(decor, px0, my, 1, 2, T_GATE_OPEN)
	_set_rect(decor, px1, my, 1, 2, T_GATE_OPEN)

func _paint_ward(b: Dictionary):
	var c := int(b["col"])
	var r := int(b["row"])
	var x0 := col_x(c)
	var y0 := row_y(r)
	var x1 := x0 + bw - 1
	var y1 := y0 + bh - 1
	# 坊内清底（覆盖先铺的街道）再围坊墙
	_set_rect(ground, x0, y0, bw, bh, T_GRASS)
	_set_wall_ring(x0, y0, bw, bh, T_WARD_WALL, T_WARD_WALL_V)
	_set_rect(decor, x0 + 1, y0 + 1, bw - 2, bh - 2, 0)
	# 散水圈已删除：人字纹竖排成"横档梯"（用户实拍反馈）；坊墙直接接街/草，横墙观感自然
	# 门洞：宽2，坊墙正中；stage>0 未解锁=闭门
	var gx0 := x0 + bw / 2 - 1
	var gy0 := y0 + bh / 2 - 1
	var open_id := T_GATE_OPEN if int(b["stage_unlock"]) == 0 else T_GATE_CLOSED
	var ward_id := String(b["id"])
	ward_gate_cells[ward_id] = []
	for g in b["gates"]:
		var cells: Array = []
		match String(g):
			"N":
				cells = [Vector2i(gx0, y0), Vector2i(gx0 + 1, y0)]
			"S":
				cells = [Vector2i(gx0, y1), Vector2i(gx0 + 1, y1)]
			"W":
				cells = [Vector2i(x0, gy0), Vector2i(x0, gy0 + 1)]
			"E":
				cells = [Vector2i(x1, gy0), Vector2i(x1, gy0 + 1)]
		for gc in cells:
			_set_rect(decor, gc.x, gc.y, 1, 1, open_id)
		ward_gate_cells[ward_id].append_array(cells)
		if int(b["stage_unlock"]) == 0:
			curfew_gates.append({"cells": cells, "kind": "ward", "ward": ward_id})
			var inward: Vector2i = {"N": Vector2i(0, 2), "S": Vector2i(0, -2), "W": Vector2i(2, 0), "E": Vector2i(-2, 0)}[String(g)]
			anchors["wardgate:%s:%s" % [ward_id, String(g)]] = cell_to_px(cells[0] + inward)
		# 门外街基（墙外1格+门洞2格深，接横/纵街）
		match String(g):
			"N":
				_set_rect(ground, gx0, y0, 2, 3, T_WARD_STREET)
			"S":
				_set_rect(ground, gx0, y1 - 2, 2, 3, T_WARD_STREET)
			"W":
				_set_rect(ground, x0, gy0, 3, 2, T_WARD_STREET)
			"E":
				_set_rect(ground, x1 - 2, gy0, 3, 2, T_WARD_STREET)
	# 坊内十字街（2宽，与门洞对齐）
	_set_rect(ground, gx0, y0 + 1, 2, bh - 2, T_WARD_STREET)
	_set_rect(ground, x0 + 1, gy0, bw - 2, 2, T_WARD_STREET)
	# 坊门门楼（S 门正面挂灰瓦榜门楼 prop，门洞内露出开/闭门瓦=宵禁可见）
	for g in b["gates"]:
		if String(g) == "S":
			_spawn_prop("market_gate", (gx0 + 1) * 16.0, (y1 + 1) * 16.0)

func _paint_market(mk: Dictionary):
	var c := int(mk["col"])
	var r := int(mk["row"])
	var x0 := col_x(c)
	var y0 := row_y(r)
	var x1 := x0 + bw - 1
	var y1 := y0 + bh - 1
	_set_rect(ground, x0, y0, bw, bh, T_PAVE)
	_set_wall_ring(x0, y0, bw, bh, T_WARD_WALL, T_WARD_WALL_V)
	_set_rect(decor, x0 + 1, y0 + 1, bw - 2, bh - 2, 0)
	# 市门四向各2格（入宵禁册，夜闭）
	var gx0 := x0 + bw / 2 - 1
	var gy0 := y0 + bh / 2 - 1
	var mname := String(mk.get("name", "市"))
	var sides := {
		"N": [Vector2i(gx0, y0), Vector2i(gx0 + 1, y0)],
		"S": [Vector2i(gx0, y1), Vector2i(gx0 + 1, y1)],
		"W": [Vector2i(x0, gy0), Vector2i(x0, gy0 + 1)],
		"E": [Vector2i(x1, gy0), Vector2i(x1, gy0 + 1)],
	}
	for g in sides:
		var cells: Array = sides[g]
		for cc in cells:
			_set_rect(decor, cc.x, cc.y, 1, 1, T_GATE_OPEN)
		curfew_gates.append({"cells": cells, "kind": "market", "ward": mname})
		var inward: Vector2i = {"N": Vector2i(0, 2), "S": Vector2i(0, -2), "W": Vector2i(2, 0), "E": Vector2i(-2, 0)}[g]
		anchors["marketgate:%s:%s" % [mname, g]] = cell_to_px(cells[0] + inward)
	# 市楼（西市钟楼/东市鼓楼，foot 3×2）压在市内中巷北端（两侧店铺间 x11~13）
	_spawn_building("bell_tower" if mname == "西市" else "drum_tower", Rect2i(x0 + 11, y0 + 2, 3, 2))
	# M5 两市店铺门面（数据驱动：grid.markets[].shops，皮肤决定门面形制）
	for shop in mk.get("shops", []):
		_paint_shop_front(x0 + int(shop["at"][0]), y0 + int(shop["at"][1]), 8, 6, shop)
	# 摊贩：市门内侧+市楼两翼固定摊位（foot 2×1 压 T_HOUSE）。
	# 布点纪律：不进中巷/环路走带——玩家碰撞体24px 需2格净宽，摊位占带即堵路
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(mname)
	var stall_props := ["stall_red", "stall_wood", "stall_red2", "stall_rw", "stall_banner"]
	var stall_spots := [Vector2i(9, 1), Vector2i(15, 1), Vector2i(8, 2), Vector2i(16, 2),
			Vector2i(9, 24), Vector2i(15, 24), Vector2i(1, 12), Vector2i(23, 12)]
	for spot in stall_spots:
		_spawn_stall(stall_props[rng.randi_range(0, stall_props.size() - 1)], x0 + spot.x, y0 + spot.y)

func _spawn_stall(pname: String, sx: int, sy: int):
	if sx < 0 or sy < 0 or sx + 2 >= W or sy >= H:
		return
	for xx in range(sx, sx + 2):
		if int(decor[sy * W + xx]) != 0:
			return
	_spawn_building(pname, Rect2i(sx, sy, 2, 1))

# 方向感知单行墙：N/S 走向段（横墙）用 cap_h，E/W 走向段（竖墙）用 cap_v——砖缝方向与墙走向一致
func _set_wall_ring(x0: int, y0: int, w: int, h: int, cap_h: int, cap_v: int):
	_set_rect(decor, x0, y0, w, 1, cap_h)
	_set_rect(decor, x0, y0 + h - 1, w, 1, cap_h)
	_set_rect(decor, x0, y0 + 1, 1, h - 2, cap_v)
	_set_rect(decor, x0 + w - 1, y0 + 1, 1, h - 2, cap_v)

func _set_rect(arr: PackedByteArray, x: int, y: int, w: int, h: int, id: int):
	for yy in range(y, y + h):
		if yy < 0 or yy >= H:
			continue
		var base = yy * W
		for xx in range(x, x + w):
			if xx < 0 or xx >= W:
				continue
			arr[base + xx] = id

func _tile_at(arr: PackedByteArray, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return T_OUTER_WALL
	return arr[y * W + x]

# ---- M1 传送落点校验（设计稿§七：3×3 可通行校验 + 螺旋外扩兜底）----
func is_spawn_clear(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := c + Vector2i(dx, dy)
			if COLLIDING.has(_tile_at(ground, p.x, p.y)) or COLLIDING.has(_tile_at(decor, p.x, p.y)):
				return false
	return true

func find_clear_spawn(near: Vector2i) -> Vector2i:
	if is_spawn_clear(near):
		return near
	for r in range(1, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(abs(dx), abs(dy)) != r:
					continue   # 只扫外圈
				var p := near + Vector2i(dx, dy)
				if is_spawn_clear(p):
					return p
	return near   # BFS 已保证门口可达，兜底原点

func cell_to_px(c: Vector2i) -> Vector2:
	return Vector2(c.x * 16 + 8, c.y * 16 + 8)

# ---- 分帧填充 TileMap：16 分区，每帧一区 ----
func _fill_tilemap_async() -> void:
	var t0 := Time.get_ticks_msec()
	tile_map = TileMap.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = TilesetGen.build_tileset()
	tile_map.add_layer(1)          # 默认仅1层：0=地面，1=装饰/墙体
	tile_map.y_sort_enabled = true             # 对齐开放世界 TileMap y-sort 玩法
	tile_map.set_layer_y_sort_enabled(1, true) # 墙体按 y_sort_origin 与玩家互遮挡
	add_child(tile_map)
	var regions := 4
	var rw := int(ceil(W / float(regions)))
	var rh := int(ceil(H / float(regions)))
	var non_ground := 0
	var decor_cnt := 0
	for ry in range(regions):
		for rx in range(regions):
			for yy in range(ry * rh, min(H, (ry + 1) * rh)):
				var base = yy * W
				for xx in range(rx * rw, min(W, (rx + 1) * rw)):
					# 地面层全量铺贴（草地也画）——跳过草地会露出背景成黑洞（M1 走查踩坑）
					var gid := ground[base + xx]
					tile_map.set_cell(0, Vector2i(xx, yy), gid, Vector2i(0, 0))
					non_ground += 1
					var d := decor[base + xx]
					if d != 0:
						tile_map.set_cell(1, Vector2i(xx, yy), d, Vector2i(0, 0))
						decor_cnt += 1
			await get_tree().process_frame
	var ms := Time.get_ticks_msec() - t0
	_build_portals()
	_register_interior_portals()
	_run_bfs()
	_run_night_bfs()
	set_curfew(_is_curfew_hour(GameManager.world_hour))   # 入场即同步宵禁（M3）
	_spawn_city_npcs()
	stats = {
		"size": "%dx%d" % [W, H], "ms": ms,
		"ground_cells": non_ground, "decor_cells": decor_cnt,
		"bfs_fail": bfs_failures.size(), "bfs_night_fail": night_bfs_failures.size(),
		"canals": canal_cells.duplicate(), "bridges": bridge_count,
		"curfew": curfew, "npcs": npc_list.size(),
	}
	print("[ChangAn-M0] %s 生成 %dms 地面=%d 装饰=%d BFS未达=%d 城门=%d" %
			[stats["size"], ms, non_ground, decor_cnt, bfs_failures.size(), gate_info.size()])
	print("[ChangAn-M3] 渠=%s 桥=%d 宵禁门=%d 夜BFS未达=%d 城内NPC=%d" %
			[canal_cells, bridge_count, curfew_gates.size(), night_bfs_failures.size(), npc_list.size()])
	done = true
	generation_done.emit()

# ---- M1 出城触发区：每门一个 Area2D 盖住豁口格，玩家触碰即请求出城 ----
func _build_portals():
	portals_node = Node2D.new()
	portals_node.name = "Portals"
	add_child(portals_node)
	for side in gate_info:
		var g: Dictionary = gate_info[side]
		var cells: Array = g["gap_cells"]
		var c0: Vector2i = cells[0]
		var c1: Vector2i = cells[cells.size() - 1]
		var center_px := Vector2((c0.x + c1.x) * 0.5 + 0.5, (c0.y + c1.y) * 0.5 + 0.5) * 16.0
		var area := Area2D.new()
		area.name = "ExitPortal_%s" % side
		area.position = center_px
		area.collision_layer = 0
		area.collision_mask = 2   # 玩家层
		area.monitoring = true
		area.set_meta("gate_id", side)
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		if side == "S" or side == "N":
			shape.size = Vector2(48, 16)
		else:
			shape.size = Vector2(16, 48)
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(_on_portal_body_entered.bind(side))
		portals_node.add_child(area)

func _on_portal_body_entered(body: Node2D, side: String):
	if body.is_in_group("player"):
		exit_requested.emit(side)


# ---- M4 内景传送门 ----
# ---- 视觉重构：店铺门面（SCKR 门面楼 prop 按皮肤，76 门垫保留=传送锚+探针基准）----
const SHOP_FACADE_BY_SKIN := {
	"wine": "lou_brown",      # 酒肆：二层楼+酒旗
	"silk": "house_shop_open",# 绸缎庄：开敞铺面
	"book": "house_shop_open",# 书肆：开敞铺面
	"herb": "house_door_a",   # 药铺：木门铺宅
	"pawn": "house_win_small",# 当铺：小窗厚墙
}
const SHOP_SIGN_BY_SKIN := {"wine": "sign_wine", "book": "banner_purple"}

func _paint_shop_front(sx: int, sy: int, sw: int, sh: int, shop: Dictionary):
	_set_rect(decor, sx, sy, sw, sh, T_WARD_WALL)
	_set_rect(decor, sx + 1, sy + 1, sw - 2, sh - 2, 0)
	var gx := sx + sw / 2
	var gy := sy + sh - 1
	_set_rect(decor, gx - 1, gy, 2, 1, 76)
	# 门面楼（foot 4×2 坐店内北侧）+ 皮肤幌子
	var skin := String(shop.get("skin", "silk"))
	_spawn_building(SHOP_FACADE_BY_SKIN.get(skin, "house_shop_open"), Rect2i(sx + 2, sy + 1, 4, 2))
	if SHOP_SIGN_BY_SKIN.has(skin):
		_spawn_prop(SHOP_SIGN_BY_SKIN[skin], (sx + 1) * 16.0 + 4.0, (sy + sh - 1) * 16.0)
	interior_portals[String(shop["ref"])] = Vector2i(gx, sy + sh)

# 剧情坊 lot 门面 → 门外 1 格触发点
func _register_lot_portal(ref: String) -> bool:
	for b in blocks:
		for lot in b.get("lots", []):
			if String(lot["ref"]) != ref:
				continue
			var lx := col_x(int(b["col"])) + int(lot["at"][0])
			var ly := row_y(int(b["row"])) + int(lot["at"][1])
			var w := int(lot["size"][0])
			var h := int(lot["size"][1])
			var gcx := lx + w / 2
			var gcy := ly + h / 2
			match String(lot.get("gate", "S")):
				"S": interior_portals[ref] = Vector2i(gcx, ly + h)
				"N": interior_portals[ref] = Vector2i(gcx, ly - 1)
				"E": interior_portals[ref] = Vector2i(lx + w, gcy)
				"W": interior_portals[ref] = Vector2i(lx - 1, gcy)
			return true
	push_warning("[ChangAn] lot 传送门未找到 ref=" + ref)
	return false

func _register_interior_portals():
	# M5 全量：stage0 坊 lots（宅邸/寺观/官署/场所/小宅）逐一门前景格挂传送门
	for b in blocks:
		if String(b["type"]) != "ward" or _in_palace(int(b["col"]), int(b["row"])) or _in_market(int(b["col"]), int(b["row"])):
			continue
		if int(b["stage_unlock"]) != 0:
			continue
		for lot in b.get("lots", []):
			_register_lot_portal(String(lot["ref"]))
	# 宫城：太极殿（标杆）/两仪殿/东宫 传送门=各殿门前（外观 prop 已立，殿脚即门）
	var pcx := col_x(5) - zq_s + zq_s / 2
	interior_portals["taiji_dian"] = Vector2i(pcx, row_y(palace_rows.x) + 6)
	var ppin := row_y(palace_rows.x) + (bh * 2 + main_s) / 2
	var pgx0 := col_x(palace_cols.x)
	var pgx1 := col_x(palace_cols.y) + bw - 1
	interior_portals["liangyi_dian"] = Vector2i(pgx1 - 7, ppin)
	interior_portals["donggong"] = Vector2i(pgx0 + 6, ppin)
	if tile_map == null:
		return
	for ref in interior_portals.keys():
		if String(ref).begins_with("area:"):
			continue
		_build_interior_portal_area(String(ref))

func _build_interior_portal_area(ref: String):
	if portals_node == null or interior_portals.has("area:" + ref):
		return
	var front: Vector2i = interior_portals[ref]
	var area := Area2D.new()
	area.name = "InteriorPortal_%s" % ref
	area.position = cell_to_px(front)
	area.collision_layer = 0
	area.collision_mask = 2
	area.set_meta("interior_ref", ref)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	cs.shape = shape
	area.add_child(cs)
	area.body_entered.connect(_on_interior_portal_body_entered.bind(ref))
	portals_node.add_child(area)
	interior_portals["area:" + ref] = true   # 已挂 Area2D 标记

# M5 门面→内景元数据：ref -> {kind, grade, name}（changan_interior 按 kind 出模板）
func get_interior_meta(ref: String) -> Dictionary:
	for b in blocks:
		for lot in b.get("lots", []):
			if String(lot["ref"]) == ref:
				return {"kind": String(lot["kind"]), "grade": String(lot["grade"]),
						"name": String(lot.get("name", ref))}
	for mk in markets:
		for shop in mk.get("shops", []):
			if String(shop["ref"]) == ref:
				return {"kind": "shop", "skin": String(shop.get("skin", "book")),
						"name": String(shop.get("name", ref))}
	for p in grid_palace_interiors:
		if String(p["ref"]) == ref:
			return {"kind": "palace", "grade": "A", "name": String(p["name"])}
	return {}

func _on_interior_portal_body_entered(body: Node2D, ref: String):
	if body.is_in_group("player"):
		interior_requested.emit(ref)

# ---- BFS 连通断言：明德门内出发，stage0 坊与两市中心须可达 ----
func _run_bfs():
	var blocked := {}
	for id in COLLIDING:
		blocked[id] = true
	var start := Vector2i(col_x(5) - zq_s + zq_s / 2 + 1, H - margin - wall - 1)
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0   # 索引指针替代 pop_front（Array.pop_front 是 O(n)，12万格会卡死）
	while qi < queue.size():
		var p: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if visited.has(q):
				continue
			if blocked.has(_tile_at(ground, q.x, q.y)) or blocked.has(_tile_at(decor, q.x, q.y)):
				continue
			visited[q] = true
			queue.append(q)
# 检查点：stage0 坊中心 + 市中心 + 四城门内侧（M1 全城骨架连通）
	for b in blocks:
		if String(b["type"]) != "ward" or int(b["stage_unlock"]) != 0:
			continue
		var cx := col_x(int(b["col"])) + bw / 2
		var cy := row_y(int(b["row"])) + bh / 2
		if not visited.has(Vector2i(cx, cy)):
			bfs_failures.append(String(b["name"]))
	for mk in markets:
		var cx2 := col_x(int(mk["col"])) + bw / 2
		var cy2 := row_y(int(mk["row"])) + bh / 2
		if not visited.has(Vector2i(cx2, cy2)):
			bfs_failures.append(String(mk["name"]) + "(市)")
	for side in gate_info:
		var inside: Vector2i = gate_info[side]["inside"]
		if not visited.has(inside):
			bfs_failures.append(String(gate_info[side]["name"]) + "(门内)")

# ---- M3 宵禁：全城坊门/市门统一广播（§六-2），_process 轮询时辰防逐门轮询 ----
func _process(_delta):
	if not done:
		return
	var c := _is_curfew_hour(GameManager.world_hour)
	if c != curfew:
		set_curfew(c)
		print("[ChangAn-M3] 宵禁%s" % ["开始，坊市闭门" if c else "解除，晨鼓开门"])

func _is_curfew_hour(h: float) -> bool:
	return h >= CURFEW_START or h < CURFEW_END

func set_curfew(closed: bool):
	curfew = closed
	var id := T_GATE_CLOSED if closed else T_GATE_OPEN
	for gate in curfew_gates:
		for c in gate["cells"]:
			decor[c.y * W + c.x] = id
			if tile_map:
				tile_map.set_cell(1, c, id, Vector2i(0, 0))

# 夜行连通断言：宵禁闭坊市门后，从朱雀大街中段出发，四城门内侧仍可达（主角夜行走大街）
func _run_night_bfs():
	var blocked := {}
	for id in COLLIDING:
		blocked[id] = true
	var blocked_cells := {}
	for gate in curfew_gates:
		for c in gate["cells"]:
			blocked_cells[c] = true
	var start := Vector2i(col_x(5) - zq_s + zq_s / 2, _origin().y + block_span_y() / 2)
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var p: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if visited.has(q) or blocked_cells.has(q):
				continue
			if blocked.has(_tile_at(ground, q.x, q.y)) or blocked.has(_tile_at(decor, q.x, q.y)):
				continue
			visited[q] = true
			queue.append(q)
	for side in gate_info:
		var inside: Vector2i = gate_info[side]["inside"]
		if not visited.has(inside):
			night_bfs_failures.append(String(gate_info[side]["name"]) + "(夜门内)")

# ---- M3 日程锚点解析（city_npc_configs 模式）----
func get_anchor_px(ref: String) -> Vector2:
	if anchors.has(ref):
		return anchors[ref]
	if ref.begins_with("citygate:"):
		var side := ref.substr(9)
		if gate_info.has(side):
			return cell_to_px(gate_info[side]["inside"])
	push_warning("[ChangAn] 未知锚点 " + ref)
	return anchors.get("plaza", cell_to_px(Vector2i(W / 2, H / 2)))

func _spawn_city_npcs():
	for cfg in CITY_NPC_CONFIGS:
		var legs: Array = []
		var first_pos := Vector2.ZERO
		var cfg_legs: Array = cfg["legs"]
		for i in range(cfg_legs.size()):
			var L: Array = cfg_legs[i]
			var p: Vector2 = get_anchor_px(String(L[1])) + Vector2(L[4]) * 16.0
			if i == 0:
				first_pos = p
			legs.append({"start": int(L[2]), "end": int(L[3]), "state": String(L[0]), "pos": p})
		var npc = NPC_SCENE.instantiate()
		npc.name = cfg["name"]
		npc.npc_type = cfg["npc_type"]
		npc.position = first_pos
		var nd = NPCData.new()
		nd.npc_id = cfg["id"]
		nd.npc_name = cfg["name"]
		nd.personality = cfg["personality"]
		nd.home_position = first_pos
		nd.work_position = first_pos
		nd.custom_schedule = legs
		npc.npc_data = nd
		add_child(npc)
		npc_list.append(npc)

# ---- M3 阶段解锁：stage1/2 坊开门+程序化院落填充+局部刷 TileMap（§六-3 阶段化城市）----
# 通用白天规则 BFS：返回从 start 出发的可达集（探针/解锁校验用）
func _bfs_from(start: Vector2i) -> Dictionary:
	var blocked := {}
	for id in COLLIDING:
		blocked[id] = true
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var p: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if visited.has(q):
				continue
			if blocked.has(_tile_at(ground, q.x, q.y)) or blocked.has(_tile_at(decor, q.x, q.y)):
				continue
			visited[q] = true
			queue.append(q)
	return visited

func unlock_stage(stage: int):
	if not done or tile_map == null:
		push_warning("[ChangAn] unlock_stage 需在生成完成后调用")
		return
	var unlocked: Array = []
	var unlocked_lot_refs: Array = []
	for b in blocks:
		if String(b["type"]) != "ward" or _in_palace(int(b["col"]), int(b["row"])):
			continue
		var su := int(b["stage_unlock"])
		if su == 0 or su > stage:
			continue
		var ward_id := String(b["id"])
		if unlocked_wards.has(ward_id):
			continue   # 递进解锁（1→2）不重复填充/开门/入宵禁册
		unlocked_wards[ward_id] = true
		unlocked.append(String(b["name"]))
		for lot in b.get("lots", []):
			unlocked_lot_refs.append(String(lot["ref"]))
		# 填充（hash 种子确定，与解锁时机无关）：lots 坊铺 lot+空象限散院，余坊程序化院落
		_fill_ward_contents(b)
		# 开坊门并入宵禁册（宵禁进行中则直接闭门）
		var gate_tile := T_GATE_CLOSED if curfew else T_GATE_OPEN
		var cells: Array = ward_gate_cells.get(ward_id, [])
		for c in cells:
			decor[c.y * W + c.x] = gate_tile
		curfew_gates.append({"cells": cells, "kind": "ward", "ward": ward_id})
		# 局部重刷该坊矩形（地面全量铺贴防黑洞，装饰空格擦除）
		var x0 := col_x(int(b["col"]))
		var y0 := row_y(int(b["row"]))
		for yy in range(y0, y0 + bh):
			var base = yy * W
			for xx in range(x0, x0 + bw):
				var cp := Vector2i(xx, yy)
				tile_map.set_cell(0, cp, int(ground[base + xx]), Vector2i(0, 0))
				var di := int(decor[base + xx])
				if di != 0:
					tile_map.set_cell(1, cp, di, Vector2i(0, 0))
				else:
					tile_map.erase_cell(1, cp)
	for lot_pending in unlocked_lot_refs:
		if not interior_portals.has(lot_pending):
			_register_lot_portal(lot_pending)
			_build_interior_portal_area(lot_pending)
	print("[ChangAn-M3] unlock_stage(%d)：解锁坊=%s" % [stage, unlocked])
