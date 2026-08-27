extends CharacterBody2D

const TextureGen = preload("res://scripts/texture_generator.gd")

const SPEED = 100.0
const SPRINT_SPEED = 175.0
const DODGE_SPEED = 250.0
const DODGE_DURATION = 0.2
const COMBO_WINDOW = 0.5
const BLOCK_QI_COST = 3.0
const BUILD_OFFSET = 24.0
const STAGGER_DURATION = 1.2

enum State {IDLE, MOVE, ATTACK, BLOCK, DODGE, MEDITATE, BUILD, STAGGER, DEAD}
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

# ---- Phase D 打磨：死亡闭环/受击反馈/音效 ----
var _is_dead: bool = false          # mob.gd经p.get("_is_dead")读取自动脱战
var hurt_timer: float = 0.0         # >0期间IDLE/MOVE不覆盖hurt动画
var _ds_hooked: bool = false        # DeathSystem信号是否已连接

# ---- Phase C 星露谷工具系统 ----
enum Tool {NONE, HOE, CAN, SEEDS, COLLECT}
const TOOL_NAMES := {"hoe": "锄头", "can": "水壶", "seeds": "菜种", "collect": "采集"}
const TOOL_ORDER := [Tool.HOE, Tool.CAN, Tool.SEEDS, Tool.COLLECT]
var equipped_tool: int = Tool.NONE
var tool_cooldown: float = 0.0
var target_indicator: Sprite2D = null

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_indicator: ColorRect = $AttackIndicator
var interact_cooldown: float = 0.0
var build_menu: Control = null
var build_labels: Array = []
var build_selected_index: int = -1
# 玩家碰撞形状半尺寸（与CollisionShape2D一致：12x8脚部盒，Stardew式深度）
const COLLISION_HALF_W = 6.0
const COLLISION_HALF_H = 4.0
var _world_gen: Node2D = null

func _ready():
	attack_indicator.visible = false
	# 碰撞分层表（地形/建筑StaticBody=层1）：玩家=层2，NPC=层4，敌人=层8
	# 玩家mask=1|4|8：被NPC/敌人挡住（空气墙）；NPC/敌人mask只含层1→
	# 它们做重叠分离时不会把玩家算进去，玩家位置绝不被实体改变
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	combo_tree = load("res://resources/combo_tree.tres") if ResourceLoader.exists("res://resources/combo_tree.tres") else null
	combat_stance = get_node_or_null("/root/Main/CombatStance")
	_world_gen = get_node_or_null("/root/Main/World/WorldGenerator")
	_create_target_indicator()
	# 纹理可能在Main._ensure_textures()中才生成（晚于本_ready），故延迟一帧重建帧动画
	call_deferred("rebuild_sprite_frames")
	# Phase D：延迟预连死亡信号——deferred时点晚于Main._ready，DeathSystem必已就绪；
	# 否则GameManager.take_hit内部触发的首次player_died会因未连接而丢失死亡表现
	call_deferred("_hook_death_signals")

# 面前目标格高亮指示器（星露谷式）：16x16描边贴图，跟随面向格移动
func _create_target_indicator():
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color(1, 1, 1, 165)
	for i in range(16):
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, 15, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(15, i, edge)
	# 四角加亮便于辨识
	for c in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 15), Vector2i(15, 15)]:
		img.set_pixel(c.x, c.y, Color(1, 1, 1, 230))
	target_indicator = Sprite2D.new()
	target_indicator.texture = ImageTexture.create_from_image(img)
	target_indicator.z_index = 30
	target_indicator.modulate = Color(1.0, 0.93, 0.45, 0.85)
	add_child(target_indicator)

func _update_target_indicator():
	if target_indicator == null:
		return
	var show_it: bool = (state == State.IDLE or state == State.MOVE) and not _is_ui_blocking()
	target_indicator.visible = show_it
	if not show_it:
		return
	var gp := global_position
	var cur := Vector2i(int(floor(gp.x / 16.0)), int(floor(gp.y / 16.0)))
	var off := Vector2i.ZERO
	match facing:
		Direction.LEFT: off = Vector2i(-1, 0)
		Direction.RIGHT: off = Vector2i(1, 0)
		Direction.UP: off = Vector2i(0, -1)
		Direction.DOWN: off = Vector2i(0, 1)
	var tgt := cur + off
	target_indicator.global_position = Vector2(tgt.x * 16.0 + 8.0, tgt.y * 16.0 + 8.0)

# 运行时从PNG直接重建SpriteFrames：绕过import系统，保证新生成的贴图立即生效
func rebuild_sprite_frames():
	var sf = SpriteFrames.new()
	var dir_names = ["down", "left", "right", "up"]
	var specs = [
		["idle", 4, 6.0, true],
		["walk", 6, 10.0, true],
		["run", 6, 10.0, true],
		["attack", 8, 14.0, false],   # Slice 轻击(8帧)
		["heavy", 8, 14.0, false],    # Pierce 重击(8帧)
		["block", 4, 5.0, true],      # Carry_Idle 持械防御姿态
		["hurt", 4, 8.0, false],      # 受击
		["death", 8, 10.0, false],    # 死亡倒地
	]
	var loaded_any = false
	for spec in specs:
		var prefix = spec[0]
		for dir_name in dir_names:
			var anim_name = prefix + "_" + dir_name
			# Phase G1：先收集帧，至少1帧才注册动画——防止磁盘帧缺失时产生空动画(角色隐身)
			var frames: Array = []
			for i in range(spec[1]):
				var tex = TextureGen.load_png_texture("res://sprites/player/%s_%s_%d.png" % [prefix, dir_name, i])
				if tex:
					frames.append(tex)
			if frames.is_empty():
				push_warning("[Player] 缺失动画帧: " + anim_name)
				continue
			if not sf.has_animation(anim_name):
				sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, spec[2])
			sf.set_animation_loop(anim_name, spec[3])
			for tex in frames:
				sf.add_frame(anim_name, tex)
			loaded_any = true
	if loaded_any:
		anim.sprite_frames = sf
		# Body_A 64x64帧人物脚线在y≈48，帧中心y=32 → 上移16px使脚底=节点原点
		anim.offset = Vector2(0, -16)
		_play_anim("idle")

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

func _physics_process(delta):
	# WorldGenerator在Main._ready()中延迟创建，此处懒加载确保获取到引用
	if _world_gen == null:
		_world_gen = get_node_or_null("/root/Main/World/WorldGenerator")
	# Phase D：死亡状态锁输入/物理，仅播死亡帧
	if _is_dead or state == State.DEAD:
		velocity = Vector2.ZERO
		return
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

func _unhandled_input(event):
	# 建造模式下ESC退出（事件驱动：ui_cancel动作轮询对注入时序敏感，真实按键事件更可靠）
	if state == State.BUILD and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle_build()
		get_viewport().set_input_as_handled()

func _is_ui_blocking() -> bool:
	"""有模态UI打开时，锁定角色移动与战斗输入"""
	if DialogManager.is_dialog_open():
		return true
	var ui = get_node_or_null("/root/Main/World/UI")
	if ui:
		var shop = ui.get_node_or_null("ShopHUD")
		if shop and shop.is_open:
			return true
		var qm = ui.get_node_or_null("QuickMenu")
		if qm and qm.is_panel_open():
			return true
		# Phase H2: 任务日志抽屉展开时同样锁定（否则数字键会同时触发接任务与切换工具）
		var ql = ui.get_node_or_null("QuestLogHUD")
		if ql and ql.expanded:
			return true
	var spawner = get_node_or_null("/root/Main/World/NPCSpawner")
	if spawner and spawner.has_method("is_interaction_open") and spawner.is_interaction_open():
		return true
	# Phase F7: 模态面板组（人物面板等）打开时锁移动
	for m in get_tree().get_nodes_in_group("ui_modal"):
		if is_instance_valid(m) and "visible" in m and m.visible:
			return true
	return false

func _movement_locked() -> bool:
	"""移动专用锁定：石伯WASD教学页(dialog teach_move)特许自由试走"""
	if not _is_ui_blocking():
		return false
	if DialogManager.is_move_teach_open():
		return false
	return true

# 供奇遇系统判定"击打怪物中"暂缓触发：出招/硬直窗口 或 面前扇形内尚有接战目标
func is_in_combat() -> bool:
	if state == State.ATTACK or state == State.STAGGER:
		return true
	return _find_mob_in_front() != null

func _is_mouse_over_ui() -> bool:
	"""鼠标悬停在任何Control上时，不触发攻击等游戏内动作"""
	return get_viewport().gui_get_hovered_control() != null

# ---- Phase F4: 点击NPC=查看信息，与攻击解耦 ----
func _npc_at_mouse() -> CharacterBody2D:
	"""鼠标位置圆形查询是否点中NPC（覆盖全身范围而非仅脚部碰撞盒）"""
	var space := get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 13.0
	params.shape = shape
	params.transform = Transform2D(0, get_global_mouse_position())
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 4   # NPC层（碰撞分层表：NPC=层4）
	var hits := space.intersect_shape(params, 8)
	for hit in hits:
		var col = hit.get("collider")
		if col != null and is_instance_valid(col) and col.is_in_group("npc"):
			return col
	return null

func _click_npc_info(npc: Node):
	"""点击NPC：远距离显示人物姓名与属性面板，不触发攻击/工具"""
	var info = get_node_or_null("/root/Main/World/UI/NPCInfoHUD")
	if info and info.has_method("show_npc_info"):
		info.show_npc_info(npc)
	if npc.has_method("show_name_tag_flash"):
		npc.show_name_tag_flash()
	_sfx("ui", -12.0)

# ---- Phase G: 点击大建筑（古堡）查看势力信息 ----
func _building_at_mouse() -> Node2D:
	"""鼠标位置是否点中带信息的大型建筑（footprint占位39判定，向下扫覆盖屋顶悬出区）"""
	var wgen = get_node_or_null("/root/Main/World/WorldGenerator")
	if wgen == null:
		return null
	var mp := get_global_mouse_position()
	var cell := Vector2i(int(floor(mp.x / 16.0)), int(floor(mp.y / 16.0)))
	var hit := false
	for dy in range(0, 8):
		if int(wgen.override_cells.get(cell + Vector2i(0, dy), -1)) == int(wgen.TILE_BUILDING_RESERVE):
			hit = true
			break
	if not hit:
		return null
	var best: Node2D = null
	var best_d := 1e12
	for b in get_tree().get_nodes_in_group("building_prop"):
		if not b.has_meta("b_name"):
			continue
		var d: float = mp.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best

func _click_building_info(bld: Node2D):
	"""点击建筑：显示势力信息面板，不触发攻击/工具"""
	var info = get_node_or_null("/root/Main/World/UI/BuildingInfoHUD")
	if info and info.has_method("show_building_info"):
		info.show_building_info(bld)
	_sfx("ui", -12.0)

func _process_idle(_delta):
	if _movement_locked():
		velocity = Vector2.ZERO
		_play_anim("idle")
		return
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		_update_facing(input_dir)
		state = State.MOVE
		return
	if hurt_timer <= 0.0:
		_play_anim("idle")
	# 教学对话页打开时仅解锁移动，战斗/工具输入保持锁定
	if not DialogManager.is_dialog_open():
		_check_combat_input()

func _process_move(_delta):
	if _movement_locked():
		velocity = Vector2.ZERO
		state = State.IDLE
		_play_anim("idle")
		return
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir == Vector2.ZERO:
		state = State.IDLE
		_play_anim("idle")
		return
	_update_facing(input_dir)
	var spd = SPEED
	if Input.is_action_pressed("player_sprint"):
		spd = SPRINT_SPEED
	velocity = input_dir * spd
	# 地形碰撞由TileSet物理层+move_and_slide处理（脚本级角点检测已移除：
	# 贴墙时角点浮点嵌入碰撞瓦片会导致四方向全部锁死，且物理碰撞本身支持沿墙滑动）
	if hurt_timer <= 0.0:
		_play_anim("walk")
	move_and_slide()
	# 教学对话页打开时仅解锁移动，战斗/工具输入保持锁定
	if not DialogManager.is_dialog_open():
		_check_combat_input()

func _check_combat_input():
	if _is_mouse_over_ui():
		return
	# Phase C 工具切换：数字键1-4（建造模式下由_process_build优先消费build_slot，不冲突）
	if Input.is_action_just_pressed("tool_slot_1"):
		_select_tool(Tool.HOE)
		return
	if Input.is_action_just_pressed("tool_slot_2"):
		_select_tool(Tool.CAN)
		return
	if Input.is_action_just_pressed("tool_slot_3"):
		_select_tool(Tool.SEEDS)
		return
	if Input.is_action_just_pressed("tool_slot_4"):
		_select_tool(Tool.COLLECT)
		return
	if Input.is_action_just_pressed("player_attack_light"):
		var clicked_npc := _npc_at_mouse()
		if clicked_npc != null:
			_click_npc_info(clicked_npc)	# Phase F4: 点中NPC→信息面板，非攻击
			return
		var clicked_bld := _building_at_mouse()
		if clicked_bld != null:
			_click_building_info(clicked_bld)	# Phase G: 点中古堡→势力信息面板
			return
		if equipped_tool != Tool.NONE:
			_use_tool()   # 装备工具时左键=使用工具（星露谷式）
		else:
			_start_attack(true)
	elif Input.is_action_just_pressed("player_attack_heavy"):
		if _npc_at_mouse() != null or _building_at_mouse() != null:
			return	# 右键重击同样为NPC/建筑点击让路
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

# ---- Phase C 工具逻辑 ----
func _tool_name(t: int) -> String:
	match t:
		Tool.HOE: return TOOL_NAMES["hoe"]
		Tool.CAN: return TOOL_NAMES["can"]
		Tool.SEEDS: return TOOL_NAMES["seeds"]
		Tool.COLLECT: return TOOL_NAMES["collect"]
	return "徒手"

func _select_tool(t: int):
	equipped_tool = Tool.NONE if equipped_tool == t else t
	_sfx("ui", -12.0)
	_float_text(global_position + Vector2(0, -34), "装备：" + _tool_name(equipped_tool), Color(0.75, 0.95, 1.0))

func _use_tool():
	if tool_cooldown > 0.0:
		return
	tool_cooldown = 0.38
	var farm = get_node_or_null("/root/Main/World/FarmSystem")
	if farm == null:
		return
	var target_pos := global_position + _facing_vector() * 14.0
	var res: Dictionary = {"ok": false, "msg": ""}
	match equipped_tool:
		Tool.HOE:
			res = farm.try_till(target_pos)
		Tool.CAN:
			res = farm.try_water(target_pos)
		Tool.SEEDS:
			res = farm.try_plant(target_pos)
		Tool.COLLECT:
			res = farm.try_collect(target_pos)
	if res["msg"] != "":
		_float_text(target_pos + Vector2(-10, -20), res["msg"], Color(1, 0.95, 0.5) if res["ok"] else Color(1, 0.55, 0.45))
	# Phase D：农活动作音效（成功才响）
	if bool(res["ok"]):
		match equipped_tool:
			Tool.HOE: _sfx("till")
			Tool.CAN: _sfx("water")
			Tool.SEEDS: _sfx("plant")
			Tool.COLLECT: _sfx("harvest")
	_play_tool_swing()

func _play_tool_swing():
	_sfx("swing", -10.0)
	anim.speed_scale = 2.6
	_play_anim("attack")
	await get_tree().create_timer(0.26).timeout
	anim.speed_scale = 1.0
	if state == State.IDLE or state == State.MOVE:
		_play_anim("idle")

# 世界坐标飘字（工具反馈/合成结果通用）
func _float_text(pos: Vector2, txt: String, color: Color):
	var lbl = Label.new()
	lbl.text = txt
	lbl.z_index = 20
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
	lbl.add_theme_constant_override("outline_size", 3)
	get_parent().add_child(lbl)
	lbl.global_position = pos + Vector2(-24, 0)
	var tw = lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "global_position:y", pos.y - 26, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.15)
	tw.chain().tween_callback(lbl.queue_free)

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
	_play_anim("heavy" if not is_light else "attack")
	_sfx("swing", -9.0)
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
			_spawn_slash_effect()

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
	# 打击反馈仅对战命中时有：特效+震屏+伤害数字
	var target_mob = _find_mob_in_front()
	if target_mob:
		var hit_pos = target_mob.global_position + Vector2(0, -10)
		target_mob.take_damage(final_damage)
		_sfx("hit")
		_spawn_hit_effect(hit_pos)
		_spawn_damage_number(hit_pos, final_damage)
		_camera_shake(4.0, 0.18)
	else:
		# 挥空不产生任何打击特效/伤害提示；命中树木则由采伐系统给轻量木屑反馈
		var ts = get_node_or_null("/root/Main/World/TreeChopSystem")
		if ts and bool(ts.try_chop_front(self).get("ok", false)):
			_camera_shake(1.6, 0.06)   # 砍中树的轻微手感，无大特效

# 面前扇形内最近的敌人（攻击距离56px，朝向夹角余弦>0.25）
func _find_mob_in_front() -> CharacterBody2D:
	var best: CharacterBody2D = null
	var best_d := 56.0
	var fwd := _facing_vector()
	for m in get_tree().get_nodes_in_group("mobs"):
		var mob := m as CharacterBody2D
		if mob == null or not is_instance_valid(mob):
			continue
		var to_m: Vector2 = mob.global_position - global_position
		if to_m.length() > best_d:
			continue
		if to_m.length() > 4.0 and fwd.dot(to_m.normalized()) < 0.25:
			continue
		best_d = to_m.length()
		best = mob
	return best

# 面向方向的单位向量
func _facing_vector() -> Vector2:
	match facing:
		Direction.LEFT: return Vector2.LEFT
		Direction.RIGHT: return Vector2.RIGHT
		Direction.UP: return Vector2.UP
		_: return Vector2.DOWN

# 挥击刀光扇形特效
func _spawn_slash_effect():
	var fx = Polygon2D.new()
	var pts = PackedVector2Array()
	pts.append(Vector2.ZERO)
	var base_angle: float
	match facing:
		Direction.DOWN: base_angle = 90.0
		Direction.LEFT: base_angle = 180.0
		Direction.RIGHT: base_angle = 0.0
		Direction.UP: base_angle = 270.0
	var arc = 100.0
	var radius = 46.0
	for ad in range(int(base_angle - arc / 2), int(base_angle + arc / 2) + 1, 6):
		var ar = deg_to_rad(ad)
		pts.append(Vector2(cos(ar), sin(ar)) * radius)
	fx.polygon = pts
	fx.color = Color(0.65, 0.88, 1.0, 0.55)
	fx.z_index = 8
	get_parent().add_child(fx)
	fx.global_position = global_position + Vector2(0, -14)
	fx.scale = Vector2(0.5, 0.5)
	var tween = fx.create_tween().set_parallel(true)
	tween.tween_property(fx, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(fx, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(fx.queue_free)

# 命中火花粒子
func _spawn_hit_effect(pos: Vector2):
	var container = Node2D.new()
	container.z_index = 9
	get_parent().add_child(container)
	container.global_position = pos
	var hit_color = _damage_color()
	hit_color.a = 1.0
	for i in range(6):
		var p = ColorRect.new()
		p.size = Vector2(4, 4)
		p.position = Vector2(-2, -2)
		p.color = hit_color.lightened(0.3)
		container.add_child(p)
		var dir_vec = Vector2.RIGHT.rotated(randf() * TAU)
		var dist = randf_range(14, 30)
		var tween = p.create_tween().set_parallel(true)
		tween.tween_property(p, "position", dir_vec * dist, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(p, "modulate:a", 0.0, 0.28)
		tween.tween_property(p, "scale", Vector2(0.3, 0.3), 0.28)
	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(container):
		container.queue_free()

# 伤害飘字
func _spawn_damage_number(pos: Vector2, dmg: float):
	var lbl = Label.new()
	lbl.text = str(int(dmg))
	lbl.z_index = 20
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
	lbl.add_theme_constant_override("outline_size", 4)
	get_parent().add_child(lbl)
	lbl.global_position = pos + Vector2(-8, -20)
	var tween = lbl.create_tween().set_parallel(true)
	tween.tween_property(lbl, "global_position:y", lbl.global_position.y - 34, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.15)
	tween.chain().tween_callback(lbl.queue_free)

# 相机震动
func _camera_shake(strength: float, duration: float):
	var cam = get_node_or_null("Camera2D")
	if cam == null:
		return
	var tween = cam.create_tween()
	var steps = 5
	for i in range(steps):
		var s = strength * (1.0 - float(i) / steps)
		tween.tween_property(cam, "offset", Vector2(randf_range(-s, s), randf_range(-s, s)), duration / steps)
	tween.tween_property(cam, "offset", Vector2.ZERO, duration / steps)

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
	_play_anim("run")

func _process_dodge(delta):
	dodge_timer -= delta
	velocity = dodge_dir * DODGE_SPEED
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
	# Phase C：优先检查附近制作站台（F键合成）
	var st_sys = get_node_or_null("/root/Main/World/StationSystem")
	if st_sys and st_sys.has_method("nearest_station"):
		var st = st_sys.nearest_station(self, 34.0)
		if st:
			var res: Dictionary = st_sys.try_craft(st)
			_float_text(st.global_position + Vector2(0, -26), res["msg"], Color(0.65, 1.0, 0.6) if res["ok"] else Color(1, 0.55, 0.45))
			_sfx("craft_ok" if bool(res["ok"]) else "craft_fail")
			return
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
	tool_cooldown -= _delta if tool_cooldown > 0 else 0
	hurt_timer -= _delta if hurt_timer > 0 else 0
	_update_target_indicator()
	# Phase D 死亡兜底轮询：毒/饿等非战斗减血到0也进死亡闭环（战斗路径见take_hit_with_stance）
	if not _is_dead and GameManager.health <= 0.0:
		var ds = _get_death_system()
		if ds:
			_hook_death_signals()
			ds.check_death()

func _toggle_build():
	if state == State.BUILD:
		state = State.IDLE
		GameManager.is_build_mode = false
		attack_indicator.visible = false
		_hide_build_menu()
		_hide_build_ghost()
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
	# 居中面板淡入动画
	var panel = build_menu.get_child(0)
	if panel:
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.92, 0.92)
		panel.pivot_offset = panel.size / 2
		var tween = create_tween().set_parallel(true)
		tween.tween_property(panel, "modulate:a", 1.0, 0.15)
		tween.tween_property(panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	build_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel = Panel.new()
	panel.name = "BuildPanel"
	panel.size = Vector2(320, 350)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	# 建造落点=玩家脚下（屏幕中心），面板居中会挡住落点——停靠右侧垂直居中留出中间视野
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_right = -20
	panel.offset_left = -340
	panel.offset_top = -175
	panel.offset_bottom = 175
	build_menu.add_child(panel)

	var title = Label.new()
	title.text = "建 造"
	title.position = Vector2(10, 10)
	title.size = Vector2(300, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(title, 16)
	panel.add_child(title)

	var buildings = [
		{"key": "1", "name": "茅屋", "cost": "15木 5石", "info": "住所(3x2)"},
		{"key": "2", "name": "练功房", "cost": "20木 15石", "info": "修炼加速(2x2)"},
		{"key": "3", "name": "炼丹房", "cost": "15木 20石", "info": "炼丹(2x2)"},
		{"key": "4", "name": "农田", "cost": "5木 2石", "info": "食物(2x2)"},
		{"key": "5", "name": "围墙", "cost": "3木 8石", "info": "防御(1x1)"},
		{"key": "6", "name": "工作台", "cost": "8木", "info": "铁锭→铁剑"},
		{"key": "7", "name": "熔炉", "cost": "12石", "info": "铁矿x2→铁锭"},
		{"key": "8", "name": "炼丹台", "cost": "8木 12石", "info": "草药x2→金创药"},
		{"key": "9", "name": "篝火", "cost": "3木", "info": "浆果→烤浆果"},
	]

	for i in range(buildings.size()):
		var d = buildings[i]
		var y = 44 + i * 30
		var lbl = Label.new()
		lbl.text = "[" + d["key"] + "] " + d["name"] + "  " + d["cost"] + " " + d["info"]
		lbl.position = Vector2(24, y)
		UITheme.style_label(lbl, 13)
		panel.add_child(lbl)
		build_labels.append(lbl)

	var hint = Label.new()
	hint.text = "B/ESC=退出  数字键=选择\n鼠标选点(手边)  绿格=可建  左键=放置"
	hint.position = Vector2(24, 308)
	hint.size = Vector2(280, 36)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(hint, 10, UITheme.TEXT_DIM)
	panel.add_child(hint)

	# 挂到UI层（CanvasLayer），屏幕居中显示，不再跟随玩家世界坐标
	var ui_layer = get_node_or_null("/root/Main/World/UI")
	if ui_layer:
		ui_layer.add_child(build_menu)
	else:
		get_parent().add_child(build_menu)

func _refresh_build_labels():
	for i in range(build_labels.size()):
		if build_selected_index == i:
			build_labels[i].add_theme_color_override("font_color", Color(1, 0.9, 0.2))
		else:
			build_labels[i].add_theme_color_override("font_color", Color(1, 1, 1))

# ---- 建造放置预览：按选中建筑在落点画绿/红幽灵格，让玩家知道会建到哪里 ----
var build_ghost: Node2D = null
var build_ghost_cells: Array = []
const BUILD_RANGE = 56.0  # 只能在手边建造：约两格内，超出钳回

func _ensure_build_ghost():
	if build_ghost:
		return
	build_ghost = Node2D.new()
	build_ghost.name = "BuildGhost"
	build_ghost.z_index = 30
	build_ghost.visible = false
	get_parent().add_child(build_ghost)
	for i in range(9):
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(-11, -11), Vector2(11, -11), Vector2(11, 11), Vector2(-11, 11)])
		poly.visible = false
		build_ghost.add_child(poly)
		build_ghost_cells.append(poly)

func _update_build_ghost():
	var tpl = GameManager.selected_building
	if state != State.BUILD or tpl == null:
		if build_ghost:
			build_ghost.visible = false
		return
	if _is_mouse_over_ui():
		# 鼠标悬停建造菜单时不显示预览，防误判
		if build_ghost:
			build_ghost.visible = false
		return
	_ensure_build_ghost()
	build_ghost.visible = true
	# 饥荒式：预览跟随鼠标位置吸附网格，但限制在玩家周围放置范围内
	var mouse = get_global_mouse_position()
	var dir = mouse - global_position
	if dir.length() > BUILD_RANGE:
		mouse = global_position + dir.normalized() * BUILD_RANGE
	var pos = mouse
	pos.x = snapped(pos.x, BUILD_OFFSET)
	pos.y = snapped(pos.y, BUILD_OFFSET)
	build_ghost.global_position = pos
	var ok = _is_area_buildable(pos, tpl.size_x, tpl.size_y)
	var col = Color(0.35, 1, 0.4, 0.38) if ok else Color(1, 0.3, 0.3, 0.45)
	var n: int = tpl.size_x * tpl.size_y
	for i in range(build_ghost_cells.size()):
		if i < n:
			var sx: int = i % int(tpl.size_x)
			var sy: int = i / int(tpl.size_x)
			build_ghost_cells[i].position = Vector2(sx * BUILD_OFFSET + BUILD_OFFSET / 2, sy * BUILD_OFFSET + BUILD_OFFSET / 2)
			build_ghost_cells[i].color = col
			build_ghost_cells[i].visible = true
		else:
			build_ghost_cells[i].visible = false

func _hide_build_ghost():
	if build_ghost:
		build_ghost.visible = false

func _process_build(delta):
	build_place_cooldown = max(build_place_cooldown - delta, 0.0)
	if Input.is_action_just_pressed("player_build"):
		_toggle_build()
		return
	# 饥荒式：建造状态下人物仍可自由移动（含疾跑），放置方位由鼠标决定
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		_update_facing(input_dir)
		var spd = SPEED
		if Input.is_action_pressed("player_sprint"):
			spd = SPRINT_SPEED
		velocity = input_dir * spd
		if hurt_timer <= 0.0:
			_play_anim("walk")
	else:
		velocity = Vector2.ZERO
		_play_anim("idle")
	move_and_slide()
	_update_build_ghost()
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
	elif Input.is_action_just_pressed("build_slot_6"):
		_select_building("工作台")
	elif Input.is_action_just_pressed("build_slot_7"):
		_select_building("熔炉")
	elif Input.is_action_just_pressed("build_slot_8"):
		_select_building("炼丹台")
	elif Input.is_action_just_pressed("build_slot_9"):
		_select_building("篝火")
	# 按住左键连放由冷却限制，避免一帧内放置多个
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and GameManager.selected_building != null:
		if build_place_cooldown <= 0 and not _is_mouse_over_ui():
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
		"工作台":
			tpl.building_name = "工作台"; tpl.building_type = "工作台"
			tpl.wood_cost = 8; tpl.stone_cost = 0
			tpl.size_x = 1; tpl.size_y = 1
			tpl.provides = "锻造"
			idx = 5
		"熔炉":
			tpl.building_name = "熔炉"; tpl.building_type = "熔炉"
			tpl.wood_cost = 0; tpl.stone_cost = 12
			tpl.size_x = 1; tpl.size_y = 1
			tpl.provides = "冶炼"
			idx = 6
		"炼丹台":
			tpl.building_name = "炼丹台"; tpl.building_type = "炼丹台"
			tpl.wood_cost = 8; tpl.stone_cost = 12
			tpl.size_x = 1; tpl.size_y = 1
			tpl.provides = "炼丹"
			idx = 7
		"篝火":
			tpl.building_name = "篝火"; tpl.building_type = "篝火"
			tpl.wood_cost = 3; tpl.stone_cost = 0
			tpl.size_x = 1; tpl.size_y = 1
			tpl.provides = "烹饪"
			idx = 8
	GameManager.selected_building = tpl
	build_selected_index = idx
	if build_menu and build_menu.visible:
		_refresh_build_labels()

func _place_building():
	var tpl = GameManager.selected_building
	if tpl == null:
		return
	if not GameManager.has_materials(tpl.wood_cost, tpl.stone_cost):
		print("[Build] 材料不足!")
		build_place_cooldown = 0.5
		return
	# 饥荒式：落点取幽灵预览当前位置（鼠标吸附点），而非玩家脚下
	var pos: Vector2
	if build_ghost and build_ghost.visible:
		pos = build_ghost.global_position
	else:
		pos = global_position
		pos.x = snapped(pos.x, BUILD_OFFSET)
		pos.y = snapped(pos.y, BUILD_OFFSET)
	# 检查占地是否为可通行的地面（不能放在水里/山上）
	if not _is_area_buildable(pos, tpl.size_x, tpl.size_y):
		print("[Build] 此处无法建造（水域或山地）!")
		build_place_cooldown = 0.5
		return
	build_place_cooldown = 0.3
	GameManager.consume_materials(tpl.wood_cost, tpl.stone_cost)
	# Phase C：站台类走 StationSystem（贴图道具+F键合成），不走通用建筑
	var st_sys = get_node_or_null("/root/Main/World/StationSystem")
	if st_sys and st_sys.STATION_DEFS.has(tpl.building_type):
		st_sys.place_station(tpl.building_type, pos)
		print("[Build] Placed station " + tpl.building_name + " at " + str(pos))
		return
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

func _is_area_buildable(pos: Vector2, sx: int, sy: int) -> bool:
	if _world_gen == null or not _world_gen.has_method("is_tile_blocking"):
		return true
	for x in range(sx):
		for y in range(sy):
			var center = pos + Vector2(x * BUILD_OFFSET + BUILD_OFFSET / 2, y * BUILD_OFFSET + BUILD_OFFSET / 2)
			if _world_gen.is_tile_blocking(center):
				return false
	return true

func _spawn_building_visual(pos: Vector2, tpl: BuildingTemplate):
	var bld_node = Node2D.new()
	bld_node.name = "Building_" + tpl.building_name
	bld_node.global_position = pos
	bld_node.y_sort_enabled = true
	var tile_tex = _building_tile_texture(tpl.building_type)
	var fallback_color = _building_color(tpl.building_type)
	for sx in range(tpl.size_x):
		for sy in range(tpl.size_y):
			var cell_pos = Vector2(sx * BUILD_OFFSET + BUILD_OFFSET / 2, sy * BUILD_OFFSET + BUILD_OFFSET / 2)
			if tile_tex:
				var sprite = Sprite2D.new()
				sprite.texture = tile_tex
				sprite.position = cell_pos
				sprite.z_index = 1
				bld_node.add_child(sprite)
			else:
				# 纹理缺失时使用色块回退，保证建筑可见
				var rect = ColorRect.new()
				rect.color = fallback_color
				rect.size = Vector2(BUILD_OFFSET - 4, BUILD_OFFSET - 4)
				rect.position = cell_pos - rect.size / 2
				rect.z_index = 1
				bld_node.add_child(rect)
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
	# 运行时直接解码PNG（新纹理无import数据，load()不可靠）
	return TextureGen.load_png_texture(path)

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
		# 失败也给可见反馈（此前仅print静默）
		GameManager.emit_event("门派", "声望不足（需%d），%s掌门婉拒了你" % [int(c.join_condition_reputation), cname], 2)
		return
	GameManager.join_clan(cname)

func _show_player_clan():
	# P键改走QuickMenu门派面板（此前仅print控制台无UI）
	var qm = get_node_or_null("/root/Main/World/UI/QuickMenu")
	if qm and qm.has_method("_open_my_clan_panel"):
		qm._open_my_clan_panel()

func _betray_clan():
	if GameManager.player_clan == null:
		print("[Clan] Not in any clan")
		GameManager.emit_event("门派", "你尚未加入任何门派，无从背叛", 2)
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

func take_hit_with_stance(damage: float, from_pos: Vector2 = Vector2(INF, INF)):
	# Phase D：死亡后免疫；from_pos为攻击者位置（mob传入），用于微击退
	if _is_dead or state == State.DEAD:
		return
	var actual_damage = damage
	var staggered := false
	if combat_stance:
		actual_damage = combat_stance.on_hit_received(damage)
		if state == State.BLOCK:
			combat_stance.on_block_hit()
		if combat_stance.is_staggered():
			staggered = true
			enter_stagger()
	# 受击反馈：红闪+hurt动画（大硬直另有STAGGER表现，不叠加hurt动画）
	hurt_timer = 0.32
	var tw := create_tween()
	modulate = Color(1.0, 0.35, 0.35)
	tw.tween_property(self, "modulate", Color.WHITE, 0.22)
	if not staggered:
		_play_anim("hurt")
	if from_pos.x != INF:
		var push := (global_position - from_pos).normalized() * 9.0
		var pt := create_tween()
		pt.tween_property(self, "global_position", global_position + push, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_camera_shake(3.0, 0.12)
	_sfx("hurt")
	GameManager.take_hit(actual_damage)
	# 气血归零立即接死亡闭环（不等下一帧轮询）
	if GameManager.health <= 0.0:
		var ds = _get_death_system()
		if ds:
			_hook_death_signals()
			ds.check_death()

# ---- Phase D 死亡闭环 ----
func _get_death_system():
	return get_node_or_null("/root/Main/DeathSystem")

func _hook_death_signals():
	if _ds_hooked:
		return
	var ds = _get_death_system()
	if ds == null:
		return
	_ds_hooked = true
	ds.player_died.connect(play_death_visual)
	ds.player_respawned.connect(on_respawn_reset)

func play_death_visual(_outcome: int = -1):
	if _is_dead:
		return
	_is_dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	attack_indicator.visible = false
	if target_indicator:
		target_indicator.visible = false
	anim.speed_scale = 1.0
	modulate = Color.WHITE
	if GameManager.is_meditating:
		GameManager.stop_meditation()
	_play_anim("death")
	_sfx("player_die")
	print("[Player] 死亡: 播放 death_" + _dir_suffix())

func on_respawn_reset():
	_is_dead = false
	state = State.IDLE
	stagger_timer = 0.0
	hurt_timer = 0.0
	current_skill = null
	attack_indicator.visible = false
	modulate = Color.WHITE
	_play_anim("idle")
	print("[Player] 复位完成回到IDLE")

# Phase D 音效快捷入口（AudioController缺失时静默降级）
func _sfx(sfx_name: String, volume_db: float = -6.0, pitch: float = 1.0):
	var ac = get_tree().get_first_node_in_group("audio_controller")
	if ac and ac.has_method("play_sfx"):
		ac.play_sfx(sfx_name, volume_db, pitch)
