extends Node

# Phase H 临时探针：H1固定四槽环/H2平滑lerp/H3低值脉动/H4资源chips/H5时辰底板
#   /H6追踪器自动展示与实时进度/H7钉选联动/H8页签计数/H9接受委托事件反馈
# 用法：run_probe_h.py 临时注入[autoload] -> 跑一局 -> 文件日志 tools/probe_h_log.txt -> 自动还原
const LOG := "C:/Learn/my-godot-project/tools/probe_h_log.txt"
var pass_n := 0
var fail_n := 0

func _log(msg: String):
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f and FileAccess.file_exists(LOG):
		f.seek_end()
	if f == null:
		f = FileAccess.open(LOG, FileAccess.WRITE)
	f.store_line(msg)
	f.close()
	print(msg)

func _chk(cond: bool, name_: String, detail := ""):
	if cond:
		pass_n += 1
		_log("[PASS] %s %s" % [name_, detail])
	else:
		fail_n += 1
		_log("[FAIL] %s %s" % [name_, detail])

func _ui(n: String) -> Control:
	return get_node_or_null("/root/Main/World/UI/" + n) as Control

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _ready():
	# 等UI就绪
	var hud: Control = null
	for i in range(900):
		hud = _ui("SurvivalHUD")
		var qt := _ui("QuestTrackerHUD")
		if hud != null and qt != null:
			break
		await get_tree().process_frame
	if hud == null:
		_log("[Probe] SurvivalHUD/QuestTrackerHUD not found")
		get_tree().quit()
		return
	await _wait(3.0)

	_log("=== H-LOGIC ===")
	# ---- H1 三大HUD挂载 ----
	for n in ["SurvivalHUD", "QuestTrackerHUD", "QuestLogHUD"]:
		_chk(_ui(n) != null, "H1 node:%s" % n)

	# ---- H2 固定四槽 ----
	_chk(hud.stat_order.size() == 4, "H2 slot-count-fixed", str(hud.stat_order))
	_chk(hud.display_arcs.size() == 4, "H2 display-arcs-init", str(hud.display_arcs.keys()))

	# ---- H3 资源chips主题化 ----
	var chip_ok := true
	for k in ["wood", "stone", "gold"]:
		var lbl = hud.resource_labels.get(k)
		if lbl == null or not (lbl is Label) or lbl.get_parent() == null or not (lbl.get_parent() is Panel):
			chip_ok = false
	_chk(chip_ok, "H3 res-chips-panel", hud.resource_labels["wood"].get_parent().name if chip_ok else "missing")

	# ---- H4 时辰底板 ----
	_chk(hud.datetime_panel != null and hud.datetime_panel is Panel, "H4 datetime-pill")

	# ---- H5 平滑lerp（设置毒后先慢后快收敛，非瞬跳）----
	GameManager.poison = 50.0
	await _wait(0.06)
	var early: float = hud.display_arcs["poison"]
	_chk(early < 0.30, "H5a lerp-not-instant", "early=%.3f" % early)
	await _wait(1.4)
	var late: float = hud.display_arcs["poison"]
	_chk(late > 0.42 and late < 0.55, "H5b lerp-converged", "late=%.3f target~%.3f" % [late, GameManager.poison / 100.0])
	_chk(hud.has_method("_pulsed_color"), "H5c pulse-fn-exists")

	# ---- H6 接受委托事件反馈 ----
	var evt_caught := {"hit": false, "title": "", "body": ""}
	var cb := func(title: String, body: String, _imp: int):
		if title == "已接委托":
			evt_caught["hit"] = true
			evt_caught["title"] = title
			evt_caught["body"] = body
	GameManager.world_event.connect(cb)
	var qs = get_node_or_null("/root/Main/QuestSystem")
	_chk(qs != null, "H6 quest-system-found")
	if qs == null:
		_finish()
		return
	var accepted: bool = qs.accept_quest(0)
	_chk(accepted, "H6 accept-ok")
	await _wait(0.1)
	_chk(evt_caught["hit"], "H6 accept-event-fired", "%s|%s" % [evt_caught["title"], evt_caught["body"]])
	GameManager.world_event.disconnect(cb)

	# ---- H7 追踪器自动展示（空pinned时自动追踪）----
	await _wait(0.6)
	var qt := _ui("QuestTrackerHUD")
	var actives: Array = qs.get_active_quests()
	_chk(actives.size() == 1, "H7 one-active", str(actives.size()))
	_chk(qt.header_btn.visible, "H7 tracker-visible")
	_chk(qt.cards.size() == 1, "H7 tracker-cards", str(qt.cards.size()))
	if qt.cards.size() == 1 and actives.size() == 1:
		var q = actives[0]
		var entry: Dictionary = qt.cards[q.quest_id]
		_chk(entry["title"].text.contains(q.title), "H7 tracker-title", entry["title"].text)
		_chk(absf(float(entry["bar"].max_value) - float(q.target_count)) < 0.01, "H7 tracker-bar-max", str(entry["bar"].max_value))

	# ---- H8 钉选单一状态源 ----
	var qid: String = actives[0].quest_id if actives.size() > 0 else ""
	qs.toggle_pin(qid)
	_chk(qs.is_pinned(qid), "H8 pin-set", str(qs.pinned_ids))
	await _wait(0.3)
	_chk(qt.cards.has(qid), "H8 pinned-card-shown")

	# ---- H9 进度实时刷新（progress无信号，靠轮询）----
	qs.progress_quest(qid, 2)
	await _wait(0.6)
	if qt.cards.has(qid):
		var bar_v = qt.cards[qid]["bar"].value
		_chk(absf(float(bar_v) - 2.0) < 0.01, "H9 progress-polled", "bar=%.1f" % float(bar_v))
	else:
		_chk(false, "H9 progress-polled", "card missing")

	# ---- H10 日志面板：开启动画+页签计数+星标按钮 ----
	var ql := _ui("QuestLogHUD")
	ql.toggle_panel()
	await _wait(0.3)
	_chk(ql.panel.visible, "H10 log-opened")
	var tab_txt: String = ql.tabs[0]["btn"].text
	_chk(tab_txt.contains("1/5") or tab_txt.contains("进行中"), "H10 tab-count", tab_txt)
	var star_btn := _find_star(ql.list_box)
	_chk(star_btn != null and star_btn.text == "★", "H10 star-pinned-state", star_btn.text if star_btn else "none")
	# 取消钉选 → 星标回退
	qs.toggle_pin(qid)
	await _wait(0.3)
	var star2 := _find_star(ql.list_box)
	_chk(star2 != null and star2.text == "☆", "H10 star-unpinned", star2.text if star2 else "none")
	ql.toggle_panel()

	# ---- H11 完成闭环 → 追踪器清空 ----
	qs.progress_quest(qid, 999)
	await _wait(0.1)
	_chk(qs.completed_quests.size() >= 1, "H11 quest-completed", str(qs.completed_quests.size()))
	await _wait(0.6)
	_chk(qt.cards.is_empty(), "H11 tracker-cleared", str(qt.cards.size()))
	_chk(not qt.header_btn.visible, "H11 tracker-hidden")

	# ---- H12 抽屉式入口（Phase H2）----
	var tab = ql.tab_btn
	_chk(tab != null and absf(tab.position.x) < 0.01 and tab.position.y > 360.0,
		"H12 drawer-tab-edge", str(tab.position if tab != null else Vector2()))
	_chk(ql.tab_lbl != null and ql.tab_lbl.text.begins_with("任\n务\n日\n志"), "H12 label-full-name")
	# 角标=已接取未完成数：当前无进行中任务应为空
	_chk(ql.badge_lbl != null and ql.badge_lbl.text == "", "H12 badge-empty-no-active",
		"badge=" + (ql.badge_lbl.text if ql.badge_lbl != null else "none"))
	# 接一单后角标应变1（accept发world_state_changed→refresh同步）
	qs.accept_quest(0)
	_chk(ql.badge_lbl != null and ql.badge_lbl.text == "1", "H12 badge-active-count",
		"badge=" + (ql.badge_lbl.text if ql.badge_lbl != null else "none"))
	var actives2: Array = qs.get_active_quests()
	var qid2: String = actives2[0].quest_id if actives2.size() > 0 else ""
	qs.abandon_quest(qid2)	# 还原现场：弃掉后角标应清空
	_chk(ql.badge_lbl.text == "", "H12 badge-clears-on-abandon", "badge=" + ql.badge_lbl.text)
	_chk(not ql.panel.visible, "H12 default-closed")
	ql.toggle_panel()
	await _wait(0.35)
	_chk(ql.panel.visible and absf(ql.panel.position.x - 34.0) < 2.0, "H12 slide-open-x", str(ql.panel.position))
	_chk(ql.tab_lbl.text.contains("◂"), "H12 indicator-open")
	ql.toggle_panel()
	await _wait(0.4)
	_chk(not ql.panel.visible, "H12 slide-closed")

	# ---- H13 对话框NextButton接线修复（BugFix：tscn无connection代码未connect）----
	var dm = get_node_or_null("/root/DialogManager")
	if dm != null:
		dm.show_dialog("探针", ["第一行提示内容", "第二行提示内容"])
		var box = dm.dialogue_box
		_chk(box != null and box.visible, "H13 dialog-shown")
		var clicks := 0
		while box != null and box.visible and clicks < 8:
			box.next_button.pressed.emit()
			clicks += 1
			await _wait(0.06)
		_chk(box != null and not box.visible, "H13 next-button-closes", "%d clicks" % clicks)
	else:
		_chk(false, "H13 dialog-manager-found", "missing")

	_finish()

func _find_star(box: Node) -> Button:
	if box == null:
		return null
	for c in box.get_children():
		if c is Button and (c.text == "★" or c.text == "☆"):
			return c
		var deep = _find_star(c)
		if deep != null:
			return deep
	return null

func _finish():
	_log("=== H-DONE pass=%d fail=%d ===" % [pass_n, fail_n])
	get_tree().quit()
