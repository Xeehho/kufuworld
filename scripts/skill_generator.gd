@tool
extends Node

func _ready():
	_generate_all()
	if not Engine.is_editor_hint():
		get_tree().quit()

func _generate_all():
	DirAccess.make_dir_recursive_absolute("res://resources/skills")
	DirAccess.make_dir_recursive_absolute("res://resources/inner")

	# 拳掌
	_create_skill("直拳", "拳掌", 12, 3, 3, 5, 8, "起手", true, "基础直拳，力道沉稳")
	_create_skill("崩拳", "拳掌", 22, 6, 5, 6, 10, "连击", true, "崩劲穿透，接续连招")
	_create_skill("破山拳", "拳掌", 50, 15, 10, 12, 20, "终结", false, "破山之力，终结一击")

	# 剑法
	_create_skill("点苍", "剑法", 15, 5, 4, 6, 10, "起手", true, "点刺苍天，剑式起手")
	_create_skill("流云剑", "剑法", 25, 8, 5, 8, 12, "连击", true, "剑如流云，连绵不绝")
	_create_skill("万剑归宗", "剑法", 60, 20, 12, 15, 25, "终结", false, "万剑归一，终极剑技")

	# 刀法
	_create_skill("横斩", "刀法", 18, 6, 5, 7, 12, "起手", true, "横刀一斩，气势凌厉")
	_create_skill("回旋斩", "刀法", 28, 10, 6, 9, 14, "连击", true, "回身旋斩，刀光如轮")
	_create_skill("裂地斩", "刀法", 55, 18, 10, 14, 22, "终结", false, "裂地一击，刀气纵横")

	# 棍法
	_create_skill("扫堂棍", "棍法", 10, 4, 4, 8, 12, "起手", true, "棍扫下盘，攻守兼备")
	_create_skill("挑云棍", "棍法", 20, 7, 5, 10, 15, "连击", true, "长棍挑空，破敌先机")
	_create_skill("霸王棍", "棍法", 48, 16, 8, 13, 22, "终结", false, "霸王举鼎，一棍绝尘")

	# 暗器
	_create_skill("飞蝗石", "暗器", 8, 2, 2, 5, 6, "起手", true, "飞蝗石直射要害")
	_create_skill("金钱镖", "暗器", 18, 5, 4, 6, 8, "连击", true, "金钱镖回旋连射")
	_create_skill("暴雨梨花", "暗器", 45, 12, 8, 10, 16, "终结", false, "漫天暗器，无处可逃")

	# 内功
	_create_skill("吐纳术", "内功", 0, 2, 5, 10, 10, "起手", true, "吐纳调息，恢复内力")
	_create_skill("护体罡气", "内功", 0, 5, 3, 15, 10, "连击", true, "罡气护体，减免伤害")
	_create_skill("真气爆发", "内功", 40, 10, 8, 10, 15, "终结", false, "真气爆发，震退群敌")

	print("[SkillGen] All skills created")

func _create_skill(name_str: String, cat: String, dmg: float, cst: float, sf: int, af: int, rf: int, tag: String, light: bool, desc: String):
	var skill = Skill.new()
	skill.skill_name = name_str
	skill.category = cat
	skill.damage = dmg
	skill.cost = cst
	skill.startup_frames = sf
	skill.active_frames = af
	skill.recovery_frames = rf
	skill.combo_tag = tag
	skill.is_light = light
	skill.description = desc
	var fname = name_str.replace(" ", "_") + ".tres"
	ResourceSaver.save(skill, "res://resources/skills/" + fname)
