extends CharacterBody2D

# Phase C 敌人系统：Orc=山贼 / Skeleton=白骨教众
# 帧源 sprites/mobs/{prefix}_{idle|run|death}_{i}.png（32x32，idle4帧/run6帧/death按文件数）
# 受击走combat_stance真实伤害闭环：玩家_deal_damage→take_damage；本AI→player.take_hit_with_stance

const TextureGen = preload("res://scripts/texture_generator.gd")
const ItemFactory = preload("res://scripts/item_factory.gd")

const KINDS := {
	"orc_warrior": {"name": "山贼刀客", "prefix": "orc___warrior", "hp": 45.0, "dmg": 8.0,
		"speed": 70.0, "aggro": 140.0, "leash": 260.0, "loot": "iron_ore", "gold": 0},
	"orc_rogue": {"name": "山贼斥候", "prefix": "orc___rogue", "hp": 28.0, "dmg": 5.0,
		"speed": 96.0, "aggro": 170.0, "leash": 300.0, "loot": "berry", "gold": 6},
	"skeleton_warrior": {"name": "白骨教众刀卒", "prefix": "skeleton___warrior", "hp": 35.0, "dmg": 7.0,
		"speed": 60.0, "aggro": 130.0, "leash": 240.0, "loot": "herb_material", "gold": 0},
	"skeleton_mage": {"name": "白骨教众法师", "prefix": "skeleton___mage", "hp": 26.0, "dmg": 9.0,
		"speed": 55.0, "aggro": 150.0, "leash": 240.0, "loot": "herb_material", "gold": 4},
	"skeleton_rogue": {"name": "白骨教众刺客", "prefix": "skeleton___rogue", "hp": 30.0, "dmg": 6.0,
		"speed": 92.0, "aggro": 160.0, "leash": 280.0, "loot": "herb_material", "gold": 3},
}

enum MobState {WANDER, CHASE, WINDUP, RECOVER, DYING}

signal mob_died(kind_id)

var kind_id: String = "orc_warrior"
var cfg: Dictionary = {}
var hp: float = 30.0
var state: int = MobState.WANDER
var home_pos: Vector2 = Vector2.ZERO
var wander_target: Vector2 = Vector2.ZERO
var wander_timer: float = 0.0
var windup_timer: float = 0.0
var recover_timer: float = 0.0
var attack_cooldown: float = 0.0
var aggro_lock_timer: float = 0.0    # 被打后强制追击时长
var knockback: Vector2 = Vector2.ZERO
var _player: CharacterBody2D = null
var _world_gen = null   # 2026-08-31：避城判定用（懒取，缺失时功能自动降级）

func _get_wg():
	if _world_gen == null or not is_instance_valid(_world_gen):
		_world_gen = get_node_or_null("/root/Main/World/WorldGenerator")
	return _world_gen

func _in_settlement(p: Vector2) -> bool:
	var wg = _get_wg()
	return wg != null and wg.has_method("is_in_settlement") and wg.is_in_settlement(p)

@onready var anim: AnimatedSprite2D = AnimatedSprite2D.new()

const WINDUP_TIME := 0.38
const ATTACK_RANGE := 26.0
const ATTACK_HIT_RANGE := 36.0
const RECOVER_TIME := 0.5
const ATTACK_CD := 1.15

func setup(id: String):
	kind_id = id
	cfg = KINDS[id]
	hp = cfg["hp"]

func _ready():
	add_to_group("mobs")
	add_to_group("hostile")
	# 碰撞分层表（地形/建筑=层1）：玩家=2，NPC=4，敌人=8
	# 敌人mask只含层1：不被玩家/NPC推挤（追击时穿身到玩家另一侧合围）；玩家侧则被敌人挡住
	collision_layer = 8
	collision_mask = 1
	if cfg.is_empty():
		setup(kind_id)
	home_pos = global_position
	wander_target = global_position
	_build_visual()
	_build_collision()

func _build_visual():
	anim.sprite_frames = _build_frames(String(cfg["prefix"]))
	anim.animation = "idle"
	anim.play("idle")
	anim.offset = Vector2(0, -15)   # 32x32帧脚线对齐节点原点（与NPC一致）
	add_child(anim)

func _build_frames(prefix: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	var specs := [["idle", 5.0, true], ["run", 9.0, true], ["death", 10.0, false]]
	for spec in specs:
		var aname: String = spec[0]
		sf.add_animation(aname)
		sf.set_animation_speed(aname, spec[1])
		sf.set_animation_loop(aname, spec[2])
		var i := 0
		while FileAccess.file_exists("res://sprites/mobs/%s_%s_%d.png" % [prefix, aname, i]):
			var tex := TextureGen.load_png_texture("res://sprites/mobs/%s_%s_%d.png" % [prefix, aname, i])
			if tex:
				sf.add_frame(aname, tex)
			i += 1
	return sf

func _build_collision():
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 8)
	cs.shape = shape
	cs.position = Vector2(0, -4)
	add_child(cs)

func _physics_process(delta):
	match state:
		MobState.DYING:
			velocity = Vector2.ZERO
			return
		MobState.WANDER:
			_tick_wander(delta)
		MobState.CHASE:
			_tick_chase(delta)
		MobState.WINDUP:
			velocity = knockback
			knockback = knockback.lerp(Vector2.ZERO, 0.2)
			move_and_slide()
			windup_timer -= delta
			if windup_timer <= 0:
				_do_attack()
		MobState.RECOVER:
			velocity = knockback
			knockback = knockback.lerp(Vector2.ZERO, 0.2)
			move_and_slide()
			recover_timer -= delta
			if recover_timer <= 0:
				state = MobState.CHASE
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	aggro_lock_timer = maxf(aggro_lock_timer - delta, 0.0)

func _get_player() -> CharacterBody2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	return _player

func _dist_to_player() -> float:
	var p := _get_player()
	return global_position.distance_to(p.global_position) if p else INF

func _tick_wander(delta):
	wander_timer -= delta
	if wander_timer <= 0:
		wander_timer = randf_range(2.0, 4.5)
		wander_target = home_pos + Vector2(randf_range(-48, 48), randf_range(-48, 48))
		# 2026-08-31：游走目标不得落进城/镇（野怪不进聚落）
		if _in_settlement(wander_target):
			wander_target = home_pos
	# 2026-08-31：异常身位纠偏（如被外力挪进城），立刻向家走
	if _in_settlement(global_position):
		wander_target = home_pos
	var to_target := wander_target - global_position
	if to_target.length() < 6.0:
		velocity = Vector2.ZERO
		_play("idle")
	else:
		velocity = to_target.normalized() * cfg["speed"] * 0.45
		_play("run")
	_update_facing()
	move_and_slide()
	# 仇恨判定：进入仇恨圈或被打锁定
	if _dist_to_player() < cfg["aggro"] or aggro_lock_timer > 0.0:
		state = MobState.CHASE

func _tick_chase(delta):
	var p := _get_player()
	if p == null or p.get("_is_dead") == true:
		state = MobState.WANDER
		return
	# 2026-08-31：玩家躲在城/镇内则脱战回家——野怪不进聚落（穿门追杀不合逻辑）
	if _in_settlement(p.global_position) or _in_settlement(global_position):
		state = MobState.WANDER
		wander_target = home_pos
		aggro_lock_timer = 0.0
		return
	var d := _dist_to_player()
	# 脱战：离家太远且玩家也远
	if d > cfg["leash"] and global_position.distance_to(home_pos) > cfg["leash"]:
		state = MobState.WANDER
		wander_target = home_pos
		return
	var in_cd := attack_cooldown > 0.0
	if d <= ATTACK_RANGE and not in_cd:
		state = MobState.WINDUP
		windup_timer = WINDUP_TIME
		velocity = Vector2.ZERO
		_play("idle")
		modulate = Color(1.0, 0.85, 0.5)   # 蓄力变黄预警
		return
	if d > ATTACK_RANGE * 1.15:
		var dir := (p.global_position - global_position).normalized()
		velocity = dir * cfg["speed"]
		_play("run")
	else:
		velocity = knockback
		_play("idle")
	knockback = knockback.lerp(Vector2.ZERO, 0.2)
	_update_facing()
	move_and_slide()

func _do_attack():
	modulate = Color.WHITE
	var d := _dist_to_player()
	if d <= ATTACK_HIT_RANGE:
		var p := _get_player()
		if p and p.has_method("take_hit_with_stance"):
			var dmg: float = cfg["dmg"] * randf_range(0.85, 1.15)
			p.take_hit_with_stance(dmg, global_position)
			print("[Mob] %s 命中玩家 %.1f" % [cfg["name"], dmg])
	recover_timer = RECOVER_TIME
	attack_cooldown = ATTACK_CD
	state = MobState.RECOVER

func _update_facing():
	if absf(velocity.x) > 4.0:
		anim.flip_h = velocity.x < 0   # 素材面朝右，向左移动时翻转

func _play(aname: String):
	if anim.sprite_frames and anim.sprite_frames.has_animation(aname) and anim.animation != aname:
		anim.play(aname)

# ---------- 受击（玩家攻击入口） ----------
func take_damage(dmg: float) -> void:
	if state == MobState.DYING:
		return
	hp -= dmg
	aggro_lock_timer = 6.0
	state = MobState.CHASE   # 打断当前动作强制进战
	knockback = (global_position - _get_player().global_position).normalized() * 120.0 if _get_player() else Vector2.ZERO
	# 红闪
	var tw := create_tween()
	modulate = Color(1, 0.25, 0.25)
	tw.tween_property(self, "modulate", Color.WHITE, 0.18)
	spawn_damage_number(dmg)
	if hp <= 0:
		_die()

func _die():
	state = MobState.DYING
	velocity = Vector2.ZERO
	# 关闭碰撞防止尸体挡路
	for c in get_children():
		if c is CollisionShape2D:
			c.set_deferred("disabled", true)
	_play("death")
	var ac = get_tree().get_first_node_in_group("audio_controller")
	if ac and ac.has_method("play_sfx"):
		ac.play_sfx("mob_die", -8.0, randf_range(0.9, 1.1))
	_drop_loot()
	mob_died.emit(kind_id)
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)
	print("[Mob] %s 被击杀" % cfg["name"])

func _drop_loot():
	var loot_id: String = cfg["loot"]
	var amount := 1 + (randi() % 2)
	ItemFactory.give(loot_id, amount)
	var gold: int = cfg["gold"]
	if gold > 0:
		GameManager.modify_gold(gold + randi() % 4)
	var txt := "+%s x%d" % [ItemFactory.create(loot_id).item_name, amount] if ItemFactory.create(loot_id) else "+战利品"
	if gold > 0:
		txt += " +%d文" % (gold + randi() % 4)
	_float_text(txt)

func spawn_damage_number(dmg: float):
	var lbl := Label.new()
	lbl.text = str(int(dmg))
	lbl.z_index = 20
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
	lbl.add_theme_constant_override("outline_size", 4)
	get_parent().add_child(lbl)
	lbl.global_position = global_position + Vector2(-8, -34)
	var tw := lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 30, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55).set_delay(0.12)
	tw.chain().tween_callback(lbl.queue_free)

func _float_text(txt: String):
	var lbl := Label.new()
	lbl.text = txt
	lbl.z_index = 20
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.65, 1.0, 0.6))
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.05))
	lbl.add_theme_constant_override("outline_size", 3)
	get_parent().add_child(lbl)
	lbl.global_position = global_position + Vector2(-20, -44)
	var tw := lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 24, 0.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.2)
	tw.chain().tween_callback(lbl.queue_free)
