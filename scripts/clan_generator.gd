@tool
extends Node

func _ready():
	_generate_all()
	if not Engine.is_editor_hint():
		get_tree().quit()

func _generate_all():
	DirAccess.make_dir_recursive_absolute("res://resources/clans")

	_create_clan("少林寺", "正派", "少室山", 95, 2000, 500, 50, ["金刚掌","罗汉拳","易筋经"])
	_create_clan("武当派", "正派", "武当山", 90, 1800, 450, 45, ["太极拳","太极剑","纯阳无极功"])
	_create_clan("峨眉派", "正派", "峨眉山", 75, 1200, 350, 35, ["峨眉剑法","九阴白骨爪","玉女心经"])
	_create_clan("丐帮", "正派", "洛阳", 85, 800, 300, 60, ["打狗棒法","降龙十八掌","混天功"])
	_create_clan("日月教", "邪派", "黑木崖", 80, 1500, 400, 40, ["吸星大法","葵花宝典","辟邪剑法"])
	_create_clan("五毒教", "邪派", "苗疆", 55, 600, 200, 25, ["五毒心经","千蛛万毒手","蛊术"])
	_create_clan("华山派", "中立", "华山", 65, 900, 300, 30, ["华山剑法","紫霞神功"])
	_create_clan("逍遥派", "中立", "灵鹫宫", 70, 1000, 250, 20, ["北冥神功","天山六阳掌","凌波微步"])

	print("[ClanGen] All clans created")

func _create_clan(name_str: String, stance_str: String, territory: String, power: float, gold: int, rep: float, members: int, skills: Array):
	var c = Clan.new()
	c.clan_name = name_str
	c.stance = stance_str
	c.territory = territory
	c.power = power
	c.gold = gold
	c.member_count = members
	c.join_condition_reputation = rep
	c.join_condition_morality = 0.0
	c.mastery_skills = skills
	c.allies = []
	c.enemies = []
	c.description = name_str + " - " + stance_str + "门派"
	var fname = name_str + ".tres"
	ResourceSaver.save(c, "res://resources/clans/" + fname)
