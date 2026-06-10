extends Node

var encounters: Array = []
var active_encounter: Encounter = null
var cooldown: float = 0.0
const COOLDOWN_MAX = 30.0

func _ready():
	_create_prototype_encounters()
	print("[Encounter] Ready - " + str(encounters.size()) + " prototype encounters")

func _create_prototype_encounters():

	# 1 - 悬崖秘洞
	encounters.append(_make_encounter("enc_001", "悬崖秘洞", "你在一处悬崖边发现了一个隐蔽的洞口，散发着幽光。",
		"true", -100, 100, 0, 0, "山地",
		[_opt("进入探索", "洞内刻满武学秘籍！你的内力大增。", 0, 50, 10, 10),
		 _opt("在洞口修炼", "沐浴洞中灵光，修为精进。", 0, 20, 5, 5),
		 _opt("离开", "你选择继续赶路。", 0, 0, 0, 0)], 0.2))

	# 2 - 高人传功
	encounters.append(_make_encounter("enc_002", "高人传功", "一位白发老者拦住去路，自称前辈高人，要传你绝学。",
		"reputation > 30", -100, 100, 30, 0, "任意",
		[_opt("恭敬拜师", "老者大笑三声，将毕生功力传与你！", 0, 100, 10, 20),
		 _opt("婉言谢绝", "老者微笑点头，赠你一本秘籍离去。", 100, 0, 5, 10),
		 _opt("怀疑是骗局", "老者叹了一声，飘然而去。", 0, 0, -5, 0)], 0.15))

	# 3 - 市井斗殴
	encounters.append(_make_encounter("enc_003", "市井斗殴", "闹市中一伙地痞正在欺负卖菜老人，围观群众敢怒不敢言。",
		"morality > -30", -30, 100, 0, 0, "城镇",
		[_opt("出手相助", "三拳两脚打跑了地痞，老人感激涕零。", 20, 0, 15, 10),
		 _opt("报官处理", "你去找了官府，但效率缓慢。老人还是受了伤。", 0, 0, 5, 2),
		 _opt("袖手旁观", "你转身离开，内心隐隐不安。", 0, 0, -10, 0)], 0.25))

	# 4 - 神秘商人
	encounters.append(_make_encounter("enc_004", "神秘商人", "一个穿黑袍的商人从暗处现身，展示各种稀奇古怪的货物。",
		"gold > 50", -100, 100, 0, 0, "任意",
		[_opt("买下古剑(200金)", "这把剑寒气逼人，品质非凡！", -200, 0, 0, 5),
		 _opt("买下丹方(100金)", "丹方记录了失传的炼丹秘术。", -100, 0, 0, 3),
		 _opt("不感兴趣", "商人哼了一声遁入暗影。", 0, 0, 0, 0)], 0.2))

	# 5 - 毒蛇袭击
	encounters.append(_make_encounter("enc_005", "毒蛇袭击", "草丛中窜出一条毒蛇，直扑而来！",
		"true", -100, 100, 0, 0, "森林",
		[_opt("闪避反击", "你灵巧避开，一掌击毙毒蛇。", 0, 0, 5, 3),
		 _opt("用内力逼退", "内力一震，毒蛇逃回草丛。消耗了内力。", 0, -20, 0, 0),
		 _opt("被咬伤了", "来不及反应，毒牙咬入手臂。", 0, 0, 0, 0, 10, 15)], 0.18))

	# 6 - 河畔渔翁
	encounters.append(_make_encounter("enc_006", "河畔渔翁", "河畔一位渔翁正在钓鱼，看起来悠闲自在。",
		"morality > -50", -50, 100, 0, 0, "水域附近",
		[_opt("坐下聊天", "渔翁与你畅谈人生哲理，如醍醐灌顶。", 0, 0, 5, 8),
		 _opt("要一条鱼吃", "渔翁慷慨送鱼，体力恢复了。", 0, 0, 3, 2),
		 _opt("抢走鱼篓", "渔翁大怒，与同来的人群起而攻。", 50, 0, -20, -10)], 0.22))

	# 7 - 荒庙夜宿
	encounters.append(_make_encounter("enc_007", "荒庙夜宿", "天色已晚，一间破庙出现在路边。进去歇息吗？",
		"is_daytime == false", -100, 100, 0, 0, "任意",
		[_opt("安心歇息", "一夜安稳，体力完全恢复。", 0, 0, 0, 5),
		 _opt("保持警惕", "半夜听到动静，原来是窃贼！你将其制服。", 30, 0, 5, 3),
		 _opt("继续赶路", "你决定不在这种地方停留。", 0, -10, 0, 0)], 0.28))

	# 8 - 酒馆斗酒
	encounters.append(_make_encounter("enc_008", "酒馆斗酒", "几位江湖豪客正在比拼酒量，看到你便邀你加入。",
		"stamina > 50", -100, 100, 0, 0, "城镇",
		[_opt("加入斗酒", "豪饮三大碗！豪客们对你刮目相看。", 20, -30, 0, 12),
		 _opt("观战助兴", "你在旁边叫好，也分到几两散碎银子。", 10, 0, 0, 2),
		 _opt("敬谢不敏", "豪客们略有失望，但并未强求。", 0, 0, 0, 0)], 0.2))

	# 9 - 古墓奇遇
	encounters.append(_make_encounter("enc_009", "古墓奇遇", "一座古墓的石门半开，阴风阵阵。",
		"qi > 50", -100, 100, 0, 50, "洞穴",
		[_opt("深入探索", "墓中发现僵尸，一番苦战后找到宝物！", 200, -40, 0, 15, 5, 0),
		 _opt("门口祭拜", "你对古人行礼致敬，感受到一股暖意。", 0, 10, 5, 3),
		 _opt("赶紧离开", "你感觉到了危险气息，原路返回。", 0, 0, 0, 0)], 0.12))

	# 10 - 侠侣相遇
	encounters.append(_make_encounter("enc_010", "侠侣相遇", "一位独行侠客与你同路，言语间颇为投机。",
		"reputation > 20", -100, 100, 20, 0, "任意",
		[_opt("结伴同行", "一路相谈甚欢，临别互赠信物。", 0, 0, 10, 15),
		 _opt("切磋武艺", "点到为止的比试，互相受益匪浅。", 0, -15, 5, 10),
		 _opt("独自离去", "侠客微微一笑，策马离去。", 0, 0, 0, 0)], 0.18))

func _make_encounter(id: String, title: String, desc: String, cond: String,
		min_m: float, max_m: float, min_r: float, min_q: float, location: String,
		options: Array, rarity: float) -> Encounter:
	var e = Encounter.new()
	e.encounter_id = id
	e.title = title
	e.description = desc
	e.trigger_condition = cond
	e.min_morality = min_m
	e.max_morality = max_m
	e.min_reputation = min_r
	e.min_qi = min_q
	e.location_hint = location
	e.options = options
	e.rarity = rarity
	return e

func _opt(text: String, result: String, gold: int = 0, qi: float = 0,
		morality: float = 0, rep: float = 0, damage: float = 0, poison: float = 0,
		unlock: String = "") -> EncounterOption:
	var o = EncounterOption.new()
	o.text = text
	o.result_text = result
	o.reward_gold = gold
	o.reward_qi = qi
	o.reward_morality = morality
	o.reward_reputation = rep
	o.damage = damage
	o.poison_amount = poison
	o.unlock_skill = unlock
	return o

func _process(delta):
	if active_encounter != null:
		return
	cooldown -= delta
	if cooldown > 0:
		return
	cooldown = COOLDOWN_MAX
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for enc in encounters:
		if rng.randf() > enc.rarity:
			continue
		if not _check_encounter_condition(enc):
			continue
		active_encounter = enc
		emit_signal_encounter_start(enc)
		break

func _check_encounter_condition(enc: Encounter) -> bool:
	if enc.min_morality > -99 and GameManager.morality < enc.min_morality:
		return false
	if enc.max_morality < 99 and GameManager.morality > enc.max_morality:
		return false
	if GameManager.reputation < enc.min_reputation:
		return false
	if GameManager.qi < enc.min_qi:
		return false
	var cond = enc.trigger_condition
	if cond == "true":
		return true
	if cond == "morality > -30":
		return GameManager.morality > -30
	if cond == "morality > -50":
		return GameManager.morality > -50
	if cond == "reputation > 30":
		return GameManager.reputation > 30
	if cond == "reputation > 20":
		return GameManager.reputation > 20
	if cond == "gold > 50":
		return GameManager.gold > 50
	if cond == "stamina > 50":
		return GameManager.stamina > 50
	if cond == "qi > 50":
		return GameManager.qi > 50
	if cond == "is_daytime == false":
		return not GameManager.is_daytime
	return true

func emit_signal_encounter_start(enc: Encounter):
	GameManager.emit_event("奇遇触发", enc.title + " - " + enc.description, 5)
	print("[Encounter] Triggered: " + enc.title)

func resolve_encounter(option_index: int):
	if active_encounter == null:
		return
	if option_index < 0 or option_index >= active_encounter.options.size():
		active_encounter = null
		return
	var opt = active_encounter.options[option_index] as EncounterOption
	print("[Encounter] Chose: " + opt.text + " -> " + opt.result_text)
	if opt.reward_gold < 0 and GameManager.gold < abs(opt.reward_gold):
		DialogManager.show_dialog("奇遇", ["铜钱不足，无法选择此项!"])
		return
	GameManager.modify_gold(opt.reward_gold)
	if opt.reward_qi > 0:
		GameManager.restore_qi(opt.reward_qi)
	elif opt.reward_qi < 0:
		GameManager.consume_qi(-opt.reward_qi)
	if opt.reward_morality != 0:
		GameManager.modify_morality(opt.reward_morality)
	if opt.reward_reputation != 0:
		GameManager.modify_reputation(opt.reward_reputation)
	if opt.damage > 0:
		GameManager.take_hit(opt.damage)
	if opt.poison_amount > 0:
		GameManager.apply_poison(opt.poison_amount)
	if opt.unlock_skill != "":
		if not GameManager.unlocked_skills.has(opt.unlock_skill):
			GameManager.unlocked_skills.append(opt.unlock_skill)
	DialogManager.show_dialog("奇遇", [active_encounter.title, opt.result_text])
	active_encounter = null
