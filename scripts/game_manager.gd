extends Node

signal world_state_changed
signal relation_changed(a, b, new_value)
signal world_event(title, body, importance)
signal story_stage_changed(stage)
signal player_appearance_changed(app: String)

var morality: float = 0.0
var reputation: float = 0.0
var gold: int = 100  # 初始盘缠，保证商店系统开局可用
var qi: float = 100.0
var max_qi: float = 100.0

# 主线剧情进度（完成主N后=N；0=序章未开始）。定义见 docs/主线剧情设计.md §四
var story_stage: int = 0

# 玩家双外观（穿越换装）：modern=穿越前现代装（MW原样）/ tang=穿越后唐装
# 帧目录 sprites/player_modern/ vs sprites/player/；剧情经 apply_story_effects("player_skin") 切换
var player_appearance: String = "modern"

func player_skin_root() -> String:
	return "res://sprites/player_modern/" if player_appearance == "modern" else "res://sprites/player/"

func set_player_appearance(app: String):
	if player_appearance == app:
		return
	player_appearance = app
	player_appearance_changed.emit(app)
	print("[GameManager] 玩家外观切换 -> %s" % app)

# W4：特性开关镜像（读 WorldFeatures.FLAG，任务冻结等系统统一经此查询）
var feature_flags: Dictionary = WorldFeatures.FLAG

var active_inner_skill: InnerSkill = null
var inner_skill_progress: float = 0.0
var current_environment: String = ""
var is_meditating: bool = false
var meditation_timer: float = 0.0
var debuff_active: bool = false

var npc_relations: Dictionary = {}

var world_hour: float = 8.0
var is_raining: bool = false
var is_snowing: bool = false
var is_daytime: bool = true

var hunger: float = 100.0
var health: float = 100.0
var poison: float = 0.0

var wood: int = 20
var stone: int = 15

var shelter_owner: String = ""
var invited_npcs: Array = []
var buildings: Array = []
var is_build_mode: bool = false
var selected_building: BuildingTemplate = null

var clans: Array = []
var player_clan: Clan = null
var player_rank: int = 0
var contribution: int = 0
var world_events: Array = []
var unlocked_skills: Array = []

const CLAN_RANKS = ["弟子", "内门弟子", "执事", "长老", "副掌门", "掌门"]
const CONTRIBUTION_THRESHOLDS = [0, 100, 300, 800, 2000, 5000]

const ELEMENT_CLASH: Dictionary = {
	"金": "木",
	"木": "土",
	"土": "水",
	"水": "火",
	"火": "金"
}

const RELATION_TYPES = ["师徒", "仇敌", "挚友", "爱慕", "中立", "同门"]

func _ready():
	_load_clans()
	_setup_initial_diplomacy()
	_equip_default_inner()

func _equip_default_inner():
	"""开局默认装备基础心法（青木长生功）。
	修"打坐无反应/无恢复进度"根因：此前active_inner_skill从未赋值→start_meditation永远静默拒绝"""
	var path := "res://resources/inner/青木长生功.tres"
	if ResourceLoader.exists(path):
		active_inner_skill = load(path)
		print("[Meditation] 默认心法已装备: " + str(active_inner_skill.skill_name))
	else:
		push_warning("[Meditation] 内功资源缺失: " + path)

func get_relation(id_a: String, id_b: String) -> float:
	var key = _relation_key(id_a, id_b)
	if npc_relations.has(key):
		return npc_relations[key]
	return 0.0

func modify_relation(id_a: String, id_b: String, delta: float, rel_type: String = "中立"):
	var key = _relation_key(id_a, id_b)
	if not npc_relations.has(key):
		npc_relations[key] = 0.0
	npc_relations[key] = clamp(npc_relations[key] + delta, -100, 100)
	relation_changed.emit(id_a, id_b, npc_relations[key])
	print("[Relation] " + id_a + " <-> " + id_b + " = " + str(npc_relations[key]))

func set_relation_type(id_a: String, id_b: String, rel_type: String):
	var key = _relation_key(id_a, id_b) + "_type"
	npc_relations[key] = rel_type

func get_relation_type(id_a: String, id_b: String) -> String:
	var key = _relation_key(id_a, id_b) + "_type"
	if npc_relations.has(key):
		return npc_relations[key]
	return "中立"

func get_all_relations_for(id_str: String) -> Dictionary:
	var result = {}
	for key in npc_relations.keys():
		if key.ends_with("_type"):
			continue
		if key.begins_with(id_str + "_") or key.ends_with("_" + id_str):
			result[key] = npc_relations[key]
	return result

func _relation_key(a: String, b: String) -> String:
	if a < b:
		return a + "_" + b
	return b + "_" + a

func modify_morality(amount: float):
	morality = clamp(morality + amount, -100.0, 100.0)
	world_state_changed.emit()

func modify_reputation(amount: float):
	reputation = max(reputation + amount, 0.0)
	world_state_changed.emit()

func modify_gold(amount: int):
	gold = max(gold + amount, 0)
	world_state_changed.emit()

func consume_qi(amount: float):
	qi = max(qi - amount, 0.0)
	world_state_changed.emit()

func restore_qi(amount: float):
	qi = min(qi + amount, max_qi)
	world_state_changed.emit()

func start_meditation():
	if active_inner_skill == null:
		print("[Meditation] 未装备内功心法")
		return
	is_meditating = true
	meditation_timer = 0.0

func stop_meditation():
	is_meditating = false

func _process(delta):
	if not is_meditating or active_inner_skill == null:
		_tick_survival(delta)
	else:
		_tick_survival(delta * 0.5)
	meditation_timer += delta
	if meditation_timer >= 1.0 and is_meditating and active_inner_skill != null:
		meditation_timer = 0.0
		_tick_cultivation()

var _survival_emit_accum := 0.0   # BugFix: 生存衰减每帧广播world_state_changed→全部监听UI每帧重刷（移动时"反复出现"感），节流至0.25s

func _tick_survival(delta):
	hunger = max(hunger - 0.5 * delta, 0)
	poison = max(poison - 0.1 * delta, 0)
	if poison > 50:
		health = max(health - 0.5 * delta, 0)
	# 节流广播：0.25s一次（数值变化粒度低，无需每帧惊动全部UI）
	_survival_emit_accum += delta
	if _survival_emit_accum >= 0.25:
		_survival_emit_accum = 0.0
		world_state_changed.emit()

func take_hit(damage: float):
	health = max(health - damage, 0)
	world_state_changed.emit()
	# 死亡检测
	if health <= 0:
		var ds = get_node_or_null("/root/Main/DeathSystem")
		if ds:
			ds.check_death()

func eat_food(amount: float):
	hunger = min(hunger + amount, 100)
	world_state_changed.emit()

func apply_poison(amount: float):
	poison = min(poison + amount, 100)
	world_state_changed.emit()

func has_materials(wood_req: int, stone_req: int) -> bool:
	return wood >= wood_req and stone >= stone_req

func consume_materials(wood_req: int, stone_req: int):
	wood = max(wood - wood_req, 0)
	stone = max(stone - stone_req, 0)
	world_state_changed.emit()

func add_building(bld: Dictionary):
	buildings.append(bld)
	world_state_changed.emit()

func invite_npc(npc_name: String) -> bool:
	if invited_npcs.has(npc_name):
		return false
	invited_npcs.append(npc_name)
	return true

func get_buildings_at(pos: Vector2) -> Array:
	var result: Array = []
	for b in buildings:
		var bp: Vector2 = b["position"]
		var sx: int = b["size_x"]
		var sy: int = b["size_y"]
		if pos.x >= bp.x and pos.x < bp.x + sx * 48 and pos.y >= bp.y and pos.y < bp.y + sy * 48:
			result.append(b)
	return result

func _tick_cultivation():
	var debuff = _check_element_clash()
	var progress = active_inner_skill.progress_per_tick
	
	if current_environment == active_inner_skill.required_location:
		progress *= 2.0
	
	if debuff:
		progress *= 0.3
		consume_qi(1.0)
		if not debuff_active:
			debuff_active = true
			print("[Meditation] 五行相克! 修炼效率降低，内力受损")
	# 打坐吐纳：每拍持续恢复内力（此前仅修炼圆满一次性回复，"打坐看不到恢复进度"）
	qi = minf(qi + 2.0, max_qi)
	
	inner_skill_progress += progress
	if inner_skill_progress >= active_inner_skill.max_progress:
		inner_skill_progress = active_inner_skill.max_progress
		qi = min(qi + active_inner_skill.qi_bonus * 0.5, max_qi)
		print("[Meditation] " + active_inner_skill.skill_name + " 修炼圆满!")
		is_meditating = false
		debuff_active = false
	world_state_changed.emit()

func _check_element_clash() -> bool:
	var self_element = active_inner_skill.element
	if ELEMENT_CLASH.has(self_element):
		var countered = ELEMENT_CLASH[self_element]
		if _env_has_element(countered):
			return true
	return false

func _env_has_element(element: String) -> bool:
	var env_elements = {
		"寒潭": "水",
		"火山": "火",
		"竹林": "木",
		"山巅": "金",
		"洞窟": "土",
		"墓地": "水"
	}
	if env_elements.has(current_environment):
		return env_elements[current_environment] == element
	return false

func _load_clans():
	clans.clear()
	var clan_dir = "res://resources/clans/"
	var dir = DirAccess.open(clan_dir)
	if dir == null:
		_create_default_clans()
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var c = load(clan_dir + file_name) as Clan
			if c:
				clans.append(c)
		file_name = dir.get_next()
	dir.list_dir_end()
	if clans.is_empty():
		_create_default_clans()
	print("[Clans] Loaded " + str(clans.size()) + " clans")

func _create_default_clans():
	_clan("少林寺","正派","少室山",95,2000,50,["金刚掌","罗汉拳","易筋经"])
	_clan("武当派","正派","武当山",90,1800,45,["太极拳","太极剑","纯阳无极功"])
	_clan("峨眉派","正派","峨眉山",75,1200,35,["峨眉剑法","玉女心经"])
	_clan("丐帮","正派","洛阳",85,800,60,["打狗棒法","降龙十八掌"])
	_clan("日月教","邪派","黑木崖",80,1500,40,["吸星大法","葵花宝典"])
	_clan("五毒教","邪派","苗疆",55,600,25,["五毒心经","千蛛万毒手"])
	_clan("华山派","中立","华山",65,900,30,["华山剑法","紫霞神功"])
	_clan("逍遥派","中立","灵鹫宫",70,1000,20,["北冥神功","天山六阳掌"])

func _clan(n: String, s: String, t: String, p: float, g: int, m: int, skills: Array):
	var c = Clan.new()
	c.clan_name = n; c.stance = s; c.territory = t
	c.power = p; c.gold = g; c.member_count = m
	c.mastery_skills = skills; c.description = n+" - "+s+"门派"
	clans.append(c)

func _setup_initial_diplomacy():
	for c in clans:
		if c.stance == "正派":
			for o in clans:
				if o != c and o.stance == "正派":
					if not c.allies.has(o.clan_name):
						c.allies.append(o.clan_name)
				if o.stance == "邪派":
					if not c.enemies.has(o.clan_name):
						c.enemies.append(o.clan_name)
		elif c.stance == "邪派":
			for o in clans:
				if o != c and o.stance == "正派":
					if not c.enemies.has(o.clan_name):
						c.enemies.append(o.clan_name)

func get_clan(name_str: String) -> Clan:
	for c in clans:
		if c.clan_name == name_str:
			return c
	return null

func set_diplomacy(clan_a: String, clan_b: String, relation: String):
	var a = get_clan(clan_a)
	var b = get_clan(clan_b)
	if not a or not b:
		return
	match relation:
		"ally":
			if not a.allies.has(b.clan_name): a.allies.append(b.clan_name)
			if not b.allies.has(a.clan_name): b.allies.append(a.clan_name)
			a.enemies.erase(b.clan_name); b.enemies.erase(a.clan_name)
			emit_event("外交变化", a.clan_name+"与"+b.clan_name+"结盟", 2)
		"enemy":
			if not a.enemies.has(b.clan_name): a.enemies.append(b.clan_name)
			if not b.enemies.has(a.clan_name): b.enemies.append(a.clan_name)
			a.allies.erase(b.clan_name); b.allies.erase(a.clan_name)
			emit_event("外交变化", a.clan_name+"与"+b.clan_name+"交恶", 2)
		"neutral":
			a.allies.erase(b.clan_name); b.allies.erase(a.clan_name)
			a.enemies.erase(b.clan_name); b.enemies.erase(a.clan_name)

func join_clan(clan_name: String) -> bool:
	if player_clan != null:
		print("[Clan] Already in " + player_clan.clan_name)
		return false
	var c = get_clan(clan_name)
	if c == null:
		return false
	if reputation < c.join_condition_reputation:
		print("[Clan] Reputation too low for " + clan_name)
		return false
	player_clan = c
	player_rank = 0
	contribution = 0
	for skill in c.mastery_skills:
		if not unlocked_skills.has(skill):
			unlocked_skills.append(skill)
	emit_event("门派加入", "你加入了"+clan_name+"，成为"+CLAN_RANKS[player_rank], 5)
	print("[Clan] Joined " + clan_name)
	world_state_changed.emit()
	return true

func add_contribution(amount: int):
	if player_clan == null:
		return
	contribution += amount
	var new_rank = player_rank
	for i in range(CONTRIBUTION_THRESHOLDS.size()):
		if contribution >= CONTRIBUTION_THRESHOLDS[i]:
			new_rank = i
	if new_rank > player_rank:
		player_rank = new_rank
		emit_event("门派晋升", "你晋升为"+player_clan.clan_name+CLAN_RANKS[player_rank], 4)
		print("[Clan] Promoted to " + CLAN_RANKS[player_rank])
	world_state_changed.emit()

func betray_clan():
	if player_clan == null:
		return
	var old_clan = player_clan.clan_name
	player_clan.power -= 10
	player_clan.member_count -= 1
	player_clan = null
	player_rank = 0
	contribution = 0
	emit_event("叛离门派", "你叛离了"+old_clan, 4)
	print("[Clan] Betrayed " + old_clan)
	world_state_changed.emit()

func handle_clan_annexation(annexer: Clan, target: Clan):
	target.power = 0
	annexer.power += target.power * 0.3
	annexer.gold += target.gold
	annexer.member_count += max(target.member_count / 2, 1)
	emit_event("门派吞并", annexer.clan_name+"吞并了"+target.clan_name, 6)
	print("[Clans] " + annexer.clan_name + " annexed " + target.clan_name)
	clans.erase(target)

func handle_clan_dissolution(target: Clan):
	emit_event("门派解散", target.clan_name+"势力衰败，自行解散", 5)
	print("[Clans] " + target.clan_name + " dissolved")
	clans.erase(target)

func emit_event(title: String, body: String, importance: int):
	world_events.append({"title": title, "body": body, "importance": importance, "time": world_hour})
	while world_events.size() > 50:
		world_events.pop_front()
	world_event.emit(title, body, importance)

func get_recent_events(count: int = 5) -> Array:
	var result: Array = []
	var start = max(world_events.size() - count, 0)
	for i in range(start, world_events.size()):
		result.append(world_events[i])
	return result

# ---------- 主线剧情支持 ----------

func advance_story_stage(n: int):
	if n > story_stage:
		story_stage = n
		story_stage_changed.emit(n)
		world_state_changed.emit()
		print("[Story] story_stage -> %d" % n)

# 主线/分支对话效果统一入口（声明式效果字典，供 main_story 与对话选项复用）
# 支持: morality/reputation/gold/hunger/wood/stone
#       relation(+relation_to 指定NPC名) / give_item(+give_count)
#       event_title(+event_body/event_importance 默认4)
#       player_skin(modern/tang——穿越换装，剧情节点挂此键切玩家外观)
func apply_story_effects(effects: Dictionary):
	if effects.is_empty():
		return
	if effects.has("player_skin"):
		set_player_appearance(str(effects["player_skin"]))
	if effects.has("morality"):
		modify_morality(effects["morality"])
	if effects.has("reputation"):
		modify_reputation(effects["reputation"])
	if effects.has("gold"):
		modify_gold(int(effects["gold"]))
	if effects.has("hunger"):
		eat_food(float(effects["hunger"]))
	if effects.has("wood"):
		wood = max(wood + int(effects["wood"]), 0)
		world_state_changed.emit()
	if effects.has("stone"):
		stone = max(stone + int(effects["stone"]), 0)
		world_state_changed.emit()
	if effects.has("relation") and effects.has("relation_to"):
		modify_relation("主角", str(effects["relation_to"]), float(effects["relation"]))
	if effects.has("give_item"):
		ItemFactory.give(str(effects["give_item"]), int(effects.get("give_count", 1)))
	if effects.has("event_title"):
		emit_event(str(effects["event_title"]), str(effects.get("event_body", "")),
			int(effects.get("event_importance", 4)))
