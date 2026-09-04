extends Node

# 回归探针（本轮需求）：主线待接取制 / 打坐坐姿+进度 / 青石城布局与城内NPC
# 截图输出 tools/cshot_*.png；日志 tools/probe_city_log.txt

const LOG := "C:/Learn/my-godot-project/tools/probe_city_log.txt"
const SHOT_DIR := "C:/Learn/my-godot-project/tools/"

func _log(m):
	var f := FileAccess.open(LOG, FileAccess.WRITE if not FileAccess.file_exists(LOG) else FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line(m)
		f.close()
	print(m)

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _shot(name_: String):
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR + "cshot_" + name_ + ".png")
	_log("shot saved: " + name_)

func _player() -> CharacterBody2D:
	return get_tree().get_first_node_in_group("player") as CharacterBody2D

func _ready():
	# 阻断开局剧情（避免对话框遮挡截图；主线待接取逻辑单独单测）
	GameManager.story_stage = 99
	var hud: Control = null
	for i in range(900):
		hud = get_node_or_null("/root/Main/World/UI/SurvivalHUD") as Control
		if hud != null:
			break
		await get_tree().process_frame
	await _wait(2.0)

	# ---------- 0. 对话挂起/恢复（WASD教学页双显修复） ----------
	DialogManager.show_dialog("石伯", ["第一页", {"text": "WASD教学页", "teach_move": true}, "第三页"], "probe_meta")
	await _wait(0.6)
	var teach_armed: bool = DialogManager.is_move_teach_open()
	DialogManager.close_dialog()   # 外部强关→应挂起而非销毁现场
	var closed: bool = not DialogManager.is_dialog_open()
	var resumed: bool = DialogManager.resume_dialog()
	await _wait(0.4)
	var box = DialogManager.dialogue_box
	var page_after: int = box.current_index if box else -1
	var still_suspended: bool = box.suspended if box else true
	_log("[T0] 教学页解锁=%s 强关后关闭=%s 恢复成功=%s 恢复后页码=%d(期望1=原地续播不重放) suspended=%s(期望false)"
		% [str(teach_armed), str(closed), str(resumed), page_after, str(still_suspended)])
	if box:
		box._finish_dialog(true)   # 清理探针对话

	# ---------- 1. 主线任务待接取制 ----------
	var qs = get_node_or_null("/root/Main/QuestSystem")
	if qs:
		var q = qs.add_story_quest("探针委托", "测试待接取链路", 2, 50, 5.0, 0.0)
		_log("[T1] 挂载后 pending=%d active=%d (期望1/0)" % [qs.pending_story_quests.size(), qs.get_active_quests().size()])
		var accepted: bool = qs.accept_story_quest(q.quest_id)
		_log("[T1] accept_story_quest=%s active=%d pinned=%s (期望true/1/true)" % [str(accepted), qs.get_active_quests().size(), str(qs.is_pinned(q.quest_id))])
		qs.progress_quest(q.quest_id, 2)
		_log("[T1] 进度满后 completed含它=%s pending=%d (期望true/0)" % [str(qs.completed_quests.has(q)), qs.pending_story_quests.size()])
		# 追踪器显示待接取卡单测（先截图再收尾，卡在追踪器可见）
		var q2 = qs.add_story_quest("探针委托2", "待接取展示", 3, 30, 1.0, 0.0)
		_log("[T1] 再挂一张 pending=%d (期望1，不接取留在池中)" % qs.pending_story_quests.size())
		await _wait(0.4)         # 等追踪器0.25s轮询刷新
		await _shot("t1_tracker")   # 追踪器应显示"待接取"金色卡
		qs.settle_story_quest(q2.quest_id)   # 收尾清理

	# ---------- 2. 打坐：坐姿动画 + 进度盘 + 内力恢复 ----------
	var player := _player()
	if player:
		GameManager.qi = 30.0   # 压低内力便于观察恢复
		var qi0: float = GameManager.qi
		var prog0: float = GameManager.inner_skill_progress
		player._toggle_meditate()
		await _wait(0.6)
		var anim_now: String = str(player.anim.animation)
		_log("[T2] 打坐中=%s 动画=%s (期望true/meditate_down)" % [str(GameManager.is_meditating), anim_now])
		_log("[T2] 进度盘可见=%s (期望true)" % str(player.meditate_ui != null and player.meditate_ui.visible))
		await _shot("t2_meditate")   # 坐姿+头顶双条+粒子
		await _wait(2.5)
		var qi_gain: float = GameManager.qi - qi0
		var prog_gain: float = GameManager.inner_skill_progress - prog0
		_log("[T2] 3秒后 内力+%.1f 修炼+%.1f (期望内力≈+6 修炼>0)" % [qi_gain, prog_gain])
		player._toggle_meditate()   # 起身
		await _wait(0.3)
		_log("[T2] 起身后打坐=%s (期望false)" % str(GameManager.is_meditating))

	# ---------- 3. 青石城：布局/建筑/NPC ----------
	var wg = get_node_or_null("/root/Main/World/WorldGenerator")
	if wg and player:
		var info: Dictionary = wg.get_city_info()
		_log("[T3] city_info建筑数=%d (期望14) 城中心=%s" % [info.get("buildings", {}).size(), str(info.get("center_px", Vector2.ZERO))])
		# 城内NPC盘点
		var center: Vector2 = info.get("center_px", Vector2.ZERO)
		var city_npcs: Array = []
		for n in get_tree().get_nodes_in_group("npc"):
			if n.global_position.distance_to(center) < 900.0:
				city_npcs.append(n)
		var names := []
		for n in city_npcs:
			names.append("%s(%s/%s)" % [n.npc_data.npc_name, n.npc_type, n._state_name()])
		_log("[T3] 城内NPC %d人: %s" % [city_npcs.size(), ", ".join(names)])
		# 3a 广场全景（玩家站广场南缘向北看）
		player.global_position = center + Vector2(0, 56)
		var cam = player.get_node_or_null("Camera2D")
		if cam and cam.has_method("reset_smoothing"):
			cam.reset_smoothing()
		await _wait(0.8)
		await _shot("t3_city_plaza")
		# 3b 酒楼与东市
		var tavern_door: Vector2 = info["buildings"]["tavern"]["door_px"]
		player.global_position = tavern_door + Vector2(0, 40)
		if cam and cam.has_method("reset_smoothing"):
			cam.reset_smoothing()
		await _wait(0.8)
		await _shot("t3_city_tavern")
		# 3c 府衙
		var yamen_door: Vector2 = info["buildings"]["yamen"]["door_px"]
		player.global_position = yamen_door + Vector2(0, 40)
		if cam and cam.has_method("reset_smoothing"):
			cam.reset_smoothing()
		await _wait(0.8)
		await _shot("t3_city_yamen")
		# 3d 西门外看城墙
		player.global_position = center + Vector2(-420, 0)
		if cam and cam.has_method("reset_smoothing"):
			cam.reset_smoothing()
		await _wait(0.8)
		await _shot("t3_city_wall_west")

	# ---------- 4. 舆图 ----------
	var mm = get_node_or_null("/root/Main/World/UI/MinimapHUD")
	if mm:
		mm._toggle()
		await _wait(1.0)
		await _shot("t4_map")
		mm._toggle()

	_log("ALL_CITY_PROBE_DONE")
	await _wait(0.3)
	get_tree().quit()
