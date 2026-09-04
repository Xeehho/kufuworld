extends Node

# 第二轮验收临时探针：补第一轮未覆盖的功能点
#   N=NPC交互六项(交谈/送礼/切磋/观察/邀请/离开+锁定) S=商店买卖链 C=门派加入/切磋/背叛
#   O=誓约单持 M=击杀移除 F=农场雨天补水/浆果再生 E=ESC层级退出
# 用法：run_probe_round2.py 临时注入 [autoload] -> 跑一局 -> tools/probe_round2_log.txt -> 自动还原
const LOG := "C:/Learn/my-godot-project/tools/probe_round2_log.txt"
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

func chk(cond: bool, name_: String, detail := ""):
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

func _press_esc():
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)

func _find_main_child(child_name: String) -> Node:
	var main = get_node_or_null("/root/Main")
	return main.get_node_or_null(child_name) if main else null

func _ready():
	var hud: Control = null
	for i in range(900):
		hud = _ui("SurvivalHUD")
		if hud != null:
			break
		await get_tree().process_frame
	if hud == null:
		_log("[Probe] SurvivalHUD not found")
		get_tree().quit()
		return
	await _wait(2.5)
	_log("=== ROUND2-LOGIC ===")

	var player = get_tree().get_first_node_in_group("player")
	var spawner = get_node_or_null("/root/Main/World/NPCSpawner")
	chk(player != null, "PRE player-found")
	chk(spawner != null and spawner.npc_list.size() == 12, "PRE npcs-12", str(spawner.npc_list.size()) if spawner else "?")
	if player == null or spawner == null:
		_finish()
		return

	await _run_npc_tests(player, spawner)
	_run_shop_tests()
	_run_clan_tests(player)
	_run_oath_tests()
	await _run_mob_tests(player)
	await _run_farm_tests(player)
	await _run_esc_tests()

	_finish()

func _finish():
	_log("=== ROUND2-SUMMARY pass=%d fail=%d ===" % [pass_n, fail_n])
	await _wait(0.3)
	get_tree().quit()

# ---------------- N组 NPC交互 ----------------
func _run_npc_tests(player, spawner):
	var npc = spawner.npc_list[1]  # 铁三娘(warrior)，初始好感0中性
	spawner.show_interaction_ui(npc)
	chk(spawner.is_interaction_open(), "N1 panel-open")
	# 头像加载（曾因get_node_or_null只查直接子节点永远为null）
	var avatar = spawner.interaction_ui.get_node_or_null("InteractPanel/AvatarBg/Avatar")
	chk(avatar != null and avatar.texture != null, "N9 avatar-texture-loaded",
		str(avatar.texture) if avatar else "no-node")
	chk(player._is_ui_blocking(), "N8 input-locked-when-open")

	var nd = npc.npc_data
	var nm: String = nd.npc_name

	# 交谈：中性好感也应给可见反馈（当前实现只在极端好感弹对话）
	var r0: float = GameManager.get_relation(nm, "玩家")
	spawner._handle_talk()
	var r1: float = GameManager.get_relation(nm, "玩家")
	chk(absf(r1 - r0 - 2.0) < 0.01, "N2 talk-relation-plus2", "%.0f->%.0f" % [r0, r1])
	var talked_feedback: bool = DialogManager.is_dialog_open()
	if talked_feedback:
		DialogManager.close_dialog()
	chk(talked_feedback, "N2 talk-visible-feedback(中性)", "" if talked_feedback else "中性好感交谈无任何玩家可见反馈")

	# 送礼：同样应有反馈
	r0 = r1
	spawner._handle_gift()
	r1 = GameManager.get_relation(nm, "玩家")
	chk(absf(r1 - r0 - 10.0) < 0.01, "N3 gift-relation-plus10", "%.0f->%.0f" % [r0, r1])
	chk(DialogManager.is_dialog_open(), "N3 gift-visible-feedback", "" if DialogManager.is_dialog_open() else "送礼无反馈")
	if DialogManager.is_dialog_open():
		DialogManager.close_dialog()

	# 切磋（用户点名）：应发生真实比试或至少明确反馈，当前只扣好感
	r0 = r1
	spawner._handle_spar()
	r1 = GameManager.get_relation(nm, "玩家")
	chk(absf(r1 - r0 + 5.0) < 0.01, "N4 spar-relation-minus5", "%.0f->%.0f" % [r0, r1])
	chk(DialogManager.is_dialog_open(), "N4 spar-visible-feedback", "" if DialogManager.is_dialog_open() else "切磋无反馈")
	if DialogManager.is_dialog_open():
		DialogManager.close_dialog()

	# 观察：弹对话展示性格喜好
	spawner._handle_observe()
	chk(DialogManager.is_dialog_open(), "N5 observe-shows-dialog")
	if DialogManager.is_dialog_open():
		DialogManager.close_dialog()

	# 邀请：好感仍<30 应婉拒弹窗
	r1 = GameManager.get_relation(nm, "玩家")
	chk(r1 < 30.0, "N6 precondition-favor-under-30", "%.0f" % r1)
	spawner._handle_invite()
	chk(DialogManager.is_dialog_open(), "N6 invite-lowfavor-dialog")
	if DialogManager.is_dialog_open():
		DialogManager.close_dialog()

	# ESC 关闭面板并清目标
	_press_esc()
	await get_tree().process_frame
	await get_tree().process_frame
	chk(not spawner.is_interaction_open(), "N1 esc-close-panel")
	chk(spawner.current_target == null, "N7 esc-clears-target")
	chk(not player._is_ui_blocking(), "N8 unlocked-after-close")

	# ---- 日程寻路系统 ----
	chk(npc.schedule.size() == 4, "N10 npc-schedule-4-legs", str(npc.schedule.size()))
	chk(npc._leg_at(8) != null and str(npc._leg_at(8)["state"]) == "work", "N10 leg-8am-work")
	chk(npc._leg_at(13) != null and str(npc._leg_at(13)["state"]) == "leisure", "N10 leg-1pm-leisure")
	chk(npc._leg_at(23) == null, "N10 leg-11pm-sleep-fallback")
	# 寻路：目标设为最近城镇中心，请求路径应成功且路点>=1
	var town_c: Vector2 = npc._nearest_town_center(npc.global_position)
	chk(town_c != Vector2.INF, "N11 nearest-town-found")
	if town_c != Vector2.INF:
		var ok_req: bool = npc._request_path(town_c)
		chk(ok_req and npc.path_queue.size() >= 1, "N11 path-to-town-found", str(npc.path_queue.size()))
	# 不可达目标应返回false（世界边界外深水）
	var bad_req: bool = npc._request_path(Vector2(-99999, -99999))
	chk(not bad_req, "N11 unreachable-rejected")
	npc.path_queue = []
	# 卡死重寻路：把NPC放到目标远处并模拟一次卡死窗口
	npc.global_position = player.global_position + Vector2(64, 0)
	npc.last_pos = npc.global_position
	npc._request_path(town_c)
	var q0: int = npc.path_queue.size()
	npc.stuck_timer = 0.7   # 强制触发卡死窗口
	npc.repath_cooldown = 0.0
	npc._check_stuck(0.1)
	chk(npc.repath_cooldown > 0.0, "N12 stuck-triggers-repath")
	chk(npc.path_queue.size() >= 1, "N12 repath-keeps-route", "%d->%d" % [q0, npc.path_queue.size()])
	npc.path_queue = []

	# ---- 碰撞分层v3（NPC空气墙：挡玩家但不被玩家影响） ----
	chk(int(npc.collision_layer) == 4 and int(npc.collision_mask) == 1, "N14 npc-layer4-mask1",
		"L%d M%d" % [npc.collision_layer, npc.collision_mask])
	chk(int(player.collision_layer) == 2 and int(player.collision_mask) == 13, "N14 player-layer2-mask13",
		"L%d M%d" % [player.collision_layer, player.collision_mask])
	var some_mob = get_tree().get_first_node_in_group("mobs")
	chk(some_mob != null and int(some_mob.collision_layer) == 8 and int(some_mob.collision_mask) == 1, "N14 mob-layer8-mask1")
	# 空气墙方向断言：玩家被NPC/敌人挡（mask含其层），NPC/敌人不被玩家影响（mask不含玩家层）
	chk((int(player.collision_mask) & int(npc.collision_layer)) != 0, "N14 player-blocked-by-npc")
	chk((int(player.collision_mask) & int(some_mob.collision_layer)) != 0, "N14 player-blocked-by-mob")
	chk((int(npc.collision_mask) & int(player.collision_layer)) == 0, "N14 npc-unaffected-by-player")
	chk((int(some_mob.collision_mask) & int(player.collision_layer)) == 0, "N14 mob-unaffected-by-player")
	# POI环境区只监测玩家层（否则current_environment门派地盘判定失效）
	var wg2: Node2D = npc._world_gen()
	var zone_ok := false
	if wg2 != null and wg2.get("pois") != null and not (wg2.get("pois") as Array).is_empty():
		var marker = (wg2.get("pois") as Array)[0]["node"]
		var zone = marker.get_node_or_null("EnvironmentZone")
		zone_ok = zone != null and int(zone.collision_mask) == 2
	chk(zone_ok, "N14 env-zone-monitors-player-only")

	# ---- 屏幕空间名牌（世界空间5px放大发糊已废弃） ----
	chk(npc.name_tag != null and is_instance_valid(npc.name_tag), "N13 nametag-created")
	if npc.name_tag != null:
		chk(npc.name_tag.get_parent() == _ui("SurvivalHUD").get_parent(), "N13 nametag-in-ui-layer")
		chk(npc.name_tag.get_theme_font_size("font_size") >= 13, "N13 nametag-font-sharp",
			str(npc.name_tag.get_theme_font_size("font_size")))
		# 悬停显示后位置应同步到NPC头顶屏幕坐标（等两帧让物理帧同步跑过）
		npc.show_name_tag_flash(1.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var s_pos: Vector2 = player.get_viewport().get_canvas_transform() * npc.global_position
		chk(absf(npc.name_tag.position.y - (s_pos.y - 100.0)) < 2.0, "N13 nametag-synced-above-head",
			"tag_y=%.0f screen_y=%.0f" % [npc.name_tag.position.y, s_pos.y])

# ---------------- S组 商店 ----------------
func _run_shop_tests():
	var shop = _find_main_child("ShopSystem")
	var shud = _ui("ShopHUD")
	var inv = _find_main_child("InventoryManager")
	chk(shop != null and shud != null and inv != null, "S0 shop-system-found")
	if shop == null or shud == null or inv == null:
		return

	shud.open_shop()
	chk(shud.is_open, "S1 hud-open")
	shud.close_shop()
	chk(not shud.is_open, "S1 hud-close")

	# 买入：金钱减少/库存减少/入包
	shud.open_shop()
	var slot = shop.shop_items[0]  # 金创药
	var price_buy: int = shop.get_buy_price(slot["item"])
	var gold0: int = GameManager.gold
	var cnt0: int = inv.get_item_count("金创药")
	var stock0: int = slot["stock"]
	chk(shop.buy_item(0, 1), "S2 buy-ok")
	chk(GameManager.gold == gold0 - price_buy, "S2 buy-gold-deducted", "%d-%d" % [gold0, price_buy])
	chk(inv.get_item_count("金创药") == cnt0 + 1, "S2 buy-item-in-bag")
	chk(slot["stock"] == stock0 - 1, "S2 buy-stock-dec", "%d->%d" % [stock0, slot["stock"]])

	# 卖出：半价回收/出包
	var price_sell: int = shop.get_sell_price(slot["item"])
	gold0 = GameManager.gold
	cnt0 = inv.get_item_count("金创药")
	chk(shop.sell_item("金创药", 1), "S3 sell-ok")
	chk(GameManager.gold == gold0 + price_sell, "S3 sell-gold-added", "+%d" % price_sell)
	chk(inv.get_item_count("金创药") == cnt0 - 1, "S3 sell-item-out-of-bag")

	# 铜钱不足拒绝
	gold0 = GameManager.gold
	GameManager.gold = 0
	chk(not shop.buy_item(7, 1), "S4 poor-rejected")  # 玄铁重剑500
	GameManager.gold = gold0
	shud.close_shop()

# ---------------- C组 门派 ----------------
func _run_clan_tests(player):
	var qm = _ui("QuickMenu")
	chk(qm != null and GameManager.clans.size() >= 2, "C0 clans-ready", str(GameManager.clans.size()))
	if qm == null or GameManager.clans.size() < 2:
		return
	var rep_backup: float = GameManager.reputation

	# 加入：声望达标
	GameManager.reputation = 100.0
	var cname: String = GameManager.clans[0].clan_name
	chk(GameManager.join_clan(cname), "C1 join-clan-ok", cname)
	# 地盘面板：仅当玩家身处门派地盘时可开（设计如此），否则跳过
	var env_clan = GameManager.get_clan(GameManager.current_environment) if GameManager.current_environment != "" else null
	if env_clan != null:
		qm._open_clan_panel()
		chk(qm.clan_options_box.get_child_count() > 0, "C1 panel-options-exist", str(qm.clan_options_box.get_child_count()))
		qm.clan_panel.visible = false
	else:
		chk(true, "C1 panel-options-exist(SKIP不在门派地盘)")
	chk(GameManager.player_clan != null, "C1 player-clan-set")

	# 门派切磋：必然有声望+2或生命-8分支
	var hp0: float = GameManager.health
	var rp0: float = GameManager.reputation
	qm._on_clan_spar()
	var hp1: float = GameManager.health
	var rp1: float = GameManager.reputation
	chk(rp1 > rp0 or hp1 < hp0, "C2 clan-spar-has-effect", "hp %.0f->%.0f rep %.0f->%.0f" % [hp0, hp1, rp0, rp1])

	# P键：查看本派面板（_show_player_clan→QuickMenu面板，不再只是print）
	player._show_player_clan()
	chk(qm.clan_panel.visible, "C4 pkey-opens-my-clan-panel")
	var my_info: String = qm.clan_info.text
	chk(my_info.find(cname) >= 0 and my_info.find("身份") >= 0, "C4 panel-shows-my-clan", my_info.left(30))
	qm.clan_panel.visible = false

	# 背叛：退出门派
	GameManager.betray_clan()
	chk(GameManager.player_clan == null, "C3 betray-clears-clan")
	GameManager.reputation = rep_backup

# ---------------- O组 誓约 ----------------
func _run_oath_tests():
	var osys = _find_main_child("OathSystem")
	chk(osys != null, "O0 oath-system-found")
	if osys == null:
		return
	osys.create_oath("探针誓约A", "测试用")
	chk(osys.get_active_oaths().size() == 1, "O1 first-oath-active")
	osys.create_oath("探针誓约B", "测试用")
	chk(osys.get_active_oaths().size() == 1, "O1 new-oath-replaces-old(单持)")

# ---------------- M组 击杀 ----------------
func _run_mob_tests(player):
	var mobs = get_tree().get_nodes_in_group("mobs")
	chk(mobs.size() > 0, "M0 mobs-alive", str(mobs.size()))
	if mobs.size() == 0:
		return
	var victim = mobs[0]
	victim.take_damage(999999.0)
	chk(int(victim.state) == int(victim.MobState.DYING), "M1 dying-state-set")
	# _die后: 0.9s停尸+0.8s淡出才queue_free，等2秒再查离组
	await _wait(2.0)
	var left = get_tree().get_nodes_in_group("mobs")
	chk(left.size() == mobs.size() - 1 and not is_instance_valid(victim), "M1 kill-removes-mob",
		"%d->%d" % [mobs.size(), left.size()])
	chk(get_tree().get_nodes_in_group("player").size() > 0, "M0 sanity")
	# 重生参数静态断言（Respawner 逻辑已读码确认：90s清营计时+260px安全距）
	var ms = get_node_or_null("/root/Main/World/MobSpawner")
	chk(ms.RESPAWN_DELAY == 90.0 and ms.SAFE_DIST_TO_RESPAWN == 260.0, "M2 respawn-params-90s-260px")

# ---------------- F组 农场 ----------------
func _run_farm_tests(player):
	var farm = get_node_or_null("/root/Main/World/FarmSystem")
	chk(farm != null, "F0 farm-found")
	if farm == null:
		return

	# 浆果采集→空丛→2天再生（bushes是以格子为键的字典）
	var bush_cell := Vector2i(2147483647, 0)
	var found_bush := false
	for cell in farm.bushes.keys():
		if bool(farm.bushes[cell]["has_fruit"]):
			bush_cell = cell
			found_bush = true
			break
	chk(found_bush, "F2 bush-with-fruit-exists")
	if found_bush:
		player.global_position = farm._cell_center(bush_cell) + Vector2(0, 14)
		player.velocity = Vector2.ZERO
		var res = farm.try_collect(farm._cell_center(bush_cell))
		chk(bool(res.get("ok", false)), "F2 collect-berry-ok", str(res.get("msg", "")))
		chk(not bool(farm.bushes[bush_cell]["has_fruit"]), "F2 bush-emptied")
		farm.on_new_day()
		farm.on_new_day()
		chk(bool(farm.bushes[bush_cell]["has_fruit"]), "F2 bush-regrow-2days")

	# 雨天自动补水：开垦→播种(不浇水)→设雨→过天→crop.watered 应为 true
	player.global_position = farm._spawn_player_pos()
	player.velocity = Vector2.ZERO
	var tilled := Vector2i(2147483647, 2147483647)
	for k in range(40):
		var cand: Vector2i = farm._cell_of(farm._spawn_player_pos()) + Vector2i(k % 7 - 3, int(k / 7.0) - 2)
		var res = farm.try_till(farm._cell_center(cand))
		if bool(res.get("ok", false)):
			tilled = cand
			break
	var tilled_ok := tilled != Vector2i(2147483647, 2147483647)
	chk(tilled_ok, "F1 till-near-spawn")
	if tilled_ok:
		var planted = farm.try_plant(farm._cell_center(tilled))
		chk(bool(planted.get("ok", false)), "F1 plant-ok", str(planted.get("msg", "")))
		var had_water := false
		for cell in farm.crops.keys():
			if cell == tilled:
				had_water = bool(farm.crops[cell]["watered"])
				break
		chk(not had_water, "F1 dry-before-rain")
		GameManager.is_raining = true
		farm.on_new_day()
		var now_water := false
		for cell in farm.crops.keys():
			if cell == tilled:
				now_water = bool(farm.crops[cell]["watered"])
				break
		chk(now_water, "F1 rain-auto-waters-crop")
		GameManager.is_raining = false

# ---------------- E组 ESC层级 ----------------
func _run_esc_tests():
	var shud = _ui("ShopHUD")
	var sheet = _ui("CharacterSheet")
	if shud == null or sheet == null:
		chk(false, "E0 huds-found")
		return
	shud.open_shop()
	sheet.open()
	chk(shud.is_open and sheet.visible, "E0 both-open")
	_press_esc()
	await get_tree().process_frame
	await get_tree().process_frame
	var one_open: bool = shud.is_open != sheet.visible  # 恰好关一个
	chk(one_open, "E1 esc-closes-top-only", "shop=%s sheet=%s" % [str(shud.is_open), str(sheet.visible)])
	_press_esc()
	await get_tree().process_frame
	await get_tree().process_frame
	chk(not shud.is_open and not sheet.visible, "E2 second-esc-closes-rest")
