extends Node

# 视觉审计临时探针：逐面板截图供走查（验收标准.md 三/四节）
# 场景：0初始HUD 1背包开 2人物档案开 3任务日志开 4建造开(选围墙) 5商店开 6奇遇面板开 7战斗中
const LOG := "C:/Learn/my-godot-project/tools/probe_shot_log.txt"

func _log(m):
	var f := FileAccess.open(LOG, FileAccess.WRITE if not FileAccess.file_exists(LOG) else FileAccess.READ_WRITE)
	if f and FileAccess.file_exists(LOG):
		f.seek_end()
	f.store_line(m)
	f.close()
	print(m)

func _ui(n: String) -> Control:
	return get_node_or_null("/root/Main/World/UI/" + n) as Control

func _wait(sec: float):
	await get_tree().create_timer(sec).timeout

func _shot(name_: String):
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Learn/my-godot-project/tools/vshot_" + name_ + ".png")
	_log("shot saved: " + name_)

func _ready():
	var hud: Control = null
	for i in range(900):
		hud = _ui("SurvivalHUD")
		if hud != null:
			break
		await get_tree().process_frame
	await _wait(2.5)

	# 0 初始HUD（折叠任务追踪+操作指南折叠态）
	await _shot("0_hud")

	# 1 背包
	var ihud = _ui("InventoryHUD")
	ihud.toggle()
	await _wait(0.4)
	await _shot("1_inventory")
	ihud.close()

	# 2 人物档案
	var sheet = _ui("CharacterSheet")
	sheet.open()
	await _wait(0.4)
	await _shot("2_sheet")
	sheet.close()

	# 3 任务日志展开
	var ql = _ui("QuestLogHUD")
	ql.toggle_panel()
	await _wait(0.5)
	await _shot("3_questlog")
	ql.toggle_panel()
	await _wait(0.4)

	# 4 建造（选中围墙，右侧停靠+幽灵格）
	var player = get_tree().get_first_node_in_group("player")
	player._toggle_build()
	player._select_building("围墙")
	await _wait(0.4)
	await _shot("4_build")
	player._toggle_build()
	await _wait(0.3)

	# 5 商店
	var shop = _ui("ShopHUD")
	shop.open_shop()
	await _wait(0.4)
	await _shot("5_shop")
	shop.close_shop()
	await _wait(0.3)

	# 6 奇遇面板
	var qm = _ui("QuickMenu")
	var es = get_node_or_null("/root/Main/EncounterSystem")
	es.active_encounter = es.encounters[0]
	await _wait(0.5)
	await _shot("6_encounter")
	es.active_encounter = null
	qm.encounter_panel.visible = false

	# 7 战斗：传送到最近mob旁打一拳
	await _wait(0.3)
	var mobs = get_tree().get_nodes_in_group("mobs")
	if mobs.size() > 0:
		player.global_position = mobs[0].global_position + Vector2(30, 0)
		await _wait(0.3)
		player._start_attack(true)
		await _wait(0.2)
	await _shot("7_combat")

	# 8 操作指南展开态
	hud._toggle_help()
	await _wait(0.3)
	await _shot("8_help")
	hud._toggle_help()

	_log("ALL_SHOTS_DONE")
	await _wait(0.3)
	get_tree().quit()
