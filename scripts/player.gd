extends CharacterBody2D

const SPEED = 200.0
const SPRINT_SPEED = 350.0
const DODGE_SPEED = 500.0
const DODGE_DURATION = 0.2
const COMBO_WINDOW = 0.5
const BLOCK_QI_COST = 3.0
const BUILD_OFFSET = 48.0
const STAGGER_DURATION = 1.2

enum State {IDLE, MOVE, ATTACK, BLOCK, DODGE, MEDITATE, BUILD, STAGGER}
enum Direction {DOWN, LEFT, RIGHT, UP}

var state: State = State.IDLE
var facing: Direction = Direction.DOWN
var current_skill: Skill = null
var frame_counter: int = 0
var skill_phase: String = ""
var dodge_timer: float = 0.0
var dodge_dir: Vector2 = Vector2.ZERO
var combo_input_queue: Array = []
var combo_timer: float = 0.0
var equipped_light_skill: String = ""
var equipped_heavy_skill: String = ""
var combo_tree: ComboTree = null
var stagger_timer: float = 0.0
var combat_stance: Node = null
var build_place_cooldown: float = 0.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_indicator: ColorRect = $AttackIndicator
var interact_cooldown: float = 0.0
var build_menu: Control = null
var build_labels: Array = []
var build_selected_index: int = -1
# 玩家碰撞形状半尺寸（与CollisionShape2D一致：24x36）
const COLLISION_HALF_W = 12.0
const COLLISION_HALF_H = 18.0
var _world_gen: Node2D = null

func _ready():
	attack_indicator.visible = false
	combo_tree = load("res://resources/combo_tree.tres") if ResourceLoader.exists("res://resources/combo_tree.tres") else null
	combat_stance = get_node_or_null("/root/Main/CombatStance")
	_world_gen = get_node_or_null("/root/Main/World/WorldGenerator")

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
	elif anim and anim.sprite_frames and anim.sprite_frames.has_animation(prefix):
		anim.play(prefix)

func _check_tile_collision():
	"""检测玩家碰撞矩形四角是否在碰撞瓦片上，阻止对应方向的移动"""
	if _world_gen == null or not _world_gen.has_method("is_tile_blocking"):
		return
	var pos = global_position
	# 检测X方向：用前方两个角
	var x_blocked = false
	if velocity.x > 0:
		# 向右移动，检查右侧两角
		if _world_gen.is_tile_blocking(Vector2(pos.x + COLLISION_HALF_W, pos.y - COLLISION_HALF_H)) or \
		   _world_gen.is_tile_blocking(Vector2(pos.x + COLLISION_HALF_W, pos.y + COLLISION_HALF_H)):
			x_blocked = true
	elif velocity.x < 0:
		# 向左移动，检查左侧两角
		if _world_gen.is_tile_blocking(Vector2(pos.x - COLLISION_HALF_W, pos.y - COLLISION_HALF_H)) or \
		   _world_gen.is_tile_blocking(Vector2(pos.x - COLLISION_HALF_W, pos.y + COLLISION_HALF_H)):
			x_blocked = true
	# 检测Y方向：用前方两个角
	var y_blocked = false
	if velocity.y > 0:
		# 向下移动，检查下方两角
		if _world_gen.is_tile_blocking(Vector2(pos.x - COLLISION_HALF_W, pos.y + COLLISION_HALF_H)) or \
		   _world_gen.is_tile_blocking(Vector2(pos.x + COLLISION_HALF_W, pos.y + COLLISION_HALF_H)):
			y_blocked = true
	elif velocity.y < 0:
		# 向上移动，检查上方两角
		if _world_gen.is_tile_blocking(Vector2(pos.x - COLLISION_HALF_W, pos.y - COLLISION_HALF_H)) or \
		   _world_gen.is_tile_blocking(Vector2(pos.x + COLLISION_HALF_W, pos.y - COLLISION_HALF_H)):
			y_blocked = true
	if x_blocked:
		velocity.x = 0
	if y_blocked:
		velocity.y = 0

func _physics_process(delta):
	match state:
		State.IDLE:
			_process_idle(delta)
		State.MOVE:
			_process_move(delta)
		State.ATTACK:
			_process_attack(delta)
		State.BLOCK:
			_process_block(delta)
		State.DODGE:
			_process_dodge(delta)
		State.MEDITATE:
			_process_meditate(delta)
		State.BUILD:
			_process_build(delta)
		State.STAGGER:
			_process_stagger(delta)

func _process_idle(_delta):
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		_update_facing(input_dir)
		state = State.MOVE
		return
	_play_anim("idle")
	_check_combat_input()

func _process_move(_delta):
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir == Vector2.ZERO:
		state = State.IDLE
		_play_anim("idle")
		return
	_update_facing(input_dir)
	var spd = SPEED
	if Input.is_action_pressed("player_dodge"):
		spd = SPRINT_SPEED
	velocity = input_dir * spd
	_check_tile_collision()
	_play_anim("walk")
	move_and_slide()
	_check_combat_input()

func _check_combat_input():
	if Input.is_action_just_pressed("player_attack_light"):
		_start_attack(true)
	elif Input.is_action_just_pressed("player_attack_heavy"):
		_start_attack(false)
	elif Input.is_action_just_pressed("player_block"):
		_start_block()
	elif Input.is_action_just_pressed("player_dodge"):
		_start_dodge()
	elif Input.is_action_just_pressed("player_meditate"):
		_toggle_meditate()
	elif Input.is_action_just_pressed("player_interact"):
		_try_interact()
	elif Input.is_action_just_pressed("player_build"):
		_toggle_build()
	elif Input.is_action_just_pressed("player_join_clan"):
		_try_join_clan()
	elif Input.is_action_just_pressed("player_show_clan"):
		_show_player_clan()
	elif Input.is_action_just_pressed("player_betray_clan"):
		_betray_clan()
	elif Input.is_action_just_pressed("stance_attack"):
		_switch_stance_attack()
	elif Input.is_action_just_pressed("stance_defense"):
		_switch_stance_defense()
	elif Input.is_action_just_pressed("stance_neutral"):
		_switch_stance_neutral()

func _start_attack(is_light: bool):
	if GameManager.qi < 2:
		return
	state = State.ATTACK
	var skill = _get_skill(is_light)
	if skill == null:
		state = State.IDLE
		return
	current_skill = skill
	frame_counter = 0
	skill_phase = "startup"
	_play_anim("attack")
	velocity = Vector2.ZERO

func _get_skill(is_light: bool) -> Skill:
	var skill: Skill = null
	if is_light and equipped_light_skill != "":
		skill = load("res://resources/skills/" + equipped_light_skill + ".tres")
	elif not is_light and equipped_heavy_skill != "":
		skill = load("res://resources/skills/" + equipped_heavy_skill + ".tres")
	elif is_light:
		skill = load("res://resources/skills/直拳.tres")
	else:
		skill = load("res://resources/skills/破山拳.tres")

	if combo_timer > 0 and combo_tree != null and combo_input_queue.size() > 0:
		var last_skill = combo_input_queue[-1] as Skill
		if last_skill and last_skill.combo_tag != "无" and last_skill.combo_tag != "终结":
			var candidates = combo_tree.get_next_skills(last_skill.combo_tag)
			if candidates.has(skill.skill_name):
				skill.damage += _get_combo_bonus(last_skill.combo_tag, skill.skill_name)

	combo_input_queue.append(skill)
	combo_timer = COMBO_WINDOW
	return skill

func _get_combo_bonus(from_tag: String, next_skill_name: String) -> float:
	if combo_tree == null:
		return 0.0
	for route in combo_tree.routes:
		if route.from_tag == from_tag and route.next_skill == next_skill_name:
			return route.bonus_damage
	return 0.0

func _process_attack(_delta):
	frame_counter += 1

	if skill_phase == "startup":
		attack_indicator.visible = false
		if frame_counter >= current_skill.startup_frames:
			frame_counter = 0
			skill_phase = "active"
			attack_indicator.visible = true
			attack_indicator.color.a = 0.7

	elif skill_phase == "active":
		match facing:
			Direction.LEFT:
				attack_indicator.position.x = -48
				attack_indicator.position.y = -16
			Direction.RIGHT:
				attack_indicator.position.x = 16
				attack_indicator.position.y = -16
			Direction.UP:
				attack_indicator.position.x = -16
				attack_indicator.position.y = -48
			Direction.DOWN:
				attack_indicator.position.x = -16
				attack_indicator.position.y = 16
		attack_indicator.color = _damage_color()

		if frame_counter >= current_skill.active_frames:
			frame_counter = 0
			skill_phase = "recovery"
			attack_indicator.visible = false
			_deal_damage()

	elif skill_phase == "recovery":
		if frame_counter >= current_skill.recovery_frames:
			_end_attack()

func _damage_color() -> Color:
	match current_skill.category:
		"拳掌": return Color(1, 0.4, 0.2, 0.7)
		"剑法": return Color(0.6, 0.8, 1, 0.7)
		"刀法": return Color(1, 0.5, 0, 0.7)
		"棍法": return Color(0.5, 0.7, 0.3, 0.7)
		"暗器": return Color(0.7, 0.3, 0.7, 0.7)
		_: return Color(0.3, 0.9, 0.9, 0.7)

func _deal_damage():
	GameManager.consume_qi(current_skill.cost)
	var base_damage = current_skill.damage
	var final_damage = base_damage
	if combat_stance:
		var dmg_mult = combat_stance.on_hit_dealt()
		var counter_mult = combat_stance.get_block_counter_damage_mult()
		final_damage = base_damage * dmg_mult * counter_mult
		if counter_mult > 1.0:
			print("[Combat] 格挡反击! 伤害x" + str(counter_mult))
	print("[Combat] " + current_skill.skill_name + " dealt " + str(final_damage) + " damage")

func _end_attack():
	state = State.IDLE
	current_skill = null
	attack_indicator.visible = false
	attack_indicator.color.a = 0.0
	combo_timer = max(combo_timer - 0.3, 0)
	if combo_timer <= 0:
		combo_input_queue.clear()

func _start_block():
	if GameManager.qi < BLOCK_QI_COST:
		return
	if combat_stance and combat_stance.is_in_block_counter:
		if combat_stance.try_block_counter():
			_start_attack(true)
			return
	state = State.BLOCK
	_play_anim("block")
	velocity = Vector2.ZERO
	attack_indicator.visible = true
	attack_indicator.color = Color(0.2, 0.5, 1, 0.6)

func _process_block(_delta):
	GameManager.consume_qi(BLOCK_QI_COST * 0.016)
	if combat_stance and combat_stance.is_in_block_counter:
		attack_indicator.color = Color(0.3, 0.8, 1, 0.8)
	if not Input.is_action_pressed("player_block"):
		attack_indicator.visible = false
		state = State.IDLE

func _start_dodge():
	state = State.DODGE
	dodge_timer = DODGE_DURATION
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	dodge_dir = input_dir.normalized() if input_dir != Vector2.ZERO else Vector2(0, 1)
	if dodge_dir != Vector2.ZERO:
		_update_facing(dodge_dir)
	attack_indicator.visible = true
	attack_indicator.color = Color(0.3, 1, 0.4, 0.5)
	GameManager.consume_qi(5)

func _process_dodge(delta):
	dodge_timer -= delta
	velocity = dodge_dir * DODGE_SPEED
	_check_tile_collision()
	move_and_slide()
	if dodge_timer <= 0:
		attack_indicator.visible = false
		attack_indicator.color.a = 0
		state = State.IDLE

func _toggle_meditate():
	if state == State.MEDITATE:
		state = State.IDLE
		GameManager.stop_meditation()
		attack_indicator.visible = false
	else:
		state = State.MEDITATE
		GameManager.start_meditation()
		velocity = Vector2.ZERO
		attack_indicator.visible = true
		attack_indicator.color = Color(0.3, 0.3, 0.8, 0.5)

func _process_meditate(_delta):
	if Input.is_action_just_pressed("player_meditate"):
		state = State.IDLE
		GameManager.stop_meditation()
		attack_indicator.visible = false
		return
	if GameManager.is_meditating == false:
		state = State.IDLE
		attack_indicator.visible = false

func _try_interact():
	if interact_cooldown > 0:
		return
	interact_cooldown = 0.5
	var npc = _get_nearest_npc()
	if npc and npc.has_method("set_interacting"):
		var spawner = get_node("/root/Main/World/NPCSpawner")
		if spawner and spawner.has_method("show_interaction_ui"):
			npc.set_interacting(true)
			spawner.show_interaction_ui(npc)

func _get_nearest_npc() -> CharacterBody2D:
	var best = null
	var best_dist = 120.0
	var npcs = get_tree().get_nodes_in_group("npc")
	for n in npcs:
		var d = global_position.distance_to(n.global_position)
		if d < best_dist:
			best_dist = d
			best = n
	return best

func _process(_delta):
	combo_timer -= _delta if combo_timer > 0 else 0
	if combo_timer <= 0 and combo_input_queue.size() > 0:
		combo_input_queue.clear()
	interact_cooldown -= _delta if interact_cooldown > 0 else 0

func _toggle_build():
	if state == State.BUILD:
		state = State.IDLE
		GameManager.is_build_mode = false
		attack_indicator.visible = false
		_hide_build_menu()
	else:
		state = State.BUILD
		GameManager.is_build_mode = true
		velocity = Vector2.ZERO
		attack_indicator.visible = true
		attack_indicator.color = Color(0.9, 0.9, 0.2, 0.5)
		_show_build_menu()

func _show_build_menu():
	if build_menu == null:
		_create_build_menu()
	build_menu.visible = true
	_refresh_build_labels()

func _hide_build_menu():
	if build_menu:
		build_menu.visible = false
	GameManager.selected_building = null
	build_selected_index = -1

func _create_build_menu():
	build_menu = Control.new()
	build_menu.name = "BuildMenu"
	build_menu.visible = false

	var panel = Panel.new()
	panel.size = Vector2(220, 190)
	panel.position = Vector2(0, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	build_menu.add_child(panel)

	var title = Label.new()
	title.text = "=== 建造菜单 ==="
	title.position = Vector2(10, 6)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	build_menu.add_child(title)

	var buildings = [
		{"key": "1", "name": "茅屋", "cost": "15木 5石", "info": "住所(3x2)"},
		{"key": "2", "name": "练功房", "cost": "20木 15石", "info": "修炼加速(2x2)"},
		{"key": "3", "name": "炼丹房", "cost": "15木 20石", "info": "炼丹(2x2)"},
		{"key": "4", "name": "农田", "cost": "5木 2石", "info": "食物(2x2)"},
		{"key": "5", "name": "围墙", "cost": "3木 8石", "info": "防御(1x1)"},
	]

	for i in range(buildings.size()):
		var d = buildings[i]
		var y = 26 + i * 28
		var lbl = Label.new()
		lbl.text = "[" + d["key"] + "] " + d["name"] + "  " + d["cost"] + " " + d["info"]
		lbl.position = Vector2(10, y)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		build_menu.add_child(lbl)
		build_labels.append(lbl)

	var hint = Label.new()
	hint.text = "B=退出  数字键=选择  左键=放置"
	hint.position = Vector2(10, 170)
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	build_menu.add_child(hint)

	get_parent().add_child(build_menu)

func _refresh_build_labels():
	for i in range(build_labels.size()):
		if build_selected_index == i:
			build_labels[i].add_theme_color_override("font_color", Color(1, 0.9, 0.2))
		else:
			build_labels[i].add_theme_color_override("font_color", Color(1, 1, 1))

func _process_build(_delta):
	if build_menu:
		build_menu.global_position = global_position + Vector2(-100, -220)
	if Input.is_action_just_pressed("player_build"):
		_toggle_build()
		return
	if Input.is_action_just_pressed("build_slot_1"):
		_select_building("茅屋")
	elif Input.is_action_just_pressed("build_slot_2"):
		_select_building("练功房")
	elif Input.is_action_just_pressed("build_slot_3"):
		_select_building("炼丹房")
	elif Input.is_action_just_pressed("build_slot_4"):
		_select_building("农田")
	elif Input.is_action_just_pressed("build_slot_5"):
		_select_building("围墙")
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and GameManager.selected_building != null:
		_place_building()

func _select_building(type_str: String):
	var idx = -1
	var tpl = BuildingTemplate.new()
	match type_str:
		"茅屋":
			tpl.building_name = "茅屋"; tpl.building_type = "茅屋"
			tpl.wood_cost = 15; tpl.stone_cost = 5
			tpl.size_x = 3; tpl.size_y = 2
			tpl.capacity = 2; tpl.provides = "住所"
			idx = 0
		"练功房":
			tpl.building_name = "练功房"; tpl.building_type = "练功房"
			tpl.wood_cost = 20; tpl.stone_cost = 15
			tpl.size_x = 2; tpl.size_y = 2
			tpl.provides = "修炼加速"
			idx = 1
		"炼丹房":
			tpl.building_name = "炼丹房"; tpl.building_type = "炼丹房"
			tpl.wood_cost = 15; tpl.stone_cost = 20
			tpl.size_x = 2; tpl.size_y = 2
			tpl.provides = "炼丹"
			idx = 2
		"农田":
			tpl.building_name = "农田"; tpl.building_type = "农田"
			tpl.wood_cost = 5; tpl.stone_cost = 2
			tpl.size_x = 2; tpl.size_y = 2
			tpl.provides = "食物"
			idx = 3
		"围墙":
			tpl.building_name = "围墙"; tpl.building_type = "围墙"
			tpl.wood_cost = 3; tpl.stone_cost = 8
			tpl.size_x = 1; tpl.size_y = 1
			tpl.tile_id = 3
			tpl.provides = "防御"
			idx = 4
	GameManager.selected_building = tpl
	build_selected_index = idx
	if build_menu and build_menu.visible:
		_refresh_build_labels()

func _place_building():
	var tpl = GameManager.selected_building
	if not GameManager.has_materials(tpl.wood_cost, tpl.stone_cost):
		print("[Build] 材料不足!")
		return
	var pos = global_position
	pos.x = snapped(pos.x, BUILD_OFFSET)
	pos.y = snapped(pos.y, BUILD_OFFSET)
	GameManager.consume_materials(tpl.wood_cost, tpl.stone_cost)
	var bld = {
		"name": tpl.building_name,
		"type": tpl.building_type,
		"position": pos,
		"size_x": tpl.size_x,
		"size_y": tpl.size_y
	}
	GameManager.add_building(bld)
	_spawn_building_visual(pos, tpl)
	print("[Build] Placed " + tpl.building_name + " at " + str(pos))
	GameManager.selected_building = null

func _spawn_building_visual(pos: Vector2, tpl: BuildingTemplate):
	var bld_node = Node2D.new()
	bld_node.name = "Building_" + tpl.building_name
	bld_node.global_position = pos
	bld_node.y_sort_enabled = true
	# 使用瓦片纹理代替ColorRect
	var tile_tex = _building_tile_texture(tpl.building_type)
	for sx in range(tpl.size_x):
		for sy in range(tpl.size_y):
			var sprite = Sprite2D.new()
			sprite.texture = tile_tex
			sprite.position = Vector2(sx * BUILD_OFFSET + BUILD_OFFSET / 2, sy * BUILD_OFFSET + BUILD_OFFSET / 2)
			sprite.z_index = 1
			bld_node.add_child(sprite)
	var lbl = Label.new()
	lbl.text = tpl.building_name
	lbl.position = Vector2(0, -18)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	bld_node.add_child(lbl)
	get_parent().add_child(bld_node)

func _building_tile_texture(type_str: String) -> Texture2D:
	var path = ""
	match type_str:
		"茅屋": path = "res://sprites/tiles/house_cottage.png"
		"练功房": path = "res://sprites/tiles/house_temple.png"
		"炼丹房": path = "res://sprites/tiles/house_cottage.png"
		"农田": path = "res://sprites/tiles/farmland.png"
		"围墙": path = "res://sprites/tiles/fence.png"
		_: path = "res://sprites/tiles/house_cottage.png"
	if ResourceLoader.exists(path):
		return load(path)
	# 回退到ColorRect方式
	return null

func _building_color(type_str: String) -> Color:
	match type_str:
		"茅屋": return Color(0.5, 0.35, 0.2, 0.7)
		"练功房": return Color(0.3, 0.3, 0.5, 0.7)
		"炼丹房": return Color(0.6, 0.2, 0.2, 0.7)
		"农田": return Color(0.3, 0.6, 0.2, 0.7)
		"围墙": return Color(0.4, 0.4, 0.4, 0.8)
		_: return Color(0.5, 0.5, 0.3, 0.7)

func _try_join_clan():
	var cname = GameManager.current_environment
	if cname == "":
		print("[Clan] Not near a clan territory")
		return
	var c = GameManager.get_clan(cname)
	if c == null:
		return
	if GameManager.reputation < c.join_condition_reputation:
		print("[Clan] Need " + str(c.join_condition_reputation) + " reputation, have " + str(GameManager.reputation))
		return
	GameManager.join_clan(cname)

func _show_player_clan():
	if GameManager.player_clan == null:
		print("[Clan] Not in any clan. Go near a clan POI and press J to join")
		return
	var c = GameManager.player_clan
	print("[Clan] " + c.clan_name + " | Rank: " + GameManager.CLAN_RANKS[GameManager.player_rank] + " | Contribution: " + str(GameManager.contribution))

func _betray_clan():
	if GameManager.player_clan == null:
		print("[Clan] Not in any clan")
		return
	GameManager.betray_clan()

func _switch_stance_attack():
	if combat_stance:
		combat_stance.switch_stance(1)

func _switch_stance_defense():
	if combat_stance:
		combat_stance.switch_stance(2)

func _switch_stance_neutral():
	if combat_stance:
		combat_stance.switch_stance(0)

func _process_stagger(delta):
	stagger_timer -= delta
	velocity = Vector2.ZERO
	attack_indicator.visible = true
	attack_indicator.color = Color(1, 0.1, 0.1, 0.5 + 0.3 * sin(stagger_timer * 10))
	if stagger_timer <= 0:
		attack_indicator.visible = false
		state = State.IDLE
		if combat_stance:
			combat_stance.vulnerability = 0
			combat_stance.vulnerability_changed.emit(0)

func enter_stagger():
	if state == State.STAGGER:
		return
	state = State.STAGGER
	stagger_timer = STAGGER_DURATION
	velocity = Vector2.ZERO
	attack_indicator.visible = true
	print("[Combat] 进入大硬直状态!")

func take_hit_with_stance(damage: float):
	var actual_damage = damage
	if combat_stance:
		actual_damage = combat_stance.on_hit_received(damage)
		if state == State.BLOCK:
			combat_stance.on_block_hit()
		if combat_stance.is_staggered():
			enter_stagger()
	GameManager.take_hit(actual_damage)
