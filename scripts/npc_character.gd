extends CharacterBody2D

const SPEED = 60.0

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
@onready var name_label: Label = $NameLabel
@onready var state_label: Label = $StateLabel

func _ready():
	add_to_group("npc")
	add_to_group("interactable")
	input_pickable = true
	if npc_data == null:
		_setup_default_npc()
	name_label.text = npc_data.npc_name
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
			var tex_path = "res://sprites/npc/%s_idle_%s_%d.png" % [npc_type, dir_name, i]
			if ResourceLoader.exists(tex_path):
				sf.add_frame(idle_name, load(tex_path))
				has_any_frame = true

		var walk_name = "walk_" + dir_name
		sf.add_animation(walk_name)
		sf.set_animation_speed(walk_name, 8.0)
		sf.set_animation_loop(walk_name, true)
		for i in range(6):
			var tex_path = "res://sprites/npc/%s_walk_%s_%d.png" % [npc_type, dir_name, i]
			if ResourceLoader.exists(tex_path):
				sf.add_frame(walk_name, load(tex_path))
				has_any_frame = true

	anim.sprite_frames = sf
	# 如果没有任何帧，创建一个占位可见色块
	if not has_any_frame:
		_create_fallback_visual()
	else:
		anim.play("idle_down")

func _create_fallback_visual():
	# 如果纹理未生成，用彩色矩形作为占位
	var fallback = ColorRect.new()
	fallback.name = "FallbackVisual"
	fallback.size = Vector2(24, 36)
	fallback.position = Vector2(-12, -36)
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
	state_label.text = _state_name()

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

func _input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
		state_label.text = "劳作"

func _get_player_position() -> Vector2:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0].global_position
	return global_position
