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
const T_OUTER_WALL = 70     # 外郭城墙（旧两行制·垛口行；墙带改造后仅探针兼容留档）
# ---- 外郭城墙整带 tile 族（2026-09-08 重切落地：考古文档§7/§8，用户 Tiled 拼法固化）----
# 横墙 5 行=crest 垛口(16px整周期)+body_a/b/c 墙身+base 墙脚（纯墙底线 y185）；
# 竖墙 3 列=墙身 90° 旋转（墙厚 48px 断面）；拐角=竖墙纵贯+横墙紧贴内列起铺（齐平式，§8.1 语法3）
const T_WB_CREST = 114
const T_WB_BODY_A = 115
const T_WB_BODY_B = 116
const T_WB_BODY_C = 117
const T_WB_BASE = 118
const T_WB_V_W0 = 119       # 西墙·外列
const T_WB_V_W1 = 120       # 西墙·中列
const T_WB_V_W2 = 121       # 西墙·内列
const T_WB_V_E0 = 122       # 东墙·外列
const T_WB_V_E1 = 123       # 东墙·中列
const T_WB_V_E2 = 124       # 东墙·内列
const T_ZHUQUE = 71         # 朱雀大街御道
const T_MAIN_ROAD = 72      # 主干街
const T_WARD_STREET = 73    # 坊内十字街
const T_LANE = 74           # 巷路
const T_QUAY = 111          # 岸石·渠岸顶面（范式v3，可走）
const T_WATER = 112         # M3 三渠/南护城河水（范式v3 换江南蓝，碰撞）
const T_BRIDGE = 17         # M3 渠桥（复用开放世界桥瓦，无碰撞）

# ---- M3 宵禁（§六-2）：暮鼓戌时闭坊门/市门，晨鼓卯时开；四城门/宫门不闭 ----
const CURFEW_START := 19.0
const CURFEW_END := 5.0

# ---- M3 三渠（龙首/清明/永安）：街缝内1宽水带，跨路处铺桥 ----
const CANALS := [{"name": "清明渠", "seam": 1}, {"name": "龙首渠", "seam": 7}, {"name": "永安渠", "seam": 10}]

const COLLIDING := [5, 3, 7, 2, 10, 11, 12, 14, 15, 40, 100, 102, 103, 104, 105, 106, 108, 109, 65, 66, 68, 69, 70, 83, 84, 86, 88, 89, 112, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124]   # 坊墙43→100、足印=T_FOOT(102)（透明碰撞）；宅门75~77已去碰撞（M4传送门）；83~89=内景瓦碰撞段；112=渠水/护城河（范式v3）；114~124=外郭城墙整带族（与 tileset_generator collision_tile_ids 双份同步）

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
var stats_v3 := {}                       # 范式v3 统计（摊数/船数/停车数，探针断言用）
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
	# ---- 范式v3 市井人群（8→22）：闹市摊海/宫城仪仗/街面行人，城市感来源 ----
	{"id": "ca09", "name": "西市果贩", "personality": "热忱", "npc_type": "merchant",
	 "legs": [["idle", "market:西市", 8, 19, Vector2(-4, -3)]]},
	{"id": "ca10", "name": "买绢娘子", "personality": "温和", "npc_type": "tavern_f",
	 "legs": [["wander", "market:西市", 9, 18, Vector2(3, 2)], ["idle", "market:西市", 18, 21, Vector2(-2, 4)]]},
	{"id": "ca11", "name": "胡饼掌柜", "personality": "爽朗", "npc_type": "merchant",
	 "legs": [["idle", "market:西市", 10, 20, Vector2(-5, 5)]]},
	{"id": "ca12", "name": "西市闲客", "personality": "散漫", "npc_type": "mysterious",
	 "legs": [["wander", "market:西市", 8, 20, Vector2(5, -4)]]},
	{"id": "ca13", "name": "东市酒保", "personality": "豪爽", "npc_type": "tavern_f",
	 "legs": [["idle", "market:东市", 9, 20, Vector2(4, -3)]]},
	{"id": "ca14", "name": "书肆先生", "personality": "儒雅", "npc_type": "scholar",
	 "legs": [["idle", "market:东市", 10, 19, Vector2(-4, 3)], ["wander", "market:东市", 19, 21, Vector2(0, 0)]]},
	{"id": "ca15", "name": "东市脚夫", "personality": "憨厚", "npc_type": "warrior",
	 "legs": [["wander", "market:东市", 8, 18, Vector2(-3, -4)]]},
	{"id": "ca16", "name": "朱雀行人甲", "personality": "匆忙", "npc_type": "peasant_f",
	 "legs": [["wander", "plaza", 6, 20, Vector2(1, 0)], ["wander", "citygate:S", 20, 22, Vector2(0, 1)]]},
	{"id": "ca17", "name": "朱雀行人乙", "personality": "悠闲", "npc_type": "elder",
	 "legs": [["wander", "plaza", 8, 18, Vector2(-1, 1)]]},
	{"id": "ca18", "name": "过路书生", "personality": "好奇", "npc_type": "scholar",
	 "legs": [["wander", "citygate:N", 10, 16, Vector2(0, 1)], ["wander", "plaza", 16, 22, Vector2(1, -1)]]},
	{"id": "ca19", "name": "承天门郎将", "personality": "威严", "npc_type": "guard",
	 "legs": [["idle", "palace_south", 6, 22, Vector2(-2, 0)]]},
	{"id": "ca20", "name": "宫门卫士", "personality": "沉默", "npc_type": "guard",
	 "legs": [["idle", "palace_south", 6, 22, Vector2(2, 0)]]},
	{"id": "ca21", "name": "城南菜农", "personality": "勤劳", "npc_type": "peasant_f",
	 "legs": [["wander", "citygate:S", 6, 12, Vector2(-2, 0)], ["idle", "plaza", 12, 18, Vector2(2, 0)]]},
	{"id": "ca22", "name": "游街货郎", "personality": "市侩", "npc_type": "merchant",
	 "legs": [["wander", "market:东市", 8, 14, Vector2(0, 0)], ["wander", "plaza", 14, 20, Vector2(0, 0)], ["wander", "market:西市", 20, 22, Vector2(0, 0)]]},
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

# ---- 外郭城墙整带（2026-09-08 重切落地：考古文档§7/§8 用户 Tiled 拼法固化）----
# 几何纪律：城内碰撞格不变（墙圈仍占 margin/margin+1 两行两列——街网冻结/BFS 不受影响），
# 墙带向外增高加厚：N 横墙 5 行 y=margin-3(crest)..margin+1(base)；S 横墙 y=H-margin-2(base)..H-margin+2(crest)；
# W 竖墙 3 列 x=margin-1(w0)..margin+1(w2)；E 竖墙 x=W-margin-2(e2)..W-margin(e0)（墙厚 48px 断面）。
# 齐平式拐角（§8.1 语法3）：竖墙纵贯 y=margin-3..H-margin+2（拐角区=竖墙断面），
# 横墙 x 从竖墙内列旁起铺（竖墙外缘=横墙端头，墙底全线连续零重叠零露缝）。
# 双档基线（§7.2 规则5）：base tile 内容止于格内 y9（源 y185 纯墙档），门楼 prop 底=格线-1（源 y191 门楼档）。
func _paint_outer_walls():
	var x0 := margin + 2
	var x1 := W - margin - 3
	var band := [T_WB_CREST, T_WB_BODY_A, T_WB_BODY_B, T_WB_BODY_C, T_WB_BASE]
	for i in range(5):
		_set_rect(decor, x0, margin - 3 + i, x1 - x0 + 1, 1, band[i])
		_set_rect(decor, x0, H - margin - 2 + i, x1 - x0 + 1, 1, band[4 - i])
	var y0 := margin - 3
	var y1 := H - margin + 2
	for cc in [[margin - 1, T_WB_V_W0], [margin, T_WB_V_W1], [margin + 1, T_WB_V_W2],
			[W - margin, T_WB_V_E0], [W - margin - 1, T_WB_V_E1], [W - margin - 2, T_WB_V_E2]]:
		_set_rect(decor, int(cc[0]), y0, 1, y1 - y0 + 1, int(cc[1]))
	# 城内清零（墙带只向外扩，城内格不受影响）
	_set_rect(decor, margin + 2, margin + 2, W - margin * 2 - 4, H - margin * 2 - 4, 0)

# 四城门豁口：挖穿整带（N/S 门 5 行×3 格、E/W 门 3 列×3 格）——门楼 prop 后铺骑豁口上
func _carve_city_gates():
	var cx := col_x(5) - zq_s + zq_s / 2
	_set_rect(decor, cx - 1, H - margin - 2, 3, 5, T_GATE_OPEN)
	_register_gate("S", "明德门", [Vector2i(cx - 1, H - margin - 1), Vector2i(cx, H - margin - 1), Vector2i(cx + 1, H - margin - 1)], Vector2i(cx, H - margin - wall - 2))
	_set_rect(decor, cx - 1, margin - 3, 3, 5, T_GATE_OPEN)
	_register_gate("N", "玄武门", [Vector2i(cx - 1, margin), Vector2i(cx, margin), Vector2i(cx + 1, margin)], Vector2i(cx, margin + wall + 1))
	var cyc := _center_seam_y()
	_set_rect(decor, W - margin - 2, cyc - 1, 3, 3, T_GATE_OPEN)
	_register_gate("E", "春明门", [Vector2i(W - margin - 1, cyc - 1), Vector2i(W - margin - 1, cyc), Vector2i(W - margin - 1, cyc + 1)], Vector2i(W - margin - wall - 2, cyc))
	_set_rect(decor, margin - 1, cyc - 1, 3, 3, T_GATE_OPEN)
	_register_gate("W", "开远门", [Vector2i(margin, cyc - 1), Vector2i(margin, cyc), Vector2i(margin, cyc + 1)], Vector2i(margin + wall + 1, cyc))

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
	# 外郭城墙整带（2026-09-08 重切落地）：替代旧两行制——官方 80px 高墙带同构复刻
	_paint_outer_walls()
	# 环路（贴城墙内侧，4宽土路）
	var m := margin + wall
	_set_rect(ground, m, m, W - m * 2, ring, T_MAIN_ROAD)
	_set_rect(ground, m, H - m - ring, W - m * 2, ring, T_MAIN_ROAD)
	_set_rect(ground, m, m, ring, H - m * 2, T_MAIN_ROAD)
	_set_rect(ground, W - m - ring, m, ring, H - m * 2, T_MAIN_ROAD)
	# 纵向街道缝 i=1..cols-1；i=5 为朱雀大街（宽9）——夯土打底、仅中轴3宽铺御道石板（史实御道制式）
	for i in range(1, cols):
		if i == 5:
			_set_rect(ground, col_x(5) - zq_s, _origin().y, zq_s, block_span_y(), T_MAIN_ROAD)
			_set_rect(ground, col_x(5) - zq_s + 3, _origin().y, 3, block_span_y(), T_ZHUQUE)
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
			# 第五轮：坊墙已退役，"锁坊"只剩地坪概念——铺夯土即可（树坑弃：生成末尾
			# unlock_stage(1/2) 全城解锁时会铺排屋肌理，树坑瓦会顶掉排位 _cells_clear）
			var uy0 := row_y(int(b["row"]))
			var ux0 := col_x(int(b["col"]))
			for yy in range(uy0 + 1, uy0 + bh - 1):
				var ubase = yy * W
				for xx in range(ux0 + 1, ux0 + bw - 1):
					if int(ground[ubase + xx]) == 0:
						ground[ubase + xx] = T_LANE
			continue
		_fill_ward_contents(b)
	# M3 三渠+范式v3 南护城河（全城一次；渠后于坊填充避免被盖，街饰避水在其后）
	_paint_canals()
	_paint_moat()
	# M1 四城门：豁口挖穿整带（5 行/3 列制）+注册（v3 起自 _fill_ward_generic 移出）
	_carve_city_gates()
	# 视觉重构：四城门楼 prop + 街巷点缀（牌坊/街灯/行道树/渠柳）——放在渠之后可避开水格
	_spawn_city_gates_all()
	_paint_street_dressing()
	# v4 坊内修缮：墙脚绿带清扫（城内一切墙体正交相邻的草格一律夯土，消"墙根绿边"）
	_sweep_wall_grass()
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
# 排屋件池（2026-09-08 重切落地 §7.2：全部取自江南 B04 第1行族——画布高全 92px「同排同高」，
# 件间身宽对接成连排长屋；gable_ma=山墙封端件 96×96。禁混第2/3行族（跨行混拼=参差根因 R1））
const ROW_HOUSE_POOL := ["house_win_a", "house_win_small", "house_door_a", "house_win_a"]

# 排屋组装器：段内件依次身宽对接（x_px 累进，缝 0）、全排底边锚同一格线（§7.2 硬规则 3/4）；
# 段宽自适应：<160px 单件居中 / 160~250px 无封端直排 / ≥250px 双 gable_ma 山墙封端。
# footprint 按 sprite 实际像素覆盖换算格压 T_FOOT（防叠摆+碰撞线）
func _spawn_house_row(x_from: int, x_to: int, ry: int, seed_val: int) -> int:
	if x_to - x_from + 1 < 4 or not _cells_clear(x_from, ry, x_to - x_from + 1, 1):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var bottom := (ry + 1) * 16.0
	var x_px := x_from * 16.0
	var x_end := (x_to + 1) * 16.0
	var seg_w := x_end - x_px
	var placed := 0

	if seg_w < 160.0:
		var pn0: String = ROW_HOUSE_POOL[seed_val % ROW_HOUSE_POOL.size()]
		var t0 := _prop_tex(pn0)
		if t0:
			_spawn_prop(pn0, (x_px + x_end) / 2.0, bottom)
			_row_foot((x_px + x_end) / 2.0 - t0.get_width() / 2.0, t0.get_width(), ry)
			placed = 1
	else:
		var cap := seg_w >= 250.0
		var gable := _prop_tex("gable_ma")
		if cap and gable:
			_spawn_prop("gable_ma", x_px + gable.get_width() / 2.0, bottom)
			_row_foot(x_px, gable.get_width(), ry)
			x_px += gable.get_width()
			placed += 1
		var idx := 0
		while true:
			var pn: String = ROW_HOUSE_POOL[(seed_val / 7 + idx * 3) % ROW_HOUSE_POOL.size()]
			var t := _prop_tex(pn)
			if t == null:
				break
			var reserve := 0.0
			if cap and gable:
				reserve = gable.get_width()
			if x_px + t.get_width() + reserve > x_end:
				break
			if cap and gable and x_px + t.get_width() + reserve > x_end - t.get_width():
				break   # 至少还差一件空间则本轮不封端（留直排收尾）
			_spawn_prop(pn, x_px + t.get_width() / 2.0, bottom)
			_row_foot(x_px, t.get_width(), ry)
			x_px += t.get_width()
			placed += 1
			idx += 1
		if cap and gable and x_px + gable.get_width() <= x_end and placed >= 2:
			_spawn_prop("gable_ma", x_px + gable.get_width() / 2.0, bottom)
			_row_foot(x_px, gable.get_width(), ry)
			placed += 1
	stats_v3["row_house"] = int(stats_v3.get("row_house", 0)) + placed
	return placed

# 排屋 footprint：按 sprite 像素覆盖换算格压 T_FOOT（ry 行内）
func _row_foot(x_left_px: float, w: float, ry: int):
	if w <= 0.0:
		return
	var c0 := int(floor(x_left_px / 16.0))
	var c1 := int(ceil((x_left_px + w) / 16.0)) - 1
	for xx in range(c0, c1 + 1):
		if xx >= 0 and xx < W and ry >= 0 and ry < H:
			decor[ry * W + xx] = T_FOOT
# 第五轮「去墙小街区」（2026-09-07）：坊内巷排排位/地标池——坊=十字巷分隔小街区，
# 排屋沿巷背靠背（屋顶平行街道=样式图核心特征），园池口袋/街角地标穿插
const ROW_SLOTS := [1, 8, 16, 22]
const LANDMARK_PROPS := ["lou_brown", "lou_blue", "lou_dark", "hall_grey"]
# 城门楼：明德门用大骑楼，其余三门中型；E/W 竖墙门用 90° 旋转件（门脸朝城外，2026-09-08 重切落地）
const CITY_GATE_PROP := {"S": "gate_tower_big", "N": "gate_tower_mid", "E": "gate_tower_mid_v_e", "W": "gate_tower_mid_v_w"}
var _prop_tex_cache := {}

func _prop_tex(pname: String) -> Texture2D:
	if _prop_tex_cache.has(pname):
		return _prop_tex_cache[pname]
	var tex: Texture2D = TextureGen.load_png_texture(PROP_ROOT + pname + ".png")
	_prop_tex_cache[pname] = tex
	return tex

# 通用 prop 生成：底边中点锚（y-sort 与玩家自然遮挡），缺失切片静默跳过
# pscale：统一缩放（车轿族 96px 高素材按 0.5 半缩——原生比城门楼还高；比例纪律：轿/车≤门楼半高）
func _spawn_prop(pname: String, center_x: float, bottom_y: float, z := 2, pscale := 1.0) -> Sprite2D:
	var tex := _prop_tex(pname)
	if tex == null:
		return null
	var prop := Sprite2D.new()
	prop.texture = tex
	prop.position = Vector2(center_x, bottom_y)
	prop.offset = Vector2(0, -tex.get_height() * pscale / 2.0)
	prop.scale = Vector2(pscale, pscale)
	prop.z_index = z
	if pname != "":
		prop.add_to_group("changan_prop")
		prop.set_meta("prop", pname)   # 探针按名断言
	add_child(prop)
	return prop

# 旋转墙带 prop：侧缘中点锚（90° 旋转件用——左/右缘=墙脚线朝城外，2026-09-08 重切落地）
func _spawn_prop_side(pname: String, x: float, y: float, side: String, z := 2) -> Sprite2D:
	var tex := _prop_tex(pname)
	if tex == null:
		return null
	var prop := Sprite2D.new()
	prop.texture = tex
	prop.position = Vector2(x, y)
	prop.offset = Vector2(tex.get_width() / 2.0 if side == "L" else -tex.get_width() / 2.0, 0)
	prop.z_index = z
	prop.add_to_group("changan_prop")
	prop.set_meta("prop", pname)
	add_child(prop)
	return prop

# 建筑 prop：footprint 占格（T_FOOT 透明碰撞，镂空 prop 不露身后画）+ 底边中点锚 sprite
func _spawn_building(pname: String, foot: Rect2i, pscale := 1.0):
	for yy in range(foot.position.y, foot.position.y + foot.size.y):
		for xx in range(foot.position.x, foot.position.x + foot.size.x):
			decor[yy * W + xx] = T_FOOT
	var tex := _prop_tex(pname)
	if tex == null:
		return
	var cx := (foot.position.x + foot.size.x / 2.0) * 16.0
	var by := (foot.position.y + foot.size.y) * 16.0
	_spawn_prop(pname, cx, by, 2, pscale)

# 城门楼 prop + 门垛碰撞（拱门走廊净宽≥26px，出城触发区仍在豁口格）
# 双档基线（§7.2 规则5）：门楼底 y=191 档（格线-1），纯墙底 y=185 档（base tile 格内 9px）——差 6px=官方透视
func _spawn_city_gate(side: String):
	var pname: String = CITY_GATE_PROP.get(side, "gate_tower_mid")
	var tex := _prop_tex(pname)
	if tex == null:
		return
	var g: Dictionary = gate_info[side]
	var cells: Array = g["gap_cells"]
	var c0: Vector2i = cells[0]
	var c1: Vector2i = cells[cells.size() - 1]
	var vertical := (side == "E" or side == "W")
	var prop := Sprite2D.new()
	prop.texture = tex
	prop.z_index = 2
	prop.add_to_group("changan_prop")
	prop.set_meta("prop", pname)
	if not vertical:
		# 横墙门（S/N）：底边中点锚，底线=墙带 base 行格线-1（门楼档 y191 vs 纯墙档 y185）
		var cx := (c0.x + c1.x) * 0.5 + 0.5
		var base_row := H - margin - 2 if side == "S" else margin + 1
		prop.position = Vector2(cx * 16.0, (base_row + 1) * 16.0 - 1.0)
		prop.offset = Vector2(0, -tex.get_height() / 2.0)
	else:
		# 竖墙门（E/W）：旋转件（94×100），墙脚线=外缘列格线-1，外缘中点锚
		var cy := (c0.y + c1.y) * 0.5 + 0.5
		if side == "E":
			prop.position = Vector2((W - margin + 1) * 16.0 - 1.0, cy * 16.0)
			prop.offset = Vector2(-tex.get_width() / 2.0, 0)
		else:
			prop.position = Vector2((margin - 1) * 16.0 + 1.0, cy * 16.0)
			prop.offset = Vector2(tex.get_width() / 2.0, 0)
	add_child(prop)
	# 门垛碰撞兜底（墙带 tile 碰撞为主，垛体防视觉缝穿行：拱门净宽 32px ≥ 玩家 24px）
	var body := StaticBody2D.new()
	body.position = prop.position
	for sgn in [-1.0, 1.0]:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(8, 30) if not vertical else Vector2(30, 8)
		if not vertical:
			cs.position = Vector2(sgn * 20.0, -6.0)
		else:
			cs.position = Vector2(0, sgn * 20.0)
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
				# 范式v3：两岸贴岸格铺岸石（可走），渠岸不再是"土路临水"
				for dx in [-1, 1]:
					var bx: int = x + dx
					if bx >= 0 and bx < W and ground[y * W + bx] != T_BRIDGE:
						ground[y * W + bx] = T_QUAY
		canal_cells[String(canal["name"])] = cells

# ---- 范式v3 南护城河：墙外 3 宽水带 + 岸石 + 御道桥（石拱桥 prop）+ 停船 ----
# 只动墙外 margin 带（BFS/传送门/落点全在墙内，无结构影响）；出城触发区在门豁口，先于水面触发
# 2026-09-08 墙带改造：S 墙 crest 行扩至 H-margin+2，护城河整体南移 3 行（wy0=H-margin+4）避让
var moat_boat_count := 0

func _paint_moat():
	var wy0 := H - margin + 4           # 北岸岸石行（墙带 crest H-margin+2 外让 1 行草）
	var wy1 := wy0 + 3                  # 水带 3 行（wy0+1..wy0+3）
	if wy1 >= H:
		return
	for x in range(margin, W - margin):
		ground[wy0 * W + x] = T_QUAY
		for y in range(wy0 + 1, wy1 + 1):
			ground[y * W + x] = T_WATER
		if wy1 + 1 < H:
			ground[(wy1 + 1) * W + x] = T_QUAY
	# 御道十字：朱雀轴线铺桥（门豁口正南），两岸各留 1 行岸石衔接
	var cx := col_x(5) - zq_s + zq_s / 2
	for x in range(cx - 2, cx + 3):
		for y in range(wy0, wy1 + 1):
			ground[y * W + x] = T_BRIDGE
			bridge_count += 1
	# 第三轮修缮（红框"桥两端接水"根治）：
	# ① 环路(至 H-margin-1)与北岸岸石行之间的草带缺口铺 3 宽引道——门→引道→桥→对岸全程无缝
	for x in range(cx - 1, cx + 2):
		for y in range(H - margin, wy0):
			if int(ground[y * W + x]) != T_WATER:
				ground[y * W + x] = T_MAIN_ROAD
	# ② 拱桥（第四轮修缮：红框"桥横放"根治——deck 横构图换 bridge_body_v 纵桥竖条 42×96，
	#    桥长轴沿南北=进城过河方向；z=1 铺玩家层下（可穿行不遮挡），两侧露真实桥面瓦，
	#    桥体覆盖 wy0..wy0+5：北端压北岸岸顶、南端收在南岸引道上）
	_spawn_prop("bridge_body_v", (cx + 0.5) * 16.0, wy0 * 16.0 + 96.0, 1)
	# 停船：切片已抠透明底（BOAT_KEY），锚点全压进 3 行水带内（底边=水带下缘-2px，防"船嵌陆地"）；
	# 距桥轴 ≥10 格（拱桥 prop 半宽 48px+船半宽 48px+余量，防"船身被桥截半"）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260906
	var boats := ["boat_cover", "boat_small", "boat_sampan", "boat_row"]
	var spots := [8, 26, 47, 68, 89, 110, 131, 152, 173, 194, 215, 236, 257, 278, 299, 320, 341, 362, 383]
	for i in range(spots.size()):
		var bx: int = margin + spots[i]
		if abs(bx - cx) < 10 or bx + 5 >= W - margin:
			continue
		_spawn_prop(boats[i % boats.size()], (bx + 2) * 16.0, (wy0 + 4) * 16.0 - 2.0)
		moat_boat_count += 1
	# 第三轮修缮（红框"树和石墩重叠"根治）：原 willow 锚列表 (px+8) 与石灯 cx-6 恰好同点叠放；
	#   现柳=远桥位（|x-cx|≥12，96px 树冠不再压桥/门垛），石灯=近桥位（cx±6），横向互距≥4 格
	for px in [cx - 22, cx + 18, margin + 34, W - margin - 42]:
		# pier_wood 平台实测读作"木板墙"，弃用（范式v3 目检修框结论）；北岸只留柳+石灯
		if _moat_bank_free(px + 8, wy0):
			_spawn_prop("willow_a" if px % 2 == 0 else "willow_b", (px + 8) * 16.0 + 8.0, (wy0 + 1) * 16.0)
	if _moat_bank_free(cx - 6, wy0):
		_spawn_prop("lantern_stone_s", (cx - 6) * 16.0 + 8.0, (wy0 + 1) * 16.0)
	if _moat_bank_free(cx + 7, wy0):
		_spawn_prop("lantern_stone_s", (cx + 7) * 16.0 + 8.0, (wy0 + 1) * 16.0)

func _moat_bank_free(x: int, y: int) -> bool:
	if x < margin or x >= W - margin or y < 0 or y >= H:
		return false
	return int(ground[y * W + x]) == T_QUAY

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

# 非剧情坊程序化填充（范式v3 高密度里坊肌理，2026-09-06）：
# ① 无空地纪律：坊内草一律铺夯土人字纹地坪（lot 已铺的方砖/院草保留）
# ② 前店后院：N/S 墙内行 2×1 店排/摊排连续（避坊门中轴），W/E 内列行道树
# ③ 宅院连片：每半坊两排 4×2 民居背靠背（西段 x0+1/7、东段 x0+14/20），园池口袋穿插
# ④ 地标 50%：二层楼/殿占据一个宅位破天际线
# occupied：lot 占用矩形（全局格坐标 Rect2），相交跳过（剧情坊补密度用）
func _fill_ward_generic(b: Dictionary, occupied: Array = []):
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(b["id"]))
	var high := String(b["fill"]) == "residential_high"
	var x0 := col_x(int(b["col"]))
	var y0 := row_y(int(b["row"]))
	var gx0 := x0 + bw / 2 - 1
	# ① 地坪：全坊矩形铺满（第五轮修缮：坊墙退役后坊缘 1 格草环裸露=无空地纪律违规；
	#    绿化只留园池口袋/树。lot 方砖/院草保留，只盖仍为草的格）
	for yy in range(y0, y0 + bh):
		var base = yy * W
		for xx in range(x0, x0 + bw):
			if int(ground[base + xx]) == 0:
				ground[base + xx] = T_LANE
	# ② N/S 店排（前店后院坊市肌理）：第四轮修缮——house 族 sprite 檐宽≈95px(6格) 而 foot 仅 2 格，
	#    原步距 3 必致相邻店 sprite 层层互叠（vision 判"红门有门无墙/短墙截断"的真凶）——
	#    改 house/stall 交替：house 位间距 7 格（sprite 6 格+1 净距），间隔位放窄 stall（46~50px 不出 3 格）
	var shop_vars := ["house_door_a", "gable_ma", "house_win_a", "gable_white", "house_win_small"]   # ≤96px 檐宽（house_shop_open 190px 巨宽弃用）
	var stall_vars := ["stall_red", "stall_wood", "stall_red2", "stall_banner"]   # 窄款 43~46px（96px 宽棚款留市场内场，防压后排院墙）
	var shop_slots := [1, 8, 15, 22]      # house 位（间距 7 ≥ sprite 6 格）
	var stall_slots := [4, 11, 18, 21]   # stall 位（窄摊 46px=3 格；与 house 位净距≥3 防叠）
	for row in [y0 + 1, y0 + bh - 2]:
		for si in range(shop_slots.size()):
			var sx := x0 + int(shop_slots[si])
			if sx + 1 >= gx0 - 1 and sx <= gx0 + 2:
				continue
			var rect := Rect2i(sx, row, 2, 1)
			if _hits_occupied(rect, occupied) or not _cells_clear(sx, row, 2, 1):
				continue
			if rng.randf() < (0.85 if high else 0.7):
				_spawn_building(shop_vars[(si + int(b["col"])) % shop_vars.size()], rect)
		for si in range(stall_slots.size()):
			var sx := x0 + int(stall_slots[si])
			if sx + 1 >= gx0 - 1 and sx <= gx0 + 2:
				continue
			var rect := Rect2i(sx, row, 2, 1)
			if _hits_occupied(rect, occupied) or not _cells_clear(sx, row, 2, 1):
				continue
			if rng.randf() < (0.75 if high else 0.6):
				_spawn_building(stall_vars[rng.randi_range(0, stall_vars.size() - 1)], rect)
	# ③ 排屋肌理（2026-09-08 重切落地重写：§7.2 硬规则——同排同高/身宽对接/底边锚）：
	#    坊=十字巷分隔的 4 小街区，每排被 N-S 巷切成东西两段，段内连排长屋连续对接
	#    （替代旧 ROW_SLOTS 散点：间距 7 格>件宽 93px 必露 19px 缝=R1「房子贴不到一起」根因）；
	#    屋顶平行街道成排、背靠背（样式图核心特征），园池口袋/街角地标楼穿插破均质。
	#    视觉带核算（排屋件 92px 高、底边锚排带格底，上探 5.75 格）：
	#    北店排 y0+1 视觉 -3..2 / 巷北排 y0+8 视觉 3.25..9 / 十字巷 12..13 /
	#    巷南排 y0+18 视觉 13.25..19（与南店排 19.25 相接=背靠背街屋）
	var gy0 := y0 + bh / 2
	var pocket_seed := hash(String(b["id"]))
	var landmark_half := rng.randi() % 2
	var landmark_slot: int = [1, 22][rng.randi() % 2]  # 街角位（临主街+坊缘，视野最开阔）
	var row_defs := [[0, y0 + 8], [1, gy0 + 6]]    # [半坊, 脚行]：巷北排 / 巷南排（gy0+6=y0+18）
	for rd in row_defs:
		var half: int = rd[0]
		var ry: int = rd[1]
		for seg in [[x0 + 1, gx0 - 1], [gx0 + 2, x0 + bw - 2]]:
			var s_from: int = seg[0]
			var s_to: int = seg[1]
			if s_to - s_from < 4 or _hits_occupied(Rect2i(s_from, ry, s_to - s_from + 1, 1), occupied):
				continue
			# 街角地标楼（每坊 1）：破天际线（段首/段尾 2 格）
			if half == landmark_half:
				if landmark_slot == 1 and s_from == x0 + 1 and _cells_clear(s_from, ry, 2, 1):
					_spawn_building(LANDMARK_PROPS[(hash(String(b["id"])) + ry) % LANDMARK_PROPS.size()], Rect2i(s_from, ry, 2, 1))
					s_from += 2
				elif landmark_slot == 22 and s_to == x0 + bw - 2 and _cells_clear(s_to - 1, ry, 2, 1):
					_spawn_building(LANDMARK_PROPS[(hash(String(b["id"])) + ry) % LANDMARK_PROPS.size()], Rect2i(s_to - 1, ry, 2, 1))
					s_to -= 2
			# 园池口袋（抽稀节奏，样式图疏密）：北排植树/南排盆景+跳过整段
			if rng.randf() < 0.16:
				if half == 0:
					_spawn_prop("tree_lush_a" if (s_from + ry) % 2 == 0 else "tree_lush_b", (s_from + 2) * 16.0, (ry + 2) * 16.0)
				else:
					_spawn_prop("bonsai_b", (s_from + 2) * 16.0, ry * 16.0)
				continue
			_spawn_house_row(s_from, s_to, ry, pocket_seed + ry * 31 + s_from)
	# ④ 临巷生活小件：贴巷北排立面（足印下缘邻格=门口放物，窄款 48px 不出排带）；
	#    巷南排前庭被南店排檐盖（背靠背街屋），不放
	for i in range(rng.randi_range(2, 3)):
		var slot2: int = ROW_SLOTS[rng.randi_range(0, ROW_SLOTS.size() - 1)]
		var px2: int = x0 + slot2 + 1
		var py2: int = y0 + 10 + (rng.randi() % 2)
		if int(decor[py2 * W + px2]) != 0 or int(ground[py2 * W + px2]) != T_LANE:
			continue
		var near_face := false   # 必须贴排屋立面（上邻 2 格内有建筑足印）
		for dy2 in range(1, 3):
			if int(decor[(py2 - dy2) * W + px2]) == T_FOOT:
				near_face = true
		if not near_face:
			continue
		var sp: String = ["bench_wood", "bonsai_b", "lantern_stone_s"][i % 3]
		_spawn_prop(sp, px2 * 16.0 + 8.0, (py2 + 1) * 16.0)
	# W/E 内列行道树（低频，免大件侧脸穿墙）
	for edge_x in [x0 + 1, x0 + bw - 2]:
		for yy in range(y0 + 5, y0 + bh - 5, 4):
			if abs(yy - (y0 + bh / 2)) < 3:
				continue
			if int(decor[yy * W + edge_x]) == 0 and rng.randf() < 0.5:
				decor[yy * W + edge_x] = 8
	if not high:   # 低密度坊散树（橡树瓦，可行走装饰）
		for i in range(rng.randi_range(2, 5)):
			var tx := x0 + rng.randi_range(2, 23)
			var ty := y0 + rng.randi_range(2, 23)
			if int(decor[ty * W + tx]) == 0 and int(ground[ty * W + tx]) == T_LANE:
				decor[ty * W + tx] = 8

# 建造校验：矩形内 decor 全空且地面不碰撞（范式v3 密度布点用）
func _cells_clear(x: int, y: int, w: int, h: int) -> bool:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx < 0 or yy < 0 or xx >= W or yy >= H:
				return false
			if int(decor[yy * W + xx]) != 0:
				return false
			if COLLIDING.has(int(ground[yy * W + xx])):
				return false
	return true

func _hits_occupied(rect: Rect2i, occupied: Array) -> bool:
	for oc in occupied:
		if oc.intersects(Rect2(rect)):
			return true
	return false
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
	# 朱雀大街：红灯笼街灯两侧成对同高（第四轮修缮：原左右交替=每行只有单侧一盏，zoom2 下读作
	#   "孤灯零散"——改同 y 两侧各一盏成对；国槐行道树交错，不与灯同行）
	var y := _origin().y + 6
	var alt := 0
	while y < H - margin - wall - 4:
		for lx2 in [zq_x0 + 1, zq_x1 - 1]:
			if _dressing_cell_free(lx2, y):
				_spawn_prop("lamp_red", lx2 * 16.0 + 8.0, (y + 1) * 16.0)
		# 街树位内移 1 格（zq_x0+2/zq_x1-2）：缘内 1 格时 96px 树冠跨过坊界压临街店排瓦顶
		#   （第四轮复验同位复发根因）；避让半径 4 格
		var tx := zq_x1 - 2 if alt % 2 == 0 else zq_x0 + 2
		if y % 16 == 6 and _dressing_cell_free(tx, y - 3) and not _near_building_foot(tx, y - 3, 4):
			_spawn_prop("tree_lush_a" if alt % 3 == 0 else "tree_lush_b", tx * 16.0 + 8.0, (y - 2) * 16.0)
		alt += 1
		y += 12
	# 三渠沿岸点景（v4 修缮：渠柳树冠 96px 必遮 1 宽水带——红框"运河被盖"同源；换 48px 石灯/盆景，
	#   岸石带上单侧交替、距水轴 2 格（sprite 几何完全不触水面），避桥带）
	for canal in CANALS:
		var cxx := col_x(int(canal["seam"])) - main_s + main_s / 2
		var wi := 0
		for wy in range(margin + wall + 4, H - margin - wall - 4, 10):
			var dx: int = -2 if wi % 2 == 0 else 2
			if _dressing_cell_free(cxx + dx, wy) and int(ground[wy * W + cxx + dx]) != T_BRIDGE:
				_spawn_prop("lantern_stone_s" if wi % 4 < 2 else "bonsai_b", (cxx + dx) * 16.0 + 8.0, (wy + 1) * 16.0)
			wi += 1
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
			if _dressing_cell_free(xx, wy) and not _near_building_foot(xx, wy):
				_spawn_prop("tree_big", xx * 16.0 + 8.0, (wy + 1) * 16.0)
	# 牌坊：承天门外金大牌坊 + 明德门内石牌坊（朱雀轴线礼制门户）
	var pcx := col_x(5) - zq_s + zq_s / 2
	var palace_south := row_y(palace_rows.y) + bh
	_spawn_prop("paifang_big_gold", (pcx + 0.5) * 16.0, (palace_south + 3) * 16.0)
	_spawn_prop("paifang_stone_g", (pcx + 0.5) * 16.0, (H - margin - wall - 4) * 16.0)
	# 明德门内石狮（第四轮修缮：原 pcx-2/pcx+3 偏 1 格不对称——中轴对称 pcx±3）+ 门楼两侧红灯笼成对
	_spawn_prop("lion_white_a", (pcx - 3) * 16.0 + 8.0, (H - margin - wall - 2) * 16.0)
	_spawn_prop("lion_white_b", (pcx + 3) * 16.0 + 8.0, (H - margin - wall - 2) * 16.0)
	for lx2 in [pcx - 4, pcx + 4]:
		if _dressing_cell_free(lx2, H - margin - wall - 3):
			_spawn_prop("lamp_red", lx2 * 16.0 + 8.0, (H - margin - wall - 2) * 16.0)
	# ---- 范式v3 街面生活道具：停车马/路口灯笼/告示牌/拴驴/金轿（均 _dressing_cell_free 避水避墙）----
	var prng := RandomNumberGenerator.new()
	prng.seed = 20260907
	# 朱雀两翼停车马（第三轮修缮：v4"路中锚"红框否决——改路缘带 zq_x0+2/zq_x1-2 交替停靠，
	#   不占御道中轴；车轿族 96px 高原生比城门楼(94px)还高——按 0.5 半缩，半缩后≤门楼半高，比例纪律）
	var street_carts := ["sedan_red", "donkey_saddle"]
	var ci := 0
	var cy := _origin().y + 20
	# 横街带（环路+主干街缝）：路口禁停（vision 验收红框"驴堵路口"根治）
	var cart_bands: Array = []
	var cm := margin + wall
	cart_bands.append([cm, cm + ring])
	cart_bands.append([H - cm - ring, H - cm])
	for j in range(1, rows):
		cart_bands.append([row_y(j) - main_s, row_y(j)])
	while cy < H - margin - wall - 30:
		var in_band := false
		for band in cart_bands:
			if cy + 2 >= band[0] and cy - 1 < band[1]:
				in_band = true
				break
		var lx: int = zq_x0 + 2 if ci % 2 == 0 else zq_x1 - 2
		if not in_band and _dressing_cell_free(lx, cy):
			_spawn_prop(street_carts[ci % street_carts.size()], lx * 16.0 + 8.0, (cy + 2) * 16.0, 2, 0.5)
			ci += 1
		cy += 34
	# 主干街十字路口：红灯笼/告示牌（第四轮修缮：原单只摆一角读作"孤灯"——改对角成对，
	#    两件同种对角摆=路口四角两两对称，语义=路口标识）
	for i in range(1, cols):
		if i == 5:
			continue
		for j in range(1, rows):
			var pick: String = "lamp_red" if (i + j) % 3 != 0 else "board_notice"
			for corner in [[1, 1], [-2, -2]]:
				var ix: int = col_x(i) - main_s + int(corner[0])
				var iy: int = row_y(j) - main_s + int(corner[1])
				if _dressing_cell_free(ix, iy):
					_spawn_prop(pick, ix * 16.0 + 8.0, (iy + 1) * 16.0)
	# 城门内侧黄灯柱（第四轮修缮：原单侧一支不对称——改门内两侧成对）
	for side in gate_info:
		var g: Dictionary = gate_info[side]
		var inside: Vector2i = g["inside"]
		var horizontal: bool = side == "S" or side == "N"
		for sgn in [-3, 3]:
			var off := Vector2i(sgn, 0) if horizontal else Vector2i(0, sgn)
			if _dressing_cell_free(inside.x + off.x, inside.y + off.y):
				_spawn_prop("lamp_yellow", (inside.x + off.x) * 16.0 + 8.0, (inside.y + off.y + 1) * 16.0)
	# 承天门外金轿仪仗（朝房意象；第三轮修缮：0.5 半缩对齐门楼比例）
	var palace_south_y := row_y(palace_rows.y) + bh
	if _dressing_cell_free(pcx - 5, palace_south_y + 1):
		_spawn_prop("sedan_gold", (pcx - 4) * 16.0, (palace_south_y + 2) * 16.0, 2, 0.5)
	if _dressing_cell_free(pcx + 5, palace_south_y + 1):
		_spawn_prop("sedan_gold", (pcx + 6) * 16.0, (palace_south_y + 2) * 16.0, 2, 0.5)

# ---- v4 墙脚绿带清扫：城墙/坊墙/宫墙正交相邻的城内草格一律夯土（"墙根绿边"根治）----
func _sweep_wall_grass():
	var wall_ids := [T_WARD_WALL, T_WARD_WALL_V, T_PALACE_WALL, T_PALACE_WALL_V, T_OUTER_WALL,
			T_WALL_BODY, T_WALL_FACE_V, T_WALL_CAP_W, T_WALL_CAP_E,
			T_WB_CREST, T_WB_BODY_A, T_WB_BODY_B, T_WB_BODY_C, T_WB_BASE,
			T_WB_V_W0, T_WB_V_W1, T_WB_V_W2, T_WB_V_E0, T_WB_V_E1, T_WB_V_E2]
	for y in range(margin, H - margin):
		var base = y * W
		for x in range(margin, W - margin):
			if int(ground[base + x]) != 0:
				continue
			var near_wall := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + int(d.x)
				var ny: int = y + int(d.y)
				if wall_ids.has(int(decor[ny * W + nx])):
					near_wall = true
					break
			if near_wall:
				ground[base + x] = T_LANE

# 点缀落格校验：格内须为可走地面且无装饰（避水/避墙/避坊内）
func _dressing_cell_free(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return false
	var g := int(ground[y * W + x])
	var d := int(decor[y * W + x])
	return d == 0 and (g == T_MAIN_ROAD or g == T_ZHUQUE or g == T_LANE)

# 建筑 sprite 邻近检查（第四轮品控§三-3）：树/大件摆放点半径 r 格内有建筑足印(T_FOOT)即避让，
# 防止树冠压邻店瓦顶（红框"树长在屋顶里"根治——只查本格 decor 挡不住 sprite 像素级外扩）
func _near_building_foot(x: int, y: int, r := 3) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx: int = x + dx
			var ny: int = y + dy
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			if int(decor[ny * W + nx]) == T_FOOT:
				return true
	return false

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
	# 宫墙整带 prop 链（2026-09-08 重切落地：palace_wall_run 48×64 整带，考古§7.1 样板间 B PASS；
	# tile ring 保留=碰撞/BFS 兜底，prop 盖上方做 50~64px 高墙视觉——修复 R5「24px 宫墙 vs 96px 宫门 1:4 断裂」）
	# 拐角/宫门豁口不铺（角格 tile 兜底+承天门 prop 骑豁口）；玩家 z=5 恒在 prop 前，无遮挡问题
	if _prop_tex("palace_wall_run") != null:
		for wx in range(px0 + 1, px1, 3):
			_spawn_prop("palace_wall_run", (wx + 1.5) * 16.0, (py0 + 1) * 16.0)
		var pcx2 := col_x(5) - zq_s + zq_s / 2
		for wx in range(px0 + 1, px1, 3):
			if abs(wx + 1 - pcx2) <= 3:
				continue   # 承天门豁口（palace_gate_red prop 骑上）
			_spawn_prop("palace_wall_run", (wx + 1.5) * 16.0, (py1 + 1) * 16.0)
		for wy2 in range(py0 + 1, py1, 3):
			_spawn_prop_side("palace_wall_run_v_w", px0 * 16.0, (wy2 + 1.5) * 16.0, "L")
			_spawn_prop_side("palace_wall_run_v_e", (px1 + 1) * 16.0, (wy2 + 1.5) * 16.0, "R")
	# 丹墀广场：院内满铺方砖（金砖漫地），中轴御道直抵太极殿
	_set_rect(ground, px0 + 1, py0 + 1, px1 - px0 - 1, py1 - py0 - 1, T_PAVE)
	var pcx := col_x(5) - zq_s + zq_s / 2
	_set_rect(ground, pcx - 1, py0 + 1, 3, py1 - py0 - 1, T_ZHUQUE)
	# 太极殿（重檐金顶，foot 9×3 压 T_HOUSE）坐北朝南；两仪殿/东宫东西对峙
	_spawn_building("hall_taiji", Rect2i(pcx - 4, py0 + 2, 9, 3))
	var mid_y := py0 + (py1 - py0) / 2
	_spawn_building("hall_gold2", Rect2i(px1 - 9, mid_y - 3, 5, 2))
	_spawn_building("hall_gold3", Rect2i(px0 + 4, mid_y - 3, 5, 2))
	# 范式v3 宫城建筑群：白石台基（岸石浅色 Stone）+ 廊庑东西各三座 + 朱红廊柱仪仗
	_set_rect(ground, pcx - 6, py0 + 6, 13, 2, T_QUAY)   # 太极殿前白石台基（可走）
	for wing_y in [mid_y - 9, mid_y + 2, py1 - 6]:
		_spawn_building("hall_gold2", Rect2i(px1 - 9, wing_y, 5, 2))
		_spawn_building("hall_gold3", Rect2i(px0 + 4, wing_y, 5, 2))
	var prng := RandomNumberGenerator.new()
	prng.seed = 20260906
	for py in range(py0 + 8, py1 - 2, 5):
		for px in [pcx - 5, pcx + 5]:
			if int(decor[py * W + px]) == 0:
				_spawn_prop("pillar_red", px * 16.0 + 8.0, (py + 1) * 16.0)
	# 中轴仪仗树对（每 8 行一株，银杏意象用茂树）——第五轮修缮：树位移 pcx±8，
	# 树冠±2.8 格缘距廊柱（pcx±5）0.2 格净空，根治"树冠裹柱"（vision 四查红框）
	for ty in range(py0 + 10, py1 - 4, 8):
		for tx in [pcx - 8, pcx + 8]:
			if int(decor[ty * W + tx]) == 0:
				_spawn_prop("tree_lush_a" if (ty / 8) % 2 == 0 else "tree_lush_b", tx * 16.0 + 8.0, (ty + 1) * 16.0)
	# 殿前香炉+宫门楼（承天门 prop 骑在南宫门豁口上，可穿行）
	_spawn_prop("incense_bronze", (pcx - 3) * 16.0 + 8.0, (py0 + 7) * 16.0)
	_spawn_prop("incense_bronze", (pcx + 4) * 16.0 + 8.0, (py0 + 7) * 16.0)
	_spawn_prop("palace_gate_red", (pcx + 0.5) * 16.0, (py1 + 2) * 16.0)
	# 四角金亭（角楼意象）+ 承天门内石狮一对
	for corner in [Vector2i(px0 + 2, py0 + 2), Vector2i(px1 - 3, py0 + 2), Vector2i(px0 + 2, py1 - 3), Vector2i(px1 - 3, py1 - 3)]:
		_spawn_building("ting_gold", Rect2i(corner.x - 1, corner.y - 1, 2, 2))
	_spawn_prop("lion_white_a", (pcx - 2) * 16.0 + 8.0, (py1 - 1) * 16.0)
	_spawn_prop("lion_white_b", (pcx + 2) * 16.0 + 8.0, (py1 - 1) * 16.0)
	# 锚点：承天门内（范式v3 宫城仪仗守卫用）
	anchors["palace_south"] = cell_to_px(Vector2i(pcx, py1 + 2))
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
	# 第五轮「去墙小街区」（2026-09-07 样式图驱动）：坊墙圈/坊门瓦/坊门楼/门外街基全退役——
	# 坊=开放街区组（沿街店排+坊内巷网+排屋肌理，见 _fill_ward_generic）；
	# 市墙市门/宫墙/外郭城墙保留（两市宵禁册/宫城礼制/出城 Portal 仍锚定其上）
	_set_rect(ground, x0, y0, bw, bh, T_GRASS)
	# 坊内十字巷（2宽，原坊内十字街位置）：小街区内部巷网骨架，与主街网连通
	var gx0 := x0 + bw / 2 - 1
	var gy0 := y0 + bh / 2 - 1
	_set_rect(ground, gx0, y0 + 1, 2, bh - 2, T_WARD_STREET)
	_set_rect(ground, x0 + 1, gy0, bw - 2, 2, T_WARD_STREET)

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
	# 锚点：市中心（范式v3 人群 NPC 用）
	anchors["market:%s" % mname] = cell_to_px(Vector2i(x0 + bw / 2, y0 + bh / 2))
	# 摊海（范式v3 闹市）：中巷两侧列摊 + 市门内侧固定摊，15 型雨棚摊/食摊循环。
	# 布点纪律：不进中巷（x11~13）/环路走带——玩家碰撞体 24px 需 2 格净宽
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(mname)
	var stall_props := ["stall_red", "stall_wood", "stall_red2", "stall_rw", "stall_banner",
			"stall_awn_blue", "stall_awn_blue2", "stall_awn_green", "stall_red_open", "stall_goods_blue",
			"stall_white_awn", "stall_green_awn", "stall_food_a", "stall_food_b", "stall_awn_bluew"]
	var stall_count := 0
	for sy in range(5, 22, 4):
		for sx in [x0 + 5, x0 + 8, x0 + 16, x0 + 19]:
			if _spawn_stall(stall_props[rng.randi_range(0, stall_props.size() - 1)], sx, sy):
				stall_count += 1
	var corner_spots := [Vector2i(2, 2), Vector2i(21, 2), Vector2i(2, 22), Vector2i(21, 22)]
	for spot in corner_spots:
		if _spawn_stall(stall_props[rng.randi_range(0, stall_props.size() - 1)], x0 + spot.x, y0 + spot.y):
			stall_count += 1
	stats_v3["market_stalls"] = int(stats_v3.get("market_stalls", 0)) + stall_count
	# 停车/歇脚：市角马车·牛车（foot 3×2）+ 市门内红轿（foot 2×2）
	# 第三轮修缮：cart_horse_a(192px) 即便半缩仍 96px 与门楼等高——下架；留蓝棚/牛车，0.5 半缩
	var cart_props := ["carriage_blue", "ox_cart_cover"]
	for cp in [[2, 18], [20, 18]]:
		var crect := Rect2i(x0 + cp[0], y0 + cp[1], 3, 2)
		if _cells_clear(crect.position.x, crect.position.y, 3, 2):
			_spawn_building(cart_props[rng.randi_range(0, cart_props.size() - 1)], crect, 0.5)
	var sedan := Rect2i(x0 + 10, y0 + 22, 2, 2)
	if _cells_clear(sedan.position.x, sedan.position.y, 2, 2):
		_spawn_building("sedan_red", sedan, 0.5)

func _spawn_stall(pname: String, sx: int, sy: int) -> bool:
	if sx < 0 or sy < 0 or sx + 2 >= W or sy >= H:
		return false
	for xx in range(sx, sx + 2):
		if int(decor[sy * W + xx]) != 0:
			return false
	_spawn_building(pname, Rect2i(sx, sy, 2, 1))
	return true

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
	stats_v3["boats"] = moat_boat_count
	print("[ChangAn-M0] %s 生成 %dms 地面=%d 装饰=%d BFS未达=%d 城门=%d" %
			[stats["size"], ms, non_ground, decor_cnt, bfs_failures.size(), gate_info.size()])
	print("[ChangAn-M3] 渠=%s 桥=%d 宵禁门=%d 夜BFS未达=%d 城内NPC=%d" %
			[canal_cells, bridge_count, curfew_gates.size(), night_bfs_failures.size(), npc_list.size()])
	print("[ChangAn-v3] 市摊=%d 护城河船=%d（范式v3 密度统计）" %
			[int(stats_v3.get("market_stalls", 0)), moat_boat_count])
	done = true
	generation_done.emit()
	# 第五轮（2026-09-07 体验模式）：剧情冻结使 stage 门制永锁——生成完成即全城解锁，
	# 排屋肌理全量铺开（探针后续 unlock_stage 调用幂等，unlocked_wards 去重）
	unlock_stage(1)
	unlock_stage(2)

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
		# 填充（hash 种子确定，与解锁时机无关）：lots 坊铺 lot+空象限排屋，余坊排屋肌理
		_fill_ward_contents(b)
		# 开坊门并入宵禁册（第五轮起坊无门，cells 恒空——留作 stage 门制恢复时的挂点）
		var gate_tile := T_GATE_CLOSED if curfew else T_GATE_OPEN
		var cells: Array = ward_gate_cells.get(ward_id, [])
		for c in cells:
			decor[c.y * W + c.x] = gate_tile
		if not cells.is_empty():
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
