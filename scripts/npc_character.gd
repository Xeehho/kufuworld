extends CharacterBody2D

const TextureGen = preload("res://scripts/texture_generator.gd")

const SPEED = 30.0

enum ScheduleState {IDLE, WALK, WORK, SLEEP}
enum Direction {DOWN, LEFT, RIGHT, UP}

var npc_data: NPCData = null
var schedule_state: ScheduleState = ScheduleState.IDLE
var waypoints: Array = []
var waypoint_index: int = 0
var idle_timer: float = 0.0
var idle_switch_interval: float = 3.0
var is_interacting: bool = false
var is_homestead: bool = false
var homestead_waypoints: Array = []
var facing: Direction = Direction.DOWN
var npc_type: String = "warrior"

# ---- 日程寻路系统：时辰日程 + 瓦片路径跟随 + 卡死重寻路 ----
var schedule: Array = []              # 日程腿 {start,end,state,pos}（21-6睡觉为兜底不单列）
var _cur_leg_key: String = ""         # 当前腿标识（变化才重寻路，避免每帧重算）
var path_queue: Array = []            # 像素路点队列（长途，来自find_npc_path）
var path_target: Vector2 = Vector2.ZERO
var wander_center: Vector2 = Vector2.ZERO  # 到达目的地后的局部游荡中心
var stuck_timer: float = 0.0          # 卡死检测计时
var last_pos: Vector2 = Vector2.ZERO
var repath_cooldown: float = 0.0      # 重寻路冷却（防抖）
var _world_gen_ref: Node2D = null

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
# 名牌改屏幕空间：世界空间5px字体经zoom3放大屏显15px发糊（小字光栅+放大），
# 改挂 UI CanvasLayer 按最终分辨率直接光栅（14px），清晰且不被树冠遮挡
var name_tag: Label = null

# Phase F4: 名牌默认隐藏（悬停/点击临时显示），F2: 字号5px*相机zoom3≈15px屏显，与32px模型比例协调
var _tag_tween: Tween = null
var _hovering: bool = false

func _ready():
	add_to_group("npc")
	add_to_group("interactable")
	input_pickable = true
	# 碰撞分层表（地形/建筑=层1）：玩家=2，NPC=4，敌人=8
	# NPC mask只含层1：玩家/敌人不在分离集合→NPC位置绝不被玩家推挤；
	# 玩家mask含NPC层→玩家被NPC挡住（空气墙，不可穿透）
	collision_layer = 4
	collision_mask = 1
	if npc_data == null:
		_setup_default_npc()
	_setup_sprite_frames()
	_create_screen_name_tag()
	last_pos = global_position
	wander_center = npc_data.home_position
	_generate_waypoints_around(npc_data.home_position)
	_build_schedule()
	_update_schedule()

func _create_screen_name_tag():
	"""屏幕空间名牌：挂World/UI层，字体按屏幕分辨率直接光栅（清晰）；同层置底让面板可盖住"""
	var ui = get_node_or_null("/root/Main/World/UI")
	if ui == null:
		return
	name_tag = Label.new()
	name_tag.text = npc_data.npc_name
	name_tag.add_theme_font_size_override("font_size", 14)
	name_tag.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	name_tag.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	name_tag.add_theme_constant_override("outline_size", 4)
	name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_tag.z_index = -1
	name_tag.visible = false
	ui.add_child(name_tag)
	ui.move_child(name_tag, 0)

func _sync_name_tag():
	"""每帧把名牌同步到NPC头顶的屏幕坐标；NPC出视口时强制隐藏"""
	if name_tag == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var screen_pos: Vector2 = vp.get_canvas_transform() * global_position
	var view_size := vp.get_visible_rect().size
	var in_view := screen_pos.x > -80.0 and screen_pos.x < view_size.x + 80.0 \
		and screen_pos.y > -100.0 and screen_pos.y < view_size.y + 60.0
	if not in_view:
		name_tag.visible = false
		return
	var min_size := name_tag.get_minimum_size()
	name_tag.size = min_size
	name_tag.position = screen_pos + Vector2(-min_size.x * 0.5, -100.0)

func _exit_tree():
	if name_tag != null and is_instance_valid(name_tag):
		name_tag.queue_free()
		name_tag = null

func _setup_default_npc():
	var personalities = ["豪爽", "阴沉", "儒雅", "暴躁", "狡诈", "慈悲", "孤傲", "市侩"]
	npc_data = NPCData.new()
	npc_data.npc_id = name
	npc_data.npc_name = name
	npc_data.personality = personalities[hash(name) % personalities.size()]
	npc_data.home_position = global_position
	npc_data.work_position = global_position + Vector2(randi_range(-100, 100), randi_range(-60, 60))
	match npc_data.personality:
		"豪爽", "暴躁":
			npc_type = "warrior"
		"儒雅", "慈悲":
			npc_type = "scholar"
		"市侩", "狡诈":
			npc_type = "merchant"
		"孤傲":
			npc_type = "mysterious"
		"阴沉":
			npc_type = "elder"

func _setup_sprite_frames():
	if anim == null:
		return
	var sf = SpriteFrames.new()
	var dir_names = ["down", "left", "right", "up"]
	var has_any_frame = false
	for dir_name in dir_names:
		var idle_name = "idle_" + dir_name
		sf.add_animation(idle_name)
		sf.set_animation_speed(idle_name, 4.0)
		sf.set_animation_loop(idle_name, true)
		for i in range(4):
			var tex = TextureGen.load_png_texture("res://sprites/npc/%s_idle_%s_%d.png" % [npc_type, dir_name, i])
			# 资源包NPC只有单方向动画，缺失方向回退到 down 帧
			if tex == null and dir_name != "down":
				tex = TextureGen.load_png_texture("res://sprites/npc/%s_idle_down_%d.png" % [npc_type, i])
			if tex:
				sf.add_frame(idle_name, tex)
				has_any_frame = true

		var walk_name = "walk_" + dir_name
		sf.add_animation(walk_name)
		sf.set_animation_speed(walk_name, 8.0)
		sf.set_animation_loop(walk_name, true)
		for i in range(6):
			var tex = TextureGen.load_png_texture("res://sprites/npc/%s_walk_%s_%d.png" % [npc_type, dir_name, i])
			if tex == null and dir_name != "down":
				tex = TextureGen.load_png_texture("res://sprites/npc/%s_walk_down_%d.png" % [npc_type, i])
			if tex:
				sf.add_frame(walk_name, tex)
				has_any_frame = true

	anim.sprite_frames = sf
	# 素材包NPC 32x32帧人物脚线在y≈31，帧中心16 → 上移15使脚底=节点原点
	anim.offset = Vector2(0, -15)
	# 如果没有任何帧，创建一个占位可见色块
	if not has_any_frame:
		_create_fallback_visual()
	else:
		anim.play("idle_down")

func _create_fallback_visual():
	# 如果纹理未生成，用彩色矩形作为占位
	var fallback = ColorRect.new()
	fallback.name = "FallbackVisual"
	fallback.size = Vector2(24, 32)
	fallback.position = Vector2(-12, -32)
	var colors = {
		"warrior": Color(0.5, 0.18, 0.12),
		"scholar": Color(0.75, 0.72, 0.60),
		"merchant": Color(0.55, 0.40, 0.20),
		"elder": Color(0.40, 0.42, 0.50),
		"mysterious": Color(0.18, 0.15, 0.25),
	}
	fallback.color = colors.get(npc_type, Color(0.5, 0.5, 0.3))
	add_child(fallback)

func _update_facing(dir: Vector2):
	if abs(dir.x) > abs(dir.y):
		if dir.x < 0:
			facing = Direction.LEFT
		else:
			facing = Direction.RIGHT
	else:
		if dir.y < 0:
			facing = Direction.UP
		else:
			facing = Direction.DOWN

func _dir_suffix() -> String:
	match facing:
		Direction.DOWN: return "down"
		Direction.LEFT: return "left"
		Direction.RIGHT: return "right"
		Direction.UP: return "up"
		_: return "down"

func _play_anim(prefix: String):
	var anim_name = prefix + "_" + _dir_suffix()
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation(anim_name):
		anim.play(anim_name)

func _generate_waypoints_around(center: Vector2):
	"""局部游荡路点：围绕center随机取5个点（就近步行，不寻路）"""
	waypoints.clear()
	for i in range(5):
		waypoints.append(center + Vector2(randi_range(-120, 120), randi_range(-80, 80)))

# ============ 时辰日程系统 ============
# 默认作息：6-12工作 → 12-14进城赶集 → 14-18工作 → 18-21进城夜市 → 21-6回家睡觉
# 附近无城镇（>4000px）的NPC以家为游荡中心；受邀安家(is_homestead)的NPC只在宅地活动

func _build_schedule():
	var home: Vector2 = npc_data.home_position
	var work: Vector2 = npc_data.work_position
	var town := _nearest_town_center(home)
	if town != Vector2.INF:
		schedule = [
			{"start": 6, "end": 12, "state": "work", "pos": work},
			{"start": 12, "end": 14, "state": "leisure", "pos": town},
			{"start": 14, "end": 18, "state": "work", "pos": work},
			{"start": 18, "end": 21, "state": "leisure", "pos": town},
		]
	else:
		schedule = [
			{"start": 6, "end": 12, "state": "wander", "pos": work},
			{"start": 12, "end": 14, "state": "wander", "pos": home},
			{"start": 14, "end": 18, "state": "wander", "pos": work},
			{"start": 18, "end": 21, "state": "wander", "pos": home},
		]

func _leg_at(hour: int) -> Variant:
	for leg in schedule:
		if hour >= int(leg["start"]) and hour < int(leg["end"]):
			return leg
	return null

func _nearest_town_center(px: Vector2) -> Vector2:
	"""最近城镇中心像素坐标（ town_positions 存瓦片坐标），超过4000px视为没有"""
	var wg = _world_gen()
	if wg == null:
		return Vector2.INF
	# 用Object.get取脚本变量（"x in typed_node"静态判定不可靠）
	var towns = wg.get("town_centers")
	if towns == null or not (towns is Array) or towns.is_empty():
		return Vector2.INF
	var best := Vector2.INF
	var best_d := 4000.0
	for t in towns:
		var c := Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 8.0)
		var d := px.distance_to(c)
		if d < best_d:
			best_d = d
			best = c
	return best

func _update_schedule():
	var hour = _current_game_hour()
	if is_homestead:
		# 受邀安家：白天在宅地周边活动，夜里原地休息（不回原籍）
		var night := hour >= 21 or hour < 6
		_transition_leg(ScheduleState.IDLE if night else ScheduleState.WALK,
			_homestead_center(), "homestead")
		return
	var idx := -1
	var leg = _leg_at(hour)
	if leg != null:
		idx = schedule.find(leg)
	if leg == null:
		_transition_leg(ScheduleState.SLEEP, npc_data.home_position, "sleep")
		return
	match str(leg["state"]):
		"work":
			_transition_leg(ScheduleState.WORK, leg["pos"], "work_%d" % idx)
		"leisure":
			_transition_leg(ScheduleState.WALK, leg["pos"], "leisure_%d" % idx)
		_:
			_transition_leg(ScheduleState.WALK, leg["pos"], "wander_%d" % idx)

func _transition_leg(state: int, target: Vector2, key: String):
	"""切换日程腿：schedule_state始终更新；腿标识变化才重新寻路"""
	schedule_state = state
	if key == _cur_leg_key:
		return
	_cur_leg_key = key
	_retarget(target)

func _retarget(target: Vector2):
	wander_center = target
	waypoints.clear()
	waypoint_index = 0
	if not _request_path(target):
		# 目标不可达：就地局部游荡兜底
		wander_center = global_position
		_generate_waypoints_around(global_position)
		path_queue = []

func _request_path(target: Vector2) -> bool:
	"""长途寻路；成功填充path_queue。不可达返回false"""
	path_target = target
	var wg = _world_gen()
	if wg == null or not wg.has_method("find_npc_path"):
		path_queue = [target]  # 无寻路器时退化为直走（旧行为）
		return true
	path_queue = wg.find_npc_path(global_position, target)
	return not path_queue.is_empty()

func _world_gen() -> Node2D:
	if _world_gen_ref == null or not is_instance_valid(_world_gen_ref):
		_world_gen_ref = get_node_or_null("../../WorldGenerator")
	return _world_gen_ref

func _homestead_center() -> Vector2:
	return homestead_waypoints[0] if homestead_waypoints.size() > 0 else global_position

# ============ 移动执行 ============

func _follow_path(delta: float, speed_mul: float):
	"""沿path_queue步行；到达目的地后velocity清零"""
	while not path_queue.is_empty() and global_position.distance_to(path_queue[0]) < 8.0:
		path_queue.pop_front()
	if path_queue.is_empty():
		velocity = Vector2.ZERO
		_play_anim("idle")
		return
	var target: Vector2 = path_queue[0]
	var dir = global_position.direction_to(target)
	_update_facing(dir)
	velocity = dir * SPEED * speed_mul
	_play_anim("walk")
	_check_stuck(delta)

func _check_stuck(delta: float):
	"""0.6s窗口位移<3px视为卡死：长途重寻路/局部游荡换点，冷却1.5s防抖"""
	repath_cooldown = maxf(repath_cooldown - delta, 0.0)
	stuck_timer += delta
	if stuck_timer < 0.6:
		return
	stuck_timer = 0.0
	var moved := global_position.distance_to(last_pos)
	last_pos = global_position
	if moved >= 3.0 or repath_cooldown > 0.0:
		return
	repath_cooldown = 1.5
	if not path_queue.is_empty():
		_request_path(path_target)   # 长途卡住→重寻路
	elif waypoints.size() > 0 and waypoint_index < waypoints.size():
		# 局部游荡卡住→该路点改走寻路，仍不可达就换随机点
		var wp: Vector2 = waypoints[waypoint_index]
		if not _request_path(wp):
			waypoints[waypoint_index] = wander_center + Vector2(randi_range(-100, 100), randi_range(-70, 70))

func _current_game_hour() -> int:
	return int(GameManager.world_hour)

func _physics_process(delta):
	if is_interacting:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_update_schedule()

	match schedule_state:
		ScheduleState.IDLE:
			_process_idle(delta)
		ScheduleState.WALK:
			_process_walk(delta)
		ScheduleState.WORK:
			_process_work(delta)
		ScheduleState.SLEEP:
			_process_sleep(delta)

	if GameManager.is_raining or GameManager.is_snowing:
		velocity *= 0.6

	move_and_slide()
	_update_hover_effect()
	_sync_name_tag()

func _state_name() -> String:
	match schedule_state:
		ScheduleState.IDLE: return "待机"
		ScheduleState.WALK: return "行走"
		ScheduleState.WORK: return "工作"
		_: return "休息"

func _process_idle(delta):
	idle_timer += delta
	if idle_timer > idle_switch_interval:
		idle_timer = 0.0
		schedule_state = ScheduleState.WALK
	velocity = Vector2.ZERO
	_play_anim("idle")

func _process_walk(delta):
	if not path_queue.is_empty():
		_follow_path(delta, 1.0)
		return
	# 已到目的地：围绕wander_center局部游荡
	if waypoints.is_empty() or waypoint_index >= waypoints.size():
		_generate_waypoints_around(wander_center)
		waypoint_index = 0
	var target = waypoints[waypoint_index]
	if global_position.distance_to(target) < 8.0:
		waypoint_index += 1
		idle_timer = 0.0
		if randi() % 3 == 0:
			schedule_state = ScheduleState.IDLE
		return
	var dir = global_position.direction_to(target)
	_update_facing(dir)
	velocity = dir * SPEED
	_play_anim("walk")
	_check_stuck(delta)

func _process_work(delta):
	if path_queue.is_empty():
		# 到岗干活：原地忙碌
		velocity = Vector2.ZERO
		_play_anim("idle")
		idle_timer += delta
		if idle_timer > 5.0:
			idle_timer = 0.0
	else:
		_follow_path(delta, 0.7)

func _process_sleep(_delta):
	if path_queue.is_empty():
		velocity = Vector2.ZERO
		_play_anim("idle")
	else:
		_follow_path(_delta, 0.5)

func set_interacting(value: bool):
	is_interacting = value
	if value:
		velocity = Vector2.ZERO

# ---- Phase F2/F4: 悬停高亮 + 名牌临时显示 ----
func _update_hover_effect():
	var vp := get_viewport()
	var ui_block: bool = vp != null and vp.gui_get_hovered_control() != null
	var mouse_pos := get_global_mouse_position()
	var near := mouse_pos.distance_to(global_position + Vector2(0, -14)) < 14.0
	_hovering = near and not ui_block and not is_interacting
	if _hovering:
		modulate = Color(1.22, 1.18, 1.05, 1.0)
		if not name_tag.visible:
			_show_name_tag(0.0)	# 悬停期间常驻，移开时隐藏
		name_tag.visible = true
	else:
		modulate = Color.WHITE
		if not is_interacting and name_tag.visible and _tag_tween == null:
			name_tag.visible = false

func show_name_tag_flash(duration: float = 2.2):
	"""远距离点击NPC时闪现名牌"""
	_show_name_tag(duration)

func _show_name_tag(duration: float):
	if _tag_tween != null:
		_tag_tween.kill()
		_tag_tween = null
	name_tag.modulate.a = 1.0
	name_tag.visible = true
	if duration > 0.0:
		_tag_tween = create_tween()
		_tag_tween.tween_interval(duration)
		_tag_tween.tween_property(name_tag, "modulate:a", 0.0, 0.5)
		_tag_tween.tween_callback(_on_tag_hidden)

func _on_tag_hidden():
	name_tag.visible = false
	_tag_tween = null

func _input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		show_name_tag_flash()
		var npc_info = get_node_or_null("/root/Main/World/UI/NPCInfoHUD")
		if npc_info and npc_info.has_method("show_npc_info"):
			npc_info.show_npc_info(self)

func set_homestead(value: bool):
	is_homestead = value
	if value:
		var player_pos = _get_player_position()
		for _i in range(4):
			homestead_waypoints.append(player_pos + Vector2(randi_range(-80, 80), randi_range(-60, 60)))
		# 触发日程重算：此后不再回原籍（_update_schedule的homestead分支接管）
		_cur_leg_key = ""
		path_queue = []

func _get_player_position() -> Vector2:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0].global_position
	return global_position
