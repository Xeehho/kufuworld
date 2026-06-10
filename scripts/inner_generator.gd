@tool
extends Node

func _ready():
	_generate_all()
	if not Engine.is_editor_hint():
		get_tree().quit()

func _generate_all():
	DirAccess.make_dir_recursive_absolute("res://resources/inner")

	_create_inner("寒冰真气", "阴", "水", 1.2, "寒潭", 15, "吸收寒气凝练真元，需在寒潭区域修炼")
	_create_inner("烈阳心经", "阳", "火", 1.0, "火山", 12, "引烈阳之力灌注经脉，需在炎热之地修炼")
	_create_inner("青木长生功", "调和", "木", 0.8, "竹林", 20, "吐纳草木精华，延年益寿")
	_create_inner("金刚不坏体", "阳", "金", 0.6, "山巅", 25, "锤炼肉身如金刚，需在高处沐风修炼")
	_create_inner("土灵归元诀", "调和", "土", 0.7, "洞窟", 18, "引地脉灵气归元，需在洞穴深处修炼")
	_create_inner("玄阴鬼录", "阴", "水", 2.0, "墓地", 5, "吞噬阴魂之力，极度危险但进境极快")

	print("[InnerSkillGen] All inner skills created")

func _create_inner(name_str: String, yy: String, el: String, pp: float, loc: String, qi: float, desc: String):
	var skill = InnerSkill.new()
	skill.skill_name = name_str
	skill.yin_yang = yy
	skill.element = el
	skill.progress_per_tick = pp
	skill.required_location = loc
	skill.qi_bonus = qi
	skill.description = desc
	var fname = name_str.replace(" ", "_") + ".tres"
	ResourceSaver.save(skill, "res://resources/inner/" + fname)
