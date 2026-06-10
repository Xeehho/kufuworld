extends Node

var active_quests: Array = []
var completed_quests: Array = []
var available_quests: Array = []
var quest_id_counter: int = 0

var quest_rules = [
	{
		"category": "除恶",
		"title_tpl": "铲除{target}",
		"desc_tpl": "听闻{target}作恶多端、欺压百姓，请大侠出手为民除害！",
		"target_count": 3,
		"reward_gold": 80,
		"reward_rep": 20,
		"reward_morality": 15,
		"condition": "morality > -20"
	},
	{
		"category": "护送",
		"title_tpl": "护送商队",
		"desc_tpl": "江南商会需要护送一批货物穿越危险地带，报酬丰厚。",
		"target_count": 1,
		"reward_gold": 120,
		"reward_rep": 10,
		"reward_morality": 5,
		"condition": "reputation > 10"
	},
	{
		"category": "寻宝",
		"title_tpl": "探寻{place}秘宝",
		"desc_tpl": "古籍记载{place}藏有失传已久的宝物，前往一探究竟。",
		"target_count": 1,
		"reward_gold": 200,
		"reward_rep": 30,
		"reward_morality": 0,
		"condition": "reputation > 30"
	},
	{
		"category": "讨伐",
		"title_tpl": "讨伐{target}",
		"desc_tpl": "附近出现了{target}，百姓惊恐不安。请前往将其击败。",
		"target_count": 5,
		"reward_gold": 150,
		"reward_rep": 25,
		"reward_morality": 10,
		"condition": "morality > -50"
	},
	{
		"category": "比武",
		"title_tpl": "比武大会挑战",
		"desc_tpl": "参加江湖比武大会，在擂台上证明自己的实力。",
		"target_count": 3,
		"reward_gold": 100,
		"reward_rep": 40,
		"reward_morality": 0,
		"condition": "reputation > 50"
	},
	{
		"category": "暗杀",
		"title_tpl": "暗杀{target}",
		"desc_tpl": "有人出高价买{target}的性命。行动隐秘，不留痕迹。",
		"target_count": 1,
		"reward_gold": 300,
		"reward_rep": -20,
		"reward_morality": -25,
		"condition": "morality < 20"
	},
	{
		"category": "采药",
		"title_tpl": "采集灵草",
		"desc_tpl": "药铺急需一批稀有药材，前往山野间采集。",
		"target_count": 5,
		"reward_gold": 60,
		"reward_rep": 5,
		"reward_morality": 5,
		"condition": "true"
	},
	{
		"category": "传功",
		"title_tpl": "指点后辈",
		"desc_tpl": "门派中有年轻弟子遇到武学瓶颈，以你的见识不妨指点一二。",
		"target_count": 1,
		"reward_gold": 30,
		"reward_rep": 15,
		"reward_morality": 10,
		"reward_contribution": 20,
		"condition": "player_clan and contribution > 50"
	},
]

var place_names: Array = ["幽谷", "荒庙", "古墓", "密林", "雪峰", "断崖", "深潭", "废墟", "古塔", "石窟"]
var enemy_names: Array = ["山贼", "悍匪", "恶霸", "凶兽", "魔教弟子", "叛徒", "妖道", "毒王"]

func _ready():
	refresh_available_quests()
	print("[Quest] System ready - " + str(quest_rules.size()) + " rule templates")

func refresh_available_quests():
	available_quests.clear()
	var rng = RandomNumberGenerator.new()
	for rule in quest_rules:
		if not _check_condition(rule["condition"]):
			continue
		quest_id_counter += 1
		var q = Quest.new()
		q.quest_id = "Q" + str(quest_id_counter)
		q.category = rule["category"]
		var place = place_names[rng.randi() % place_names.size()]
		var enemy = enemy_names[rng.randi() % enemy_names.size()]
		var title = rule["title_tpl"]
		title = title.replace("{place}", place)
		title = title.replace("{target}", enemy)
		q.title = title
		var desc = rule["desc_tpl"]
		desc = desc.replace("{place}", place)
		desc = desc.replace("{target}", enemy)
		q.description = desc
		q.target_count = rule["target_count"]
		q.reward_gold = rule["reward_gold"] + rng.randi_range(-20, 30)
		q.reward_reputation = rule["reward_rep"]
		q.reward_morality = rule["reward_morality"]
		q.reward_contribution = rule.get("reward_contribution", 0)
		q.difficulty = _calc_difficulty(q.target_count, q.reward_gold)
		available_quests.append(q)

func _check_condition(cond: String) -> bool:
	match cond:
		"true": return true
		"morality > -20": return GameManager.morality > -20
		"morality > -50": return GameManager.morality > -50
		"morality < 20": return GameManager.morality < 20
		"reputation > 10": return GameManager.reputation > 10
		"reputation > 30": return GameManager.reputation > 30
		"reputation > 50": return GameManager.reputation > 50
		"player_clan and contribution > 50":
			return GameManager.player_clan != null and GameManager.contribution > 50
	return true

func _calc_difficulty(count: int, gold: int) -> int:
	var d = 1
	if count >= 5 or gold >= 200: d = 3
	elif count >= 3 or gold >= 120: d = 2
	return d

func accept_quest(index: int) -> bool:
	if index < 0 or index >= available_quests.size():
		return false
	var q = available_quests[index]
	if active_quests.size() >= 5:
		print("[Quest] Max active quests reached")
		return false
	q.is_active = true
	active_quests.append(q)
	available_quests.remove_at(index)
	print("[Quest] Accepted: " + q.title)
	GameManager.world_state_changed.emit()
	return true

func progress_quest(quest_id: String, amount: int = 1):
	for q in active_quests:
		if q.quest_id == quest_id and q.is_active:
			q.current_count = min(q.current_count + amount, q.target_count)
			if q.current_count >= q.target_count and not q.is_completed:
				_complete_quest(q)

func _complete_quest(q: Quest):
	q.is_completed = true
	q.is_active = false
	GameManager.gold += q.reward_gold
	GameManager.modify_reputation(q.reward_reputation)
	GameManager.modify_morality(q.reward_morality)
	if q.reward_contribution > 0 and GameManager.player_clan != null:
		GameManager.add_contribution(q.reward_contribution)
	active_quests.erase(q)
	completed_quests.append(q)
	GameManager.emit_event("任务完成", q.title + " 已完成! 奖励:" + str(q.reward_gold) + "金", 3)
	GameManager.world_state_changed.emit()

func abandon_quest(quest_id: String):
	for i in range(active_quests.size()):
		if active_quests[i].quest_id == quest_id:
			active_quests[i].is_active = false
			active_quests.remove_at(i)
			print("[Quest] Abandoned: " + quest_id)
			return

func get_active_quests() -> Array:
	return active_quests

func get_available_quests() -> Array:
	return available_quests
