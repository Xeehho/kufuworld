extends Node

# 誓言立场分类：善誓与自身道行相悖（道德堕落/入邪派）时自动解除
const OATH_ALIGNMENT := {
	"行侠仗义": "善",
	"灭掉魔教": "善",
	"成为天下第一": "中",
	"富甲一方": "中",
	"博学多才": "中",
}
const FALLEN_MORALITY := -30.0   # 道德低于此值视为堕入魔道

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
	# 规则：未竟之誓不可更换——除非先做完其中一个
	for o in oaths:
		if not o["is_fulfilled"]:
			var deny := {"ok": false, "msg": "已有未竟之誓「" + o["title"] + "」，不可另立新誓"}
			GameManager.emit_event("誓愿未竟", deny["msg"], 3)
			print("[Oath] Denied (active oath exists): " + title)
			return deny
	# 善誓与自身道行相斥：堕入魔道（道德过低/已入邪派）时不可立善誓
	var alignment: String = OATH_ALIGNMENT.get(title, "中")
	if alignment == "善" and _is_fallen():
		var deny2 := {"ok": false, "msg": "你的所作所为已与善誓相悖（道德/阵营不符），无法立此誓"}
		GameManager.emit_event("立誓受阻", deny2["msg"], 3)
		print("[Oath] Denied (fallen): " + title)
		return deny2

	var milestones: Array = []
	if milestone_templates.has(title):
		milestones = milestone_templates[title].duplicate()
	else:
		milestones = ["持续推进: " + title]

	var oath = {
		"title": title,
		"description": description,
		"alignment": alignment,
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
	return {"ok": true, "msg": "立誓成功"}

func _is_fallen() -> bool:
	"""堕入魔道判定：道德过低 或 已入邪派门派"""
	if GameManager.morality < FALLEN_MORALITY:
		return true
	var c = GameManager.player_clan
	return c != null and c.stance == "邪派"

# 善誓与道行相悖时自动解除（附声望惩罚）
func _break_oath_by_conflict(oath: Dictionary):
	oaths.erase(oath)
	GameManager.modify_reputation(-20)
	GameManager.emit_event("背誓",
		"你道行日损，善誓「" + str(oath["title"]) + "」自然消解（声望-20）", 6)
	print("[Oath] Broken by conflict: " + str(oath["title"]))

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
	# BugFix：原实现恒返回0（引用了不存在的get_completed_quests）——改为直接遍历已完成任务
	var qs = get_node_or_null("/root/Main/QuestSystem")
	if qs == null:
		return 0
	var count := 0
	for q in qs.completed_quests:
		if q.category == cat:
			count += 1
	return count

func _process(_delta):
	# 善誓与道行相斥：堕入魔道时自动解除（duplicate防遍历中移除）
	for oath in oaths.duplicate():
		if not oath["is_fulfilled"]:
			if str(oath.get("alignment", "中")) == "善" and _is_fallen():
				_break_oath_by_conflict(oath)
				continue
			_check_oath_progress(oath)

func get_oaths() -> Array:
	return oaths

func get_active_oaths() -> Array:
	var result: Array = []
	for o in oaths:
		if not o["is_fulfilled"]:
			result.append(o)
	return result
