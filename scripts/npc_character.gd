extends CharacterBody2D

const SPEED = 60.0

enum ScheduleState {IDLE, WALK, WORK, SLEEP}

var npc_data: NPCData = null
var schedule_state: ScheduleState = ScheduleState.IDLE
var waypoints: Array = []
var waypoint_index: int = 0
var idle_timer: float = 0.0
var idle_switch_interval: float = 3.0
var is_interacting: bool = false
var is_homestead: bool = false
var homestead_waypoints: Array = []

@onready var sprite: ColorRect = $ColorRect
@onready var name_label: Label = $NameLabel
@onready var state_label: Label = $StateLabel

func _ready():
	add_to_group("npc")
	add_to_group("interactable")
	if npc_data == null:
		_setup_default_npc()
	name_label.text = npc_data.npc_name
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

func _generate_waypoints():
	var base = global_position
	for i in range(5):
		waypoints.append(base + Vector2(randi_range(-120, 120), randi_range(-80, 80)))

func _update_schedule():
	var hour = _current_game_hour()
	if hour >= npc_data.sleep_start_hour or hour < 6:
		schedule_state = ScheduleState.SLEEP
		sprite.color = Color(0.3, 0.3, 0.5)
	elif hour >= npc_data.work_start_hour and hour < npc_data.sleep_start_hour:
		schedule_state = ScheduleState.WORK
		sprite.color = Color(0.5, 0.5, 0.3)
	else:
		schedule_state = ScheduleState.WALK
		sprite.color = Color(0.3, 0.6, 0.4)

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

func _process_walk(_delta):
	if waypoints.is_empty():
		schedule_state = ScheduleState.IDLE
		return
	var target = waypoints[waypoint_index]
	var dir = global_position.direction_to(target)
	velocity = dir * SPEED
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
		idle_timer += _delta
		if idle_timer > 5.0:
			idle_timer = 0.0
	else:
		velocity = dir * SPEED * 0.7

func _process_sleep(_delta):
	var target = npc_data.home_position
	var dir = global_position.direction_to(target)
	if global_position.distance_to(target) < 16:
		velocity = Vector2.ZERO
	else:
		velocity = dir * SPEED * 0.5

func set_interacting(value: bool):
	is_interacting = value
	if value:
		velocity = Vector2.ZERO

func set_homestead(value: bool):
	is_homestead = value
	if value:
		sprite.color = Color(0.8, 0.6, 0.2)
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
