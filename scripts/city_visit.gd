extends Node2D
# 长安城进出·世界切换管理器（M1）—— docs/长安城地图设计.md §2.1/§七
# 开放世界侧：长安外郭轮廓 footprint（城砖40围圈+四门豁口铺路，符号性存在非1:1）+ 四门入城触发区
# 进城：淡出 → 冻结开放世界系统 → changan.tscn 挂 World 偏移坐标空间 → 玩家落门内 3×3 校验点 → 淡入
# 出城：反向，玩家回 footprint 对应城门外（设计稿§2.1：出口回到开放世界对应城门外位置）
# 注意：玩家节点不可重挂父节点（survival_hud/minimap 等按 /root/Main/World/Player 路径引用），
#       城内行走靠"传送玩家到偏移空间"，开放世界 TileMap 物理不在该空间、互不干扰

const ChangAnScene := preload("res://scenes/changan.tscn")
const ChangAnV2Scene := preload("res://scenes/changan_v2.tscn")   # 长安v2·剧情尺度新城（docs/长安城v2-剧情尺度规划.md）
const INTERIOR_SCRIPT := preload("res://scripts/changan_interior.gd")
const TILE_CITY_WALL := 40
const TILE_PATH := 1
# 城市版本开关：1=旧城（108坊史实尺度 401×304）；2=v2剧情尺度新城（30街区 168×142 灰盒文字占位）
# 两城坐标空间错开共存——v2 城挂 y=60000，旧城/旧内景 40000/80000 原样保留可随时切回对比
const CITY_VERSION := 2
const CITY_OFFSET_V1 := Vector2(0, 40000)      # 城内坐标空间（开放世界半径200格=±3200px 之外）
const INTERIOR_OFFSET_V1 := Vector2(0, 80000)  # v1 内景坐标空间
const CITY_OFFSET_V2 := Vector2(0, 60000)
const INTERIOR_OFFSET_V2 := Vector2(0, 100000) # v2 内景（灰盒期未启用）
const FP_W_V1 := 64                            # v1 footprint 外郭轮廓尺寸（格）
const FP_H_V1 := 44
const FP_W_V2 := 44                            # v2 城更小，footprint 同比缩（152:126 ≈ 44:36）
const FP_H_V2 := 36
const FP_SCAN_PAD := 8                         # 选址扫描净空外扩
const FREEZE_NODES := ["WorldGenerator", "FarmSystem", "StationSystem", "MobSpawner", "NPCSpawner", "TreeChopSystem"]
# 注意：WeatherController 不冻结（M3）——城内时辰照常流动驱动宵禁，World CanvasModulate 夜色覆盖全画布

# 按版本初始化的运行期量（名沿用旧 const，调用处零改动）
var CITY_OFFSET := CITY_OFFSET_V1
var INTERIOR_OFFSET := INTERIOR_OFFSET_V1
var FP_W := FP_W_V1
var FP_H := FP_H_V1

var world: Node2D = null
var world_gen = null
var player: CharacterBody2D = null
var changan: Node2D = null               # 城内场景实例（null=不在城内）
var interior: Node2D = null              # M4 当前内景实例（null=不在内景）
var interior_return_cell := Vector2i.ZERO   # 进内景前的城内格坐标（返回原位）
var _portal_unlock_ms := 0               # 出内景后短暂忽略触发（仅限原触发格，离开即解锁）
var in_city := false
var footprint_origin := Vector2i.ZERO
var gate_cells := {}                     # side -> {gap: Vector2i, outside: Vector2i}（footprint 格坐标）
var _busy := false                       # 进出城过渡互斥
var _fade_rect: ColorRect = null
var _minimap: Control = null
var _hint_shown := false
var auto_spawn_in_city := true           # 出生点=长安明德门内（探针环境自动跳过，防干扰回归/E2E）


func _ready():
	world = get_node_or_null("/root/Main/World")
	if world == null:
		push_error("[CityVisit] World 缺失，进出城功能停用")
		return
	player = world.get_node_or_null("Player")
	world_gen = world.get_node_or_null("WorldGenerator")
	_minimap = world.get_node_or_null("UI/MinimapHUD")
	_setup_fade_layer()
	if CITY_VERSION == 2:
		CITY_OFFSET = CITY_OFFSET_V2
		INTERIOR_OFFSET = INTERIOR_OFFSET_V2
		FP_W = FP_W_V2
		FP_H = FP_H_V2
	# WorldGenerator._ready 在 Main._ready 同帧早已跑完（_setup_city_visit 排最后），可直接铺轮廓
	_setup_footprint()
	if auto_spawn_in_city and not _probe_present():
		_auto_enter_city()

# 探针判定：root 下挂载 res://tools/ 脚本的节点（regress/E2E/mob/mtn 探针均为临时注入的 autoload）
func _probe_present() -> bool:
	for child in get_tree().root.get_children():
		var s = child.get_script()
		if s != null and String(s.resource_path).begins_with("res://tools/"):
			return true
	return false

# 开局直接入城（2026-09-07 长安体验模式）：出生点=长安明德门内，黑屏直达不给开放世界画面
# ——先淡入黑屏再等系统稳定（NPC/纹理/世界首帧），玩家视角全程黑屏→城内淡入
func _auto_enter_city():
	_fade_rect.color = Color(0, 0, 0, 1.0)   # 立即压黑，跳过 0.25s 渐暗暴露开放世界
	await get_tree().create_timer(1.2).timeout   # 系统稳定窗口（任务冻结后无主线弹窗，4s→1.2s）
	if in_city or changan != null or _busy:
		return
	print("[CityVisit] 出生点=长安明德门内（开局直达）")
	enter_city("S", true)   # force=true：直入（弹窗为CanvasLayer不依赖世界）

# ---- 开放世界侧：外郭轮廓 + 四门触发区 ----
func _setup_footprint():
	if world_gen == null:
		return
	footprint_origin = _find_footprint_origin()
	_paint_footprint()
	_force_load_footprint_chunks()
	_build_entry_triggers()
	print("[CityVisit] 长安外郭轮廓落地 origin=%s size=%dx%d 四城门=明德S/玄武N/春明E/开远W" %
			[footprint_origin, FP_W, FP_H])
	if not _hint_shown and not (auto_spawn_in_city and not _probe_present()):
		_hint_shown = true
		GameManager.emit_event("长安城郭", "东行远望，长安城郭巍然——走近城门即可入京。", 6)

func _find_footprint_origin() -> Vector2i:
	var half := Vector2i(FP_W / 2, FP_H / 2)
	var radius_cap: int = world_gen.WORLD_RADIUS - 30
	# 偏东优先（设计稿：灞桥/入京在城东），步长2粗扫控制开销，逐格严格校验
	# 2026-09-07：青石城已退役删除，避城排除随之移除
	for cx in range(168, 40, -2):
		for cy in range(-136, 137, 2):
			var center := Vector2i(cx, cy)
			if center.length() > radius_cap:
				continue
			var o := center - half
			if _rect_clear(o, FP_W + FP_SCAN_PAD * 2, FP_H + FP_SCAN_PAD * 2):
				return o
	# 兜底2：全图扫描（任意方位净空点——东带无净空时世界其他区域通常仍有；
	# 2026-09-07 实测删城后东带满镇/崖，回退固定点(120,40)会压在镇上截断door可达）
	for cx in range(-168, 169, 2):
		for cy in range(-136, 137, 2):
			var center := Vector2i(cx, cy)
			if center.length() > radius_cap:
				continue
			var o := center - half
			if _rect_clear(o, FP_W + FP_SCAN_PAD * 2, FP_H + FP_SCAN_PAD * 2):
				print("[CityVisit] 兜底全图扫描命中 origin=%s" % str(o))
				return o
	# 兜底3：固定东城点（最后手段；日志可诊断）
	print("[CityVisit] WARN: 全图扫描仍无净空点，回退固定位置(120,40)")
	return Vector2i(120 - half.x, 40 - half.y)

func _rect_clear(o: Vector2i, w: int, h: int) -> bool:
	for dy in range(h):
		for dx in range(w):
			var c := o + Vector2i(dx, dy)
			if Vector2(c.x, c.y).length() > world_gen.WORLD_RADIUS - 10:
				return false
			if world_gen.override_cells.has(c):
				return false
			if world_gen.collision_tiles.has(world_gen.get_tile_id(c.x, c.y)):
				return false
	return true

func _paint_footprint():
	var ox := footprint_origin.x
	var oy := footprint_origin.y
	for dy in range(FP_H):
		for dx in range(FP_W):
			if dx != 0 and dx != FP_W - 1 and dy != 0 and dy != FP_H - 1:
				continue   # 只画轮廓环
			world_gen.override_cells[Vector2i(ox + dx, oy + dy)] = TILE_CITY_WALL
	# 四门豁口（3格铺路）+ 门外2格落点登记
	var gx := ox + FP_W / 2
	var gy := oy + FP_H / 2
	_carve_footprint_gate("S", Vector2i(gx, oy + FP_H - 1), Vector2i(0, 1))
	_carve_footprint_gate("N", Vector2i(gx, oy), Vector2i(0, -1))
	_carve_footprint_gate("E", Vector2i(ox + FP_W - 1, gy), Vector2i(1, 0))
	_carve_footprint_gate("W", Vector2i(ox, gy), Vector2i(-1, 0))

func _carve_footprint_gate(side: String, gap: Vector2i, outward: Vector2i):
	var vertical := (outward.y != 0)
	for i in range(-1, 2):
		var c := gap + (Vector2i(i, 0) if vertical else Vector2i(0, i))
		world_gen.override_cells[c] = TILE_PATH
	gate_cells[side] = {"gap": gap, "outside": gap + outward * 2}

func _force_load_footprint_chunks():
	var c0: Vector2i = world_gen.world_to_chunk(Vector2(footprint_origin.x * 16, footprint_origin.y * 16))
	var c1: Vector2i = world_gen.world_to_chunk(Vector2((footprint_origin.x + FP_W) * 16, (footprint_origin.y + FP_H) * 16))
	for cy in range(c0.y - 1, c1.y + 2):
		for cx in range(c0.x - 1, c1.x + 2):
			var c := Vector2i(cx, cy)
			if not world_gen.loaded_chunks.has(c):
				world_gen._load_chunk(c)

func _build_entry_triggers():
	for side in gate_cells:
		var gap: Vector2i = gate_cells[side]["gap"]
		var area := Area2D.new()
		area.name = "EntryGate_%s" % side
		area.position = Vector2(gap.x * 16 + 8, gap.y * 16 + 8)
		area.collision_layer = 0
		area.collision_mask = 2   # 玩家层
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(48, 16) if side == "S" or side == "N" else Vector2(16, 48)
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(_on_entry_gate_body_entered.bind(side))
		add_child(area)

func _on_entry_gate_body_entered(body: Node2D, side: String):
	if body.is_in_group("player"):
		enter_city(side)

# ---- 进出城流程 ----
func enter_city(gate_id: String, force: bool = false) -> void:
	if _busy or in_city or changan != null:
		return
	if not force and DialogManager.is_dialog_open():
		return   # 对话中不入城（M1 从简；开局自动入城走 force）
	_busy = true
	await _fade(1.0)
	_set_world_frozen(true)
	var scene_packed = ChangAnV2Scene if CITY_VERSION == 2 else ChangAnScene
	changan = scene_packed.instantiate()
	changan.exit_requested.connect(_on_city_exit_requested)
	changan.interior_requested.connect(enter_interior)
	world.add_child(changan)
	changan.position = CITY_OFFSET
	# v2 生成器同步完成（_ready 内即 emit）——信号可能已发过，done 守卫防 await 永挂
	if not changan.done:
		await changan.generation_done
	var g: Dictionary = changan.gate_info[gate_id]
	var spawn_cell: Vector2i = changan.find_clear_spawn(g["inside"])
	player.global_position = CITY_OFFSET + changan.cell_to_px(spawn_cell)
	player.velocity = Vector2.ZERO
	if player.has_node("Camera2D"):
		player.get_node("Camera2D").reset_smoothing()   # 42000px传送后相机直接吸附，防镜头长距离漂移
	_set_camera_limits(true)
	if _minimap:
		_minimap.visible = false   # 小地图渲染开放世界数据，城内隐藏（M3 做城内图）
	await _fade(0.0)
	in_city = true
	_busy = false
	print("[CityVisit] 入城 %s（%s）落点=%s 城内生成统计=%s" %
			[gate_id, g["name"], spawn_cell, changan.stats])

func _on_city_exit_requested(gate_id: String) -> void:
	exit_city(gate_id)

func exit_city(gate_id: String) -> void:
	if _busy or not in_city or changan == null:
		return
	_busy = true
	await _fade(1.0)
	var exit_cell: Vector2i = gate_cells[gate_id]["outside"]
	changan.queue_free()
	changan = null
	interior = null
	_set_camera_limits(false)
	if _minimap:
		_minimap.visible = true
	_set_world_frozen(false)
	player.global_position = Vector2(exit_cell.x * 16 + 8, exit_cell.y * 16 + 8)
	player.velocity = Vector2.ZERO
	if player.has_node("Camera2D"):
		player.get_node("Camera2D").reset_smoothing()
	await _fade(0.0)
	in_city = false
	_busy = false
	print("[CityVisit] 出城 %s → 开放世界门外 %s" % [gate_id, exit_cell])

func _set_world_frozen(frozen: bool):
	for n in FREEZE_NODES:
		var node = world.get_node_or_null(n)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT

func _set_camera_limits(city: bool):
	var cam = player.get_node_or_null("Camera2D")
	if cam == null:
		return
	if city:
		cam.limit_left = 0
		cam.limit_top = int(CITY_OFFSET.y)
		cam.limit_right = int(changan.W * 16)
		cam.limit_bottom = int(CITY_OFFSET.y + changan.H * 16)
		# 第三轮修缮：城内 zoom 3→2（世界像素=2屏像素，整数比不糊）——单体建筑占屏减半，
		# 一眼一坊组群+街面密度，对齐概念图中远视距；开放世界维持 zoom 3
		cam.zoom = Vector2(2.0, 2.0)
	else:
		cam.limit_left = -10000000
		cam.limit_top = -10000000
		cam.limit_right = 10000000
		cam.limit_bottom = 10000000
		cam.zoom = Vector2(3.0, 3.0)

# ---- M4 内景：门面触发区 → 独立子地图（INTERIOR_OFFSET 空间）；出口垫/ESC 返回门面原位 ----
func enter_interior(ref: String) -> void:
	if _busy or interior != null or changan == null:
		return
	if Time.get_ticks_msec() < _portal_unlock_ms:
		# 刚出内景落在门前景格，忽略重触发；玩家离开该格即解锁（不误伤其它传送门/瞬移）
		var pcell_now := Vector2i(int((player.global_position.x - CITY_OFFSET.x) / 16), int((player.global_position.y - CITY_OFFSET.y) / 16))
		if pcell_now == interior_return_cell:
			return
		_portal_unlock_ms = 0
	if DialogManager.is_dialog_open():
		return
	_busy = true
	await _fade(1.0)
	interior_return_cell = Vector2i(int((player.global_position.x - CITY_OFFSET.x) / 16), int((player.global_position.y - CITY_OFFSET.y) / 16))
	var node := Node2D.new()
	node.set_script(INTERIOR_SCRIPT)
	var meta: Dictionary = changan.get_interior_meta(ref)   # M5：门面元数据决定内景模板族
	if not node.build(ref, meta):
		node.free()
		_busy = false
		return
	world.add_child(node)
	node.position = INTERIOR_OFFSET
	interior = node
	player.global_position = INTERIOR_OFFSET + node.cell_to_px(node.spawn_cell)
	player.velocity = Vector2.ZERO
	if player.has_node("Camera2D"):
		player.get_node("Camera2D").reset_smoothing()
	_set_interior_camera_limits(true)
	await _fade(0.0)
	_busy = false
	node.exit_entered.connect(_on_interior_exit)   # 淡入完成后才受理出口（busy 窗口防丢）
	print("[CityVisit] 进内景 %s（%s）spawn=%s" % [ref, node.display_name, node.spawn_cell])

func _on_interior_exit():
	exit_interior()

func exit_interior() -> void:
	if _busy or interior == null:
		return
	_busy = true
	await _fade(1.0)
	var iname: String = interior.display_name
	interior.queue_free()
	interior = null
	_set_interior_camera_limits(false)
	# 直接回进内景时的站位（该格玩家实际站过，必可站立；find_clear_spawn 数组检查不含内景家具瓦会误搬迁）
	var back: Vector2i = interior_return_cell
	player.global_position = CITY_OFFSET + changan.cell_to_px(back)
	player.velocity = Vector2.ZERO
	if player.has_node("Camera2D"):
		player.get_node("Camera2D").reset_smoothing()
	_portal_unlock_ms = Time.get_ticks_msec() + 800   # 落点即门面触发区，短暂防重进
	await _fade(0.0)
	_busy = false
	print("[CityVisit] 出内景 %s → 城内门面前 %s" % [iname, back])

func _unhandled_input(event: InputEvent):
	if interior != null and not _busy and event.is_action_pressed("ui_cancel"):
		exit_interior()

func _set_interior_camera_limits(in_interior: bool):
	var cam = player.get_node_or_null("Camera2D")
	if cam == null:
		return
	if in_interior:
		cam.limit_left = int(INTERIOR_OFFSET.x)
		cam.limit_top = int(INTERIOR_OFFSET.y) - 96   # 内景换皮：北墙高家具/挂画 sprite 上探出图，上沿留 96px 头部空间
		cam.limit_right = int(INTERIOR_OFFSET.x + interior.W * 16)
		cam.limit_bottom = int(INTERIOR_OFFSET.y + interior.H * 16)
	else:
		_set_camera_limits(true)   # 回城内限位

# ---- 淡入淡出（陷阱#23：整色插值替代 modulate.a 子路径）----
func _setup_fade_layer():
	var layer := CanvasLayer.new()
	layer.layer = 95
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)

func _fade(target_a: float):
	var tw = create_tween()
	tw.tween_property(_fade_rect, "color", Color(0, 0, 0, target_a), 0.25)
	await tw.finished
