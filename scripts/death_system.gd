extends Node

# 死亡与继承机制 - 根据正邪值和声望触发不同结局

enum DeathOutcome { RESCUED, IMPRISONED, INHERITANCE }

var is_dead: bool = false
var death_outcome: int = -1
var inheritance_data: Dictionary = {}
var respawn_timer: float = 0.0
var respawn_delay: float = 3.0
var imprisonment_timer: float = 0.0
var imprisonment_duration: float = 30.0  # 囚禁30秒
var inheritance_count: int = 0  # 传承代数

signal player_died(outcome)
signal player_respawned
signal inheritance_started(generation)

func _process(delta):
	if is_dead:
		respawn_timer -= delta
		if respawn_timer <= 0:
			_apply_outcome()
	# 囚禁计时
	if imprisonment_timer > 0:
		imprisonment_timer -= delta
		if imprisonment_timer <= 0:
			_free_from_prison()

func check_death():
	if is_dead:
		return
	if GameManager.health <= 0:
		trigger_death()

func trigger_death():
	if is_dead:
		return
	is_dead = true
	respawn_timer = respawn_delay
	
	# 根据正邪值和声望决定结局
	death_outcome = _determine_outcome()
	inheritance_data = _prepare_inheritance_data()
	
	var outcome_names = ["被救", "囚禁", "传承"]
	print("[Death] 玩家死亡! 结局: " + outcome_names[death_outcome])
	player_died.emit(death_outcome)

func _determine_outcome() -> int:
	var morality = GameManager.morality
	var reputation = GameManager.reputation
	
	# 正派高声望 → 被救
	if morality >= 30 and reputation >= 50:
		return DeathOutcome.RESCUED
	# 邪派低声望 → 囚禁
	if morality <= -30 and reputation < 30:
		return DeathOutcome.IMPRISONED
	# 中间情况：声望高→被救，声望低→囚禁
	if reputation >= 30:
		return DeathOutcome.RESCUED
	elif reputation < 10:
		return DeathOutcome.IMPRISONED
	# 默认：传承
	return DeathOutcome.INHERITANCE

func _prepare_inheritance_data() -> Dictionary:
	var data = {}
	data["morality"] = GameManager.morality
	data["reputation"] = GameManager.reputation
	data["gold"] = GameManager.gold
	data["unlocked_skills"] = GameManager.unlocked_skills.duplicate()
	data["clan_name"] = GameManager.player_clan.clan_name if GameManager.player_clan else ""
	data["contribution"] = GameManager.contribution
	data["player_rank"] = GameManager.player_rank
	data["npc_relations"] = GameManager.npc_relations.duplicate()
	data["buildings"] = GameManager.buildings.duplicate()
	data["invited_npcs"] = GameManager.invited_npcs.duplicate()
	# 继承部分武学（随机选一半）
	var inherited_skills = []
	var skill_list = GameManager.unlocked_skills.duplicate()
	skill_list.shuffle()
	var inherit_count = max(1, skill_list.size() / 2)
	for i in range(min(inherit_count, skill_list.size())):
		inherited_skills.append(skill_list[i])
	data["inherited_skills"] = inherited_skills
	# 继承部分金钱（30%）
	data["inherited_gold"] = int(GameManager.gold * 0.3)
	# 继承部分关系（好感度减半）
	var inherited_relations = {}
	for key in GameManager.npc_relations.keys():
		if not key.ends_with("_type"):
			inherited_relations[key] = GameManager.npc_relations[key] * 0.5
	data["inherited_relations"] = inherited_relations
	return data

func _apply_outcome():
	is_dead = false
	if death_outcome == DeathOutcome.RESCUED:
		_apply_rescue()
	elif death_outcome == DeathOutcome.IMPRISONED:
		_apply_imprisonment()
	elif death_outcome == DeathOutcome.INHERITANCE:
		_apply_inheritance()
	player_respawned.emit()

func _apply_rescue():
	# 被救：恢复部分气血，损失部分金钱
	GameManager.health = 40.0
	GameManager.hunger = 50.0
	GameManager.qi = GameManager.max_qi * 0.5
	GameManager.poison = 0
	var gold_loss = int(GameManager.gold * 0.2)
	GameManager.modify_gold(-gold_loss)
	GameManager.emit_event("获救", "路过的侠士将你救起，损失了" + str(gold_loss) + "铜钱", 4)
	print("[Death] 被救! 损失" + str(gold_loss) + "铜钱")

func _apply_imprisonment():
	# 囚禁：关押一段时间，损失金钱和声望
	GameManager.health = 20.0
	GameManager.hunger = 30.0
	GameManager.qi = GameManager.max_qi * 0.2
	GameManager.poison = 0
	imprisonment_timer = imprisonment_duration
	var gold_loss = int(GameManager.gold * 0.4)
	GameManager.modify_gold(-gold_loss)
	GameManager.modify_reputation(-10)
	GameManager.modify_morality(-5)
	GameManager.emit_event("囚禁", "你被关入大牢，损失" + str(gold_loss) + "铜钱，声望-10", 5)
	print("[Death] 囚禁! 损失" + str(gold_loss) + "铜钱，关押" + str(imprisonment_duration) + "秒")

func _apply_inheritance():
	# 传承：以弟子/子女身份继续，继承部分武学和关系
	inheritance_count += 1
	var gen_str = "第" + str(inheritance_count) + "代传人"
	
	# 重置基础属性
	GameManager.health = 80.0
	GameManager.hunger = 80.0
	GameManager.qi = GameManager.max_qi * 0.6
	GameManager.poison = 0
	GameManager.morality = 0
	GameManager.reputation = max(GameManager.reputation * 0.3, 0)
	GameManager.gold = inheritance_data.get("inherited_gold", 0)
	
	# 继承武学
	GameManager.unlocked_skills.clear()
	var inherited_skills = inheritance_data.get("inherited_skills", [])
	for skill in inherited_skills:
		if not GameManager.unlocked_skills.has(skill):
			GameManager.unlocked_skills.append(skill)
	
	# 继承关系（减半）
	GameManager.npc_relations.clear()
	var inherited_relations = inheritance_data.get("inherited_relations", {})
	for key in inherited_relations:
		GameManager.npc_relations[key] = inherited_relations[key]
	
	# 门派关系：降为外门弟子
	if GameManager.player_clan != null:
		GameManager.player_rank = 0
		GameManager.contribution = int(GameManager.contribution * 0.3)
	
	GameManager.emit_event("传承", "你以" + gen_str + "的身份继续江湖路，继承了" + str(inherited_skills.size()) + "门武学", 6)
	inheritance_started.emit(inheritance_count)
	print("[Death] 传承! " + gen_str + " 继承" + str(inherited_skills.size()) + "门武学，" + str(GameManager.gold) + "铜钱")

func _free_from_prison():
	GameManager.emit_event("出狱", "刑满释放，重获自由", 3)
	print("[Death] 出狱!")

func is_imprisoned() -> bool:
	return imprisonment_timer > 0

func get_death_outcome_name() -> String:
	if death_outcome == DeathOutcome.RESCUED:
		return "被救"
	elif death_outcome == DeathOutcome.IMPRISONED:
		return "囚禁"
	elif death_outcome == DeathOutcome.INHERITANCE:
		return "传承"
	return "未知"

func get_inheritance_info() -> String:
	if inheritance_data.is_empty():
		return "无传承数据"
	var info = "传承代数: " + str(inheritance_count) + "\n"
	info += "继承武学: " + str(inheritance_data.get("inherited_skills", []).size()) + "门\n"
	info += "继承铜钱: " + str(inheritance_data.get("inherited_gold", 0)) + "\n"
	info += "继承关系: " + str(inheritance_data.get("inherited_relations", {}).size()) + "条"
	return info
