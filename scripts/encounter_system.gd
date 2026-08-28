extends Node

var encounters: Array = []
var active_encounter: Encounter = null
# 开局宽限期：避免游戏第一帧就强制触发奇遇弹出面板
var cooldown: float = 45.0
# 反馈调整：30s一发过于频繁，改为最长2分钟一次
const COOLDOWN_MAX = 120.0

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
		"health > 50", -100, 100, 0, 0, "城镇",
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

	# 11 - 山贼拦路
	encounters.append(_make_encounter("enc_011", "山贼拦路", "“此山是我开！”一伙山贼挥舞钢刀拦住去路。",
		"true", -100, 100, 0, 0, "山地",
		[_opt("杀出重围", "刀光剑影过后，山贼落荒而逃，丢下不少财物。", 80, -20, 5, 8, 8, 0),
		 _opt("破财免灾", "你交出买路钱，山贼哄笑着让开道路。", -50, 0, 0, -3),
		 _opt("绕路而行", "你翻山越岭绕开贼人，颇费了一番脚力。", 0, -10, 0, 0)], 0.2))

	# 12 - 乞丐讨饭
	encounters.append(_make_encounter("enc_012", "乞丐讨饭", "一位衣衫褴褛的老乞丐向你伸出破碗，目光浑浊却隐含精光。",
		"gold > 20", -100, 100, 0, 0, "城镇",
		[_opt("施舍百钱", "老乞丐接过铜钱，低声传你一句心法口诀。", -10, 30, 8, 5),
		 _opt("给些干粮", "老乞丐狼吞虎咽，临别赠你半张残破地图。", 0, 0, 5, 3),
		 _opt("挥手驱赶", "老乞丐深深看了你一眼，蹒跚而去。", 0, 0, -8, -5)], 0.22))

	# 13 - 比武招亲
	encounters.append(_make_encounter("enc_013", "比武招亲", "大户人家设下擂台比武招亲，台下人山人海，热闹非凡。",
		"reputation > 40", -100, 100, 40, 0, "城镇",
		[_opt("上台打擂", "你连胜三场技惊四座！虽婉拒婚事，名声却传遍全城。", 100, -25, 0, 20),
		 _opt("台下观战", "你观摩各路招式，若有所悟。", 0, 10, 0, 3),
		 _opt("转身离开", "喧嚣渐远，你继续自己的江湖路。", 0, 0, 0, 0)], 0.15))

	# 14 - 夜观天象
	encounters.append(_make_encounter("enc_014", "夜观天象", "夜深人静，你抬头望见紫微星大放异彩，似有玄机。",
		"is_daytime == false", -100, 100, 0, 0, "任意",
		[_opt("静心参悟", "星光如水流入眉心，你对武学有了新的领悟。", 0, 40, 0, 8),
		 _opt("盘膝打坐", "借星月之华修炼内功，事半功倍。", 0, 25, 0, 0),
		 _opt("倒头便睡", "天象再好，不如一觉到天明。", 0, 5, 0, 0)], 0.2))

	# 15 - 落水孩童
	encounters.append(_make_encounter("enc_015", "落水孩童", "河中传来呼救声，一个孩童正在水中挣扎！",
		"morality > -20", -20, 100, 0, 0, "水域附近",
		[_opt("跳水救人", "你救起孩童，村民敲锣打鼓感谢你。", 30, -15, 15, 15),
		 _opt("竹竿施救", "你急中生智用竹竿将其拉上岸，孩子家人千恩万谢。", 20, 0, 10, 8),
		 _opt("熟视无睹", "你加快脚步离开，呼救声渐渐听不见了。", 0, 0, -15, -10)], 0.18))

	# 16 - 秘境寻宝
	encounters.append(_make_encounter("enc_016", "秘境寻宝", "按残图指引，你在乱石间发现一处隐秘石缝，隐约有宝光透出。",
		"qi > 30", -100, 100, 0, 30, "山地",
		[_opt("探入取宝", "石缝中藏着前朝遗物，价值连城！", 150, -20, 0, 5, 5, 0),
		 _opt("小心查探", "你避开机关，只取了外围几件小物。", 50, 0, 0, 2),
		 _opt("疑有埋伏", "你怀疑是圈套，退了出来。", 0, 0, 0, 0)], 0.12))

	# 17 - 瘟疫村庄
	encounters.append(_make_encounter("enc_017", "瘟疫村庄", "路过一个村庄，村口挂着白幡，瘟疫正在蔓延。",
		"morality > 0", 0, 100, 0, 0, "任意",
		[_opt("留下施救", "你以内力为村民驱毒疗疾，耗尽心力却救了全村。", 50, -40, 20, 25),
		 _opt("赠药离开", "你留下些药材，略尽绵薄之力。", -20, 0, 10, 8),
		 _opt("绕道避开", "疫病凶险，你掩鼻匆匆绕过村庄。", 0, 0, -5, 0)], 0.15))

	# 18 - 剑客挑战
	encounters.append(_make_encounter("enc_018", "剑客挑战", "一名背负长剑的冷面剑客拦住你：“久闻大名，请赐教！”",
		"reputation > 50", -100, 100, 50, 0, "任意",
		[_opt("拔剑应战", "三十招后你险胜半招，剑客抱剑一揖：“后会有期！”", 0, -30, 0, 25, 10, 0),
		 _opt("以和为贵", "你拱手谢绝，剑客也不纠缠，飘然远去。", 0, 0, 0, 5),
		 _opt("转身就跑", "你施展轻功甩开剑客，颇为狼狈。", 0, -15, 0, -8)], 0.14))

	# 19 - 古寺听经
	encounters.append(_make_encounter("enc_019", "古寺听经", "深山古寺传来阵阵梵音，让人心神宁静。",
		"true", -100, 100, 0, 0, "山地",
		[_opt("入寺听经", "经文涤荡心灵，多日戾气一扫而空。", 0, 15, 10, 5),
		 _opt("上香祈福", "你虔诚上香，祈求江湖路顺遂。", -5, 5, 3, 3),
		 _opt("过门不入", "你双手合十行了一礼，继续赶路。", 0, 0, 0, 0)], 0.18))

	# 20 - 黑市交易
	encounters.append(_make_encounter("enc_020", "黑市交易", "阴暗巷子里，蒙面人低声兜售来路不明的宝物。",
		"gold > 100", -100, 30, 0, 0, "城镇",
		[_opt("买下宝物(150金)", "到手一看竟是稀世珍品，转手可翻数倍！", -150, 0, -5, 5),
		 _opt("讨价还价(80金)", "你三寸不烂之舌砍下大半价，捡了个漏。", -80, 0, -3, 2),
		 _opt("报官揭发", "蒙面人闻风而逃，官府赏你一笔线人费。", 40, 0, 10, 5)], 0.16))

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
	# 剧情对话进行中暂缓掷骰（冷却不消耗，对话结束后恢复原节奏）
	# 否则随机奇遇会经 _force_open_encounter 强制关闭主线对话，导致剧情断链
	if DialogManager.is_dialog_open():
		return
	# 击打怪物中不触发（出招/硬直窗口 或 贴身接战）；NPC交互菜单开着也不触发
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("is_in_combat") and pl.is_in_combat():
		return
	var spawner := get_node_or_null("/root/Main/World/NPCSpawner")
	if spawner and spawner.has_method("is_interaction_open") and spawner.is_interaction_open():
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
	if cond == "health > 50":
		return GameManager.health > 50
	if cond == "qi > 50":
		return GameManager.qi > 50
	if cond == "is_daytime == false":
		return not GameManager.is_daytime
	return true

func emit_signal_encounter_start(enc: Encounter):
	GameManager.emit_event("奇遇触发", "⚡ " + enc.title + "！已自动弹出面板处理", 5)
	print("[Encounter] Triggered: " + enc.title)

# 结算奇遇选项，返回结果字典供面板展示：
# {ok: bool, title: String, result_text: String, rewards: Array[Dictionary{text,good}], error: String}
# 铜钱不足时 ok=false 且 active_encounter 保持不清除，玩家可重新选择
func resolve_encounter(option_index: int) -> Dictionary:
	if active_encounter == null:
		return {"ok": false, "error": ""}
	if option_index < 0 or option_index >= active_encounter.options.size():
		active_encounter = null
		return {"ok": false, "error": ""}
	var opt = active_encounter.options[option_index] as EncounterOption
	print("[Encounter] Chose: " + opt.text + " -> " + opt.result_text)
	if opt.reward_gold < 0 and GameManager.gold < abs(opt.reward_gold):
		return {"ok": false, "error": "铜钱不足，无法选择此项！"}

	var rewards: Array = []
	if opt.reward_gold != 0:
		GameManager.modify_gold(opt.reward_gold)
		rewards.append({"text": "金钱 %s%d" % ["+" if opt.reward_gold > 0 else "", opt.reward_gold], "good": opt.reward_gold > 0})
	if opt.reward_qi > 0:
		GameManager.restore_qi(opt.reward_qi)
		rewards.append({"text": "内力 +%d" % int(opt.reward_qi), "good": true})
	elif opt.reward_qi < 0:
		GameManager.consume_qi(-opt.reward_qi)
		rewards.append({"text": "内力 %d" % int(opt.reward_qi), "good": false})
	if opt.reward_morality != 0:
		GameManager.modify_morality(opt.reward_morality)
		rewards.append({"text": "道德 %s%d" % ["+" if opt.reward_morality > 0 else "", int(opt.reward_morality)], "good": opt.reward_morality > 0})
	if opt.reward_reputation != 0:
		GameManager.modify_reputation(opt.reward_reputation)
		rewards.append({"text": "声望 %s%d" % ["+" if opt.reward_reputation > 0 else "", int(opt.reward_reputation)], "good": opt.reward_reputation > 0})
	if opt.damage > 0:
		GameManager.take_hit(opt.damage)
		rewards.append({"text": "受伤 生命 -%d" % int(opt.damage), "good": false})
	if opt.poison_amount > 0:
		GameManager.apply_poison(opt.poison_amount)
		rewards.append({"text": "中毒 %d" % int(opt.poison_amount), "good": false})
	if opt.unlock_skill != "":
		if not GameManager.unlocked_skills.has(opt.unlock_skill):
			GameManager.unlocked_skills.append(opt.unlock_skill)
		rewards.append({"text": "习得技能「%s」" % opt.unlock_skill, "good": true})

	var title = active_encounter.title
	active_encounter = null
	# 同步到江湖风云事件流
	var gain_text = ""
	for r in rewards:
		gain_text += (" " if gain_text == "" else "，") + r["text"]
	GameManager.emit_event("奇遇·" + title, opt.result_text + ("（" + gain_text + "）" if gain_text != "" else ""), 3)
	return {"ok": true, "title": title, "result_text": opt.result_text, "rewards": rewards}
