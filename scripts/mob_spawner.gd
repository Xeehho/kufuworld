extends Node2D

# Phase C 敌人营地生成器：以玩家出生点为锚点放两座营地
# 山贼营地(Orc) + 白骨祭坛(Skeleton)，全灭后延时重生（玩家远离时）
# 挂载于 /root/Main/World/MobSpawner

const MobScript = preload("res://scripts/mob.gd")

const RESPAWN_DELAY := 90.0
const SAFE_DIST_TO_RESPAWN := 260.0
const MAX_ALIVE := 12

# 营地定义：相对出生点的瓦片偏移 + 成员构成
const CAMPS := [
	{"name": "山贼营地", "offset": Vector2i(-30, -22),
	 "members": ["orc_warrior", "orc_rogue", "orc_warrior"]},
	{"name": "白骨祭坛", "offset": Vector2i(28, 32),
	 "members": ["skeleton_warrior", "skeleton_mage", "skeleton_rogue"]},
]

var camps_runtime: Array = []   # {def, center:Vector2, alive:int, respawn_timer:float}
var _world_gen: Node2D = null

func _ready():
	add_to_group("mob_spawner")

func _process(_delta):
	if _world_gen == null:
		_world_gen = get_node_or_null("/root/Main/World/WorldGenerator")
		if _world_gen:
			_setup_camps()
		return
	_tick_respawns(_delta)

func _setup_camps():
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var spawn_tile := Vector2i(int(player.global_position.x / 16), int(player.global_position.y / 16))
	for def in CAMPS:
		var want := spawn_tile + (def["offset"] as Vector2i)
		var center_px := Vector2(want.x * 16.0 + 8.0, want.y * 16.0 + 8.0)
		center_px = _world_gen.find_nearest_reachable(center_px, 40)
		camps_runtime.append({"def": def, "center": center_px, "alive": 0, "respawn_timer": 0.0})
		print("[MobSpawner] 营地[%s]锚点=%s 解析到=%s" % [def["name"], str(want), str(center_px)])
		_spawn_camp(camps_runtime[-1])
	print("[MobSpawner] %d 座营地就绪 共%d只" % [camps_runtime.size(), _count_alive()])

func _spawn_camp(camp: Dictionary):
	var members: Array = camp["def"]["members"]
	for i in range(members.size()):
		var ring: Vector2 = [Vector2(0, 0), Vector2(-20, 10), Vector2(20, -12)][i % 3]
		var pos: Vector2 = camp["center"] + ring
		pos = _world_gen.find_nearest_reachable(pos, 20)
		_spawn_mob(members[i], pos, camp)

func _spawn_mob(kind_id: String, pos: Vector2, camp: Dictionary):
	if _count_alive() >= MAX_ALIVE:
		return
	var mob := CharacterBody2D.new()
	mob.set_script(MobScript)
	mob.name = "Mob_" + kind_id + "_" + str(randi() % 10000)
	mob.position = pos
	mob.z_index = 5
	mob.setup(kind_id)
	get_parent().add_child(mob)
	mob.mob_died.connect(_on_mob_died.bind(camp))
	camp["alive"] = int(camp["alive"]) + 1
	print("[MobSpawner] 生成 %s @ %s (%s)" % [kind_id, pos, mob.name])

func _on_mob_died(_kind_id: String, camp: Dictionary):
	camp["alive"] = int(camp["alive"]) - 1
	if int(camp["alive"]) <= 0 and float(camp["respawn_timer"]) <= 0.0:
		camp["respawn_timer"] = RESPAWN_DELAY
		print("[MobSpawner] %s 已清空，%ds后重生" % [camp["def"]["name"], RESPAWN_DELAY])

func _tick_respawns(delta):
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for camp in camps_runtime:
		if float(camp["respawn_timer"]) <= 0.0 or int(camp["alive"]) > 0:
			continue
		camp["respawn_timer"] = float(camp["respawn_timer"]) - delta
		if float(camp["respawn_timer"]) <= 0.0:
			var far := true
			if player:
				far = player.global_position.distance_to(camp["center"]) > SAFE_DIST_TO_RESPAWN
			if far:
				_spawn_camp(camp)
				camp["respawn_timer"] = 0.0
			else:
				camp["respawn_timer"] = 5.0   # 玩家还在附近，稍后再试

func _count_alive() -> int:
	return get_tree().get_nodes_in_group("mobs").size()
