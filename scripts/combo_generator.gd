@tool
extends Node

func _ready():
	_generate()
	if not Engine.is_editor_hint():
		get_tree().quit()

func _generate():
	var ct = ComboTree.new()
	ct.routes = []

	_add_route(ct, "起手", "直拳", "连击", "崩拳", 5)
	_add_route(ct, "连击", "崩拳", "终结", "破山拳", 15)

	_add_route(ct, "起手", "点苍", "连击", "流云剑", 5)
	_add_route(ct, "连击", "流云剑", "终结", "万剑归宗", 15)

	_add_route(ct, "起手", "横斩", "连击", "回旋斩", 5)
	_add_route(ct, "连击", "回旋斩", "终结", "裂地斩", 15)

	_add_route(ct, "起手", "扫堂棍", "连击", "挑云棍", 5)
	_add_route(ct, "连击", "挑云棍", "终结", "霸王棍", 15)

	_add_route(ct, "起手", "飞蝗石", "连击", "金钱镖", 5)
	_add_route(ct, "连击", "金钱镖", "终结", "暴雨梨花", 10)

	_add_route(ct, "起手", "吐纳术", "连击", "护体罡气", 3)
	_add_route(ct, "连击", "护体罡气", "终结", "真气爆发", 12)

	ResourceSaver.save(ct, "res://resources/combo_tree.tres")
	print("[ComboGen] ComboTree saved with " + str(ct.routes.size()) + " routes")

func _add_route(ct: ComboTree, from_tag: String, from_skill: String, to_tag: String, to_skill: String, bonus: float):
	var route = ComboRoute.new()
	route.from_tag = from_tag
	route.next_skill = to_skill
	route.bonus_damage = bonus
	ct.routes.append(route)
