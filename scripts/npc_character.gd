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

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_tag: Label = $NameTag

# Phase F4: 名牌默认隐藏（悬停/点击临时显示），F2: 字号5px*相机zoom3≈15px屏显，与32px模型比例协调
var _tag_tween: Tween = null
var _hovering: bool = false

func _ready():
	add_to_group("npc")
	add_to_group("interactable")
	input_pickable = true
	if npc_data == null:
		_setup_default_npc()
	name_tag.text = npc_data.npc_name
	name_tag.visible = false
	_setup_sprite_frames()
	_generate_waypoints()
	_update_schedule()

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

func _generate_waypoints():
	var base = global_position
	for i in range(5):
		waypoints.append(base + Vector2(randi_range(-120, 120), randi_range(-80, 80)))

func _update_schedule():
	var hour = _current_game_hour()
	if hour >= npc_data.sleep_start_hour or hour < 6:
		schedule_state = ScheduleState.SLEEP
	elif hour >= npc_data.work_start_hour and hour < npc_data.sleep_start_hour:
		schedule_state = ScheduleState.WORK
	else:
		schedule_state = ScheduleState.WALK

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

func _process_walk(_delta):
	if waypoints.is_empty():
		schedule_state = ScheduleState.IDLE
		return
	var target = waypoints[waypoint_index]
	var dir = global_position.direction_to(target)
	_update_facing(dir)
	velocity = dir * SPEED
	_play_anim("walk")
	if global_position.distance_to(target) < 8:
		waypoint_index = (waypoint_index + 1) % waypoints.size()
		idle_timer = 0.0
		if randi() % 3 == 0:
			schedule_state = ScheduleState.IDLE

func _process_work(_delta):
	var target = npc_data.work_position
	var dir = global_position.direction_to(target)
	if global_position.distance_to(target) < 16:
		velocity = Vector2.ZERO
		_play_anim("idle")
		idle_timer += _delta
		if idle_timer > 5.0:
			idle_timer = 0.0
	else:
		_update_facing(dir)
		velocity = dir * SPEED * 0.7
		_play_anim("walk")

func _process_sleep(_delta):
	var target = npc_data.home_position
	var dir = global_position.direction_to(target)
	if global_position.distance_to(target) < 16:
		velocity = Vector2.ZERO
		_play_anim("idle")
	else:
		_update_facing(dir)
		velocity = dir * SPEED * 0.5
		_play_anim("walk")

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
		schedule_state = ScheduleState.WORK
		var player_pos = _get_player_position()
		for _i in range(4):
			homestead_waypoints.append(player_pos + Vector2(randi_range(-80, 80), randi_range(-60, 60)))
		waypoints = homestead_waypoints

func _get_player_position() -> Vector2:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0].global_position
	return global_position
