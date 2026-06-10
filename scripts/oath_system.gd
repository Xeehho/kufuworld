extends Node

var oaths: Array = []
var milestone_templates = {
	"成为天下第一": [
		"声望达到 500",
		"击败武林盟主",
		"公认天下第一"
	],
	"富甲一方": [
		"积攒 1000 两黄金",
		"建造 5 座建筑",
		"雇佣 3 名 NPC"
	],
	"灭掉魔教": [
		"加入正派门派",
		"削弱魔教势力至 30 以下",
		"击败魔教教主"
	],
	"博学多才": [
		"学习 5 种武学",
		"内力达到 150",
		"声望达到 200"
	],
	"行侠仗义": [
		"完成 3 个除恶任务",
		"完成 2 个护送任务",
		"正邪值达到 80"
	],
}

func create_oath(title: String, description: String = "") -> Dictionary:
	if title == "自定义":
		title = description
	var milestones: Array = []
	if milestone_templates.has(title):
		milestones = milestone_templates[title].duplicate()
	else:
		milestones = ["持续推进: " + title]

	var oath = {
		"title": title,
		"description": description,
		"milestones": milestones,
		"completed_milestones": [],
		"progress": 0.0,
		"is_fulfilled": false,
		"fulfilled_timestamp": ""
	}
	oaths.append(oath)
	_check_oath_progress(oath)
	GameManager.emit_event("立誓", "你在心中立下誓言: " + title, 4)
	print("[Oath] Created: " + title)
	GameManager.world_state_changed.emit()
	return oath

func _check_oath_progress(oath: Dictionary):
	var title = oath["title"]
	var completed = []
	for m in oath["milestones"]:
		if _is_milestone_met(m, title):
			if not oath["completed_milestones"].has(m):
				completed.append(m)
				GameManager.emit_event("誓言推进", "你离「" + title + "」更近一步: " + m, 3)
				print("[Oath] Milestone reached: " + m)
	for m in completed:
		oath["completed_milestones"].append(m)
	oath["progress"] = float(oath["completed_milestones"].size()) / max(oath["milestones"].size(), 1)
	if oath["progress"] >= 1.0 and not oath["is_fulfilled"]:
		oath["is_fulfilled"] = true
		oath["fulfilled_timestamp"] = str(GameManager.world_hour)
		GameManager.reputation += 50
		GameManager.emit_event("誓言达成！", "你兑现了誓言：「" + title + "」！江湖人人称颂！", 8)
		print("[Oath] FULFILLED: " + title)

func _is_milestone_met(milestone: String, oath_title: String) -> bool:
	if milestone.contains("声望达到") or milestone.contains("声望达到"):
		var target = _extract_number(milestone)
		return GameManager.reputation >= target
	if milestone.contains("黄金") or milestone.contains("两"):
		var target = _extract_number(milestone)
		return GameManager.gold >= target
	if milestone.contains("建造"):
		var target = _extract_number(milestone)
		return GameManager.buildings.size() >= target
	if milestone.contains("雇佣"):
		var target = _extract_number(milestone)
		return GameManager.invited_npcs.size() >= target
	if milestone.contains("加入正派"):
		return GameManager.player_clan != null and GameManager.player_clan.stance == "正派"
	if milestone.contains("削弱魔教"):
		for c in GameManager.clans:
			if c.stance == "邪派":
				if c.power < 30:
					return true
	if milestone.contains("武学"):
		var target = _extract_number(milestone)
		return GameManager.unlocked_skills.size() >= target
	if milestone.contains("内力达到"):
		var target = _extract_number(milestone)
		return GameManager.max_qi >= target
	if milestone.contains("除恶任务"):
		var target = _extract_number(milestone)
		return _count_completed_category("除恶") >= target
	if milestone.contains("护送任务"):
		var target = _extract_number(milestone)
		return _count_completed_category("护送") >= target
	if milestone.contains("正邪值"):
		var target = _extract_number(milestone)
		return GameManager.morality >= target
	if milestone.contains("击败"):
		return false
	if milestone.contains("公认"):
		return GameManager.reputation >= 500
	if milestone.contains("持续推进"):
		return false
	return false

func _extract_number(text: String) -> int:
	var num_str = ""
	for ch in text:
		if ch.is_valid_int():
			num_str += ch
	if num_str != "":
		return int(num_str)
	return 999

func _count_completed_category(cat: String) -> int:
	var count = 0
	var qs = get_node_or_null("/root/Main/QuestSystem")
	if qs and qs.has_method("get_completed_quests"):
		return 0
	return count

func _process(_delta):
	for oath in oaths:
		if not oath["is_fulfilled"]:
			_check_oath_progress(oath)

func get_oaths() -> Array:
	return oaths

func get_active_oaths() -> Array:
	var result: Array = []
	for o in oaths:
		if not o["is_fulfilled"]:
			result.append(o)
	return result
